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
        pauses: [PauseInterval]
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
            initialStageTimings: stageTimings
        )
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
        initialStageTimings: [ProcessingStageTiming] = []
    ) async throws -> PacketProcessingResult {
        var processingNotes: [String] = []
        var stageTimings = initialStageTimings
        let prepareStart = Date()
        try prepareDerivedOutputs(context: context)
        try writeProjectContextIfConfigured(context: context, notes: &processingNotes)
        stageTimings.append(processingTiming("prepare-derived-outputs-and-project-context", startedAt: prepareStart))

        let processedVideo: ProcessedVideoResult
        let renderStart = Date()
        do {
            processedVideo = try await VideoUtilities.renderProcessedRecording(
                rawURL: context.rawRecordingURL,
                finalURL: context.finalRecordingURL,
                capture: capture,
                pointerEvents: pointerEvents,
                annotations: annotations,
                activeWindowSamples: activeWindowSamples
            )
            processingNotes.append(contentsOf: processedVideo.notes)
            if processedVideo.renderedClickCount > 0 {
                processingNotes.append("Rendered \(processedVideo.renderedClickCount) click bubble overlays into recording.mp4.")
            }
            if processedVideo.renderedAnnotationCount > 0 {
                processingNotes.append("Rendered \(processedVideo.renderedAnnotationCount) annotation overlays into recording.mp4.")
            }
        } catch {
            try VideoUtilities.copyFinalRecording(rawURL: context.rawRecordingURL, finalURL: context.finalRecordingURL)
            processingNotes.append("Processed video rendering failed; recording.mp4 is a raw copy. Error: \(error.localizedDescription)")
            processedVideo = ProcessedVideoResult(
                duration: duration,
                renderSize: capture.outputSize ?? CodableSize(width: 0, height: 0),
                pointerEvents: pointerEvents,
                renderedClickCount: 0,
                annotations: annotations,
                renderedAnnotationCount: 0,
                notes: []
            )
        }
        stageTimings.append(processingTiming("render-processed-video", startedAt: renderStart))

        let overlayMetadataStart = Date()
        try JSONEncoder.synEncoder.encode(processedVideo.pointerEvents).write(to: context.pointerEventsURL)
        try JSONEncoder.synEncoder.encode(processedVideo.annotations).write(to: context.annotationEventsURL)
        stageTimings.append(processingTiming("write-pointer-and-annotation-metadata", startedAt: overlayMetadataStart))

        let frameResult: FrameExtractionResult
        let frameExtractionStart = Date()
        do {
            frameResult = try await frameExtractor.extractFrames(
                from: context.finalRecordingURL,
                context: context,
                capture: capture,
                activeWindowSamples: activeWindowSamples
            )
        } catch {
            processingNotes.append("Frame extraction failed: \(error.localizedDescription)")
            let emptyFrames: [CandidateFrameMetadata] = []
            try JSONEncoder.synEncoder.encode(emptyFrames).write(to: context.candidateMetadataURL)
            frameResult = FrameExtractionResult(candidateFrames: [], selectedFrames: [], duration: duration)
        }
        stageTimings.append(processingTiming("extract-frames-and-ocr", startedAt: frameExtractionStart))

        let transcriptResult: TranscriptResult
        let transcriptionStart = Date()
        do {
            transcriptResult = try await transcriptionService.transcribe(videoURL: context.finalRecordingURL, context: context)
        } catch {
            processingNotes.append("Transcription failed: \(error.localizedDescription)")
            let markdown = """
            # Transcript

            Local Whisper transcription failed.

            Error: \(error.localizedDescription)
            """
            try markdown.write(to: context.transcriptURL, atomically: true, encoding: .utf8)
            transcriptResult = TranscriptResult(
                markdown: markdown,
                provider: "local-whisper.cpp",
                model: "unavailable",
                notes: [error.localizedDescription]
            )
        }
        stageTimings.append(processingTiming("transcribe-local-whisper", startedAt: transcriptionStart))

        let framePlanningStart = Date()
        var framePlanningResult = await framePlanningService.planFrames(
            extraction: frameResult,
            transcript: transcriptResult.markdown,
            context: context
        )
        stageTimings.append(processingTiming("plan-semantic-frames-openai", startedAt: framePlanningStart))
        processingNotes.append(contentsOf: framePlanningResult.notes)
        let semanticArtifactsStart = Date()
        framePlanningResult.candidateFrames = pruneUnselectedFrameFiles(
            framePlanningResult.candidateFrames,
            context: context
        )
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

        let summaryStart = Date()
        let summaryResult = await aiProviderService.createSummary(
            transcript: transcriptResult.markdown,
            frames: framePlanningResult.selectedFrames,
            context: context
        )
        stageTimings.append(processingTiming("summarize-claude", startedAt: summaryStart))
        processingNotes.append(contentsOf: transcriptResult.notes)
        processingNotes.append(contentsOf: summaryResult.notes)
        try summaryResult.markdown.write(to: context.summaryURL, atomically: true, encoding: .utf8)

        let manifestPromptStart = Date()
        var manifest = makeManifest(
            context: context,
            duration: duration,
            capture: capture,
            transcriptResult: transcriptResult,
            framePlanningResult: framePlanningResult,
            summaryResult: summaryResult,
            processingNotes: processingNotes,
            pauses: pauses,
            processedVideo: processedVideo,
            hasActiveWindowSamples: !activeWindowSamples.isEmpty,
            stageTimings: stageTimings
        )

        try JSONEncoder.synEncoder.encode(manifest).write(to: context.manifestURL)
        var prompt = try writeAgentPrompts(context: context, manifest: manifest)
        stageTimings.append(processingTiming("write-manifest-and-agent-prompts", startedAt: manifestPromptStart))

        let zipStart = Date()
        do {
            try ZipService.createZip(for: context)
        } catch {
            processingNotes.append("Zip creation failed: \(error.localizedDescription)")
        }
        stageTimings.append(processingTiming("create-default-zip", startedAt: zipStart))
        processingNotes.append(stageTimingSummary(stageTimings))

        manifest = makeManifest(
            context: context,
            duration: duration,
            capture: capture,
            transcriptResult: transcriptResult,
            framePlanningResult: framePlanningResult,
            summaryResult: summaryResult,
            processingNotes: processingNotes,
            pauses: pauses,
            processedVideo: processedVideo,
            hasActiveWindowSamples: !activeWindowSamples.isEmpty,
            stageTimings: stageTimings
        )
        try JSONEncoder.synEncoder.encode(manifest).write(to: context.manifestURL)
        prompt = try writeAgentPrompts(context: context, manifest: manifest)

        copyToClipboard(prompt, folderURL: context.folderURL)

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
        let transcriptExcerpt = excerpt(
            readTextIfPresent(context.transcriptURL),
            maxCharacters: 6_000,
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

        You are receiving an implementation-agent feedback packet generated from a narrated screen recording. \(profile.openingInstruction)

        ## Packet Locations

        Packet title: `\(context.title)`

        Packet folder: `\(context.folderURL.path)`

        Shareable zip: `\(context.zipURL.path)`

        The zip is the normal handoff artifact. The packet folder is the source of truth and may contain local-only raw recovery files under `raw/`; do not ask the user for those unless retry/debugging requires them.

        ## Prompt Profile

        Selected profile: \(profile.title) (`\(profile.rawValue)`)

        \(promptProfiles)

        ## How To Use This Packet

        \(workflowSteps)

        \(profile.additionalSections)

        ## Packet Files

        - `recording.mp4`: processed final recording with cursor/click overlays where available
        - `transcript.md`: local Whisper transcript
        - `summary.md`: Claude Opus or local fallback coding-agent summary
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

        ## Selected Frame References

        \(frameReferences)

        ## Semantic Timeline

        \(semanticTimelineExcerpt)

        ## Project Context

        \(projectContextExcerpt)

        ## Summary

        \(summaryExcerpt)

        ## Transcript Excerpt

        \(transcriptExcerpt)
        """
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
        _ = PacketClipboard.copyPacket(prompt: string, folderURL: folderURL)
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
