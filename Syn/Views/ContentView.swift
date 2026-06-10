import SwiftUI
import AppKit
import AVFoundation

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 252, max: 300)
        } detail: {
            DetailView()
        }
    }
}

// MARK: - Status mapping

private func statusBadge(for status: PacketStatus) -> (SynState, String) {
    switch status {
    case .succeeded: return (.success, "Ready")
    case .processing: return (.processing, "Processing")
    case .partial: return (.warning, "Partial")
    case .failed: return (.error, "Failed")
    }
}

private func relativeText(_ date: Date) -> String {
    date.formatted(.relative(presentation: .named))
}

private func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}

// MARK: - Sidebar

private struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                eyebrow("Capture")
                SidebarActionRow(icon: "record.circle", label: "Start Recording") { appState.openCapturePicker() }
                SidebarActionRow(icon: "repeat", label: "Repeat Last Recording") { appState.repeatLastCapture() }
                SidebarActionRow(icon: "gearshape", label: "Settings") { appState.showSettingsWindow() }

                eyebrow("Previous Recordings").padding(.top, 14)

                if appState.recentPackets.isEmpty {
                    Text("No recordings yet")
                        .synFont(.subhead)
                        .foregroundStyle(SynColor.text3)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                } else {
                    ForEach(appState.recentPackets) { packet in
                        SidebarPacketCell(packet: packet, selected: appState.selectedPacketID == packet.id) {
                            appState.selectedPacketID = packet.id
                        }
                    }
                }
            }
            .padding(8)
        }
        .background(SynColor.sidebar)
        .navigationTitle("Syn")
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .synFont(.caption)
            .foregroundStyle(SynColor.text3)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}

private struct SidebarActionRow: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(SynColor.text2)
                    .frame(width: 18)
                Text(label)
                    .synFont(.body)
                    .foregroundStyle(SynColor.text1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(hover ? SynColor.selected : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct SidebarPacketCell: View {
    let packet: PacketSummary
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let info = statusBadge(for: packet.status)
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(packet.title)
                        .synFont(.headline)
                        .foregroundStyle(SynColor.text1)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        SynStatusBadge(state: info.0, pulse: packet.status == .processing, label: info.1)
                        Text(relativeText(packet.createdAt))
                            .synFont(.footnote)
                            .foregroundStyle(SynColor.text3)
                    }
                }
                Spacer(minLength: 4)
                Text(DurationFormatter.string(from: packet.duration))
                    .font(SynFont.mono(11))
                    .foregroundStyle(SynColor.text3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? SynColor.accentRing.opacity(0.6) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var background: Color {
        selected ? SynColor.accentTint : (hover ? SynColor.selected : .clear)
    }
}

// MARK: - Detail

private struct DetailView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isChromeTabPickerPresented {
                pickerWrapper { ChromeTabPickerView().environmentObject(appState).frame(maxWidth: 620) }
            } else {
                main
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SynColor.canvas)
        .navigationTitle("Overview")
    }

    private func pickerWrapper<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var main: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if appState.activeRecording != nil || appState.statusMessage != nil || appState.lastErrorMessage != nil {
                    StatusBannerView()
                }
                if let packet = appState.selectedPacket {
                    PacketDetailContent(packet: packet)
                } else {
                    EmptyDetailView { appState.openCapturePicker() }
                        .frame(minHeight: 380)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct EmptyDetailView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(SynColor.text3)
            Text("No recording selected")
                .synFont(.title3)
                .foregroundStyle(SynColor.text1)
            Text("Pick a previous recording, or start a new capture.")
                .synFont(.subhead)
                .foregroundStyle(SynColor.text2)
            Button(action: onStart) {
                Label("Start Recording", systemImage: "record.circle")
            }
            .buttonStyle(.synPrimary)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Section card

private struct SectionCard<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).synFont(.caption).foregroundStyle(SynColor.text3)
                Spacer()
                if let trailing {
                    Text(trailing).font(SynFont.mono(11)).foregroundStyle(SynColor.text3)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .synCard(padding: 16)
    }
}

// MARK: - Packet detail content

private struct PacketFileItem: Identifiable {
    var id: String { name }
    let name: String
    let sizeText: String
    let isHero: Bool
}

private struct PacketDetails {
    var modeTitle: String?
    var sourceTitle: String?
    var summary: String?
    var files: [PacketFileItem]
}

private struct PacketDetailContent: View {
    @EnvironmentObject private var appState: AppState
    let packet: PacketSummary
    @State private var details = PacketDetails(modeTitle: nil, sourceTitle: nil, summary: nil, files: [])
    @State private var thumbnail: NSImage?

    private var recordingURL: URL { packet.folderURL.appendingPathComponent("recording.mp4") }
    private var hasRecording: Bool { FileManager.default.fileExists(atPath: recordingURL.path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if hasRecording {
                VideoPreviewCard(thumbnail: thumbnail) { NSWorkspace.shared.open(recordingURL) }
            }
            overviewCard
            if let summary = details.summary, !summary.isEmpty {
                SectionCard(title: "Summary") {
                    Text(summary)
                        .synFont(.body)
                        .foregroundStyle(SynColor.text1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !details.files.isEmpty {
                filesCard
            }
            pathsCard
            VideoEditPanel(packet: packet)
        }
        .task(id: packet.id) {
            details = loadPacketDetails(packet)
            thumbnail = nil
            if hasRecording {
                thumbnail = await makeThumbnail(recordingURL)
            }
        }
    }

    private var header: some View {
        let info = statusBadge(for: packet.status)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Text(packet.title).synFont(.title2).foregroundStyle(SynColor.text1).lineLimit(1)
                SynStatusBadge(state: info.0, pulse: packet.status == .processing, label: info.1)
                Spacer(minLength: 0)
            }
            Text(metadataLine)
                .font(SynFont.mono(11.5))
                .foregroundStyle(SynColor.text2)
            actionBar
        }
    }

    private var metadataLine: String {
        var parts: [String] = []
        if let mode = details.modeTitle { parts.append(mode) }
        parts.append(DurationFormatter.string(from: packet.duration))
        parts.append(relativeText(packet.createdAt))
        return parts.joined(separator: "  ·  ")
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button { appState.copyPacketHandoff(for: packet) } label: {
                Label("Copy Packet", systemImage: "doc.on.doc")
            }
            .buttonStyle(.synPrimary)

            Button { NSWorkspace.shared.open(packet.folderURL) } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .buttonStyle(.synSecondary)

            if let zip = packet.availableZipURL {
                Button { NSWorkspace.shared.activateFileViewerSelecting([zip]) } label: {
                    Label("Reveal Zip", systemImage: "archivebox")
                }
                .buttonStyle(.synSecondary)
            }

            overflowMenu
            Spacer(minLength: 0)
        }
        .disabled(packet.status == .processing)
    }

    private var overflowMenu: some View {
        Menu {
            if let compact = packet.availableCompactZipURL {
                Button("Reveal Compact Zip") { NSWorkspace.shared.activateFileViewerSelecting([compact]) }
            } else {
                Button("Create Compact Zip") { appState.createCompactZip(for: packet) }
            }
            if let raw = packet.availableRawZipURL {
                Button("Reveal Raw Zip") { NSWorkspace.shared.activateFileViewerSelecting([raw]) }
            } else if FileManager.default.fileExists(atPath: packet.folderURL.appendingPathComponent("raw").path) {
                Button("Create Raw Zip") { appState.createRawZip(for: packet) }
            }
            if packet.availableEditedRecordingURL != nil {
                Button("Reveal Edited Recording") { appState.revealEditedRecording(for: packet) }
            }
            if packet.status == .partial || packet.status == .failed {
                Button("Retry Processing") { appState.retry(packet: packet) }
            }
            Divider()
            Button("Delete", role: .destructive) { appState.delete(packet: packet) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SynColor.text2)
                .frame(width: 34, height: 30)
                .background(SynColor.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(SynColor.hairlineStrong, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var overviewCard: some View {
        let info = statusBadge(for: packet.status)
        return SectionCard(title: "Overview") {
            VStack(spacing: 9) {
                detailRow("Status") { SynStatusBadge(state: info.0, label: info.1) }
                if let mode = details.modeTitle { textRow("Capture mode", mode) }
                if let source = details.sourceTitle { textRow("Source", source) }
                textRow("Duration", DurationFormatter.string(from: packet.duration))
                textRow("Created", packet.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private var filesCard: some View {
        SectionCard(title: "Included files (\(details.files.count))") {
            VStack(spacing: 2) {
                ForEach(details.files) { file in
                    HStack(spacing: 9) {
                        Image(systemName: file.isHero ? "sparkles" : "doc")
                            .font(.system(size: 12))
                            .foregroundStyle(file.isHero ? SynColor.accentDeep : SynColor.text3)
                            .frame(width: 16)
                        Text(file.name)
                            .font(SynFont.mono(12))
                            .foregroundStyle(file.isHero ? SynColor.accentDeep : SynColor.text1)
                        if file.isHero {
                            Text("HERO").synFont(.caption).foregroundStyle(SynColor.accentDeep)
                        }
                        Spacer()
                        Text(file.sizeText).synFont(.footnote).foregroundStyle(SynColor.text3)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var pathsCard: some View {
        SectionCard(title: "Paths") {
            VStack(spacing: 10) {
                pathRow("Packet folder", path: packet.folderURL.path,
                        reveal: { NSWorkspace.shared.activateFileViewerSelecting([packet.folderURL]) })
                if let zip = packet.availableZipURL {
                    pathRow("Shareable zip", path: zip.path,
                            reveal: { NSWorkspace.shared.activateFileViewerSelecting([zip]) })
                }
            }
        }
    }

    private func pathRow(_ label: String, path: String, reveal: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).synFont(.subhead).foregroundStyle(SynColor.text2)
                Text(path)
                    .font(SynFont.mono(11))
                    .foregroundStyle(SynColor.text1)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Button { copyToPasteboard(path) } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.plain).foregroundStyle(SynColor.text3).help("Copy path")
            Button(action: reveal) { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.plain).foregroundStyle(SynColor.text3).help("Reveal in Finder")
        }
    }

    private func textRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).synFont(.subhead).foregroundStyle(SynColor.text2).frame(width: 110, alignment: .leading)
            Text(value).synFont(.body).foregroundStyle(SynColor.text1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailRow<V: View>(_ label: String, @ViewBuilder _ value: () -> V) -> some View {
        HStack {
            Text(label).synFont(.subhead).foregroundStyle(SynColor.text2).frame(width: 110, alignment: .leading)
            value()
            Spacer()
        }
    }
}

private struct VideoPreviewCard: View {
    let thumbnail: NSImage?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                } else {
                    SynColor.surface3
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.42), in: Circle())
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: SynRadius.lg, style: .continuous))
            // The .fill thumbnail overflows its frame; clipShape only clips
            // drawing, not hit-testing. Without this contentShape the card's
            // invisible overflow swallows clicks meant for the action bar and
            // cards around it.
            .contentShape(RoundedRectangle(cornerRadius: SynRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SynRadius.lg, style: .continuous)
                    .strokeBorder(SynColor.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Disk loaders

private func loadPacketDetails(_ packet: PacketSummary) -> PacketDetails {
    let fm = FileManager.default
    var modeTitle: String?
    var sourceTitle: String?

    let manifestURL = packet.folderURL.appendingPathComponent("manifest.json")
    if let data = try? Data(contentsOf: manifestURL),
       let manifest = try? JSONDecoder.synDecoder.decode(PacketManifest.self, from: data) {
        modeTitle = CaptureMode(rawValue: manifest.capture.mode)?.title ?? manifest.capture.mode
        if let app = manifest.capture.appName {
            if let windowTitle = manifest.capture.windowTitle, !windowTitle.isEmpty {
                sourceTitle = "\(app) — \(windowTitle)"
            } else {
                sourceTitle = app
            }
        }
    }

    var summary: String?
    if let text = try? String(contentsOf: packet.folderURL.appendingPathComponent("summary.md"), encoding: .utf8) {
        summary = excerpt(from: text)
    }

    var files: [PacketFileItem] = []
    if let names = try? fm.contentsOfDirectory(atPath: packet.folderURL.path) {
        let order = ["agent-prompt.md", "summary.md", "transcript.md", "semantic-timeline.md", "recording.mp4", "manifest.json"]
        let sorted = names.filter { !$0.hasPrefix(".") }.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? Int.max
            let ib = order.firstIndex(of: b) ?? Int.max
            return ia != ib ? ia < ib : a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        for name in sorted.prefix(9) {
            let url = packet.folderURL.appendingPathComponent(name)
            var sizeText = ""
            if let attrs = try? fm.attributesOfItem(atPath: url.path) {
                if (attrs[.type] as? FileAttributeType) == .typeDirectory {
                    let count = (try? fm.contentsOfDirectory(atPath: url.path).count) ?? 0
                    sizeText = "\(count) items"
                } else if let size = attrs[.size] as? Int64 {
                    sizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                }
            }
            files.append(PacketFileItem(name: name, sizeText: sizeText, isHero: name == "agent-prompt.md"))
        }
    }

    return PacketDetails(modeTitle: modeTitle, sourceTitle: sourceTitle, summary: summary, files: files)
}

private func excerpt(from markdown: String) -> String {
    let lines = markdown
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("---") }
    return String(lines.joined(separator: " ").prefix(320))
}

private func makeThumbnail(_ url: URL) async -> NSImage? {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 1280, height: 1280)
    let time = CMTime(seconds: 0.5, preferredTimescale: 600)
    if let cgImage = try? await generator.image(at: time).image {
        return NSImage(cgImage: cgImage, size: .zero)
    }
    return nil
}

// MARK: - Status banner (live recording / messages)

private struct StatusBannerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.activeRecording != nil || appState.statusMessage != nil || appState.lastErrorMessage != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let recording = appState.activeRecording {
                    HStack(spacing: 10) {
                        SynStatusDot(
                            state: bannerState(for: recording),
                            pulse: recording.phase == .recording || recording.phase == .processing,
                            size: 9
                        )

                        Text(statusTitle(for: recording))
                            .synFont(.headline)
                            .foregroundStyle(SynColor.text1)

                        Text(recording.mode.title)
                            .synFont(.subhead)
                            .foregroundStyle(SynColor.text2)

                        Spacer()

                        Button(recording.isPaused ? "Resume" : "Pause") {
                            appState.pauseOrResumeRecording()
                        }
                        .buttonStyle(.synSecondary(.small))
                        .disabled(recording.phase == .processing)

                        Button("Stop") {
                            appState.stopRecording()
                        }
                        .buttonStyle(.synDestructive)
                        .disabled(recording.phase == .processing)
                    }
                }

                if let statusMessage = appState.statusMessage {
                    Text(statusMessage)
                        .synFont(.subhead)
                        .foregroundStyle(SynColor.text2)
                }

                if let warningMessage = appState.recordingDurationWarningMessage {
                    Label(warningMessage, systemImage: "exclamationmark.triangle.fill")
                        .synFont(.subhead)
                        .foregroundStyle(SynColor.warning)
                }

                if let lastErrorMessage = appState.lastErrorMessage {
                    Label(lastErrorMessage, systemImage: "xmark.octagon.fill")
                        .synFont(.subhead)
                        .foregroundStyle(SynColor.destructive)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .synCard(padding: 14)
        }
    }

    private func bannerState(for recording: ActiveRecording) -> SynState {
        switch recording.phase {
        case .processing: .processing
        case .paused: .paused
        default: .recording
        }
    }

    private func statusTitle(for recording: ActiveRecording) -> String {
        switch recording.phase {
        case .processing: "Processing"
        case .paused: "Paused"
        default: "Recording"
        }
    }
}

// MARK: - Video trim

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
            SectionCard(title: "Trim") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        timeField("Start", value: $trimStart)
                        timeField("End", value: $trimEnd)
                        Text(DurationFormatter.string(from: max(0, trimEnd - trimStart)))
                            .font(SynFont.mono(12))
                            .foregroundStyle(SynColor.text2)

                        Spacer()

                        if packet.availableEditedRecordingURL != nil {
                            Button("Reveal Edited") {
                                appState.revealEditedRecording(for: packet)
                            }
                            .buttonStyle(.synSecondary)
                        }

                        Button(isExporting ? "Saving…" : "Save Trimmed Copy") {
                            appState.createTrimmedRecording(for: packet, start: trimStart, end: trimEnd)
                        }
                        .buttonStyle(.synSecondary)
                        .disabled(isExporting || !isValidRange)
                    }
                }
            }
            .onAppear { prepareIfNeeded() }
            .onChange(of: packet.id) { _, _ in prepareIfNeeded(force: true) }
            .onChange(of: trimStart) { _, _ in clampRange() }
            .onChange(of: trimEnd) { _, _ in clampRange() }
        }
    }

    private func timeField(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(title).synFont(.subhead).foregroundStyle(SynColor.text2)
            TextField(title, value: value, format: .number.precision(.fractionLength(1)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .monospacedDigit()
            Text("s").synFont(.subhead).foregroundStyle(SynColor.text3)
        }
    }

    private func prepareIfNeeded(force: Bool = false) {
        guard force || preparedPacketID != packet.id else { return }
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
