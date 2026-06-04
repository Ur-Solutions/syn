import AppKit
import ApplicationServices
import AVFAudio
import AVFoundation
import CoreGraphics

enum SynPermissionError: LocalizedError {
    case screenRecordingMissing
    case microphoneMissing

    var errorDescription: String? {
        switch self {
        case .screenRecordingMissing:
            "Screen Recording permission is required before Syn can start recording."
        case .microphoneMissing:
            "Microphone permission is required before Syn can start recording."
        }
    }
}

struct CapturePermissionResult: Sendable {
    var notes: [String]
}

enum PermissionService {
    static var shouldShowSetupChecklist: Bool {
        return !CGPreflightScreenCaptureAccess() || !MicrophonePermissionProbe.snapshot.isGranted
    }

    static func verifyBeforeRecording() async throws -> CapturePermissionResult {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            openScreenRecordingSettings()
            throw SynPermissionError.screenRecordingMissing
        }

        let microphoneGranted = await MicrophonePermissionProbe.requestAccessAndVerifyInput()
        guard microphoneGranted else {
            openMicrophoneSettings()
            throw SynPermissionError.microphoneMissing
        }

        var notes: [String] = []
        if !AXIsProcessTrusted() {
            notes.append("Accessibility permission is not granted; pointer metadata may be incomplete.")
        }

        return CapturePermissionResult(notes: notes)
    }

    static func openScreenRecordingSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openMicrophoneSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    static func openAccessibilitySettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func openSettings(_ string: String) {
        guard let url = URL(string: string) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

struct MicrophonePermissionSnapshot: Sendable {
    var recordPermission: AVAudioApplication.recordPermission
    var captureDeviceAuthorization: AVAuthorizationStatus

    var isGranted: Bool {
        recordPermission == .granted || captureDeviceAuthorization == .authorized
    }

    var isNotDetermined: Bool {
        recordPermission == .undetermined && captureDeviceAuthorization == .notDetermined
    }

    var combinedStatusString: String {
        if isGranted {
            return "authorized"
        }

        if isNotDetermined {
            return "not_determined"
        }

        return "denied"
    }

    var recordPermissionString: String {
        switch recordPermission {
        case .granted:
            "granted"
        case .denied:
            "denied"
        case .undetermined:
            "undetermined"
        @unknown default:
            "unknown"
        }
    }

    var captureDeviceAuthorizationString: String {
        switch captureDeviceAuthorization {
        case .authorized:
            "authorized"
        case .notDetermined:
            "not_determined"
        case .denied:
            "denied"
        case .restricted:
            "restricted"
        @unknown default:
            "unknown"
        }
    }
}

enum MicrophonePermissionProbe {
    static var snapshot: MicrophonePermissionSnapshot {
        MicrophonePermissionSnapshot(
            recordPermission: AVAudioApplication.shared.recordPermission,
            captureDeviceAuthorization: AVCaptureDevice.authorizationStatus(for: .audio)
        )
    }

    static func requestAccessAndVerifyInput() async -> Bool {
        let recordGranted = await requestRecordPermissionIfNeeded()
        let captureDeviceGranted = await requestCaptureDevicePermissionIfNeeded()
        guard recordGranted || captureDeviceGranted else {
            return false
        }

        return await verifyInputCanStart()
    }

    private static func requestRecordPermissionIfNeeded() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func requestCaptureDevicePermissionIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func verifyInputCanStart() async -> Bool {
        await Task.detached {
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0 else {
                return true
            }

            do {
                try engine.start()
                engine.stop()
                return true
            } catch {
                return false
            }
        }.value
    }
}

enum PermissionDiagnostics {
    static let statusOutputArgumentName = "--syn-permission-status-output"
    static let requestMicrophoneArgumentName = "--syn-request-microphone"

    static var statusOutputURL: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: statusOutputArgumentName),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        return URL(fileURLWithPath: arguments[index + 1])
    }

    static var shouldRequestMicrophone: Bool {
        ProcessInfo.processInfo.arguments.contains(requestMicrophoneArgumentName)
    }

    static func statusLines() -> [String] {
        let microphone = MicrophonePermissionProbe.snapshot
        return [
            "SYN_PERMISSION_BUNDLE_PATH=\(Bundle.main.bundleURL.path)",
            "SYN_PERMISSION_BUNDLE_ID=\(Bundle.main.bundleIdentifier ?? "missing")",
            "SYN_PERMISSION_MICROPHONE=\(microphone.combinedStatusString)",
            "SYN_PERMISSION_MICROPHONE_RECORD=\(microphone.recordPermissionString)",
            "SYN_PERMISSION_MICROPHONE_CAPTURE_DEVICE=\(microphone.captureDeviceAuthorizationString)",
            "SYN_PERMISSION_SCREEN=\(CGPreflightScreenCaptureAccess() ? "granted" : "not_granted")",
            "SYN_PERMISSION_ACCESSIBILITY=\(AXIsProcessTrusted() ? "granted" : "not_granted")"
        ]
    }

    static func writeStatusIfRequested() {
        guard let url = statusOutputURL else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try (statusLines().joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Syn permission status write failed: \(error.localizedDescription)")
        }
    }
}
