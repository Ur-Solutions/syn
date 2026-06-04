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

        guard let installation = findWhisperInstallation() else {
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

    private func findWhisperInstallation() -> WhisperInstallation? {
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

    private func findBundledWhisperInstallation() -> WhisperInstallation? {
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

    private func preferredBundledCPUBackendPath(in whisperURL: URL) -> String? {
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

    private func findDevelopmentWhisperModel() -> String? {
        let candidates = [
            "/Users/trmd/Library/Caches/Ravn/whisper-models/ggml-large-v3-turbo.bin",
            "/Users/trmd/Library/Caches/Ravn/whisper-models/ggml-base.en.bin"
        ]

        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func findExecutable(_ candidates: [String]) -> String? {
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
