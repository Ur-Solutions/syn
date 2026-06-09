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
        Form {
            Section {
                PermissionChecklistView()
            }

            Section("Hotkeys") {
                LabeledContent("Picker", value: appState.preferredPickerHotkey)
                LabeledContent("Picker status", value: appState.pickerHotkeyStatus)
                LabeledContent("Repeat", value: appState.preferredRepeatHotkey)
                LabeledContent("Repeat status", value: appState.repeatHotkeyStatus)
            }

            Section("Output") {
                LabeledContent("Folder", value: appState.outputRoot.path)
            }

            Section("Agent Prompt") {
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

                Text(appState.defaultPromptProfile.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Project Context") {
                LabeledContent("Folder") {
                    Text(appState.projectContextFolderPath ?? "Not configured")
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                HStack {
                    Button("Choose Folder") {
                        appState.chooseProjectContextFolder()
                    }

                    Button("Clear") {
                        appState.clearProjectContextFolder()
                    }
                    .disabled(appState.projectContextFolderPath == nil)
                }
            }

            Section("AI Providers") {
                LabeledContent("Transcription", value: "Local Whisper")
                LabeledContent("Frame planning", value: "OpenAI")
                LabeledContent("Summary", value: "Claude Opus")
                LabeledContent("Anthropic key", value: anthropicKeyStatus)
                LabeledContent("OpenAI key", value: openAIKeyStatus)

                SecureField("Anthropic API key", text: $anthropicKey)
                SecureField("OpenAI API key", text: $openAIKey)

                HStack {
                    Button("Save Keys to Keychain") {
                        saveKeys()
                    }

                    Button("Clear Saved Keys") {
                        clearKeys()
                    }
                }

                if let savedMessage {
                    Text(savedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            appState.refreshHotkeyStatus()
            refreshKeyStatus()
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
