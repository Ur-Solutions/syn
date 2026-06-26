import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SynSpace.s4) {
                SetupChecklistView(context: .settings)
                    .environmentObject(appState)

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
            }
            .padding(SynSpace.s5)
        }
        .background(SynColor.canvas)
        .onAppear {
            appState.refreshHotkeyStatus()
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
