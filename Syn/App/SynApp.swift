import SwiftUI

@main
struct SynApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Syn", systemImage: "record.circle") {
            MenuBarView()
                .environmentObject(appState)
        }

        WindowGroup("Syn", id: "main") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 780, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appSettings) {
                Button("Setup...") {
                    appState.showSetupWindow()
                }
            }

            CommandMenu("Capture") {
                Button("Start with Picker") {
                    appState.openCapturePicker()
                }

                Button("Repeat Last Capture") {
                    appState.repeatLastCapture()
                }
            }

            CommandMenu("Packet") {
                Button("Open Packet Folder") {
                    appState.openCommandPacketFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(appState.commandPacket == nil)

                Button("Copy Packet") {
                    appState.copyCommandPacketHandoff()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(appState.commandPacket == nil)

                Button("Reveal Packet Zip") {
                    appState.revealCommandPacketZip()
                }
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(appState.commandPacketZipURL == nil)

                if appState.commandPacketRawZipURL == nil {
                    Button("Create Raw Packet Zip") {
                        appState.createCommandPacketRawZip()
                    }
                    .disabled(appState.commandPacket == nil)
                } else {
                    Button("Reveal Raw Packet Zip") {
                        appState.revealCommandPacketRawZip()
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 520)
        }
    }
}
