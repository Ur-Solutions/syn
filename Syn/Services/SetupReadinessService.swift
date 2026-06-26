import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation

enum SetupRequirementState: Equatable {
    case ready
    case actionNeeded
    case notChecked
    case checking

    var isReady: Bool {
        self == .ready
    }
}

struct SetupRuntimeStatus: Equatable {
    var state: SetupRequirementState
    var title: String
    var detail: String
}

struct SetupReadinessSnapshot: Equatable {
    var screenRecording: SetupRequirementState
    var microphone: SetupRequirementState
    var accessibility: SetupRequirementState
    var openAIKey: SecretAvailability
    var anthropicKey: SecretAvailability
    var runtime: SetupRuntimeStatus
    var testCaptureSucceededAt: Date?

    var requiredReady: Bool {
        screenRecording.isReady
            && microphone.isReady
            && accessibility.isReady
            && openAIKey.isAvailable
            && runtime.state.isReady
    }

    var readyCount: Int {
        [
            screenRecording.isReady,
            microphone.isReady,
            accessibility.isReady,
            openAIKey.isAvailable,
            runtime.state.isReady
        ].filter { $0 }.count
    }

    var requiredCount: Int { 5 }

    static func current(testCaptureSucceededAt: Date?) -> SetupReadinessSnapshot {
        let microphoneSnapshot = MicrophonePermissionProbe.snapshot
        return SetupReadinessSnapshot(
            screenRecording: CGPreflightScreenCaptureAccess() ? .ready : .actionNeeded,
            microphone: microphoneSnapshot.isGranted ? .ready : .actionNeeded,
            accessibility: AXIsProcessTrusted() ? .ready : .actionNeeded,
            openAIKey: SecretStore.openAIKeyAvailability(),
            anthropicKey: SecretStore.anthropicKeyAvailability(),
            runtime: Self.runtimeStatus(),
            testCaptureSucceededAt: testCaptureSucceededAt
        )
    }

    private static func runtimeStatus() -> SetupRuntimeStatus {
        let runtime = TranscriptionService.runtimeStatus()
        if runtime.isBundledReady {
            return SetupRuntimeStatus(
                state: .ready,
                title: "Bundled Whisper ready",
                detail: runtime.detail
            )
        }

        if runtime.isReady {
            return SetupRuntimeStatus(
                state: .ready,
                title: "Development Whisper fallback ready",
                detail: runtime.detail
            )
        }

        return SetupRuntimeStatus(
            state: .actionNeeded,
            title: "Whisper runtime missing",
            detail: runtime.detail
        )
    }
}

enum ProviderKeyTestResult {
    case success(String)
    case failure(String)
}

enum ProviderKeyTester {
    static func testOpenAI(key explicitKey: String?) async -> ProviderKeyTestResult {
        guard let key = usableKey(explicitKey ?? SecretStore.readOpenAIKey()) else {
            return .failure("No OpenAI key is available.")
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        return await run(request: request, provider: "OpenAI")
    }

    static func testAnthropic(key explicitKey: String?) async -> ProviderKeyTestResult {
        guard let key = usableKey(explicitKey ?? SecretStore.readAnthropicKey()) else {
            return .failure("No Anthropic key is available.")
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        return await run(request: request, provider: "Anthropic")
    }

    private static func usableKey(_ key: String?) -> String? {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func run(request: URLRequest, provider: String) async -> ProviderKeyTestResult {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure("\(provider) returned a non-HTTP response.")
            }

            switch http.statusCode {
            case 200..<300:
                return .success("\(provider) key works.")
            case 401, 403:
                return .failure("\(provider) rejected the key.")
            default:
                let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                return .failure("\(provider) test failed: \(body.prefix(240))")
            }
        } catch {
            return .failure("\(provider) test failed: \(error.localizedDescription)")
        }
    }
}
