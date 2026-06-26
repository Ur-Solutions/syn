import Security
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var anthropicKey = ""
    @State private var openAIKey = ""
    @State private var anthropicKeyStatus = "Not checked"
    @State private var openAIKeyStatus = "Not checked"
    @State private var savedMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SynSpace.s4) {
                SettingsCard(title: "Permissions") {
                    PermissionChecklistView()
                }

                SettingsCard(title: "Shortcuts") {
                    VStack(alignment: .leading, spacing: 10) {
                        shortcutRow(
                            label: "Open capture picker",
                            keys: [("⇧", "L"), ("⇧", "R"), ("R", nil)],
                            status: appState.pickerHotkeyStatus
                        )
                        shortcutRow(
                            label: "Repeat last capture",
                            keys: [("⇧", "L"), ("⇧", "R")],
                            status: appState.repeatHotkeyStatus
                        )
                        shortcutRow(
                            label: "Stop recording",
                            keys: [("⇧", "R"), ("S", nil)],
                            status: appState.stopRecordingHotkeyStatus
                        )
                    }
                }

                SettingsCard(title: "Output") {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Packets folder")
                                .synFont(.subhead)
                                .foregroundStyle(SynColor.text2)
                            Text(appState.outputRoot.path)
                                .font(SynFont.mono(11))
                                .foregroundStyle(SynColor.text1)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Open") {
                            NSWorkspace.shared.open(appState.outputRoot)
                        }
                        .buttonStyle(.synSecondary(.small))
                    }
                }

                SettingsCard(title: "Agent Prompt") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(
                            "Default profile",
                            selection: Binding(
                                get: { appState.defaultPromptProfile },
                                set: { appState.setDefaultPromptProfile($0) }
                            )
                        ) {
                            ForEach(AgentPromptProfile.allCases) { profile in
                                Text(profile.title).tag(profile)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()

                        Text(appState.defaultPromptProfile.detail)
                            .synFont(.footnote)
                            .foregroundStyle(SynColor.text2)
                    }
                }

                SettingsCard(title: "Project Context") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Attached folder")
                                    .synFont(.subhead)
                                    .foregroundStyle(SynColor.text2)
                                Text(appState.projectContextFolderPath ?? "Not configured")
                                    .font(SynFont.mono(11))
                                    .foregroundStyle(appState.projectContextFolderPath == nil ? SynColor.text3 : SynColor.text1)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                        }

                        HStack(spacing: 8) {
                            Button("Choose Folder") {
                                appState.chooseProjectContextFolder()
                            }
                            .buttonStyle(.synSecondary(.small))

                            Button("Clear") {
                                appState.clearProjectContextFolder()
                            }
                            .buttonStyle(.synSecondary(.small))
                            .disabled(appState.projectContextFolderPath == nil)
                        }

                        Text("When set, each packet includes a metadata snapshot of this folder so agents get project context without source files.")
                            .synFont(.footnote)
                            .foregroundStyle(SynColor.text3)
                    }
                }

                SettingsCard(title: "AI Providers") {
                    VStack(alignment: .leading, spacing: 10) {
                        providerRow("Transcription", value: "Local Whisper")
                        providerRow("Frame planning", value: "OpenAI")
                        providerRow("Summary", value: "Claude Opus")

                        Divider().overlay(SynColor.hairline)

                        providerRow("Anthropic key", value: anthropicKeyStatus)
                        providerRow("OpenAI key", value: openAIKeyStatus)

                        SecureField("Anthropic API key", text: $anthropicKey)
                            .textFieldStyle(.roundedBorder)
                        SecureField("OpenAI API key", text: $openAIKey)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 8) {
                            Button("Save Keys to Keychain") {
                                saveKeys()
                            }
                            .buttonStyle(.synPrimary(.small))

                            Button("Clear Saved Keys") {
                                clearKeys()
                            }
                            .buttonStyle(.synSecondary(.small))
                        }

                        if let savedMessage {
                            Text(savedMessage)
                                .synFont(.footnote)
                                .foregroundStyle(SynColor.text2)
                        }
                    }
                }
            }
            .padding(SynSpace.s5)
        }
        .background(SynColor.canvas)
        .onAppear {
            appState.refreshHotkeyStatus()
            refreshKeyStatus()
        }
    }

    private func shortcutRow(label: String, keys: [(String, String?)], status: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .synFont(.body)
                .foregroundStyle(SynColor.text1)
            Spacer()
            SynStatusBadge(
                state: status == "Registered" ? .success : (status == "Not checked" ? .idle : .warning),
                label: status
            )
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { entry in
                    SynKeyCap(label: entry.element.0, side: entry.element.1)
                }
            }
        }
    }

    private func providerRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .synFont(.subhead)
                .foregroundStyle(SynColor.text2)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .synFont(.body)
                .foregroundStyle(SynColor.text1)
            Spacer()
        }
    }

    private func saveKeys() {
        let trimmedAnthropicKey = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAIKey = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnthropicKey.isEmpty || !trimmedOpenAIKey.isEmpty else {
            savedMessage = "Enter at least one key to save."
            return
        }

        var results: [String] = []
        if !trimmedAnthropicKey.isEmpty {
            let status = SecretStore.save(value: trimmedAnthropicKey, account: "anthropic-api-key")
            results.append(statusMessage(label: "Anthropic", successText: "saved", failureText: "save failed", status: status, emptySuccess: false))
            if status == errSecSuccess {
                anthropicKey = ""
            }
        }

        if !trimmedOpenAIKey.isEmpty {
            let status = SecretStore.save(value: trimmedOpenAIKey, account: "openai-api-key")
            results.append(statusMessage(label: "OpenAI", successText: "saved", failureText: "save failed", status: status, emptySuccess: false))
            if status == errSecSuccess {
                openAIKey = ""
            }
        }

        savedMessage = results.joined(separator: " ")
        refreshKeyStatus()
    }

    private func clearKeys() {
        let anthropicStatus = SecretStore.delete(account: "anthropic-api-key")
        let openAIStatus = SecretStore.delete(account: "openai-api-key")
        anthropicKey = ""
        openAIKey = ""
        savedMessage = [
            statusMessage(label: "Anthropic", successText: "cleared", failureText: "clear failed", status: anthropicStatus, emptySuccess: true),
            statusMessage(label: "OpenAI", successText: "cleared", failureText: "clear failed", status: openAIStatus, emptySuccess: true)
        ].joined(separator: " ")
        refreshKeyStatus()
    }

    private func refreshKeyStatus() {
        anthropicKeyStatus = SecretStore.anthropicKeyAvailability().displayText
        openAIKeyStatus = SecretStore.openAIKeyAvailability().displayText
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
}

private struct SettingsCard<Content: View>: View {
    let title: String
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
