import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: $appState.selectedPacketID) {
            Section("Capture") {
                Button {
                    appState.openCapturePicker()
                } label: {
                    Label("Start with Picker", systemImage: "record.circle")
                }

                Button {
                    appState.repeatLastCapture()
                } label: {
                    Label("Repeat Last Capture", systemImage: "repeat")
                }

                Button {
                    appState.showSettingsWindow()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }

            Section("History") {
                if appState.recentPackets.isEmpty {
                    Text("No recordings")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.recentPackets) { packet in
                        PacketRow(packet: packet)
                            .tag(packet.id)
                    }
                }
            }
        }
        .navigationTitle("Syn")
        .listStyle(.sidebar)
    }
}

private struct DetailView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if appState.isChromeTabPickerPresented {
                VStack(alignment: .leading, spacing: 0) {
                    ChromeTabPickerView()
                        .environmentObject(appState)
                        .frame(maxWidth: 620)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if appState.isCapturePickerPresented {
                VStack(alignment: .leading, spacing: 0) {
                    CapturePickerView()
                        .environmentObject(appState)
                        .frame(maxWidth: 760)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                StatusBannerView()

                PermissionChecklistView()

                Divider()

                if let packet = appState.selectedPacket {
                    PacketDetailView(packet: packet)
                } else {
                    ContentUnavailableView(
                        "No Packet Selected",
                        systemImage: "tray",
                        description: Text("Recent feedback packets will appear here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(24)
        .navigationTitle("Overview")
    }
}

private struct StatusBannerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.activeRecording != nil || appState.statusMessage != nil || appState.lastErrorMessage != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let recording = appState.activeRecording {
                    HStack {
                        Label(statusTitle(for: recording), systemImage: statusIcon(for: recording))
                            .foregroundStyle(statusColor(for: recording))

                        Text(recording.mode.title)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(recording.isPaused ? "Resume" : "Pause") {
                            appState.pauseOrResumeRecording()
                        }
                        .disabled(recording.phase == .processing)

                        Button("Stop", role: .destructive) {
                            appState.stopRecording()
                        }
                        .disabled(recording.phase == .processing)
                    }
                }

                if let statusMessage = appState.statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }

                if let warningMessage = appState.recordingDurationWarningMessage {
                    Label(warningMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }

                if let lastErrorMessage = appState.lastErrorMessage {
                    Text(lastErrorMessage)
                        .foregroundStyle(.red)
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func statusTitle(for recording: ActiveRecording) -> String {
        switch recording.phase {
        case .processing:
            "Processing"
        case .paused:
            "Paused"
        default:
            recording.phase.rawValue.capitalized
        }
    }

    private func statusIcon(for recording: ActiveRecording) -> String {
        switch recording.phase {
        case .processing:
            "gearshape.circle.fill"
        case .paused:
            "pause.circle.fill"
        default:
            "record.circle"
        }
    }

    private func statusColor(for recording: ActiveRecording) -> Color {
        switch recording.phase {
        case .processing:
            .blue
        case .paused:
            .yellow
        default:
            .red
        }
    }
}

private struct PacketRow: View {
    let packet: PacketSummary

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(packet.title)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(packet.status.title)
                    Text(packet.createdAt.formatted(date: .omitted, time: .shortened))
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(DurationFormatter.string(from: packet.duration))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } icon: {
            Image(systemName: "shippingbox")
        }
    }
}

private struct PacketDetailView: View {
    @EnvironmentObject private var appState: AppState
    let packet: PacketSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(packet.title)
                .font(.title2)
                .fontWeight(.semibold)

            LabeledContent("Status", value: packet.status.title)
            LabeledContent("Created", value: packet.createdAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Duration", value: DurationFormatter.string(from: packet.duration))
            LabeledContent("Folder", value: packet.folderURL.path)

            HStack {
                Button("Open Folder") {
                    NSWorkspace.shared.open(packet.folderURL)
                }

                Button("Copy Packet") {
                    appState.copyPacketHandoff(for: packet)
                }

                if let zipURL = packet.availableZipURL {
                    Button("Reveal Zip") {
                        NSWorkspace.shared.activateFileViewerSelecting([zipURL])
                    }
                }
            }
            .disabled(packet.status == .processing)

            HStack {
                if let compactZipURL = packet.availableCompactZipURL {
                    Button("Reveal Compact Zip") {
                        NSWorkspace.shared.activateFileViewerSelecting([compactZipURL])
                    }
                } else {
                    Button("Create Compact Zip") {
                        appState.createCompactZip(for: packet)
                    }
                }

                if let rawZipURL = packet.availableRawZipURL {
                    Button("Reveal Raw Zip") {
                        NSWorkspace.shared.activateFileViewerSelecting([rawZipURL])
                    }
                } else if FileManager.default.fileExists(atPath: packet.folderURL.appendingPathComponent("raw").path) {
                    Button("Create Raw Zip") {
                        appState.createRawZip(for: packet)
                    }
                }

                if packet.status == .partial || packet.status == .failed {
                    Button("Retry Processing") {
                        appState.retry(packet: packet)
                    }
                }

                Button("Delete", role: .destructive) {
                    appState.delete(packet: packet)
                }
            }
            .disabled(packet.status == .processing)

            VideoEditPanel(packet: packet)
        }
    }
}

private struct VideoEditPanel: View {
    @EnvironmentObject private var appState: AppState
    let packet: PacketSummary
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var preparedPacketID: UUID?

    private var recordingURL: URL {
        packet.folderURL.appendingPathComponent("recording.mp4")
    }

    private var canEdit: Bool {
        packet.status != .processing
            && packet.duration > 0
            && FileManager.default.fileExists(atPath: recordingURL.path)
    }

    private var isExporting: Bool {
        appState.videoEditInProgressPacketID == packet.id
    }

    private var isValidRange: Bool {
        trimStart >= 0
            && trimEnd <= packet.duration
            && trimEnd - trimStart >= 0.1
    }

    var body: some View {
        if canEdit {
            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Edit Video", systemImage: "scissors")
                        .font(.headline)

                    Spacer()

                    if packet.availableEditedRecordingURL != nil {
                        Button("Reveal Edited") {
                            appState.revealEditedRecording(for: packet)
                        }
                    }
                }

                HStack(spacing: 16) {
                    timeField("Start", value: $trimStart)
                    timeField("End", value: $trimEnd)
                    Text(DurationFormatter.string(from: max(0, trimEnd - trimStart)))
                        .foregroundStyle(.secondary)

                    Button(isExporting ? "Saving..." : "Save Trimmed Copy") {
                        appState.createTrimmedRecording(for: packet, start: trimStart, end: trimEnd)
                    }
                    .disabled(isExporting || !isValidRange)
                }

            }
            .onAppear {
                prepareIfNeeded()
            }
            .onChange(of: packet.id) { _, _ in
                prepareIfNeeded(force: true)
            }
            .onChange(of: trimStart) { _, _ in
                clampRange()
            }
            .onChange(of: trimEnd) { _, _ in
                clampRange()
            }
        }
    }

    private func timeField(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number.precision(.fractionLength(1)))
                    .frame(width: 64)
                    .monospacedDigit()
                Text("s")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func prepareIfNeeded(force: Bool = false) {
        guard force || preparedPacketID != packet.id else {
            return
        }
        preparedPacketID = packet.id
        trimStart = 0
        trimEnd = max(packet.duration, 0)
    }

    private func clampRange() {
        let duration = max(packet.duration, 0)
        trimStart = min(max(trimStart, 0), duration)
        trimEnd = min(max(trimEnd, 0), duration)
        if trimEnd < trimStart + 0.1 {
            trimEnd = min(duration, trimStart + 0.1)
        }
        if trimStart > trimEnd - 0.1 {
            trimStart = max(0, trimEnd - 0.1)
        }
    }
}
