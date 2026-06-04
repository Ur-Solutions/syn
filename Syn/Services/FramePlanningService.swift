import Foundation

struct FramePlanningResult: Sendable {
    var selectedFrames: [CandidateFrameMetadata]
    var candidateFrames: [CandidateFrameMetadata]
    var semanticSegments: [SemanticSegment]
    var provider: String
    var model: String
    var notes: [String]
}

final class FramePlanningService {
    private let model = "gpt-5-mini"
    private let maxFrames = 12

    func planFrames(
        extraction: FrameExtractionResult,
        transcript: String,
        context: PacketContext
    ) async -> FramePlanningResult {
        let pixelSelected = extraction.selectedFrames.filter { $0.compressedPath != nil }
        guard !pixelSelected.isEmpty else {
            return FramePlanningResult(
                selectedFrames: [],
                candidateFrames: extraction.candidateFrames,
                semanticSegments: [],
                provider: "pixel-dedupe",
                model: "none",
                notes: ["Frame planning skipped because no visual-change frames were selected."]
            )
        }

        guard let key = SecretStore.readOpenAIKey() else {
            return fallbackPlan(extraction: extraction, note: "OpenAI frame planning skipped because no OpenAI API key was available.")
        }

        do {
            let plan = try await callOpenAI(key: key, candidates: pixelSelected, transcript: transcript)
            let selected = apply(selectedTimestamps: plan.timestamps, extraction: extraction)
            if selected.selectedFrames.isEmpty {
                return fallbackPlan(extraction: extraction, note: "OpenAI frame planning returned no usable timestamps.")
            }

            var notes = plan.notes
            notes.append("OpenAI selected \(selected.selectedFrames.count) semantically relevant frames from \(pixelSelected.count) visual-change candidates.")
            let segments = makeSemanticSegments(
                selectedFrames: selected.selectedFrames,
                duration: extraction.duration,
                source: "openai-semantic-frame-plan"
            )
            return FramePlanningResult(
                selectedFrames: selected.selectedFrames,
                candidateFrames: selected.candidateFrames,
                semanticSegments: segments,
                provider: "openai-semantic",
                model: model,
                notes: notes
            )
        } catch {
            return fallbackPlan(extraction: extraction, note: "OpenAI frame planning failed: \(error.localizedDescription)")
        }
    }

    private func fallbackPlan(extraction: FrameExtractionResult, note: String) -> FramePlanningResult {
        let selected = Array(extraction.selectedFrames.prefix(maxFrames))
        let selectedTimestamps = Set(selected.map { timestampKey($0.timestamp) })
        let candidates = extraction.candidateFrames.map { frame -> CandidateFrameMetadata in
            var frame = frame
            if selectedTimestamps.contains(timestampKey(frame.timestamp)) {
                frame.selected = true
                frame.reason = "visual-change"
            } else if frame.selected {
                frame.selected = false
                frame.reason = "pixel-dedupe-not-in-default-limit"
            }
            return frame
        }

        return FramePlanningResult(
            selectedFrames: selected,
            candidateFrames: candidates,
            semanticSegments: makeSemanticSegments(
                selectedFrames: selected,
                duration: extraction.duration,
                source: "pixel-dedupe-fallback"
            ),
            provider: "pixel-dedupe",
            model: "none",
            notes: [note]
        )
    }

    private func callOpenAI(
        key: String,
        candidates: [CandidateFrameMetadata],
        transcript: String
    ) async throws -> (timestamps: [TimeInterval], notes: [String]) {
        let candidateLines = candidates.prefix(60).map { frame in
            let diff = frame.pixelDifferenceFromPrevious.map { String(format: "%.3f", $0) } ?? "first"
            let app = frame.appName ?? "unknown-app"
            let title = frame.windowTitle ?? "untitled"
            let bounds = frame.captureBounds.map {
                "x=\(Int($0.x)),y=\(Int($0.y)),w=\(Int($0.width)),h=\(Int($0.height))"
            } ?? "bounds=unknown"
            let ocr = frame.ocrText.map { "ocr=\(Self.compactForPrompt($0, maxLength: 260))" } ?? "ocr=none"
            return "\(String(format: "%.2f", frame.timestamp))s | diff=\(diff) | app=\(app) | window=\(title) | \(bounds) | \(ocr) | path=\(frame.compressedPath ?? "")"
        }.joined(separator: "\n")

        let prompt = """
        Select up to \(maxFrames) screenshot timestamps for a coding-agent feedback packet.

        The user's spoken transcript is the PRIMARY driver of this selection. Choose frames that best ILLUSTRATE the specific points, requests, bugs, and UI states the user TALKS ABOUT. Walk the narration in order and, for each distinct thing the user calls out, pick the candidate frame whose timestamp and on-screen content best shows what they are referring to.

        The visual-change metadata and OCR text are SECONDARY: use them only to pick the clearest frame among visually similar candidates and to avoid near-duplicates and decorative choices. Do not select a frame just because it has a large visual change if the user never speaks to that moment.

        Return only timestamps that appear in the candidate list.

        PRIMARY - Transcript (drive selection from what the user says):
        \(transcript.prefix(40_000))

        SECONDARY - Candidate frames (corroborating visuals; pick those that match the narration):
        \(candidateLines)
        """

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "selected_timestamps": [
                    "type": "array",
                    "items": ["type": "number"],
                    "description": "Candidate timestamps, in seconds, selected for the final packet."
                ],
                "notes": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Brief reasons or caveats for the frame plan."
                ]
            ],
            "required": ["selected_timestamps", "notes"]
        ]

        let body: [String: Any] = [
            "model": model,
            "input": [[
                "role": "user",
                "content": [[
                    "type": "input_text",
                    "text": prompt
                ]]
            ]],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "syn_frame_plan",
                    "strict": true,
                    "schema": schema
                ]
            ],
            // Frame selection is a lightweight ranking task; low reasoning keeps it fast
            // (the default medium effort spends many seconds on hidden reasoning tokens).
            "reasoning": ["effort": "low"],
            "max_output_tokens": 1200
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.timeoutInterval = 45
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
              let text = extractOutputText(from: json),
              let payload = text.data(using: .utf8),
              let plan = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw NSError(domain: "Syn.OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not parse structured frame plan."])
        }

        let timestamps = (plan["selected_timestamps"] as? [Any] ?? []).compactMap { value -> TimeInterval? in
            if let number = value as? NSNumber { return number.doubleValue }
            return value as? TimeInterval
        }
        let notes = plan["notes"] as? [String] ?? []
        return (Array(timestamps.prefix(maxFrames)), notes)
    }

    private func apply(
        selectedTimestamps: [TimeInterval],
        extraction: FrameExtractionResult
    ) -> (selectedFrames: [CandidateFrameMetadata], candidateFrames: [CandidateFrameMetadata]) {
        var matchedKeys = Set<Int>()
        let selectable = extraction.selectedFrames.filter { $0.fullPath != nil || $0.compressedPath != nil }

        for timestamp in selectedTimestamps {
            guard let nearest = selectable.min(by: { abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp) }),
                  abs(nearest.timestamp - timestamp) <= 0.35 else {
                continue
            }
            matchedKeys.insert(timestampKey(nearest.timestamp))
        }

        let candidateFrames = extraction.candidateFrames.map { frame -> CandidateFrameMetadata in
            var frame = frame
            if matchedKeys.contains(timestampKey(frame.timestamp)) {
                frame.selected = true
                frame.reason = "semantic-topic-shift"
            } else if frame.selected {
                frame.selected = false
                frame.reason = "visual-change-not-semantic-selected"
            }
            return frame
        }

        let selectedFrames = candidateFrames.filter(\.selected)
        return (selectedFrames, candidateFrames)
    }

    private func timestampKey(_ timestamp: TimeInterval) -> Int {
        Int((timestamp * 1000).rounded())
    }

    private func makeSemanticSegments(
        selectedFrames: [CandidateFrameMetadata],
        duration: TimeInterval,
        source: String
    ) -> [SemanticSegment] {
        let sortedFrames = selectedFrames
            .sorted { $0.timestamp < $1.timestamp }
            .prefix(maxFrames)
        guard !sortedFrames.isEmpty else {
            return []
        }

        return sortedFrames.enumerated().map { index, frame in
            let previousTimestamp = index > 0 ? sortedFrames[sortedFrames.index(sortedFrames.startIndex, offsetBy: index - 1)].timestamp : 0
            let nextTimestamp = index + 1 < sortedFrames.count ? sortedFrames[sortedFrames.index(sortedFrames.startIndex, offsetBy: index + 1)].timestamp : max(duration, frame.timestamp)
            let start = index == 0 ? 0 : (previousTimestamp + frame.timestamp) / 2
            let end = index + 1 == sortedFrames.count ? max(duration, frame.timestamp) : (frame.timestamp + nextTimestamp) / 2
            let title = segmentTitle(for: frame, index: index)
            let ocrSnippet = frame.ocrText.map { Self.compactForPrompt($0, maxLength: 180) }
            let visualDelta = frame.pixelDifferenceFromPrevious.map { String(format: "%.3f", $0) } ?? "first selected frame"
            let summaryParts = [
                "Representative frame at \(DurationFormatter.string(from: frame.timestamp)) selected because \(frame.reason).",
                "Visual change: \(visualDelta).",
                ocrSnippet.map { "OCR: \($0)." }
            ].compactMap { $0 }

            return SemanticSegment(
                index: index + 1,
                startTime: max(0, start),
                endTime: max(max(0, start), end),
                title: title,
                summary: summaryParts.joined(separator: " "),
                representativeFrameTimestamp: frame.timestamp,
                framePaths: [frame.fullPath, frame.compressedPath].compactMap { $0 },
                source: source
            )
        }
    }

    private func segmentTitle(for frame: CandidateFrameMetadata, index: Int) -> String {
        if let windowTitle = frame.windowTitle,
           !windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return windowTitle
        }
        if let appName = frame.appName,
           !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return appName
        }
        return "Topic \(index + 1)"
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

    private func extractOutputText(from object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let text = dictionary["output_text"] as? String {
                return text
            }
            if let text = dictionary["text"] as? String,
               dictionary["type"] as? String == "output_text" {
                return text
            }
            for value in dictionary.values {
                if let text = extractOutputText(from: value) {
                    return text
                }
            }
        }

        if let array = object as? [Any] {
            for value in array {
                if let text = extractOutputText(from: value) {
                    return text
                }
            }
        }

        return nil
    }
}
