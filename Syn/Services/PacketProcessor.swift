import AppKit
import AVFoundation
import Foundation

enum PacketProcessorError: LocalizedError {
    case missingRawRecording

    var errorDescription: String? {
        switch self {
        case .missingRawRecording:
            "The raw recording is missing, so the packet cannot be retried."
        }
    }
}

struct PacketProcessingResult {
    var packet: PacketSummary
    var manifest: PacketManifest
}

final class PacketProcessor {
    private let frameExtractor = FrameExtractor()
    private let framePlanningService = FramePlanningService()
    private let transcriptionService = TranscriptionService()
    private let aiProviderService = AIProviderService()
    var defaultPromptProfile: AgentPromptProfile = .generalCoding
    var projectContextFolderURL: URL?

    func process(
        context: PacketContext,
        segments: [URL],
        capture: CaptureSourceMetadata,
        pointerEvents: [PointerEvent],
        annotations: [AnnotationStroke],
        activeWindowSamples: [ActiveWindowSample],
        pauses: [PauseInterval],
        deferFinalize: Bool = false,
        liveRender: LiveRenderArtifact? = nil,
        liveFrames: LiveFrameSamplingArtifact? = nil,
        streamingTranscript: Task<StreamingTranscriptResult?, Never>? = nil,
        flaggedElements: [FlaggedElementSnapshot] = []
    ) async throws -> PacketProcessingResult {
        var stageTimings: [ProcessingStageTiming] = []

        let rawMetadataStart = Date()
        try writeRawRecoveryMetadata(
            context: context,
            capture: capture,
            pointerEvents: pointerEvents,
            annotations: annotations,
            activeWindowSamples: activeWindowSamples,
            pauses: pauses
        )
        stageTimings.append(processingTiming("write-raw-recovery-metadata", startedAt: rawMetadataStart))

        let mergeStart = Date()
        let duration = try await VideoUtilities.mergeSegments(segments, outputURL: context.rawRecordingURL)
        stageTimings.append(processingTiming("merge-raw-segments", startedAt: mergeStart))

        return try await processRawRecording(
            context: context,
            capture: capture,
            pointerEvents: pointerEvents,
            annotations: annotations,
            activeWindowSamples: activeWindowSamples,
            pauses: pauses,
            duration: duration,
            initialStageTimings: stageTimings,
            deferFinalize: deferFinalize,
            liveRender: liveRender,
            liveFrames: liveFrames,
            streamingTranscript: streamingTranscript,
            flaggedElements: flaggedElements
        )
    }

    // MARK: - Deferred layered summary

    struct SummaryTierOutcome {
        let lineup: String
        let tier: SummaryTier
        let provider: String
        let seconds: Double
        let succeeded: Bool
    }

    func progressiveLineups() -> [(name: String, tiers: [SummaryTier])] {
        // Read the editable config every time so models / budgets can be swapped between captures
        // without rebuilding or relaunching. Falls back to the built-in default lineup.
        let config = SummaryConfigStore.load()
        return [("summary", config.tiers(fallback: SummaryLineups.default))]
    }

    static func summaryPlaceholderMarkdown() -> String {
        """
        # Summary

        _The layered summary is generating in the background. This file is replaced as each tier
        finishes (fast → balanced → full). See `progress.md` for live status. The transcript,
        recording, and selected frames are already available._
        """
    }

    /// Runs the layered summary lineup(s) after the packet folder has been revealed: tiers run
    /// concurrently, `summary.md` is promoted as each richer tier lands, per-tier outputs are
    /// written under `summaries/`, `progress.md` is kept live, and finally the shareable zip is
    /// created. Owned by the long-lived app so it is not killed mid-flight.
    func runDeferredFinalize(context: PacketContext, capture: CaptureSourceMetadata) async {
        let transcript = (try? String(contentsOf: context.transcriptURL, encoding: .utf8)) ?? ""

        // Phase 1: refine the instant heuristic frame selection with the OpenAI semantic plan.
        // This used to sit on the reveal critical path; the packet is already usable with the
        // heuristic selection, and the summary tiers below pick up the refined frames.
        await refineFramePlan(context: context, transcript: transcript)

        let frames = reloadSelectedFrames(context: context)
        let lineups = progressiveLineups()

        // Resolve each provider's key ONCE up front. Reading the Anthropic key spawns a `hem`
        // subprocess that races under concurrency, so reading it per-tier would make most of the
        // concurrent Claude tiers fail; resolving once and passing the value in avoids that.
        let anthropicKey = SecretStore.readAnthropicKey()
        let openAIKey = SecretStore.readOpenAIKey()

        var outcomes: [SummaryTierOutcome] = []
        var bestRank = -1

        await withTaskGroup(of: (SummaryTierOutcome, SummaryResult).self) { group in
            for lineup in lineups {
                for tier in lineup.tiers {
                    group.addTask {
                        let started = Date()
                        let result = await self.aiProviderService.generateSummary(
                            tier: tier, transcript: transcript, frames: frames, context: context,
                            anthropicKey: anthropicKey, openAIKey: openAIKey
                        )
                        let outcome = SummaryTierOutcome(
                            lineup: lineup.name,
                            tier: tier,
                            provider: result.provider,
                            seconds: Date().timeIntervalSince(started),
                            succeeded: result.provider != "local-fallback"
                        )
                        return (outcome, result)
                    }
                }
            }

            for await (outcome, result) in group {
                outcomes.append(outcome)
                writeTierSummaryFile(context: context, outcome: outcome, markdown: result.markdown)
                SynPerf.log("summary tier \(outcome.tier.label) (\(outcome.tier.model))", seconds: outcome.seconds)

                if outcome.succeeded {
                    let rank = promotionRank(outcome)
                    if rank > bestRank {
                        bestRank = rank
                        try? result.markdown.write(to: context.summaryURL, atomically: true, encoding: .utf8)
                        refreshHandoff(context: context, best: outcome)
                    }
                }
                writeProgressFile(context: context, lineups: lineups, outcomes: outcomes, zipReady: false, summaryComplete: false)
            }
        }

        // If no tier succeeded, leave a local fallback summary rather than the placeholder.
        if bestRank < 0 {
            try? AIProviderService.fallbackSummary(transcript: transcript, frames: frames)
                .write(to: context.summaryURL, atomically: true, encoding: .utf8)
            refreshHandoff(context: context, best: nil)
        }

        // All summary tiers done; create the shareable zip now that the best summary is in place.
        let zipStart = Date()
        try? ZipService.createZip(for: context)
        SynPerf.log("background zip (after summary)", seconds: Date().timeIntervalSince(zipStart))

        if let data = try? Data(contentsOf: context.manifestURL),
           var manifest = try? JSONDecoder.synDecoder.decode(PacketManifest.self, from: data) {
            manifest.processing.zipStatus = "ready"
            manifest.processing.summaryStatus = bestRank < 0 ? "local-fallback" : "ready"
            try? JSONEncoder.synEncoder.encode(manifest).write(to: context.manifestURL)
        }
        writeProgressFile(context: context, lineups: lineups, outcomes: outcomes, zipReady: true, summaryComplete: true)
        SynPerf.event("deferred finalize complete: \(outcomes.count) tiers, \(outcomes.filter(\.succeeded).count) succeeded")
    }

    /// Promotion priority: richer tier wins; on an A/B tie, prefer the default (claude) lineup.
    private func promotionRank(_ outcome: SummaryTierOutcome) -> Int {
        outcome.tier.rank
    }

    /// Background semantic frame refinement: rebuild the extraction from disk, run the OpenAI
    /// plan, prune the now-unselected candidate files, rewrite the frame/semantic artifacts, and
    /// refresh the manifest + prompts so agents see the refined selection.
    private func refineFramePlan(context: PacketContext, transcript: String) async {
        guard let data = try? Data(contentsOf: context.candidateMetadataURL),
              let candidates = try? JSONDecoder.synDecoder.decode([CandidateFrameMetadata].self, from: data),
              !candidates.isEmpty else {
            return
        }

        let manifestDuration = loadManifest(context: context)?.duration
        let duration = manifestDuration ?? (candidates.map(\.timestamp).max() ?? 0)
        // Offer the planner every candidate whose image files still exist — the deferred path
        // skips pruning precisely so the semantic plan can choose from the full visual-change
        // pool, not just the heuristic top picks shown at reveal time.
        let extraction = FrameExtractionResult(
            candidateFrames: candidates,
            selectedFrames: candidates.filter { $0.compressedPath != nil },
            duration: duration
        )

        let started = Date()
        var plan = await framePlanningService.planFrames(
            extraction: extraction,
            transcript: transcript,
            context: context
        )
        SynPerf.log("deferred frame plan (\(plan.provider))", seconds: Date().timeIntervalSince(started))

        plan.candidateFrames = pruneUnselectedFrameFiles(plan.candidateFrames, context: context)
        plan.selectedFrames = plan.candidateFrames.filter(\.selected)
        plan.semanticSegments = makeSemanticSegmentsIfNeeded(
            plan.semanticSegments,
            selectedFrames: plan.selectedFrames,
            duration: duration,
            source: plan.provider
        )
        try? JSONEncoder.synEncoder.encode(plan.candidateFrames).write(to: context.candidateMetadataURL)
        try? writeSemanticArtifacts(context: context, segments: plan.semanticSegments)

        guard let manifestData = try? Data(contentsOf: context.manifestURL),
              var manifest = try? JSONDecoder.synDecoder.decode(PacketManifest.self, from: manifestData) else {
            return
        }
        manifest.processing.frameSelectionProvider = plan.provider
        manifest.processing.frameSelectionModel = plan.model
        manifest.processing.notes.append(contentsOf: plan.notes)
        try? JSONEncoder.synEncoder.encode(manifest).write(to: context.manifestURL)
        if let prompt = try? writeAgentPrompts(context: context, manifest: manifest) {
            copyToClipboard(prompt, folderURL: context.folderURL)
        }
    }

    private func reloadSelectedFrames(context: PacketContext) -> [CandidateFrameMetadata] {
        guard let data = try? Data(contentsOf: context.candidateMetadataURL),
              let frames = try? JSONDecoder.synDecoder.decode([CandidateFrameMetadata].self, from: data) else {
            return []
        }
        return frames.filter(\.selected)
    }

    private func writeTierSummaryFile(context: PacketContext, outcome: SummaryTierOutcome, markdown: String) {
        let dir = context.folderURL.appendingPathComponent("summaries", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let header = "<!-- tier=\(outcome.tier.label) model=\(outcome.tier.model) maxTokens=\(outcome.tier.maxTokens) seconds=\(String(format: "%.2f", outcome.seconds)) provider=\(outcome.provider) -->\n\n"
        try? (header + markdown).write(
            to: dir.appendingPathComponent("\(outcome.tier.label).md"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Re-point the manifest's summary provider/model at the current best tier and rewrite the
    /// agent prompts (which re-embed the now-promoted summary.md) + clipboard handoff.
    private func refreshHandoff(context: PacketContext, best: SummaryTierOutcome?) {
        guard let data = try? Data(contentsOf: context.manifestURL),
              var manifest = try? JSONDecoder.synDecoder.decode(PacketManifest.self, from: data) else {
            return
        }
        if let best {
            manifest.processing.summaryProvider = best.provider
            manifest.processing.summaryModel = best.tier.model
        }
        try? JSONEncoder.synEncoder.encode(manifest).write(to: context.manifestURL)
        if let prompt = try? writeAgentPrompts(context: context, manifest: manifest) {
            copyToClipboard(prompt, folderURL: context.folderURL)
        }
    }

    func writeProgressFile(
        context: PacketContext,
        lineups: [(name: String, tiers: [SummaryTier])],
        outcomes: [SummaryTierOutcome],
        zipReady: Bool,
        summaryComplete: Bool,
        frameSelectionStatus: String = "ready"
    ) {
        let totalTiers = lineups.reduce(0) { $0 + $1.tiers.count }
        let doneTiers = outcomes.count
        let bestDone = outcomes.filter(\.succeeded).max(by: { promotionRank($0) < promotionRank($1) })
        let bestLabel = bestDone.map { "\($0.tier.label) (\($0.tier.model))" } ?? "none yet"

        var rows = "| tier | model | max tokens | status | seconds |\n|---|---|---|---|---|\n"
        for lineup in lineups {
            for tier in lineup.tiers {
                let outcome = outcomes.first { $0.lineup == lineup.name && $0.tier.label == tier.label }
                let status = outcome.map { $0.succeeded ? "done" : "fallback" } ?? "pending"
                let seconds = outcome.map { String(format: "%.2f", $0.seconds) } ?? "—"
                rows += "| \(tier.label) | \(tier.model) | \(tier.maxTokens) | \(status) | \(seconds) |\n"
            }
        }

        let markdown = """
        # Packet Progress

        Status: \(summaryComplete ? "complete" : "generating summary…")

        The recording, transcript (`transcript.md`), selected frames, and `manifest.json` are ready.
        The summary is produced in layered tiers; richer tiers replace earlier ones in `summary.md`
        as they finish, and each tier's raw output is kept under `summaries/`.

        ## Stages

        - Recording / transcript / frames / manifest: ready
        - Frame selection: \(frameSelectionStatus)
        - Summary: \(summaryComplete ? "complete" : "\(doneTiers)/\(totalTiers) tiers done") — best so far: \(bestLabel)
        - Shareable zip: \(zipReady ? "ready" : "pending")

        ## Summary tiers

        \(rows)
        Each tier's raw output is kept under `summaries/` (fast / balanced / full).
        """
        try? markdown.write(to: context.progressURL, atomically: true, encoding: .utf8)
    }

    func retry(context: PacketContext) async throws -> PacketProcessingResult {
        var stageTimings: [ProcessingStageTiming] = []
        if !FileManager.default.fileExists(atPath: context.rawRecordingURL.path) {
            let segments = rawSegmentURLs(context: context)
            guard !segments.isEmpty else {
                throw PacketProcessorError.missingRawRecording
            }
            let mergeStart = Date()
            _ = try await VideoUtilities.mergeSegments(segments, outputURL: context.rawRecordingURL)
            stageTimings.append(processingTiming("merge-raw-segments", startedAt: mergeStart))
        }

        let manifest = loadManifest(context: context)
        let rawSession = loadRawCaptureSession(context: context)
        let pointerEvents = (try? JSONDecoder.synDecoder.decode(
            [PointerEvent].self,
            from: Data(contentsOf: context.pointerEventsURL)
        )) ?? []
        let annotations = (try? JSONDecoder.synDecoder.decode(
            [AnnotationStroke].self,
            from: Data(contentsOf: context.annotationEventsURL)
        )) ?? []

        let activeWindowSamples = loadActiveWindowSamples(context: context, manifest: manifest)
        let duration = try await AVURLAsset(url: context.rawRecordingURL).durationSeconds()

        return try await processRawRecording(
            context: context,
            capture: try await retryCaptureMetadata(context: context, manifest: manifest, rawSession: rawSession),
            pointerEvents: pointerEvents,
            annotations: annotations,
            activeWindowSamples: activeWindowSamples,
            pauses: manifest?.pauses ?? rawSession?.pauses ?? [],
            duration: duration,
            initialStageTimings: stageTimings
        )
    }

    @discardableResult
    func writePartialFailureArtifacts(
        context: PacketContext,
        capture: CaptureSourceMetadata,
        pointerEvents: [PointerEvent],
        annotations: [AnnotationStroke],
        activeWindowSamples: [ActiveWindowSample],
        pauses: [PauseInterval],
        duration fallbackDuration: TimeInterval,
        error: Error
    ) async throws -> PacketSummary {
        try context.ensureDerivedDirectories()
        try writeRawRecoveryMetadata(
            context: context,
            capture: capture,
            pointerEvents: pointerEvents,
            annotations: annotations,
            activeWindowSamples: activeWindowSamples,
            pauses: pauses
        )

        if !FileManager.default.fileExists(atPath: context.candidateMetadataURL.path) {
            let emptyFrames: [CandidateFrameMetadata] = []
            try JSONEncoder.synEncoder.encode(emptyFrames).write(to: context.candidateMetadataURL)
        }

        var notes: [String] = []
        try writeProjectContextIfConfigured(context: context, notes: &notes)

        let rawExists = FileManager.default.fileExists(atPath: context.rawRecordingURL.path)
        let finalExists = FileManager.default.fileExists(atPath: context.finalRecordingURL.path)
        notes.append(contentsOf: [
            "Processing failed before Syn could finish the packet: \(error.localizedDescription)",
            "Raw capture metadata was retained for retry."
        ])

        if rawExists && !finalExists {
            do {
                try Self.copyFinalRecording(rawURL: context.rawRecordingURL, finalURL: context.finalRecordingURL)
                notes.append("recording.mp4 is a raw copy because processed rendering did not complete.")
            } catch {
                notes.append("Could not create recording.mp4 raw copy: \(error.localizedDescription)")
            }
        }

        let duration = rawExists
            ? ((try? await AVURLAsset(url: context.rawRecordingURL).durationSeconds()) ?? fallbackDuration)
            : fallbackDuration
        let transcriptMarkdown = existingOrFailedTranscript(context: context, error: error)
        try transcriptMarkdown.write(to: context.transcriptURL, atomically: true, encoding: .utf8)

        let summaryMarkdown = partialFailureSummary(context: context, error: error)
        try summaryMarkdown.write(to: context.summaryURL, atomically: true, encoding: .utf8)

        let transcriptResult = TranscriptResult(
            markdown: transcriptMarkdown,
            provider: "local-whisper.cpp-bundled",
            model: "unavailable",
            notes: ["Transcription did not complete in this partial packet."]
        )
        let framePlanningResult = FramePlanningResult(
            selectedFrames: [],
            candidateFrames: [],
            semanticSegments: [],
            provider: "partial-failure",
            model: "none",
            notes: ["Frame planning did not complete in this partial packet."]
        )
        let summaryResult = SummaryResult(
            markdown: summaryMarkdown,
            provider: "local-partial-fallback",
            model: "none",
            notes: ["Syn generated a local partial-failure summary."]
        )
        let processedVideo = ProcessedVideoResult(
            duration: duration,
            renderSize: capture.outputSize ?? CodableSize(width: 0, height: 0),
            pointerEvents: pointerEvents,
            renderedClickCount: 0,
            annotations: annotations,
            renderedAnnotationCount: 0,
            notes: notes
        )
        let manifest = makeManifest(
            context: context,
            duration: duration,
            capture: capture,
            transcriptResult: transcriptResult,
            framePlanningResult: framePlanningResult,
            summaryResult: summaryResult,
            processingNotes: notes,
            pauses: pauses,
            processedVideo: processedVideo,
            hasActiveWindowSamples: !activeWindowSamples.isEmpty
        )
        try JSONEncoder.synEncoder.encode(manifest).write(to: context.manifestURL)

        let prompt = try writeAgentPrompts(context: context, manifest: manifest)

        do {
            try ZipService.createZip(for: context)
        } catch {
            notes.append("Zip creation failed for partial packet: \(error.localizedDescription)")
        }

        copyToClipboard(prompt, folderURL: context.folderURL)
        return PacketSummary(
            id: context.id,
            title: context.title,
            createdAt: context.createdAt,
            duration: duration,
            status: rawExists ? .partial : .failed,
            folderURL: context.folderURL,
            zipURL: context.zipURL
        )
    }

    private func processRawRecording(
        context: PacketContext,
        capture: CaptureSourceMetadata,
        pointerEvents: [PointerEvent],
        annotations: [AnnotationStroke],
        activeWindowSamples: [ActiveWindowSample],
        pauses: [PauseInterval],
        duration: TimeInterval,
        initialStageTimings: [ProcessingStageTiming] = [],
        deferFinalize: Bool = false,
        liveRender: LiveRenderArtifact? = nil,
        liveFrames: LiveFrameSamplingArtifact? = nil,
        streamingTranscript: Task<StreamingTranscriptResult?, Never>? = nil,
        flaggedElements: [FlaggedElementSnapshot] = []
    ) async throws -> PacketProcessingResult {
        var processingNotes: [String] = []
        var stageTimings = initialStageTimings
        let pipelineStart = Date()
        let prepareStart = Date()
        try prepareDerivedOutputs(context: context)
        try writeProjectContextIfConfigured(context: context, notes: &processingNotes)
        stageTimings.append(processingTiming("prepare-derived-outputs-and-project-context", startedAt: prepareStart))

        // The video branch (render -> overlay metadata -> frame extraction) needs a video.
        // The transcript branch needs only the audio track, which is already present in the
        // raw merged recording. They have no mutual data dependency and write disjoint files,
        // so run them concurrently and join before frame planning. This collapses the two
        // longest independent stages into one wall-clock window.
        // Flagged elements burn into the video through the annotation pipeline as
        // synthetic rectangles (forcing the offline render); they are stripped from
        // annotation metadata afterwards by ID.
        let elementStrokes = flaggedElements.map { $0.syntheticStroke(recordingDuration: duration) }
        let syntheticIDs = Set(elementStrokes.map(\.id))
        async let videoBranch = renderAndExtract(
            context: context,
            capture: capture,
            pointerEvents: pointerEvents,
            annotations: annotations + elementStrokes,
            activeWindowSamples: activeWindowSamples,
            duration: duration,
            liveRender: liveRender,
            liveFrames: liveFrames
        )
        async let transcriptBranch = transcribeFromRaw(context: context, streamingTranscript: streamingTranscript)

        let video = await videoBranch
        let transcript = await transcriptBranch
        var processedVideo = video.processedVideo
        if !syntheticIDs.isEmpty {
            var enriched = flaggedElements
            for stroke in processedVideo.annotations where syntheticIDs.contains(stroke.id) {
                if let points = stroke.videoPoints, points.count >= 2,
                   let index = enriched.firstIndex(where: { $0.id == stroke.id }) {
                    let xs = points.map(\.x)
                    let ys = points.map(\.y)
                    enriched[index].videoBounds = CodableRect(CGRect(
                        x: xs.min() ?? 0,
                        y: ys.min() ?? 0,
                        width: (xs.max() ?? 0) - (xs.min() ?? 0),
                        height: (ys.max() ?? 0) - (ys.min() ?? 0)
                    ))
                }
            }
            processedVideo.annotations.removeAll { syntheticIDs.contains($0.id) }
            let elementsDirectory = context.folderURL.appendingPathComponent("elements", isDirectory: true)
            try? FileManager.default.createDirectory(at: elementsDirectory, withIntermediateDirectories: true)
            try? JSONEncoder.synEncoder.encode(enriched)
                .write(to: elementsDirectory.appendingPathComponent("flagged-elements.json"))
            processingNotes.append("Element intelligence flagged \(flaggedElements.count) element(s); see elements/flagged-elements.json. Highlights are burned into recording.mp4 at their flag timestamps.")
        }
        let frameResult = video.frameResult
        let transcriptResult = transcript.result
        processingNotes.append(contentsOf: video.notes)
        processingNotes.append(contentsOf: transcript.notes)
        stageTimings.append(contentsOf: video.timings)
        stageTimings.append(contentsOf: transcript.timings)

        // For interactive recordings BOTH model calls are deferred: the packet reveals with the
        // extractor's instant visual-change frame selection, then runDeferredFinalize refines the
        // selection with the OpenAI semantic plan and generates the layered summary in the
        // background. The OpenAI plan alone was ~12s of critical-path wall clock.
        var framePlanningResult: FramePlanningResult
        let summaryResult: SummaryResult
        if deferFinalize {
            let framePlanStart = Date()
            framePlanningResult = framePlanningService.heuristicPlan(extraction: frameResult)
            stageTimings.append(processingTiming("plan-frames-heuristic", startedAt: framePlanStart))
            summaryResult = SummaryResult(
                markdown: "",
                provider: "pending",
                model: "deferred",
                notes: ["Summary is generating in the background; see progress.md."]
            )
        } else {
            // Fixtures/retry: frame plan + a single synchronous summary run concurrently. Both read
            // the extracted frame files BEFORE the prune below, so there is no file race.
            async let planPair: (result: FramePlanningResult, seconds: Double) = {
                let started = Date()
                let result = await framePlanningService.planFrames(
                    extraction: frameResult, transcript: transcriptResult.markdown, context: context)
                return (result, Date().timeIntervalSince(started))
            }()
            async let summaryPair: (result: SummaryResult, seconds: Double) = {
                let started = Date()
                let result = await aiProviderService.createSummary(
                    transcript: transcriptResult.markdown, frames: frameResult.selectedFrames, context: context)
                return (result, Date().timeIntervalSince(started))
            }()
            let plan = await planPair
            let summary = await summaryPair
            framePlanningResult = plan.result
            summaryResult = summary.result
            stageTimings.append(ProcessingStageTiming(name: "plan-semantic-frames-openai", durationSeconds: plan.seconds))
            stageTimings.append(ProcessingStageTiming(name: "summarize-claude", durationSeconds: summary.seconds))
        }
        processingNotes.append(contentsOf: framePlanningResult.notes)

        // Prune unselected frame files after the frame plan — but only when the plan is final.
        // The deferred path keeps every candidate's files on disk so the background semantic
        // refinement can still promote any of them; it prunes after the refined plan lands.
        let semanticArtifactsStart = Date()
        if !deferFinalize {
            framePlanningResult.candidateFrames = pruneUnselectedFrameFiles(
                framePlanningResult.candidateFrames,
                context: context
            )
        }
        framePlanningResult.selectedFrames = framePlanningResult.candidateFrames.filter(\.selected)
        framePlanningResult.semanticSegments = makeSemanticSegmentsIfNeeded(
            framePlanningResult.semanticSegments,
            selectedFrames: framePlanningResult.selectedFrames,
            duration: frameResult.duration,
            source: framePlanningResult.provider
        )
        try JSONEncoder.synEncoder.encode(framePlanningResult.candidateFrames).write(to: context.candidateMetadataURL)
        try writeSemanticArtifacts(context: context, segments: framePlanningResult.semanticSegments)
        stageTimings.append(processingTiming("write-frame-and-semantic-artifacts", startedAt: semanticArtifactsStart))

        processingNotes.append(contentsOf: transcriptResult.notes)
        processingNotes.append(contentsOf: summaryResult.notes)
        // Surface a blank transcript as an explicit, actionable note instead of silently
        // shipping an empty transcript (e.g. denied microphone permission or a silent clip).
        let spokenTranscript = transcriptResult.markdown
            .replacingOccurrences(of: "# Transcript", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if spokenTranscript.isEmpty || spokenTranscript.contains("No speech was detected") {
            processingNotes.append("Transcript is empty: no narration audio was detected. Confirm microphone permission is granted to Syn and that you spoke during the recording.")
        }

        func wallClockTiming() -> ProcessingStageTiming {
            ProcessingStageTiming(
                name: "pipeline-wall-clock-total",
                durationSeconds: max(0, Date().timeIntervalSince(pipelineStart))
            )
        }

        let manifest: PacketManifest
        let prompt: String
        if deferFinalize {
            // Interactive: write a placeholder summary + initial progress.md, then return so the
            // folder reveals immediately. runDeferredFinalize produces the layered summary, promotes
            // summary.md, refreshes the handoff, and creates the zip — all in the background.
            try Self.summaryPlaceholderMarkdown().write(to: context.summaryURL, atomically: true, encoding: .utf8)
            writeProgressFile(
                context: context,
                lineups: progressiveLineups(),
                outcomes: [],
                zipReady: false,
                summaryComplete: false,
                frameSelectionStatus: "instant visual-change selection — semantic refinement running in background"
            )
            stageTimings.append(wallClockTiming())
            processingNotes.append(stageTimingSummary(stageTimings))
            var deferredManifest = makeManifest(
                context: context, duration: duration, capture: capture,
                transcriptResult: transcriptResult, framePlanningResult: framePlanningResult,
                summaryResult: summaryResult, processingNotes: processingNotes, pauses: pauses,
                processedVideo: processedVideo, hasActiveWindowSamples: !activeWindowSamples.isEmpty,
                stageTimings: stageTimings
            )
            deferredManifest.processing.zipStatus = "pending"
            deferredManifest.processing.summaryStatus = "pending"
            try JSONEncoder.synEncoder.encode(deferredManifest).write(to: context.manifestURL)
            prompt = try writeAgentPrompts(context: context, manifest: deferredManifest)
            manifest = deferredManifest
        } else {
            // Fixtures/retry: summary is done; write it, the manifest + prompts, then zip
            // synchronously and rewrite the manifest with the final zip/wall-clock timings.
            try summaryResult.markdown.write(to: context.summaryURL, atomically: true, encoding: .utf8)
            writeProgressFile(
                context: context,
                lineups: [("summary", [SummaryTier(label: "full", provider: .anthropic, model: summaryResult.model, maxTokens: 4000)])],
                outcomes: [SummaryTierOutcome(lineup: "summary", tier: SummaryTier(label: "full", provider: .anthropic, model: summaryResult.model, maxTokens: 4000), provider: summaryResult.provider, seconds: 0, succeeded: summaryResult.provider != "local-fallback")],
                zipReady: false,
                summaryComplete: true
            )
            let preliminaryManifest = makeManifest(
                context: context, duration: duration, capture: capture,
                transcriptResult: transcriptResult, framePlanningResult: framePlanningResult,
                summaryResult: summaryResult, processingNotes: processingNotes, pauses: pauses,
                processedVideo: processedVideo, hasActiveWindowSamples: !activeWindowSamples.isEmpty,
                stageTimings: stageTimings
            )
            try JSONEncoder.synEncoder.encode(preliminaryManifest).write(to: context.manifestURL)
            _ = try writeAgentPrompts(context: context, manifest: preliminaryManifest)

            let zipStart = Date()
            do {
                try ZipService.createZip(for: context)
            } catch {
                processingNotes.append("Zip creation failed: \(error.localizedDescription)")
            }
            stageTimings.append(processingTiming("create-default-zip", startedAt: zipStart))
            stageTimings.append(wallClockTiming())
            processingNotes.append(stageTimingSummary(stageTimings))

            var finalManifest = makeManifest(
                context: context, duration: duration, capture: capture,
                transcriptResult: transcriptResult, framePlanningResult: framePlanningResult,
                summaryResult: summaryResult, processingNotes: processingNotes, pauses: pauses,
                processedVideo: processedVideo, hasActiveWindowSamples: !activeWindowSamples.isEmpty,
                stageTimings: stageTimings
            )
            finalManifest.processing.zipStatus = "ready"
            finalManifest.processing.summaryStatus = "ready"
            try JSONEncoder.synEncoder.encode(finalManifest).write(to: context.manifestURL)
            writeProgressFile(
                context: context,
                lineups: [("summary", [SummaryTier(label: "full", provider: .anthropic, model: summaryResult.model, maxTokens: 4000)])],
                outcomes: [SummaryTierOutcome(lineup: "summary", tier: SummaryTier(label: "full", provider: .anthropic, model: summaryResult.model, maxTokens: 4000), provider: summaryResult.provider, seconds: 0, succeeded: summaryResult.provider != "local-fallback")],
                zipReady: true,
                summaryComplete: true
            )
            prompt = try writeAgentPrompts(context: context, manifest: finalManifest)
            manifest = finalManifest
        }
        copyToClipboard(prompt, folderURL: context.folderURL)

        // Stream the per-stage timing breakdown + which providers ran so a slow finalize can be
        // diagnosed live via `--telemetry` or ~/Library/Logs/Syn/perf.log.
        SynPerf.event("packet processed (deferFinalize=\(deferFinalize)): transcription=\(transcriptResult.provider), framePlan=\(framePlanningResult.provider)/\(framePlanningResult.model ?? "none"), summary=\(summaryResult.provider)/\(summaryResult.model)")
        for timing in stageTimings {
            SynPerf.log("stage \(timing.name)", seconds: timing.durationSeconds)
        }

        let packetStatus = packetStatus(for: processingNotes)
        let packet = PacketSummary(
            id: context.id,
            title: context.title,
            createdAt: context.createdAt,
            duration: duration,
            status: packetStatus,
            folderURL: context.folderURL,
            zipURL: context.zipURL
        )

        return PacketProcessingResult(packet: packet, manifest: manifest)
    }

    /// Video branch: render the processed recording, persist overlay metadata, and extract
    /// frames + OCR. Needs a video and runs concurrently with `transcribeFromRaw`.
    ///
    /// For static-geometry modes (everything except the Active Window / Smart Region moving
    /// crops) the raw recording frames match the final video's framing, so frame extraction
    /// reads the RAW recording and runs in parallel with the render instead of after it —
    /// extraction is no longer on the video branch's critical path. Dynamic-crop modes keep
    /// the sequential extract-from-final order because their final framing differs.
    private func renderAndExtract(
        context: PacketContext,
        capture: CaptureSourceMetadata,
        pointerEvents: [PointerEvent],
        annotations: [AnnotationStroke],
        activeWindowSamples: [ActiveWindowSample],
        duration: TimeInterval,
        liveRender: LiveRenderArtifact? = nil,
        liveFrames: LiveFrameSamplingArtifact? = nil
    ) async -> (processedVideo: ProcessedVideoResult, frameResult: FrameExtractionResult, notes: [String], timings: [ProcessingStageTiming]) {
        var notes: [String] = []
        var timings: [ProcessingStageTiming] = []

        // Frames sampled during the recording replace extraction entirely: move the staged
        // files into frames/, enrich with per-timestamp window context, write metadata.
        var liveFrameResult: FrameExtractionResult?
        if let liveFrames, liveFrames.usable {
            let liveFramesStart = Date()
            liveFrameResult = try? adoptLiveSampledFrames(
                liveFrames,
                context: context,
                capture: capture,
                activeWindowSamples: activeWindowSamples,
                duration: duration
            )
            if liveFrameResult != nil {
                notes.append("Candidate frames were sampled live during the recording; stop-time extraction was skipped.")
                timings.append(processingTiming("extract-frames-live-adopt", startedAt: liveFramesStart))
                SynPerf.log("live frame adoption", seconds: Date().timeIntervalSince(liveFramesStart))
            }
        }
        if let liveFrames {
            try? FileManager.default.removeItem(at: liveFrames.stagingDirectory)
        }

        let extractFromRawInParallel = liveFrameResult == nil && !VideoUtilities.usesDynamicCropRender(
            capture: capture,
            activeWindowSamples: activeWindowSamples
        )

        async let parallelExtraction: (FrameExtractionResult?, Double) = {
            guard extractFromRawInParallel else {
                return (nil, 0)
            }
            let started = Date()
            let result = try? await self.frameExtractor.extractFrames(
                from: context.rawRecordingURL,
                context: context,
                capture: capture,
                activeWindowSamples: activeWindowSamples
            )
            return (result, Date().timeIntervalSince(started))
        }()

        // Fast path: click bubbles were already burned during capture, so finalize is a
        // passthrough remux of the live segments + raw audio (≈1s instead of a re-encode).
        // Annotations are not live-composited, so canvas recordings take the offline path.
        var liveProcessedVideo: ProcessedVideoResult?
        if let liveRender, liveRender.usable, annotations.isEmpty {
            let liveFinalizeStart = Date()
            do {
                liveProcessedVideo = try await VideoUtilities.fastFinalizeLiveRender(
                    liveSegmentURLs: liveRender.segmentURLs,
                    rawURL: context.rawRecordingURL,
                    finalURL: context.finalRecordingURL,
                    capture: capture,
                    pointerEvents: pointerEvents,
                    renderedClickCount: liveRender.renderedClickCount
                )
                timings.append(processingTiming("finalize-live-render-remux", startedAt: liveFinalizeStart))
                SynPerf.log("live render fast finalize", seconds: Date().timeIntervalSince(liveFinalizeStart))
            } catch {
                notes.append("Live render finalize failed (\(error.localizedDescription)); fell back to the offline render.")
            }
        }
        cleanUpLiveRenderSegments(context: context)

        let processedVideo: ProcessedVideoResult
        let renderStart = Date()
        if let liveProcessedVideo {
            processedVideo = liveProcessedVideo
            notes.append(contentsOf: liveProcessedVideo.notes)
            if liveProcessedVideo.renderedClickCount > 0 {
                notes.append("Rendered \(liveProcessedVideo.renderedClickCount) click bubble overlays into recording.mp4 live during capture.")
            }
        } else { do {
            processedVideo = try await VideoUtilities.renderProcessedRecording(
                rawURL: context.rawRecordingURL,
                finalURL: context.finalRecordingURL,
                capture: capture,
                pointerEvents: pointerEvents,
                annotations: annotations,
                activeWindowSamples: activeWindowSamples
            )
            notes.append(contentsOf: processedVideo.notes)
            if processedVideo.renderedClickCount > 0 {
                notes.append("Rendered \(processedVideo.renderedClickCount) click bubble overlays into recording.mp4.")
            }
            if processedVideo.renderedAnnotationCount > 0 {
                notes.append("Rendered \(processedVideo.renderedAnnotationCount) annotation overlays into recording.mp4.")
            }
        } catch {
            try? VideoUtilities.copyFinalRecording(rawURL: context.rawRecordingURL, finalURL: context.finalRecordingURL)
            notes.append("Processed video rendering failed; recording.mp4 is a raw copy. Error: \(error.localizedDescription)")
            processedVideo = ProcessedVideoResult(
                duration: duration,
                renderSize: capture.outputSize ?? CodableSize(width: 0, height: 0),
                pointerEvents: pointerEvents,
                renderedClickCount: 0,
                annotations: annotations,
                renderedAnnotationCount: 0,
                notes: []
            )
        } }
        timings.append(processingTiming(
            liveProcessedVideo != nil ? "render-processed-video-live" : "render-processed-video",
            startedAt: renderStart
        ))

        let overlayMetadataStart = Date()
        try? JSONEncoder.synEncoder.encode(processedVideo.pointerEvents).write(to: context.pointerEventsURL)
        try? JSONEncoder.synEncoder.encode(processedVideo.annotations).write(to: context.annotationEventsURL)
        timings.append(processingTiming("write-pointer-and-annotation-metadata", startedAt: overlayMetadataStart))

        var frameResult: FrameExtractionResult? = liveFrameResult
        let (rawExtraction, rawExtractionSeconds) = await parallelExtraction
        if frameResult == nil, let rawExtraction {
            frameResult = rawExtraction
            notes.append("Frames were extracted from the raw capture in parallel with the render (pre-overlay framing).")
            timings.append(ProcessingStageTiming(name: "extract-frames-and-ocr", durationSeconds: rawExtractionSeconds))
        }

        if frameResult == nil {
            let frameExtractionStart = Date()
            do {
                frameResult = try await frameExtractor.extractFrames(
                    from: context.finalRecordingURL,
                    context: context,
                    capture: capture,
                    activeWindowSamples: activeWindowSamples
                )
            } catch {
                notes.append("Frame extraction failed: \(error.localizedDescription)")
                let emptyFrames: [CandidateFrameMetadata] = []
                try? JSONEncoder.synEncoder.encode(emptyFrames).write(to: context.candidateMetadataURL)
                frameResult = FrameExtractionResult(candidateFrames: [], selectedFrames: [], duration: duration)
            }
            timings.append(processingTiming("extract-frames-and-ocr", startedAt: frameExtractionStart))
        }

        return (processedVideo, frameResult ?? FrameExtractionResult(candidateFrames: [], selectedFrames: [], duration: duration), notes, timings)
    }

    /// Adopts frames sampled during the recording: moves staged PNG/JPEGs into frames/,
    /// fills in per-timestamp app/window context, and writes candidate metadata — the
    /// entire offline extraction collapses into file moves.
    private func adoptLiveSampledFrames(
        _ artifact: LiveFrameSamplingArtifact,
        context: PacketContext,
        capture: CaptureSourceMetadata,
        activeWindowSamples: [ActiveWindowSample],
        duration: TimeInterval
    ) throws -> FrameExtractionResult {
        var metadata: [CandidateFrameMetadata] = []
        for frame in artifact.frames {
            var fullPath: String?
            var compressedPath: String?
            var fullBytes: Int?
            var compressedBytes: Int?

            if let fullFileName = frame.fullFileName {
                let destination = context.fullFramesURL.appendingPathComponent(fullFileName)
                try FileManager.default.moveItem(
                    at: artifact.stagingDirectory.appendingPathComponent(fullFileName),
                    to: destination
                )
                fullPath = FrameExtractor.relativePath(destination, base: context.folderURL)
                fullBytes = FrameExtractor.fileSize(destination)
            }
            if let compressedFileName = frame.compressedFileName {
                let destination = context.compressedFramesURL.appendingPathComponent(compressedFileName)
                try FileManager.default.moveItem(
                    at: artifact.stagingDirectory.appendingPathComponent(compressedFileName),
                    to: destination
                )
                compressedPath = FrameExtractor.relativePath(destination, base: context.folderURL)
                compressedBytes = FrameExtractor.fileSize(destination)
            }

            let sample = activeWindowSamples.last(where: { $0.timestamp <= frame.timestamp }) ?? activeWindowSamples.first
            metadata.append(CandidateFrameMetadata(
                timestamp: frame.timestamp,
                fullPath: fullPath,
                compressedPath: compressedPath,
                candidatePath: nil,
                fullSize: frame.fullSize,
                compressedSize: frame.compressedSize,
                candidateSize: nil,
                fullBytes: fullBytes,
                compressedBytes: compressedBytes,
                candidateBytes: nil,
                perceptualHash: String(format: "%016llx", frame.perceptualHash),
                pixelDifferenceFromPrevious: frame.pixelDifferenceFromPrevious,
                appName: sample?.appName ?? capture.appName,
                windowTitle: sample?.windowTitle ?? capture.windowTitle,
                captureBounds: capture.sourceRect,
                ocrText: frame.ocr.text,
                ocrMeanConfidence: frame.ocr.meanConfidence,
                ocrObservations: frame.ocr.observations.isEmpty ? nil : frame.ocr.observations,
                selected: frame.selected,
                reason: frame.selected ? "visual-change-pixel-diff" : "pixel-dedupe"
            ))
        }

        try JSONEncoder.synEncoder.encode(metadata).write(to: context.candidateMetadataURL)
        return FrameExtractionResult(
            candidateFrames: metadata,
            selectedFrames: metadata.filter(\.selected),
            duration: duration
        )
    }

    /// The live overlay segments are working files only — once recording.mp4 exists (via the
    /// fast remux or the offline fallback) they have no further use and are removed so they
    /// never leak into raw recovery merges or zips.
    private func cleanUpLiveRenderSegments(context: PacketContext) {
        let liveDirectory = context.rawSegmentsURL
            .deletingLastPathComponent()
            .appendingPathComponent("live-render", isDirectory: true)
        try? FileManager.default.removeItem(at: liveDirectory)
    }

    /// Transcript branch: transcribe the raw recording's audio with local Whisper. Needs only
    /// the audio track (available immediately after capture), so it runs concurrently with the
    /// video render instead of waiting for it.
    private func transcribeFromRaw(
        context: PacketContext,
        streamingTranscript: Task<StreamingTranscriptResult?, Never>? = nil
    ) async -> (result: TranscriptResult, notes: [String], timings: [ProcessingStageTiming]) {
        var notes: [String] = []
        var timings: [ProcessingStageTiming] = []

        // Streamed transcription (chunks transcribed while the user was still recording)
        // replaces the full offline pass when it produced real text; awaiting it here only
        // costs the final partial chunk, which overlaps the video branch. An empty or
        // failed stream falls through to the offline transcription below.
        if let streamingTranscript {
            let streamedStart = Date()
            if let streamed = await streamingTranscript.value, streamed.isUsable {
                let markdown = "# Transcript\n\n" + streamed.text + "\n"
                try? markdown.write(to: context.transcriptURL, atomically: true, encoding: .utf8)
                timings.append(processingTiming("transcribe-streamed-tail", startedAt: streamedStart))
                SynPerf.log("streamed transcript finalize (\(streamed.chunkCount) chunks)", seconds: Date().timeIntervalSince(streamedStart))
                return (
                    TranscriptResult(
                        markdown: markdown,
                        provider: streamed.provider,
                        model: streamed.model,
                        notes: streamed.notes
                    ),
                    notes,
                    timings
                )
            }
            notes.append("Streamed transcription was unavailable or empty; ran the full offline transcription instead.")
        }

        let transcriptResult: TranscriptResult
        let transcriptionStart = Date()
        do {
            transcriptResult = try await transcriptionService.transcribe(videoURL: context.rawRecordingURL, context: context)
        } catch {
            notes.append("Transcription failed: \(error.localizedDescription)")
            let markdown = """
            # Transcript

            Local Whisper transcription failed.

            Error: \(error.localizedDescription)
            """
            try? markdown.write(to: context.transcriptURL, atomically: true, encoding: .utf8)
            transcriptResult = TranscriptResult(
                markdown: markdown,
                provider: "local-whisper.cpp",
                model: "unavailable",
                notes: [error.localizedDescription]
            )
        }
        timings.append(processingTiming("transcribe-local-whisper", startedAt: transcriptionStart))

        return (transcriptResult, notes, timings)
    }

    private func makeManifest(
        context: PacketContext,
        duration: TimeInterval,
        capture: CaptureSourceMetadata,
        transcriptResult: TranscriptResult,
        framePlanningResult: FramePlanningResult,
        summaryResult: SummaryResult,
        processingNotes: [String],
        pauses: [PauseInterval],
        processedVideo: ProcessedVideoResult,
        hasActiveWindowSamples: Bool,
        stageTimings: [ProcessingStageTiming] = []
    ) -> PacketManifest {
        let hasRawCaptureSession = FileManager.default.fileExists(atPath: context.rawCaptureSessionURL.path)
        let usesActiveWindowTimeline = capture.mode == CaptureMode.activeWindowFollow.rawValue && hasActiveWindowSamples
        return PacketManifest(
            schemaVersion: 1,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
            createdAt: context.createdAt,
            duration: duration,
            capture: capture,
            files: PacketFiles(
                recording: "recording.mp4",
                transcript: "transcript.md",
                summary: "summary.md",
                agentPrompt: "agent-prompt.md",
                agentPrompts: "agent-prompts",
                framesFull: "frames/full",
                framesCompressed: "frames/compressed",
                candidateMetadata: "frames/candidates/metadata.json",
                rawRecording: "raw/recording-source.mp4",
                rawCaptureSession: hasRawCaptureSession ? "raw/capture-session.json" : nil,
                pointerEvents: "raw/pointer-events.json",
                annotations: processedVideo.annotations.isEmpty ? nil : "raw/annotations.json",
                activeWindowSamples: hasActiveWindowSamples ? "raw/active-window-samples.json" : nil,
                zip: context.zipURL.path,
                rawZip: FileManager.default.fileExists(atPath: context.rawZipURL.path) ? context.rawZipURL.path : nil,
                editedRecording: FileManager.default.fileExists(atPath: context.folderURL.appendingPathComponent("recording-edited.mp4").path) ? context.folderURL.appendingPathComponent("recording-edited.mp4").path : nil,
                compactZip: nil,
                projectContext: FileManager.default.fileExists(atPath: context.projectContextURL.path) ? "project-context.md" : nil,
                semanticSegments: FileManager.default.fileExists(atPath: context.semanticSegmentsURL.path) ? "semantic-segments.json" : nil,
                semanticTimeline: FileManager.default.fileExists(atPath: context.semanticTimelineURL.path) ? "semantic-timeline.md" : nil
            ),
            processing: PacketProcessing(
                transcriptionProvider: transcriptResult.provider,
                transcriptionModel: transcriptResult.model,
                frameSelectionProvider: framePlanningResult.provider,
                frameSelectionModel: framePlanningResult.model,
                summaryProvider: summaryResult.provider,
                summaryModel: summaryResult.model,
                status: packetStatus(for: processingNotes).rawValue,
                notes: processingNotes,
                stageTimings: stageTimings.isEmpty ? nil : stageTimings
            ),
            pauses: pauses,
            pointerEventCount: processedVideo.pointerEvents.count,
            pointerMapping: makePointerMapping(
                processedVideo: processedVideo,
                usesActiveWindowTimeline: usesActiveWindowTimeline
            ),
            annotationCount: processedVideo.annotations.count,
            annotationMapping: makeAnnotationMapping(processedVideo: processedVideo),
            agentPromptProfile: defaultPromptProfile.rawValue
        )
    }

    private func makePointerMapping(
        processedVideo: ProcessedVideoResult,
        usesActiveWindowTimeline: Bool
    ) -> PointerMappingMetadata {
        let mappedCount = processedVideo.pointerEvents.filter { $0.videoCoordinates != nil }.count
        let unmappedCount = processedVideo.pointerEvents.count - mappedCount
        let staticPadding = usesActiveWindowTimeline || processedVideo.notes.contains(where: { $0.contains("24 px padded") })
            ? 24.0
            : 0.0

        return PointerMappingMetadata(
            sourceCoordinateSpace: "macOS global screen points from NSEvent.mouseLocation",
            videoCoordinateSpace: "final recording pixels with origin at top-left",
            renderSize: processedVideo.renderSize,
            mappedEventCount: mappedCount,
            unmappedEventCount: unmappedCount,
            renderedClickCount: processedVideo.renderedClickCount,
            staticPadding: staticPadding,
            usesActiveWindowTimeline: usesActiveWindowTimeline
        )
    }

    private func makeAnnotationMapping(processedVideo: ProcessedVideoResult) -> AnnotationMappingMetadata? {
        guard !processedVideo.annotations.isEmpty else {
            return nil
        }

        let mappedCount = processedVideo.annotations.filter { $0.videoPoints != nil }.count
        let unmappedCount = processedVideo.annotations.count - mappedCount
        return AnnotationMappingMetadata(
            sourceCoordinateSpace: "macOS global screen points captured from the Syn annotation overlay",
            videoCoordinateSpace: "final recording pixels with origin at top-left",
            renderSize: processedVideo.renderSize,
            mappedStrokeCount: mappedCount,
            unmappedStrokeCount: unmappedCount,
            renderedStrokeCount: processedVideo.renderedAnnotationCount
        )
    }

    private func writeAgentPrompts(context: PacketContext, manifest: PacketManifest) throws -> String {
        try FileManager.default.createDirectory(at: context.agentPromptsURL, withIntermediateDirectories: true)
        var selectedPrompt = ""

        for profile in AgentPromptProfile.allCases {
            let prompt = buildAgentPrompt(context: context, manifest: manifest, profile: profile)
            try prompt.write(
                to: context.agentPromptsURL.appendingPathComponent(profile.fileName),
                atomically: true,
                encoding: .utf8
            )
            if profile == defaultPromptProfile {
                selectedPrompt = prompt
            }
        }

        if selectedPrompt.isEmpty {
            selectedPrompt = buildAgentPrompt(context: context, manifest: manifest, profile: .generalCoding)
        }
        try selectedPrompt.write(to: context.agentPromptURL, atomically: true, encoding: .utf8)
        return selectedPrompt
    }

    private func buildAgentPrompt(
        context: PacketContext,
        manifest: PacketManifest,
        profile: AgentPromptProfile
    ) -> String {
        let summaryExcerpt = excerpt(
            readTextIfPresent(context.summaryURL),
            maxCharacters: 10_000,
            fallback: "Summary was not available. Read `summary.md` in the packet folder if it appears after retry."
        )
        // The spoken transcript is the user's authoritative intent, so it gets a larger budget
        // than the derived summary and is presented first below.
        let transcriptExcerpt = excerpt(
            readTextIfPresent(context.transcriptURL),
            maxCharacters: 12_000,
            fallback: "Transcript was not available. Read `transcript.md` in the packet folder if it appears after retry."
        )
        let projectContextExcerpt = excerpt(
            readTextIfPresent(context.projectContextURL),
            maxCharacters: 4_000,
            fallback: "No project context folder was configured for this packet."
        )
        let semanticTimelineExcerpt = excerpt(
            readTextIfPresent(context.semanticTimelineURL),
            maxCharacters: 4_000,
            fallback: "Semantic topic segments were not available for this packet."
        )
        let frameReferences = selectedFrameReferences(context: context)
        let processingNotes = manifest.processing.notes.isEmpty
            ? "- No processing caveats were recorded."
            : manifest.processing.notes.map { "- \($0)" }.joined(separator: "\n")
        let pauseSummary = manifest.pauses.isEmpty
            ? "- No pause intervals."
            : manifest.pauses.enumerated().map { index, pause in
                "- Pause \(index + 1): \(pause.startedAt.formatted(date: .omitted, time: .standard)) to \(pause.endedAt.formatted(date: .omitted, time: .standard))"
            }.joined(separator: "\n")
        let pointerMapping = manifest.pointerMapping.map { mapping in
            """
            - Render size: \(Int(mapping.renderSize.width))x\(Int(mapping.renderSize.height))
            - Pointer events: \(mapping.mappedEventCount) mapped, \(mapping.unmappedEventCount) unmapped, \(mapping.renderedClickCount) click bubbles rendered
            - Static padding: \(Int(mapping.staticPadding)) px
            - Active-window timeline: \(mapping.usesActiveWindowTimeline ? "yes" : "no")
            """
        } ?? "- Pointer mapping metadata was unavailable."
        let annotationMapping = manifest.annotationMapping.map { mapping in
            """
            - Annotations: \(mapping.mappedStrokeCount) mapped, \(mapping.unmappedStrokeCount) unmapped, \(mapping.renderedStrokeCount) drawn overlays rendered
            - Annotation source coordinates: \(mapping.sourceCoordinateSpace)
            - Annotation video coordinates: \(mapping.videoCoordinateSpace)
            """
        } ?? "- Annotations: none."
        let processingTimings = processingTimingReferences(manifest.processing.stageTimings ?? [])
        let workflowSteps = profile.workflowSteps.enumerated()
            .map { index, step in "\(index + 1). \(step)" }
            .joined(separator: "\n")
        let promptProfiles = AgentPromptProfile.allCases.map { candidate in
            let marker = candidate == profile ? "selected" : "available"
            return "- \(candidate.title) (\(marker)): `agent-prompts/\(candidate.fileName)` - \(candidate.detail)"
        }.joined(separator: "\n")

        return """
        # Syn Feedback Packet - \(profile.title)

        Start with the Summary and Transcript below — they are the substance of this review. Packet locations, files, and capture/processing metadata follow further down. \(profile.openingInstruction)

        ## Summary

        \(summaryExcerpt)

        ## Transcript Excerpt

        Primary signal — prioritize what the user says. The spoken transcript is the authoritative record of what the user wants. Treat it as the primary intent and treat the summary, selected frames, and `recording.mp4` as corroborating evidence that confirms or locates what the user said.

        \(transcriptExcerpt)

        ## How To Use This Packet

        \(workflowSteps)

        \(profile.additionalSections)

        ## Packet Locations

        Packet title: `\(context.title)`

        Packet folder: `\(context.folderURL.path)`

        Shareable zip: `\(context.zipURL.path)`

        The zip is the normal handoff artifact. The packet folder is the source of truth and may contain local-only raw recovery files under `raw/`; do not ask the user for those unless retry/debugging requires them.

        ## Prompt Profile

        Selected profile: \(profile.title) (`\(profile.rawValue)`)

        \(promptProfiles)

        ## Packet Files

        - `recording.mp4`: processed final recording with cursor/click overlays where available
        - `transcript.md`: local Whisper transcript
        - `summary.md`: coding-agent summary. May be generating in the background — check `progress.md`; it is replaced by richer tiers as they finish, so re-read it if `progress.md` is not yet complete
        - `progress.md`: live finalize status (what is ready, summary tiers, zip status)
        - `summaries/`: per-tier summary outputs (fast / balanced / full)
        - `manifest.json`: capture, processing, frame, pointer, and retry metadata
        - `agent-prompts/`: alternate agent prompt profiles
        - `project-context.md`: optional local project metadata snapshot when configured
        - `semantic-segments.json`: timestamped topic boundaries derived from the semantic frame plan
        - `semantic-timeline.md`: readable topic timeline for quick navigation
        - `frames/full/`: selected full-resolution frames
        - `frames/compressed/`: selected downscaled LLM-ready frames
        - `frames/candidates/metadata.json`: sampled/selected frame metadata
        - `raw/annotations.json`: drawing overlay strokes when annotation tools were used

        ## Capture And Processing

        - Duration: \(DurationFormatter.string(from: manifest.duration))
        - Capture mode: \(manifest.capture.mode)
        - Transcription: \(manifest.processing.transcriptionProvider) / \(manifest.processing.transcriptionModel)
        - Frame planning: \(manifest.processing.frameSelectionProvider) / \(manifest.processing.frameSelectionModel ?? "none")
        - Summary: \(manifest.processing.summaryProvider) / \(manifest.processing.summaryModel)
        - Processing status: \(manifest.processing.status)

        ## Processing Notes

        \(processingNotes)

        ## Processing Timings

        \(processingTimings)

        ## Pointer And Pause Metadata

        \(pointerMapping)

        \(annotationMapping)

        \(pauseSummary)

        ## Flagged Elements

        \(flaggedElementReferences(context: context))

        ## Selected Frame References

        \(frameReferences)

        ## Semantic Timeline

        \(semanticTimelineExcerpt)

        ## Project Context

        \(projectContextExcerpt)
        """
    }

    private func flaggedElementReferences(context: PacketContext) -> String {
        let url = context.folderURL.appendingPathComponent("elements/flagged-elements.json")
        guard let data = try? Data(contentsOf: url),
              let elements = try? JSONDecoder.synDecoder.decode([FlaggedElementSnapshot].self, from: data),
              !elements.isEmpty else {
            return "- No UI elements were flagged in this recording."
        }
        return elements.map { element in
            let name = element.label ?? element.value ?? element.identifier ?? "element"
            let role = element.role ?? "unknown-role"
            let app = [element.appName, element.windowTitle].compactMap { $0 }.joined(separator: " — ")
            let video = element.videoBounds.map { "video=(\(Int($0.x)),\(Int($0.y)) \(Int($0.width))x\(Int($0.height)))" } ?? "video=unmapped"
            var details = [
                "\(DurationFormatter.string(from: element.timestamp)): [\(element.index)] \(role) \"\(name)\" in \(app.isEmpty ? "unknown app" : app)",
                video,
                "provider: \(element.provider)"
            ]
            // Web/framework identity (browser.* providers) is the fastest path for an
            // agent to locate the code; surface it inline instead of only in the JSON.
            if let selector = element.web?.selector { details.append("DOM: \(selector)") }
            if let component = element.framework?.componentName { details.append("component: <\(component)>") }
            if let source = element.framework?.source { details.append("source: \(source)") }
            if let route = element.web?.route ?? element.web?.url { details.append("route: \(route)") }
            return "- \(details.joined(separator: "; ")). A highlight is burned into recording.mp4 at this timestamp. Full metadata: elements/flagged-elements.json"
        }.joined(separator: "\n")
    }

    private func selectedFrameReferences(context: PacketContext) -> String {
        guard let data = try? Data(contentsOf: context.candidateMetadataURL),
              let frames = try? JSONDecoder.synDecoder.decode([CandidateFrameMetadata].self, from: data) else {
            return "- Selected frame metadata was unavailable."
        }

        let selected = frames.filter(\.selected)
        guard !selected.isEmpty else {
            return "- No selected frames were available."
        }

        return selected.prefix(12).map { frame in
            let fullPath = frame.fullPath ?? "none"
            let compressedPath = frame.compressedPath ?? "none"
            let timestamp = DurationFormatter.string(from: frame.timestamp)
            let titleParts = [frame.appName, frame.windowTitle]
                .compactMap { value -> String? in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " - ")
            let context = titleParts.isEmpty ? "unknown app/window" : titleParts
            return "- \(timestamp): `\(fullPath)` and `\(compressedPath)`; \(context); reason: \(frame.reason)"
        }.joined(separator: "\n")
    }

    private func processingTiming(_ name: String, startedAt: Date) -> ProcessingStageTiming {
        ProcessingStageTiming(
            name: name,
            durationSeconds: max(0, Date().timeIntervalSince(startedAt))
        )
    }

    private func stageTimingSummary(_ timings: [ProcessingStageTiming]) -> String {
        guard !timings.isEmpty else {
            return "Processing timings were not recorded."
        }

        let total = timings.reduce(0) { $0 + $1.durationSeconds }
        let topStages = timings
            .sorted { $0.durationSeconds > $1.durationSeconds }
            .prefix(4)
            .map { "\($0.name)=\(String(format: "%.2fs", $0.durationSeconds))" }
            .joined(separator: ", ")
        return "Processing timings: total \(String(format: "%.2fs", total)); top stages: \(topStages)."
    }

    private func processingTimingReferences(_ timings: [ProcessingStageTiming]) -> String {
        guard !timings.isEmpty else {
            return "- Processing stage timings were not recorded."
        }

        let total = timings.reduce(0) { $0 + $1.durationSeconds }
        let rows = timings.map { timing in
            "- \(timing.name): \(String(format: "%.2fs", timing.durationSeconds))"
        }.joined(separator: "\n")
        return """
        - Total measured processing time: \(String(format: "%.2fs", total))
        \(rows)
        """
    }

    private func readTextIfPresent(_ url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    private func excerpt(_ text: String?, maxCharacters: Int, fallback: String) -> String {
        guard let text else {
            return fallback
        }

        if text.count <= maxCharacters {
            return text
        }

        let end = text.index(text.startIndex, offsetBy: maxCharacters)
        return "\(text[..<end])\n\n[Truncated in prompt. Open the packet file for the full content.]"
    }

    private func copyToClipboard(_ string: String, folderURL: URL) {
        // The full prompt is written to agent-prompt.md; the clipboard gets the concise,
        // text-only handoff that points the agent at the summary + agent prompt.
        _ = PacketClipboard.copyHandoff(folderURL: folderURL)
    }

    private static func copyFinalRecording(rawURL: URL, finalURL: URL) throws {
        try VideoUtilities.copyFinalRecording(rawURL: rawURL, finalURL: finalURL)
    }

    private func existingOrFailedTranscript(context: PacketContext, error: Error) -> String {
        if let existing = readTextIfPresent(context.transcriptURL) {
            return existing
        }

        return """
        # Transcript

        Transcription did not complete before processing failed.

        Error: \(error.localizedDescription)
        """
    }

    private func partialFailureSummary(context: PacketContext, error: Error) -> String {
        """
        # Summary

        ## Overview

        Syn could not finish processing this recording, but it kept the raw recording and recovery metadata so the packet can be retried from History.

        ## Prioritized Feedback And Issues

        - P0: Retry processing in Syn before treating this packet as complete.
        - P1: If retry fails again, inspect `raw/recording-source.mp4`, `raw/capture-session.json`, and `raw/pointer-events.json`.

        ## Timestamped Observations

        - Timestamped observations were not generated because processing failed before frame selection and summary generation completed.

        ## Frame References

        - No selected frames were available in this partial packet.

        ## Suggested Implementation Tasks

        - Use Syn History -> Retry Processing for this packet.
        - If the raw recording content is safe, keep this packet folder available for debugging the failed processing stage.

        ## Open Questions And Uncertainty

        - Processing error: \(error.localizedDescription)
        - Packet folder: `\(context.folderURL.path)`
        - Raw recording: `raw/recording-source.mp4`
        """
    }

    private func writeProjectContextIfConfigured(context: PacketContext, notes: inout [String]) throws {
        guard let projectContextFolderURL else {
            try? FileManager.default.removeItem(at: context.projectContextURL)
            return
        }

        guard FileManager.default.fileExists(atPath: projectContextFolderURL.path) else {
            notes.append("Project context skipped: configured folder was not found: \(projectContextFolderURL.path)")
            try? FileManager.default.removeItem(at: context.projectContextURL)
            return
        }

        do {
            let result = try ProjectContextService.writeContext(
                for: projectContextFolderURL,
                to: context.projectContextURL
            )
            notes.append("Project context snapshot added for \(result.projectName).")
        } catch {
            notes.append("Project context snapshot failed: \(error.localizedDescription)")
        }
    }

    private func makeSemanticSegmentsIfNeeded(
        _ existingSegments: [SemanticSegment],
        selectedFrames: [CandidateFrameMetadata],
        duration: TimeInterval,
        source: String
    ) -> [SemanticSegment] {
        if !existingSegments.isEmpty {
            return existingSegments
        }

        let sortedFrames = selectedFrames.sorted { $0.timestamp < $1.timestamp }
        guard !sortedFrames.isEmpty else {
            return []
        }

        return sortedFrames.enumerated().map { index, frame in
            let previousTimestamp = index > 0 ? sortedFrames[index - 1].timestamp : 0
            let nextTimestamp = index + 1 < sortedFrames.count ? sortedFrames[index + 1].timestamp : max(duration, frame.timestamp)
            let start = index == 0 ? 0 : (previousTimestamp + frame.timestamp) / 2
            let end = index + 1 == sortedFrames.count ? max(duration, frame.timestamp) : (frame.timestamp + nextTimestamp) / 2
            let windowTitle = frame.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let appName = frame.appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = !windowTitle.isEmpty ? windowTitle : (!appName.isEmpty ? appName : "Topic \(index + 1)")

            return SemanticSegment(
                index: index + 1,
                startTime: max(0, start),
                endTime: max(max(0, start), end),
                title: title,
                summary: "Representative frame at \(DurationFormatter.string(from: frame.timestamp)) selected because \(frame.reason).",
                representativeFrameTimestamp: frame.timestamp,
                framePaths: [frame.fullPath, frame.compressedPath].compactMap { $0 },
                source: source
            )
        }
    }

    private func writeSemanticArtifacts(context: PacketContext, segments: [SemanticSegment]) throws {
        guard !segments.isEmpty else {
            try? FileManager.default.removeItem(at: context.semanticSegmentsURL)
            try? FileManager.default.removeItem(at: context.semanticTimelineURL)
            return
        }

        try JSONEncoder.synEncoder.encode(segments).write(to: context.semanticSegmentsURL)
        try semanticTimelineMarkdown(context: context, segments: segments)
            .write(to: context.semanticTimelineURL, atomically: true, encoding: .utf8)
    }

    private func semanticTimelineMarkdown(context: PacketContext, segments: [SemanticSegment]) -> String {
        let rows = segments.map { segment in
            let start = DurationFormatter.string(from: segment.startTime)
            let end = DurationFormatter.string(from: segment.endTime)
            let frameList = segment.framePaths.isEmpty
                ? "No representative frame file."
                : segment.framePaths.map { "`\($0)`" }.joined(separator: ", ")
            return """
            ## \(segment.index). \(segment.title)

            Time: \(start) - \(end)

            Representative frame: \(frameList)

            \(segment.summary)

            Source: \(segment.source)
            """
        }.joined(separator: "\n\n")

        return """
        # Semantic Timeline

        Packet: `\(context.title)`

        These segments are derived from the semantic frame plan and visual-change candidates. Use them as navigation aids, then verify details against `recording.mp4`, `transcript.md`, and selected frame files.

        \(rows)
        """
    }

    private func prepareDerivedOutputs(context: PacketContext) throws {
        try context.ensureDerivedDirectories()

        [
            context.finalRecordingURL,
            context.transcriptURL,
            context.summaryURL,
            context.agentPromptURL,
            context.projectContextURL,
            context.semanticSegmentsURL,
            context.semanticTimelineURL,
            context.manifestURL,
            context.zipURL
        ].forEach { url in
            try? FileManager.default.removeItem(at: url)
        }

        [
            context.fullFramesURL,
            context.compressedFramesURL,
            context.candidateMetadataURL.deletingLastPathComponent(),
            context.agentPromptsURL
        ].forEach { url in
            try? FileManager.default.removeItem(at: url)
        }

        try context.ensureDerivedDirectories()
    }

    private func loadManifest(context: PacketContext) -> PacketManifest? {
        guard let data = try? Data(contentsOf: context.manifestURL) else {
            return nil
        }
        return try? JSONDecoder.synDecoder.decode(PacketManifest.self, from: data)
    }

    private func loadRawCaptureSession(context: PacketContext) -> RawCaptureSession? {
        guard let data = try? Data(contentsOf: context.rawCaptureSessionURL) else {
            return nil
        }
        return try? JSONDecoder.synDecoder.decode(RawCaptureSession.self, from: data)
    }

    private func retryCaptureMetadata(
        context: PacketContext,
        manifest: PacketManifest?,
        rawSession: RawCaptureSession?
    ) async throws -> CaptureSourceMetadata {
        if let manifest {
            return manifest.capture
        }

        if let rawSession {
            return rawSession.capture
        }

        return try await fallbackCaptureMetadata(context: context)
    }

    private func fallbackCaptureMetadata(context: PacketContext) async throws -> CaptureSourceMetadata {
        let asset = AVURLAsset(url: context.rawRecordingURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let naturalSize = try await videoTracks.first?.load(.naturalSize) ?? .zero
        let mode = inferredCaptureMode(from: context.title)

        return CaptureSourceMetadata(
            mode: mode.rawValue,
            displayID: nil,
            windowID: nil,
            appName: nil,
            windowTitle: nil,
            sourceRect: naturalSize == .zero ? nil : CodableRect(CGRect(origin: .zero, size: naturalSize)),
            outputSize: naturalSize == .zero ? nil : CodableSize(naturalSize),
            notes: ["Recovered with fallback capture metadata because manifest and raw/capture-session.json were missing."]
        )
    }

    private func inferredCaptureMode(from title: String) -> CaptureMode {
        let lowercased = title.lowercased()
        if lowercased.contains("smart") && lowercased.contains("region") {
            return .smartRegion
        }
        if lowercased.contains("region") {
            return .region
        }
        if lowercased.contains("select") || lowercased.contains("window") {
            return .selectedWindow
        }
        if lowercased.contains("active") {
            return .activeWindowFollow
        }
        return .screen
    }

    private func loadActiveWindowSamples(context: PacketContext, manifest: PacketManifest?) -> [ActiveWindowSample] {
        let url: URL
        if let relativePath = manifest?.files.activeWindowSamples {
            url = context.folderURL.appendingPathComponent(relativePath)
        } else {
            url = context.activeWindowSamplesURL
        }

        guard let data = try? Data(contentsOf: url),
              let samples = try? JSONDecoder.synDecoder.decode([ActiveWindowSample].self, from: data) else {
            return []
        }
        return samples
    }

    private func rawSegmentURLs(context: PacketContext) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: context.rawSegmentsURL,
            includingPropertiesForKeys: nil
        )) ?? []

        return contents
            .filter { $0.pathExtension.lowercased() == "mp4" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func writeRawRecoveryMetadata(
        context: PacketContext,
        capture: CaptureSourceMetadata,
        pointerEvents: [PointerEvent],
        annotations: [AnnotationStroke],
        activeWindowSamples: [ActiveWindowSample],
        pauses: [PauseInterval]
    ) throws {
        try context.ensureDerivedDirectories()

        let rawSession = RawCaptureSession(
            schemaVersion: 1,
            packetID: context.id,
            title: context.title,
            createdAt: context.createdAt,
            capture: capture,
            pauses: pauses
        )
        try JSONEncoder.synEncoder.encode(rawSession).write(to: context.rawCaptureSessionURL)
        try JSONEncoder.synEncoder.encode(pointerEvents).write(to: context.pointerEventsURL)
        try JSONEncoder.synEncoder.encode(annotations).write(to: context.annotationEventsURL)

        if !activeWindowSamples.isEmpty {
            try JSONEncoder.synEncoder.encode(activeWindowSamples).write(to: context.activeWindowSamplesURL)
        }
    }

    private func pruneUnselectedFrameFiles(
        _ frames: [CandidateFrameMetadata],
        context: PacketContext
    ) -> [CandidateFrameMetadata] {
        frames.map { frame in
            guard !frame.selected else {
                return frame
            }

            var pruned = frame
            if let fullPath = frame.fullPath {
                try? FileManager.default.removeItem(at: context.folderURL.appendingPathComponent(fullPath))
                pruned.fullPath = nil
                pruned.fullSize = nil
                pruned.fullBytes = nil
            }
            if let compressedPath = frame.compressedPath {
                try? FileManager.default.removeItem(at: context.folderURL.appendingPathComponent(compressedPath))
                pruned.compressedPath = nil
                pruned.compressedSize = nil
                pruned.compressedBytes = nil
            }
            return pruned
        }
    }

    private func packetStatus(for notes: [String]) -> PacketStatus {
        let warningNeedles = [
            "processing failed",
            "rendering failed",
            "frame extraction failed",
            "transcription failed",
            "summary failed",
            "zip creation failed",
            "skipped because no",
            "unavailable",
            "error:",
            "could not",
            "raw copy"
        ]

        let hasWarning = notes.contains { note in
            let lowercased = note.lowercased()
            return warningNeedles.contains { lowercased.contains($0) }
        }

        return hasWarning ? .partial : .succeeded
    }
}
