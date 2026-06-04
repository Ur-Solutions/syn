import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button("Open Syn") {
            appState.showMainWindow()
        }

        Divider()

        Button("Start with Picker") {
            appState.openCapturePicker()
        }

        Button("Repeat Last Capture") {
            appState.repeatLastCapture()
        }

        if appState.activeRecording != nil {
            Divider()

            Button(appState.activeRecording?.isPaused == true ? "Resume" : "Pause") {
                appState.pauseOrResumeRecording()
            }

            Button("Stop Recording") {
                appState.stopRecording()
            }
        }

        if appState.commandPacket != nil {
            Divider()

            Button("Open Packet Folder") {
                appState.openCommandPacketFolder()
            }

            Button("Copy Packet") {
                appState.copyCommandPacketHandoff()
            }

            if appState.commandPacketZipURL != nil {
                Button("Reveal Packet Zip") {
                    appState.revealCommandPacketZip()
                }
            }

            if appState.commandPacketCompactZipURL == nil {
                Button("Create Compact Packet Zip") {
                    appState.createCommandPacketCompactZip()
                }
            } else {
                Button("Reveal Compact Packet Zip") {
                    appState.revealCommandPacketCompactZip()
                }
            }

            if appState.commandPacketRawZipURL == nil {
                Button("Create Raw Packet Zip") {
                    appState.createCommandPacketRawZip()
                }
            } else {
                Button("Reveal Raw Packet Zip") {
                    appState.revealCommandPacketRawZip()
                }
            }
        }

        Divider()

        Button("Open Output Folder") {
            NSWorkspace.shared.open(appState.outputRoot)
        }

        Button("Settings") {
            appState.showSettingsWindow()
        }

        Divider()

        Button("Quit Syn") {
            NSApp.terminate(nil)
        }
    }

}
