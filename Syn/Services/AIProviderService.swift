import Foundation

struct SummaryResult: Sendable {
    var markdown: String
    var provider: String
    var model: String
    var notes: [String]
}

final class AIProviderService {
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
            let markdown = try await callClaude(key: key, transcript: transcript, frames: frames, context: context)
            return SummaryResult(markdown: markdown, provider: "anthropic", model: "claude-opus-4-8", notes: [])
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
        transcript: String,
        frames: [CandidateFrameMetadata],
        context: PacketContext
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.timeoutInterval = 90
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: Self.claudeRequestBody(transcript: transcript, frames: frames, context: context)
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
        claudeRequestBody(transcript: transcript, frames: frames, context: context)
    }

    private static func claudeRequestBody(
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
            "model": "claude-opus-4-8",
            "max_tokens": 4000,
            "messages": [[
                "role": "user",
                "content": content
            ]]
        ]
    }

    private static func summaryPrompt(transcript: String, frames: [CandidateFrameMetadata]) -> String {
        """
        You are preparing an implementation-agent feedback packet from a narrated screen recording.

        Produce concise markdown using these exact section headings:
        # Summary
        ## Overview
        ## Prioritized Feedback And Issues
        ## Timestamped Observations
        ## Frame References
        ## Suggested Implementation Tasks
        ## Open Questions And Uncertainty

        Use explicit uncertainty when the transcript, selected images, or metadata do not prove something. Reference frame filenames and timestamps where possible. The attached images are compressed/downscaled JPEGs in the same order as the selected-frame metadata below; raw audio and raw video are not attached.

        Transcript:
        \(transcript)

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

        let transcriptPreview = String(transcript.prefix(4000))

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
