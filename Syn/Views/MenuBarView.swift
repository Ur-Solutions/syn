import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            appState.showMainWindow()
        } label: {
            Label("Open Syn", systemImage: "macwindow")
        }

        Divider()

        Button {
            appState.openCapturePicker()
        } label: {
            Label("Start Recording…", systemImage: "record.circle")
        }

        Button {
            appState.repeatLastCapture()
        } label: {
            Label(
                appState.lastCaptureMode.map { "Repeat \($0.title)" } ?? "Repeat Last Capture",
                systemImage: "repeat"
            )
        }

        if let recording = appState.activeRecording {
            Divider()

            Text("\(recording.isPaused ? "Paused" : "Recording") — \(recording.mode.title)")

            Button {
                appState.pauseOrResumeRecording()
            } label: {
                Label(
                    recording.isPaused ? "Resume" : "Pause",
                    systemImage: recording.isPaused ? "play.fill" : "pause.fill"
                )
            }

            Button {
                appState.stopRecording()
            } label: {
                Label("Stop Recording", systemImage: "stop.fill")
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

        Button("Setup") {
            appState.showSetupWindow()
        }

        Divider()

        Button("Quit Syn") {
            NSApp.terminate(nil)
        }
    }

}
