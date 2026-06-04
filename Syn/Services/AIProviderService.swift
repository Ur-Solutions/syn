import Foundation

struct SummaryResult: Sendable {
    var markdown: String
    var provider: String
    var model: String
    var notes: [String]
}

enum SummaryModelProvider: String, Sendable {
    case anthropic
    case openai
}

/// One rung in a progressive summary lineup: a model + an output-token budget. The fast tier
/// (small budget) lands almost immediately; richer tiers replace it as they finish.
struct SummaryTier: Sendable {
    var label: String          // "fast" | "balanced" | "full"
    var provider: SummaryModelProvider
    var model: String
    var maxTokens: Int

    /// Higher rung wins when promoting the canonical summary.md.
    var rank: Int {
        switch label {
        case "fast": 0
        case "balanced": 1
        default: 2
        }
    }
}

enum SummaryLineups {
    /// The progressive summary lineup: a fast first pass, a balanced pass, then the full pass.
    /// Edit `~/Library/Application Support/Syn/summary.json` to change models / token budgets at
    /// runtime — e.g. set the "full" tier model to `claude-sonnet-4-6` instead of
    /// `claude-opus-4-8`. (gpt-5.5 has no nano/mini variants, so the small rungs use gpt-5.4.)
    static let `default`: [SummaryTier] = [
        SummaryTier(label: "fast", provider: .openai, model: "gpt-5.4-nano", maxTokens: 500),
        SummaryTier(label: "balanced", provider: .openai, model: "gpt-5.4-mini", maxTokens: 1000),
        SummaryTier(label: "full", provider: .anthropic, model: "claude-opus-4-8", maxTokens: 5000)
    ]
}

/// Editable lineup configuration. The app reads `~/Library/Application Support/Syn/summary.json`
/// at the start of every deferred finalize, so models / token budgets can be swapped between
/// captures without rebuilding or relaunching. A documented template is written on first use.
struct SummaryConfig: Codable {
    struct Tier: Codable {
        var label: String
        var provider: String   // "anthropic" | "openai"
        var model: String
        var maxTokens: Int
    }
    var lineup: [Tier]?

    func tiers(fallback: [SummaryTier]) -> [SummaryTier] {
        guard let raw = lineup, !raw.isEmpty else { return fallback }
        return raw.map {
            SummaryTier(
                label: $0.label,
                provider: $0.provider.lowercased() == "openai" ? .openai : .anthropic,
                model: $0.model,
                maxTokens: $0.maxTokens
            )
        }
    }
}

enum SummaryConfigStore {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Syn/summary.json")
    }

    /// Load the lineup config, writing a template populated with the built-in default on first
    /// use. Re-read per capture so edits take effect on the next recording.
    static func load() -> SummaryConfig {
        ensureTemplate()
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(SummaryConfig.self, from: data) else {
            return SummaryConfig(lineup: nil)
        }
        return config
    }

    private static func ensureTemplate() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let template: [String: Any] = [
            "lineup": SummaryLineups.default.map {
                ["label": $0.label, "provider": $0.provider.rawValue, "model": $0.model, "maxTokens": $0.maxTokens]
            }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: template, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: fileURL)
        }
    }
}

final class AIProviderService {
    /// Generate one summary for a specific tier. Dispatches to the matching provider and degrades
    /// to the local fallback when the key is missing or the call fails, so a single tier never
    /// blocks the rest of the lineup.
    func generateSummary(
        tier: SummaryTier,
        transcript: String,
        frames: [CandidateFrameMetadata],
        context: PacketContext,
        anthropicKey: String?,
        openAIKey: String?
    ) async -> SummaryResult {
        switch tier.provider {
        case .anthropic:
            guard let key = anthropicKey else {
                return SummaryResult(
                    markdown: fallbackSummary(transcript: transcript, frames: frames),
                    provider: "local-fallback",
                    model: "none",
                    notes: ["\(tier.label) summary skipped: no Anthropic API key was available."]
                )
            }
            do {
                let markdown = try await callClaude(
                    key: key, model: tier.model, maxTokens: tier.maxTokens,
                    transcript: transcript, frames: frames, context: context
                )
                return SummaryResult(markdown: markdown, provider: "anthropic", model: tier.model, notes: [])
            } catch {
                return SummaryResult(
                    markdown: fallbackSummary(transcript: transcript, frames: frames),
                    provider: "local-fallback",
                    model: "none",
                    notes: ["\(tier.label) summary failed (\(tier.model)): \(error.localizedDescription)"]
                )
            }
        case .openai:
            guard let key = openAIKey else {
                return SummaryResult(
                    markdown: fallbackSummary(transcript: transcript, frames: frames),
                    provider: "local-fallback",
                    model: "none",
                    notes: ["\(tier.label) summary skipped: no OpenAI API key was available."]
                )
            }
            do {
                let markdown = try await callOpenAISummary(
                    key: key, model: tier.model, maxTokens: tier.maxTokens,
                    transcript: transcript, frames: frames, context: context
                )
                return SummaryResult(markdown: markdown, provider: "openai", model: tier.model, notes: [])
            } catch {
                return SummaryResult(
                    markdown: fallbackSummary(transcript: transcript, frames: frames),
                    provider: "local-fallback",
                    model: "none",
                    notes: ["\(tier.label) summary failed (\(tier.model)): \(error.localizedDescription)"]
                )
            }
        }
    }

    func createSummary(
        transcript: String,
        frames: [CandidateFrameMetadata],
        context: PacketContext
    ) async -> SummaryResult {
        guard let key = SecretStore.readAnthropicKey() else {
            let fallback = fallbackSummary(transcript: transcript, frames: frames)
            return SummaryResult(
                markdown: fallback,
                provider: "local-fallback",
                model: "none",
                notes: ["Claude summary skipped because no Anthropic API key was available."]
            )
        }

        do {
            let markdown = try await callClaude(
                key: key, model: "claude-sonnet-4-6", maxTokens: 4000,
                transcript: transcript, frames: frames, context: context
            )
            return SummaryResult(markdown: markdown, provider: "anthropic", model: "claude-sonnet-4-6", notes: [])
        } catch {
            let fallback = fallbackSummary(transcript: transcript, frames: frames)
            return SummaryResult(
                markdown: fallback,
                provider: "local-fallback",
                model: "none",
                notes: ["Claude summary failed: \(error.localizedDescription)"]
            )
        }
    }

    private func callClaude(
        key: String,
        model: String,
        maxTokens: Int,
        transcript: String,
        frames: [CandidateFrameMetadata],
        context: PacketContext
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.timeoutInterval = 180
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: Self.claudeRequestBody(
                model: model, maxTokens: maxTokens,
                transcript: transcript, frames: frames, context: context
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "Syn.Anthropic", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]] else {
            return fallbackSummary(transcript: transcript, frames: frames)
        }

        let text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n\n")
        return text.isEmpty ? fallbackSummary(transcript: transcript, frames: frames) : text
    }

    static func summaryPromptForTesting(transcript: String, frames: [CandidateFrameMetadata]) -> String {
        summaryPrompt(transcript: transcript, frames: frames)
    }

    static func claudeRequestBodyForTesting(
        transcript: String,
        frames: [CandidateFrameMetadata],
        context: PacketContext
    ) -> [String: Any] {
        claudeRequestBody(
            model: "claude-sonnet-4-6", maxTokens: 4000,
            transcript: transcript, frames: frames, context: context
        )
    }

    private static func claudeRequestBody(
        model: String,
        maxTokens: Int,
        transcript: String,
        frames: [CandidateFrameMetadata],
        context: PacketContext
    ) -> [String: Any] {
        let selectedFrames = Array(frames.prefix(8))
        var content: [[String: Any]] = [[
            "type": "text",
            "text": summaryPrompt(transcript: transcript, frames: selectedFrames)
        ]]

        for frame in selectedFrames {
            guard let path = frame.compressedPath else {
                continue
            }
            let frameURL = context.folderURL.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: frameURL) else {
                continue
            }
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": data.base64EncodedString()
                ]
            ])
        }

        return [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [[
                "role": "user",
                "content": content
            ]]
        ]
    }

    private func callOpenAISummary(
        key: String,
        model: String,
        maxTokens: Int,
        transcript: String,
        frames: [CandidateFrameMetadata],
        context: PacketContext
    ) async throws -> String {
        let selectedFrames = Array(frames.prefix(8))
        var content: [[String: Any]] = [[
            "type": "input_text",
            "text": Self.summaryPrompt(transcript: transcript, frames: selectedFrames)
        ]]
        for frame in selectedFrames {
            guard let path = frame.compressedPath,
                  let data = try? Data(contentsOf: context.folderURL.appendingPathComponent(path)) else {
                continue
            }
            content.append([
                "type": "input_image",
                "image_url": "data:image/jpeg;base64,\(data.base64EncodedString())"
            ])
        }

        let body: [String: Any] = [
            "model": model,
            "input": [["role": "user", "content": content]],
            "max_output_tokens": maxTokens
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.timeoutInterval = 180
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "Syn.OpenAI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = Self.extractOpenAIOutputText(from: json),
              !text.isEmpty else {
            return fallbackSummary(transcript: transcript, frames: frames)
        }
        return text
    }

    private static func extractOpenAIOutputText(from object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let text = dictionary["output_text"] as? String, !text.isEmpty {
                return text
            }
            if dictionary["type"] as? String == "output_text", let text = dictionary["text"] as? String {
                return text
            }
            for value in dictionary.values {
                if let text = extractOpenAIOutputText(from: value) {
                    return text
                }
            }
        }
        if let array = object as? [Any] {
            let parts = array.compactMap { extractOpenAIOutputText(from: $0) }
            if !parts.isEmpty {
                return parts.joined(separator: "\n")
            }
        }
        return nil
    }

    private static func summaryPrompt(transcript: String, frames: [CandidateFrameMetadata]) -> String {
        """
        You are preparing an implementation-agent feedback packet from a narrated screen recording.

        AUTHORITY AND WEIGHTING (read first):
        - The spoken transcript is the PRIMARY and authoritative source of the user's intent, requests, priorities, and reasoning. Treat what the user SAYS as what they MEAN, and drive every section of your output from the transcript.
        - The selected frames and their metadata (OCR, window titles, pixel-diff, bounds) are SECONDARY, corroborating evidence. Use them only to confirm, locate, illustrate, or timestamp points the user makes in the transcript. Do not introduce a priority, issue, or task that the transcript does not support.
        - When the transcript and the visuals appear to disagree, the transcript wins for intent; record the visual discrepancy under Open Questions And Uncertainty rather than overriding what the user said.
        - If the transcript is silent about something the visuals show, mention it only under Open Questions And Uncertainty, clearly marked as not stated by the user.

        Produce concise markdown using these exact section headings:
        # Summary
        ## Overview
        ## Prioritized Feedback And Issues
        ## Timestamped Observations
        ## Frame References
        ## Suggested Implementation Tasks
        ## Open Questions And Uncertainty

        Use explicit uncertainty when the transcript does not prove something; the frames and metadata are corroboration, not independent intent. Reference frame filenames and timestamps where possible. The attached images are compressed/downscaled JPEGs in the same order as the selected-frame metadata below; raw audio and raw video are not attached.

        PRIMARY SOURCE - Spoken transcript (authoritative; base your deductions on what the user says):
        \(transcript)

        SECONDARY SOURCE - Selected frame metadata (corroborating visuals only):
        Selected frame metadata:
        \(selectedFrameMetadataLines(frames))
        """
    }

    private static func selectedFrameMetadataLines(_ frames: [CandidateFrameMetadata]) -> String {
        if frames.isEmpty {
            return "- No selected frames were available."
        }

        return frames.enumerated().map { index, frame in
            let timestamp = timestampString(frame.timestamp)
            let seconds = String(format: "%.3f", frame.timestamp)
            let fullPath = frame.fullPath ?? "none"
            let compressedPath = frame.compressedPath ?? "none"
            let appName = frame.appName ?? "unknown app"
            let windowTitle = frame.windowTitle ?? "unknown window"
            let diff = frame.pixelDifferenceFromPrevious.map { String(format: "%.3f", $0) } ?? "first selected frame"
            let bounds = frame.captureBounds.map {
                "x=\(Int($0.x)), y=\(Int($0.y)), w=\(Int($0.width)), h=\(Int($0.height))"
            } ?? "unknown"
            let fullSize = frame.fullSize.map {
                "\(Int($0.width))x\(Int($0.height))"
            } ?? "unknown"
            let compressedSize = frame.compressedSize.map {
                "\(Int($0.width))x\(Int($0.height))"
            } ?? "unknown"
            let fullBytes = frame.fullBytes.map(String.init) ?? "unknown"
            let compressedBytes = frame.compressedBytes.map(String.init) ?? "unknown"
            let ocrText = frame.ocrText.map { compactForPrompt($0, maxLength: 500) } ?? "none"
            let ocrConfidence = frame.ocrMeanConfidence.map { String(format: "%.3f", $0) } ?? "unknown"
            let ocrLineCount = frame.ocrObservations?.count ?? 0

            return """
            - Frame \(index + 1): \(timestamp) (\(seconds)s)
              fullPath: \(fullPath)
              compressedPath: \(compressedPath)
              appName: \(appName)
              windowTitle: \(windowTitle)
              selectionReason: \(frame.reason)
              pixelDifferenceFromPrevious: \(diff)
              perceptualHash: \(frame.perceptualHash)
              captureBounds: \(bounds)
              fullSize: \(fullSize), fullBytes: \(fullBytes)
              compressedSize: \(compressedSize), compressedBytes: \(compressedBytes)
              ocrText: \(ocrText)
              ocrMeanConfidence: \(ocrConfidence), ocrLineCount: \(ocrLineCount)
            """
        }.joined(separator: "\n")
    }

    private static func compactForPrompt(_ text: String, maxLength: Int) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: " / ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard oneLine.count > maxLength else {
            return oneLine
        }

        return String(oneLine.prefix(maxLength)) + "..."
    }

    private func fallbackSummary(transcript: String, frames: [CandidateFrameMetadata]) -> String {
        Self.fallbackSummary(transcript: transcript, frames: frames)
    }

    static func fallbackSummary(transcript: String, frames: [CandidateFrameMetadata]) -> String {
        let selectedFrames = Array(frames.prefix(12))
        let frameList = selectedFrames.map { frame -> String in
            let path = frame.fullPath ?? frame.compressedPath ?? "no frame file"
            let titleParts = [frame.appName, frame.windowTitle]
                .compactMap { value -> String? in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .joined(separator: " - ")
            let context = titleParts.isEmpty ? "" : " — \(titleParts)"
            return "- \(timestampString(frame.timestamp)): `\(path)`\(context); reason: \(frame.reason)."
        }.joined(separator: "\n")

        let observations = selectedFrames.map { frame -> String in
            let bounds = frame.captureBounds.map {
                "capture bounds x=\(Int($0.x)), y=\(Int($0.y)), w=\(Int($0.width)), h=\(Int($0.height))"
            } ?? "capture bounds unavailable"
            return "- \(timestampString(frame.timestamp)): selected frame from \(bounds). Verify the visual state directly in the referenced frame before treating this as implementation evidence."
        }.joined(separator: "\n")

        let transcriptPreview = String(transcript.prefix(12000))

        return """
        # Summary

        ## Overview

        Claude summary was not available, so Syn generated this local fallback summary. The packet still contains the processed recording, transcript, selected frames, and manifest metadata. Treat this summary as a navigation aid, not as an interpretation of the user's intent.

        ## Prioritized Feedback And Issues

        - P0: Review `recording.mp4`, `transcript.md`, and the selected frames before making code changes; the local fallback cannot infer priorities from the visuals.
        - P1: Check whether the transcript identifies concrete bugs, UI states, or requested implementation changes.
        - P2: Use `manifest.json` to inspect capture mode, frame-selection notes, pointer mapping, and processing caveats.

        ## Timestamped Observations

        \(observations.isEmpty ? "- No selected frames were available, so timestamped visual observations could not be generated." : observations)

        ## Frame References

        \(frameList.isEmpty ? "- No selected frame files were available." : frameList)

        ## Suggested Implementation Tasks

        - Read `summary.md`, then verify details against `transcript.md` and `recording.mp4`.
        - Inspect each selected frame before implementing UI or interaction changes.
        - Convert transcript-backed requests into concrete code tasks, keeping uncertain visual claims separate from confirmed issues.

        ## Open Questions And Uncertainty

        - Claude was unavailable, so semantic interpretation of transcript plus images is incomplete.
        - Any issue priority above is provisional until a human or model reviews the actual transcript and frames.
        - Transcript preview:

        \(transcriptPreview)
        """
    }

    private static func timestampString(_ timestamp: TimeInterval) -> String {
        let seconds = Int(timestamp.rounded())
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
}
