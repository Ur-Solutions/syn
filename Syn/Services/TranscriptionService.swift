import AVFoundation
import Foundation

enum TranscriptionServiceError: LocalizedError {
    case whisperUnavailable
    case modelUnavailable
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .whisperUnavailable:
            "whisper-cli is not available."
        case .modelUnavailable:
            "No local Whisper model is available."
        case .processFailed(let output):
            "Whisper failed: \(output)"
        }
    }
}

struct TranscriptResult: Sendable {
    var markdown: String
    var provider: String
    var model: String
    var notes: [String]
}

final class TranscriptionService {
    func transcribe(videoURL: URL, context: PacketContext) async throws -> TranscriptResult {
        try await extractAudio(from: videoURL, to: context.rawAudioURL)

        guard let installation = Self.findWhisperInstallation() else {
            throw TranscriptionServiceError.whisperUnavailable
        }

        let outputBase = context.rawURL.appendingPathComponent("transcript")
        let result = try run(
            executable: installation.executablePath,
            arguments: [
                "-m", installation.modelPath,
                "-f", context.rawAudioURL.path,
                "-l", "auto",
                "-ovtt",
                "-otxt",
                "-oj",
                "-of", outputBase.path,
                "-np"
            ],
            workingDirectory: installation.workingDirectory,
            environment: installation.environment
        )

        guard result.status == 0 else {
            throw TranscriptionServiceError.processFailed(result.output)
        }

        let markdown = try buildTranscriptMarkdown(outputBase: outputBase)
        try markdown.write(to: context.transcriptURL, atomically: true, encoding: .utf8)

        return TranscriptResult(
            markdown: markdown,
            provider: installation.provider,
            model: URL(fileURLWithPath: installation.modelPath).lastPathComponent,
            notes: installation.notes
        )
    }

    private func buildTranscriptMarkdown(outputBase: URL) throws -> String {
        let vttURL = outputBase.appendingPathExtension("vtt")
        let txtURL = outputBase.appendingPathExtension("txt")

        var body = "# Transcript\n\n"

        // Whisper emits a clean plain-text transcript via -otxt and a cue-timed VTT
        // via -ovtt. Prefer the plain text; only fall back to the VTT (with cue
        // timing/index/header lines stripped) so the transcript is readable prose
        // instead of being polluted with "00:00:00.000 --> 00:00:06.320" cue noise.
        if let txt = try? String(contentsOf: txtURL, encoding: .utf8) {
            body += Self.cleanedTranscriptText(txt)
        } else if let vtt = try? String(contentsOf: vttURL, encoding: .utf8) {
            body += Self.cleanedTranscriptText(vtt)
        } else {
            body += "_No transcript text was emitted._"
        }

        if body.trimmingCharacters(in: .whitespacesAndNewlines) == "# Transcript" {
            body += "_No speech was detected in the recording (silent or no microphone audio)._"
        }

        body += "\n"
        return body
    }

    private static func cleanedTranscriptText(_ raw: String) -> String {
        raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                if line.isEmpty { return false }
                if line.hasPrefix("WEBVTT") { return false }
                if line.contains("-->") { return false }      // VTT cue timing lines
                if Int(line) != nil { return false }            // numeric cue indices
                if line == "[BLANK_AUDIO]" { return false }     // whisper silence marker
                return true
            }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractAudio(from videoURL: URL, to audioURL: URL) async throws {
        if try extractAudioWithAFConvert(from: videoURL, to: audioURL) {
            return
        }

        try await VideoUtilities.extractAudioWAV(from: videoURL, to: audioURL)
    }

    private func extractAudioWithAFConvert(from videoURL: URL, to audioURL: URL) throws -> Bool {
        let executable = "/usr/bin/afconvert"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return false
        }

        try? FileManager.default.removeItem(at: audioURL)
        let result = try run(
            executable: executable,
            arguments: [
                "-f", "WAVE",
                "-d", "LEI16@16000",
                "-c", "1",
                videoURL.path,
                audioURL.path
            ]
        )

        guard result.status == 0,
              let attributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
              (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else {
            try? FileManager.default.removeItem(at: audioURL)
            return false
        }

        return true
    }

    fileprivate static func findWhisperInstallation() -> WhisperInstallation? {
        if let bundled = findBundledWhisperInstallation() {
            return bundled
        }

        guard let whisperPath = findExecutable(["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli", "whisper-cli"]),
              let modelPath = findDevelopmentWhisperModel() else {
            return nil
        }

        let libraryPath = URL(fileURLWithPath: whisperPath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib").path
        return WhisperInstallation(
            executablePath: whisperPath,
            modelPath: modelPath,
            provider: "local-whisper.cpp-development-fallback",
            workingDirectory: nil,
            environment: ["DYLD_LIBRARY_PATH": libraryPath],
            notes: ["Used development Whisper fallback. The app bundle did not contain a complete Whisper runtime."]
        )
    }

    fileprivate static func findBundledWhisperInstallation() -> WhisperInstallation? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }

        let whisperURL = resourceURL.appendingPathComponent("Whisper", isDirectory: true)
        let executableURL = whisperURL.appendingPathComponent("whisper-cli")
        let modelURL = whisperURL
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("ggml-base.en.bin")

        guard FileManager.default.isExecutableFile(atPath: executableURL.path),
              FileManager.default.fileExists(atPath: modelURL.path) else {
            return nil
        }

        var environment = [
            "DYLD_LIBRARY_PATH": [
                whisperURL.path,
                whisperURL.appendingPathComponent("Backends", isDirectory: true).path
            ].joined(separator: ":")
        ]
        if let backendPath = preferredBundledCPUBackendPath(in: whisperURL) {
            environment["GGML_BACKEND_PATH"] = backendPath
        }

        return WhisperInstallation(
            executablePath: executableURL.path,
            modelPath: modelURL.path,
            provider: "local-whisper.cpp-bundled",
            workingDirectory: whisperURL,
            environment: environment,
            notes: []
        )
    }

    static func preferredBundledCPUBackendPath(in whisperURL: URL) -> String? {
        let brand = ((try? run(executable: "/usr/sbin/sysctl", arguments: ["-n", "machdep.cpu.brand_string"]))?.output ?? "")
            .lowercased()
        let orderedNames: [String]
        if brand.contains("m4") {
            orderedNames = ["libggml-cpu-apple_m4.so", "libggml-cpu-apple_m2_m3.so", "libggml-cpu-apple_m1.so"]
        } else if brand.contains("m2") || brand.contains("m3") {
            orderedNames = ["libggml-cpu-apple_m2_m3.so", "libggml-cpu-apple_m1.so", "libggml-cpu-apple_m4.so"]
        } else {
            orderedNames = ["libggml-cpu-apple_m1.so", "libggml-cpu-apple_m2_m3.so", "libggml-cpu-apple_m4.so"]
        }

        let backendsURL = whisperURL.appendingPathComponent("Backends", isDirectory: true)
        for name in orderedNames {
            if FileManager.default.fileExists(atPath: backendsURL.appendingPathComponent(name).path) {
                return "./Backends/\(name)"
            }
        }
        return nil
    }

    static func findDevelopmentWhisperModel() -> String? {
        let candidates = [
            "/Users/trmd/Library/Caches/Ravn/whisper-models/ggml-large-v3-turbo.bin",
            "/Users/trmd/Library/Caches/Ravn/whisper-models/ggml-base.en.bin"
        ]

        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    static func findExecutable(_ candidates: [String]) -> String? {
        for candidate in candidates {
            if candidate.contains("/"), FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }

            let result = try? run(executable: "/usr/bin/which", arguments: [candidate])
            if let result, result.status == 0 {
                let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty {
                    return path
                }
            }
        }

        return nil
    }
}

private struct WhisperInstallation {
    var executablePath: String
    var modelPath: String
    var provider: String
    var workingDirectory: URL?
    var environment: [String: String]
    var notes: [String]
}

// MARK: - Streaming transcription (during recording)

struct StreamingTranscriptResult: Sendable {
    var text: String
    var chunkCount: Int
    var transcribedChunkCount: Int
    var provider: String
    var model: String
    var notes: [String]

    /// Streamed transcription is only trusted when it produced actual speech text;
    /// an empty result falls back to the full offline transcription.
    var isUsable: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Transcribes the narration WHILE the recording runs: PCM from the existing mic-meter
/// tap is resampled to Whisper's 16 kHz mono, cut into ~20 s chunks at silence points,
/// and each chunk runs through the bundled whisper-cli in the background. Stopping the
/// recording only has to transcribe the final partial chunk, so the stop-time cost is
/// a couple of seconds regardless of recording length. Any failure makes `finish()`
/// return nil and the offline full-file transcription runs instead.
final class StreamingTranscriber: @unchecked Sendable {
    private static let targetSampleRate = 16_000.0
    private static let chunkTargetSamples = Int(targetSampleRate * 20)   // ~20 s
    private static let minimumCutSamples = Int(targetSampleRate * 6)     // never cut before 6 s
    private static let cutSearchSamples = Int(targetSampleRate * 2.5)    // search last 2.5 s for silence
    private static let cutWindowSamples = Int(targetSampleRate * 0.2)    // 200 ms energy windows
    /// A chunk is "silent" only when it has no speech-like transient at all. Peak-based on
    /// purpose: real microphones often record speech at low gain (observed mean |sample|
    /// ≈ 70 on Int16 for normal narration), so mean-energy thresholds misfire.
    private static let silencePeakAbs: Double = 400                      // ≈ -38 dBFS on Int16

    private let lock = NSLock()
    private let whisperQueue = DispatchQueue(label: "syn.streaming-transcriber", qos: .utility)
    private let jobs = DispatchGroup()

    private var installation: WhisperInstallation?
    private var workDirectory: URL?
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var pending: [Int16] = []
    private var chunkTexts: [Int: String] = [:]
    private var chunkIndex = 0
    private var transcribedChunkCount = 0
    private var active = false
    private var failureNote: String?

    func start(workDirectory: URL) {
        lock.lock()
        defer { lock.unlock() }
        installation = TranscriptionService.findWhisperInstallation()
        self.workDirectory = workDirectory
        try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        converter = nil
        converterInputFormat = nil
        pending = []
        chunkTexts = [:]
        chunkIndex = 0
        transcribedChunkCount = 0
        failureNote = installation == nil ? "whisper-cli was not available for streaming transcription." : nil
        active = installation != nil
    }

    func cancel() {
        lock.lock()
        active = false
        pending = []
        let directory = workDirectory
        lock.unlock()
        whisperQueue.async {
            if let directory {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    /// Called from the mic tap's audio thread with whatever format the input device uses.
    func ingest(buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard active, failureNote == nil else {
            lock.unlock()
            return
        }
        if converter == nil || converterInputFormat != buffer.format {
            guard let target = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Self.targetSampleRate,
                channels: 1,
                interleaved: true
            ), let newConverter = AVAudioConverter(from: buffer.format, to: target) else {
                failureNote = "Could not build the 16 kHz audio converter for streaming transcription."
                lock.unlock()
                return
            }
            converter = newConverter
            converterInputFormat = buffer.format
        }
        guard let converter else {
            lock.unlock()
            return
        }
        let targetFormat = converter.outputFormat
        lock.unlock()

        let ratio = Self.targetSampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return
        }
        var consumed = false
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard conversionError == nil,
              converted.frameLength > 0,
              let channel = converted.int16ChannelData?[0] else {
            return
        }

        lock.lock()
        pending.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
        if pending.count >= Self.chunkTargetSamples {
            cutChunkLocked(final: false)
        }
        lock.unlock()
    }

    /// Flushes the tail chunk, waits for in-flight whisper jobs, and stitches the text.
    func finish() async -> StreamingTranscriptResult? {
        guard beginFinish() else {
            return nil
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            jobs.notify(queue: whisperQueue) {
                continuation.resume()
            }
        }

        return collectResult()
    }

    /// Synchronous half of finish(): flips inactive and flushes the tail chunk.
    private func beginFinish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard active else {
            return false
        }
        active = false
        cutChunkLocked(final: true)
        return true
    }

    private func collectResult() -> StreamingTranscriptResult? {
        lock.lock()
        let texts = chunkTexts
        let totalChunks = chunkIndex
        let transcribed = transcribedChunkCount
        let note = failureNote
        let installationInfo = installation
        let directory = workDirectory
        lock.unlock()

        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }

        guard note == nil, let installationInfo, totalChunks > 0 else {
            return nil
        }

        let stitched = (0..<totalChunks)
            .compactMap { texts[$0] }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return StreamingTranscriptResult(
            text: stitched,
            chunkCount: totalChunks,
            transcribedChunkCount: transcribed,
            provider: installationInfo.provider,
            model: URL(fileURLWithPath: installationInfo.modelPath).lastPathComponent,
            notes: [
                "Transcribed live during the recording in \(totalChunks) chunk\(totalChunks == 1 ? "" : "s") with silence-aligned boundaries; stop-time transcription only covered the final chunk."
            ] + installationInfo.notes
        )
    }

    // MARK: Chunking

    /// Must be called with `lock` held.
    private func cutChunkLocked(final isFinal: Bool) {
        while pending.count >= Self.chunkTargetSamples {
            let cut = silenceAlignedCutIndex()
            enqueueChunkLocked(samples: Array(pending[0..<cut]))
            pending.removeFirst(cut)
        }
        if isFinal {
            // Anything shorter than half a second is silence/no-speech tail.
            if pending.count >= Int(Self.targetSampleRate / 2) {
                enqueueChunkLocked(samples: pending)
            }
            pending = []
        }
    }

    /// Finds the quietest 200 ms window in the last 2.5 s of the target chunk and cuts
    /// at its center, so words are not split mid-syllable at chunk boundaries.
    private func silenceAlignedCutIndex() -> Int {
        let target = Self.chunkTargetSamples
        let searchStart = max(Self.minimumCutSamples, target - Self.cutSearchSamples)
        var bestStart = target - Self.cutWindowSamples
        var bestEnergy = Double.greatestFiniteMagnitude
        var windowStart = searchStart
        while windowStart + Self.cutWindowSamples <= target {
            var sum = 0.0
            for index in windowStart..<(windowStart + Self.cutWindowSamples) {
                sum += abs(Double(pending[index]))
            }
            if sum < bestEnergy {
                bestEnergy = sum
                bestStart = windowStart
            }
            windowStart += Self.cutWindowSamples / 2
        }
        return min(bestStart + Self.cutWindowSamples / 2, target)
    }

    /// Must be called with `lock` held.
    private func enqueueChunkLocked(samples: [Int16]) {
        guard let installation, let workDirectory else {
            return
        }
        let index = chunkIndex
        chunkIndex += 1

        var peak = 0.0
        for sample in samples {
            peak = max(peak, abs(Double(sample)))
        }
        if peak < Self.silencePeakAbs {
            chunkTexts[index] = ""
            return
        }

        jobs.enter()
        whisperQueue.async { [weak self] in
            defer { self?.jobs.leave() }
            guard let self else { return }
            let chunkBase = workDirectory.appendingPathComponent(String(format: "chunk-%03d", index))
            let wavURL = chunkBase.appendingPathExtension("wav")
            do {
                try Self.writeWAV(samples: samples, to: wavURL)
                let result = try run(
                    executable: installation.executablePath,
                    arguments: [
                        "-m", installation.modelPath,
                        "-f", wavURL.path,
                        "-l", "auto",
                        "-otxt",
                        "-of", chunkBase.path,
                        "-np"
                    ],
                    workingDirectory: installation.workingDirectory,
                    environment: installation.environment
                )
                guard result.status == 0 else {
                    throw TranscriptionServiceError.processFailed(result.output)
                }
                let text = (try? String(contentsOf: chunkBase.appendingPathExtension("txt"), encoding: .utf8)) ?? ""
                self.lock.lock()
                self.chunkTexts[index] = TranscriptionService.cleanedStreamedChunkText(text)
                self.transcribedChunkCount += 1
                self.lock.unlock()
            } catch {
                self.lock.lock()
                self.failureNote = "Streaming chunk \(index) failed: \(error.localizedDescription)"
                self.lock.unlock()
            }
            try? FileManager.default.removeItem(at: wavURL)
        }
    }

    private static func writeWAV(samples: [Int16], to url: URL) throws {
        var data = Data(capacity: 44 + samples.count * 2)
        let byteCount = UInt32(samples.count * 2)
        let sampleRate = UInt32(targetSampleRate)

        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8))
        append(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(16)
        append16(1)               // PCM
        append16(1)               // mono
        append(sampleRate)
        append(sampleRate * 2)    // byte rate
        append16(2)               // block align
        append16(16)              // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(byteCount)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        try data.write(to: url)
    }
}

extension TranscriptionService {
    /// Chunk-level cleanup for streamed transcription (same filters as the offline path).
    static func cleanedStreamedChunkText(_ raw: String) -> String {
        cleanedTranscriptText(raw)
    }
}

struct ProcessResult {
    var status: Int32
    var output: String
}

@discardableResult
func run(
    executable: String,
    arguments: [String],
    workingDirectory: URL? = nil,
    environment: [String: String] = [:]
) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory
    if !environment.isEmpty {
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    }

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return ProcessResult(status: process.terminationStatus, output: output)
}
