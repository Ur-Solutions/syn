import AppKit
import Security
import SwiftUI

struct SetupChecklistView: View {
    enum Context {
        case firstRun
        case settings
    }

    @EnvironmentObject private var appState: AppState

    var context: Context = .firstRun

    @State private var snapshot = SetupReadinessSnapshot.current(testCaptureSucceededAt: nil)
    @State private var anthropicKey = ""
    @State private var openAIKey = ""
    @State private var keyMessage: String?
    @State private var openAITestState: SetupRequirementState = .notChecked
    @State private var anthropicTestState: SetupRequirementState = .notChecked
    @State private var openAITestMessage = "Not checked"
    @State private var anthropicTestMessage = "Not checked"

    var body: some View {
        Group {
            if context == .firstRun {
                ScrollView {
                    content
                }
            } else {
                content
            }
        }
        .background(SynColor.canvas)
        .onAppear {
            refresh()
            appState.refreshHotkeyStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            refresh()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SynSpace.s4) {
            header

            SetupSectionCard(title: "Required Permissions") {
                PermissionChecklistView()
            }

            SetupSectionCard(title: "AI Keys") {
                VStack(alignment: .leading, spacing: 12) {
                    keyStatusRows
                    keyFields
                    keyActions
                    providerTests
                    if let keyMessage {
                        Text(keyMessage)
                            .synFont(.footnote)
                            .foregroundStyle(SynColor.text2)
                    }
                }
            }

            SetupSectionCard(title: "Bundled Runtime") {
                SetupRequirementRow(
                    systemImage: "waveform",
                    title: snapshot.runtime.title,
                    detail: snapshot.runtime.detail,
                    state: snapshot.runtime.state,
                    required: true
                ) {
                    Button("Download Syn") {
                        openLatestRelease()
                    }
                    .buttonStyle(.synSecondary(.small))
                    .disabled(snapshot.runtime.state.isReady)
                }
            }

            SetupSectionCard(title: "Optional Integrations") {
                SetupRequirementRow(
                    systemImage: "globe",
                    title: "Chrome Tab Automation",
                    detail: "macOS asks for Automation access the first time you choose Chrome Tab capture.",
                    state: .notChecked,
                    required: false
                )
            }

            SetupSectionCard(title: "Test Capture") {
                VStack(alignment: .leading, spacing: 10) {
                    SetupRequirementRow(
                        systemImage: "record.circle",
                        title: "5 second raw recording",
                        detail: testCaptureDetail,
                        state: testCaptureState,
                        required: false
                    ) {
                        Button(appState.isSetupTestCaptureRunning ? "Running..." : "Run Test") {
                            appState.runSetupTestCapture()
                        }
                        .buttonStyle(.synPrimary(.small))
                        .disabled(appState.isSetupTestCaptureRunning || appState.activeRecording != nil)
                    }

                    Text("The test records screen and microphone locally, writes a raw packet, and stops before AI processing.")
                        .synFont(.footnote)
                        .foregroundStyle(SynColor.text3)
                }
            }

            finishBar
        }
        .padding(context == .firstRun ? SynSpace.s5 : 0)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Syn Setup")
                        .synFont(.largeTitle)
                        .foregroundStyle(SynColor.text1)
                    Text("Complete the required checks once; revisit this page from Settings anytime.")
                        .synFont(.subhead)
                        .foregroundStyle(SynColor.text2)
                }

                Spacer()

                SynStatusBadge(
                    state: snapshot.requiredReady ? .success : .warning,
                    label: "\(snapshot.readyCount)/\(snapshot.requiredCount) required"
                )
            }

            if !snapshot.requiredReady {
                Text("Syn can open before setup is complete, but recording and agent-ready packets need these checks to pass.")
                    .synFont(.footnote)
                    .foregroundStyle(SynColor.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var keyStatusRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            SetupRequirementRow(
                systemImage: "sparkles",
                title: "OpenAI key",
                detail: "Required for semantic frame planning and fast summary tiers. Status: \(snapshot.openAIKey.displayText).",
                state: snapshot.openAIKey.isAvailable ? .ready : .actionNeeded,
                required: true
            )

            SetupRequirementRow(
                systemImage: "text.bubble",
                title: "Anthropic key",
                detail: "Recommended for the full summary tier. Syn falls back locally if it is missing. Status: \(snapshot.anthropicKey.displayText).",
                state: snapshot.anthropicKey.isAvailable ? .ready : .notChecked,
                required: false
            )
        }
    }

    private var keyFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("OpenAI API key", text: $openAIKey)
                .textFieldStyle(.roundedBorder)
            SecureField("Anthropic API key", text: $anthropicKey)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var keyActions: some View {
        HStack(spacing: 8) {
            Button("Save Keys") {
                saveKeys()
            }
            .buttonStyle(.synPrimary(.small))

            Button("Clear Saved Keys") {
                clearKeys()
            }
            .buttonStyle(.synSecondary(.small))
        }
    }

    private var providerTests: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SynStatusBadge(state: badgeState(openAITestState), label: openAITestMessage)
                Spacer()
                Button(openAITestState == .checking ? "Testing..." : "Test OpenAI") {
                    testOpenAI()
                }
                .buttonStyle(.synSecondary(.small))
                .disabled(openAITestState == .checking)
            }

            HStack(spacing: 8) {
                SynStatusBadge(state: badgeState(anthropicTestState), label: anthropicTestMessage)
                Spacer()
                Button(anthropicTestState == .checking ? "Testing..." : "Test Anthropic") {
                    testAnthropic()
                }
                .buttonStyle(.synSecondary(.small))
                .disabled(anthropicTestState == .checking)
            }
        }
    }

    private var finishBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.requiredReady ? "Required setup is complete." : "Required setup is incomplete.")
                    .synFont(.headline)
                    .foregroundStyle(SynColor.text1)
                Text("OpenAI, permissions, and the local runtime are required. Anthropic and the test capture are recommended.")
                    .synFont(.footnote)
                    .foregroundStyle(SynColor.text3)
            }

            Spacer()

            Button("Refresh") {
                refresh()
            }
            .buttonStyle(.synSecondary(.small))

            Button(context == .firstRun ? "Finish Setup" : "Mark Complete") {
                appState.markInitialSetupComplete()
                refresh()
            }
            .buttonStyle(.synPrimary(.small))
            .disabled(!snapshot.requiredReady)
        }
        .synCard(padding: SynSpace.s4)
    }

    private var testCaptureState: SetupRequirementState {
        if appState.isSetupTestCaptureRunning {
            return .checking
        }
        return appState.setupTestSucceededAt == nil ? .notChecked : .ready
    }

    private var testCaptureDetail: String {
        if appState.isSetupTestCaptureRunning {
            return appState.setupTestStatus
        }
        if let date = appState.setupTestSucceededAt {
            return "Last passed \(date.formatted(date: .abbreviated, time: .shortened)). \(appState.setupTestStatus)"
        }
        return appState.setupTestStatus
    }

    private func refresh() {
        snapshot = SetupReadinessSnapshot.current(testCaptureSucceededAt: appState.setupTestSucceededAt)
    }

    private func saveKeys() {
        let trimmedOpenAIKey = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnthropicKey = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOpenAIKey.isEmpty || !trimmedAnthropicKey.isEmpty else {
            keyMessage = "Enter at least one key to save."
            return
        }

        var results: [String] = []
        if !trimmedOpenAIKey.isEmpty {
            let status = SecretStore.save(value: trimmedOpenAIKey, account: "openai-api-key")
            results.append(statusMessage(label: "OpenAI", successText: "saved", failureText: "save failed", status: status, emptySuccess: false))
            if status == errSecSuccess {
                openAIKey = ""
            }
        }

        if !trimmedAnthropicKey.isEmpty {
            let status = SecretStore.save(value: trimmedAnthropicKey, account: "anthropic-api-key")
            results.append(statusMessage(label: "Anthropic", successText: "saved", failureText: "save failed", status: status, emptySuccess: false))
            if status == errSecSuccess {
                anthropicKey = ""
            }
        }

        keyMessage = results.joined(separator: " ")
        refresh()
    }

    private func clearKeys() {
        let openAIStatus = SecretStore.delete(account: "openai-api-key")
        let anthropicStatus = SecretStore.delete(account: "anthropic-api-key")
        openAIKey = ""
        anthropicKey = ""
        openAITestState = .notChecked
        anthropicTestState = .notChecked
        openAITestMessage = "Not checked"
        anthropicTestMessage = "Not checked"
        keyMessage = [
            statusMessage(label: "OpenAI", successText: "cleared", failureText: "clear failed", status: openAIStatus, emptySuccess: true),
            statusMessage(label: "Anthropic", successText: "cleared", failureText: "clear failed", status: anthropicStatus, emptySuccess: true)
        ].joined(separator: " ")
        refresh()
    }

    private func testOpenAI() {
        openAITestState = .checking
        openAITestMessage = "Testing OpenAI..."
        let key = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let result = await ProviderKeyTester.testOpenAI(key: key.isEmpty ? nil : key)
            await MainActor.run {
                switch result {
                case .success(let message):
                    openAITestState = .ready
                    openAITestMessage = message
                case .failure(let message):
                    openAITestState = .actionNeeded
                    openAITestMessage = message
                }
                refresh()
            }
        }
    }

    private func testAnthropic() {
        anthropicTestState = .checking
        anthropicTestMessage = "Testing Anthropic..."
        let key = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let result = await ProviderKeyTester.testAnthropic(key: key.isEmpty ? nil : key)
            await MainActor.run {
                switch result {
                case .success(let message):
                    anthropicTestState = .ready
                    anthropicTestMessage = message
                case .failure(let message):
                    anthropicTestState = .actionNeeded
                    anthropicTestMessage = message
                }
                refresh()
            }
        }
    }

    private func statusMessage(
        label: String,
        successText: String,
        failureText: String,
        status: OSStatus,
        emptySuccess: Bool
    ) -> String {
        if status == errSecSuccess || (emptySuccess && status == errSecItemNotFound) {
            return "\(label) \(successText)."
        }

        return "\(label) \(failureText) (\(status))."
    }

    private func badgeState(_ state: SetupRequirementState) -> SynState {
        switch state {
        case .ready:
            return .success
        case .checking:
            return .processing
        case .actionNeeded:
            return .warning
        case .notChecked:
            return .idle
        }
    }

    private func openLatestRelease() {
        guard let url = URL(string: "https://github.com/Ur-Solutions/syn/releases/latest") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct SetupSectionCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: SynSpace.s3) {
            Text(title)
                .synFont(.caption)
                .foregroundStyle(SynColor.text3)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .synCard(padding: SynSpace.s4)
    }
}

private struct SetupRequirementRow<Accessory: View>: View {
    var systemImage: String
    var title: String
    var detail: String
    var state: SetupRequirementState
    var required: Bool
    @ViewBuilder var accessory: () -> Accessory

    init(
        systemImage: String,
        title: String,
        detail: String,
        state: SetupRequirementState,
        required: Bool,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.state = state
        self.required = required
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SynColor.text2)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .synFont(.body)
                        .foregroundStyle(SynColor.text1)
                    Text(required ? "Required" : "Optional")
                        .synFont(.footnote)
                        .foregroundStyle(required ? SynColor.accentDeep : SynColor.text3)
                }

                Text(detail)
                    .synFont(.footnote)
                    .foregroundStyle(SynColor.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            SynStatusBadge(state: badgeState, pulse: state == .checking, label: statusLabel)
                .layoutPriority(1)

            accessory()
        }
    }

    private var badgeState: SynState {
        switch state {
        case .ready:
            .success
        case .checking:
            .processing
        case .actionNeeded:
            .warning
        case .notChecked:
            .idle
        }
    }

    private var statusLabel: String {
        switch state {
        case .ready:
            "Ready"
        case .checking:
            "Checking"
        case .actionNeeded:
            "Needed"
        case .notChecked:
            "On demand"
        }
    }
}

private extension SetupRequirementRow where Accessory == EmptyView {
    init(
        systemImage: String,
        title: String,
        detail: String,
        state: SetupRequirementState,
        required: Bool
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            detail: detail,
            state: state,
            required: required
        ) {
            EmptyView()
        }
    }
}
