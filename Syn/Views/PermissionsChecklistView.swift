import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI

private let pendingMicrophoneRequestDefaultsKey = "SynPendingMicrophoneRequestAfterReset"

struct PermissionChecklistView: View {
    @State private var snapshot = PermissionSnapshot.current()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(snapshot.items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.kind.systemImage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SynColor.text2)
                            .frame(width: 20)

                        Text(item.kind.title)
                            .synFont(.body)
                            .foregroundStyle(SynColor.text1)

                        Spacer()

                        SynStatusBadge(state: item.badgeState, label: item.statusTitle)

                        Button(item.actionTitle) {
                            handle(item)
                        }
                        .buttonStyle(.synSecondary(.small))
                        .disabled(item.status == .granted)
                        .opacity(item.status == .granted ? 0.45 : 1)
                    }
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.bundlePath)
                        .font(SynFont.mono(10.5))
                        .foregroundStyle(SynColor.text3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Text(snapshot.bundleIdentifier)
                        .font(SynFont.mono(10.5))
                        .foregroundStyle(SynColor.text3)
                        .textSelection(.enabled)
                }

                Spacer()

                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snapshot.bundlePath, forType: .string)
                }
                .buttonStyle(.synSecondary(.small))

                Button("Refresh") {
                    snapshot = .current()
                }
                .buttonStyle(.synSecondary(.small))
            }

            if snapshot.requiresScreenRecordingRestart {
                HStack(alignment: .firstTextBaseline) {
                    Text("Screen Recording changes require a full Syn relaunch; Refresh cannot detect a new grant in this process.")
                        .synFont(.footnote)
                        .foregroundStyle(SynColor.text2)

                    Spacer()

                    Button("Relaunch Syn") {
                        relaunchSyn()
                    }
                    .buttonStyle(.synSecondary(.small))
                }
            }

            if snapshot.requiresMicrophoneReset {
                HStack(alignment: .firstTextBaseline) {
                    Text("Microphone is denied or stuck. Reset only Syn's microphone grant; Syn will relaunch and request it again.")
                        .synFont(.footnote)
                        .foregroundStyle(SynColor.text2)

                    Spacer()

                    Button("Reset Mic") {
                        resetMicrophonePermissionAndRelaunch()
                    }
                    .buttonStyle(.synSecondary(.small))
                }
            }
        }
        .onAppear {
            snapshot = .current()
            PermissionDiagnostics.writeStatusIfRequested()
            requestMicrophoneIfPendingAfterReset()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            snapshot = .current()
            PermissionDiagnostics.writeStatusIfRequested()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            snapshot = .current()
            PermissionDiagnostics.writeStatusIfRequested()
        }
    }

    private func handle(_ item: PermissionItem) {
        switch item.kind {
        case .screenRecording:
            let granted = CGRequestScreenCaptureAccess()
            if !granted {
                item.kind.openSettings()
            }
            snapshot = .current()
        case .microphone where item.status == .notDetermined:
            requestMicrophoneAccess()
        case .microphone where item.status == .notGranted:
            resetMicrophonePermissionAndRelaunch()
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            snapshot = .current()
        case .microphone:
            item.kind.openSettings()
        }
    }

    private func requestMicrophoneIfPendingAfterReset() {
        guard UserDefaults.standard.bool(forKey: pendingMicrophoneRequestDefaultsKey) else {
            return
        }

        UserDefaults.standard.set(false, forKey: pendingMicrophoneRequestDefaultsKey)
        requestMicrophoneAccess(afterDelay: true)
    }

    private func requestMicrophoneAccess(afterDelay: Bool = false) {
        Task {
            if afterDelay {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }

            _ = await MicrophonePermissionProbe.requestAccessAndVerifyInput()
            await MainActor.run {
                snapshot = .current()
                PermissionDiagnostics.writeStatusIfRequested()
            }
        }
    }

    private func relaunchSyn() {
        let bundlePath = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            "sleep 0.4; /usr/bin/open -n \"$1\"",
            "syn-relaunch",
            bundlePath
        ]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func resetMicrophonePermissionAndRelaunch() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            PermissionKind.microphone.openSettings()
            return
        }

        UserDefaults.standard.set(true, forKey: pendingMicrophoneRequestDefaultsKey)
        UserDefaults.standard.synchronize()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Microphone", bundleIdentifier]
        do {
            try task.run()
        } catch {
            UserDefaults.standard.set(false, forKey: pendingMicrophoneRequestDefaultsKey)
            PermissionKind.microphone.openSettings()
            return
        }
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            UserDefaults.standard.set(false, forKey: pendingMicrophoneRequestDefaultsKey)
            PermissionKind.microphone.openSettings()
            snapshot = .current()
            return
        }

        relaunchSyn()
    }
}

private struct PermissionSnapshot {
    var items: [PermissionItem]
    var bundlePath: String
    var bundleIdentifier: String

    var requiresScreenRecordingRestart: Bool {
        items.contains { $0.kind == .screenRecording && $0.status != .granted }
    }

    var requiresMicrophoneReset: Bool {
        items.contains { $0.kind == .microphone && $0.status == .notGranted }
    }

    static func current() -> PermissionSnapshot {
        PermissionSnapshot(
            items: PermissionKind.allCases.map { kind in
                PermissionItem(kind: kind, status: kind.currentStatus)
            },
            bundlePath: Bundle.main.bundleURL.path,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "missing"
        )
    }
}

private struct PermissionItem: Identifiable {
    var kind: PermissionKind
    var status: PermissionStatus

    var id: PermissionKind { kind }

    var actionTitle: String {
        if kind == .microphone, status == .notDetermined {
            return "Request"
        }
        if kind == .microphone, status == .notGranted {
            return "Reset Mic"
        }
        if kind == .accessibility {
            return "Request"
        }
        return "Open"
    }

    var statusTitle: String {
        if kind == .accessibility, status != .granted {
            return "Optional"
        }

        return status.title
    }

    var badgeState: SynState {
        if kind == .accessibility, status != .granted {
            return .idle
        }

        switch status {
        case .granted: return .success
        case .notDetermined: return .idle
        case .notGranted: return .warning
        }
    }

    var foregroundStyle: Color {
        if kind == .accessibility, status != .granted {
            return .secondary
        }

        return status.foregroundStyle
    }
}

private enum PermissionKind: CaseIterable, Identifiable {
    case screenRecording
    case microphone
    case accessibility

    var id: Self { self }

    var title: String {
        switch self {
        case .screenRecording:
            "Screen Recording"
        case .microphone:
            "Microphone"
        case .accessibility:
            "Accessibility"
        }
    }

    var systemImage: String {
        switch self {
        case .screenRecording:
            "rectangle.on.rectangle"
        case .microphone:
            "mic"
        case .accessibility:
            "figure"
        }
    }

    var currentStatus: PermissionStatus {
        switch self {
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        case .microphone:
            let microphone = MicrophonePermissionProbe.snapshot
            if microphone.isGranted {
                return .granted
            } else if microphone.isNotDetermined {
                return .notDetermined
            } else {
                return .notGranted
            }
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notGranted
        }
    }

    func openSettings() {
        guard let url = URL(string: settingsURLString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private var settingsURLString: String {
        switch self {
        case .screenRecording:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
    }
}

private enum PermissionStatus: Equatable {
    case granted
    case notDetermined
    case notGranted

    var title: String {
        switch self {
        case .granted:
            "Allowed"
        case .notDetermined:
            "Not requested"
        case .notGranted:
            "Needed"
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .granted:
            .green
        case .notDetermined:
            .secondary
        case .notGranted:
            .orange
        }
    }
}
