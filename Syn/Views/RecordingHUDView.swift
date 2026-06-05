import SwiftUI

struct RecordingHUDView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isDiscardArmed = false
    @State private var disarmTask: Task<Void, Never>?

    var body: some View {
        Group {
            if appState.completionFlash {
                completionFlash
            } else {
                recordingControls
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: appState.completionFlash)
    }

    private var completionFlash: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .repeat(2))
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.yellow)
                .symbolEffect(.variableColor.iterative, options: .repeating)
            VStack(alignment: .leading, spacing: 1) {
                Text("Packet ready")
                    .font(.callout)
                    .fontWeight(.semibold)
                Text("Transcript & summary done")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private var recordingControls: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(phaseTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(elapsedText(at: timeline.date))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                        if appState.activeRecording?.hasDurationWarning == true
                            || elapsed(at: timeline.date) >= RecordingDurationWarning.threshold {
                            Text(RecordingDurationWarning.shortLabel)
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
            }
            .frame(width: 112, alignment: .leading)

            MicLevelMeter(level: appState.micLevel, isActive: appState.isMicMeterActive)
                .frame(width: 54, height: 18)

            Divider()
                .frame(height: 24)

            Button {
                appState.toggleCanvasMode()
            } label: {
                Image(systemName: appState.isCanvasModeEnabled ? "paintpalette.fill" : "paintpalette")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(appState.isCanvasModeEnabled ? .accentColor : nil)
            .disabled(isProcessing || appState.activeRecording?.phase != .recording)
            .help("Canvas Mode")

            Button {
                appState.pauseOrResumeRecording()
            } label: {
                Image(systemName: appState.activeRecording?.isPaused == true ? "play.fill" : "pause.fill")
            }
            .disabled(isProcessing)
            .help(appState.activeRecording?.isPaused == true ? "Resume" : "Pause")

            Button(role: .destructive) {
                if isDiscardArmed {
                    disarmTask?.cancel()
                    disarmTask = nil
                    isDiscardArmed = false
                    appState.discardRecording()
                } else {
                    isDiscardArmed = true
                    disarmTask?.cancel()
                    disarmTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if !Task.isCancelled {
                            isDiscardArmed = false
                            disarmTask = nil
                        }
                    }
                }
            } label: {
                Image(systemName: isDiscardArmed ? "trash.fill" : "trash")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isDiscardArmed ? .red : nil)
            .disabled(isProcessing)
            .help(isDiscardArmed ? "Click again to discard recording" : "Discard recording")

            Button(role: .destructive) {
                appState.stopRecording()
            } label: {
                Image(systemName: "stop.fill")
            }
            .disabled(isProcessing)
            .help("Stop")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch appState.activeRecording?.phase {
        case .paused:
            "pause.circle.fill"
        case .processing:
            "gearshape.circle.fill"
        default:
            "record.circle.fill"
        }
    }

    private var iconColor: Color {
        switch appState.activeRecording?.phase {
        case .paused:
            .yellow
        case .processing:
            .blue
        default:
            .red
        }
    }

    private var phaseTitle: String {
        switch appState.activeRecording?.phase {
        case .processing:
            "Processing"
        case .paused:
            "Paused"
        default:
            appState.activeRecording?.mode.title ?? "Recording"
        }
    }

    private var isProcessing: Bool {
        appState.activeRecording?.phase == .processing
    }

    private func elapsedText(at date: Date) -> String {
        let elapsed = elapsed(at: date)
        let seconds = Int(elapsed.rounded())
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func elapsed(at date: Date) -> TimeInterval {
        appState.activeRecording?.elapsed(at: date) ?? 0
    }
}

private struct MicLevelMeter: View {
    let level: Double
    let isActive: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "mic.fill")
                .font(.caption2)
                .foregroundStyle(isActive ? .secondary : .tertiary)

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(barColor(index: index))
                        .frame(width: 4, height: barHeight(index: index))
                }
            }
            .frame(width: 28, height: 16, alignment: .bottom)
        }
        .help("Microphone level")
    }

    private func barHeight(index: Int) -> CGFloat {
        let threshold = Double(index + 1) / 5
        return level >= threshold && isActive ? CGFloat(6 + index * 2) : 4
    }

    private func barColor(index: Int) -> Color {
        guard isActive else {
            return .secondary.opacity(0.25)
        }

        let threshold = Double(index + 1) / 5
        if level >= threshold {
            return index >= 4 ? .yellow : .green
        }
        return .secondary.opacity(0.25)
    }
}

@MainActor
final class RecordingHUDController {
    static let shared = RecordingHUDController()

    private var panel: NSPanel?
    private weak var appState: AppState?

    private init() {}

    var currentFrame: NSRect? {
        panel?.frame
    }

    func show(appState: AppState) {
        self.appState = appState

        if panel == nil {
            let hostingView = NSHostingView(rootView: RecordingHUDView().environmentObject(appState))
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 72),
                styleMask: [.nonactivatingPanel, .hudWindow],
                backing: .buffered,
                defer: false
            )
            panel.contentView = hostingView
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.title = "Syn Recording"
            self.panel = panel
        }

        positionPanel()
        panel?.orderFrontRegardless()
    }

    func update(appState: AppState) {
        show(appState: appState)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func positionPanel() {
        guard let panel else {
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else {
            return
        }

        let size = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 24
        )
        panel.setFrameOrigin(origin)
    }
}

private struct CanvasToolbarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .help("Drag canvas toolbar")

            ForEach(AnnotationTool.canvasTools) { tool in
                Button {
                    appState.selectCanvasTool(tool)
                } label: {
                    Image(systemName: tool.symbolName)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(appState.selectedAnnotationTool == tool ? .accentColor : nil)
                .help(toolHelp(tool))
            }

            Divider()
                .frame(height: 22)

            Button {
                appState.deleteSelectedAnnotation()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.selectedAnnotationStrokeID == nil)
            .help("Delete selected annotation")

            Button {
                appState.clearAnnotations()
            } label: {
                Image(systemName: "eraser")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.visibleAnnotationStrokes.isEmpty)
            .help("Clear canvas")

            Button {
                appState.setCanvasMode(false)
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Exit canvas mode")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func toolHelp(_ tool: AnnotationTool) -> String {
        if let shortcut = tool.shortcutLabel {
            return "\(tool.title) (Right Shift + \(shortcut))"
        }
        return tool.title
    }
}

@MainActor
final class CanvasToolbarController {
    static let shared = CanvasToolbarController()

    private var panel: NSPanel?
    private weak var appState: AppState?

    private init() {}

    func show(appState: AppState) {
        self.appState = appState

        if panel == nil {
            let hostingView = NSHostingView(rootView: CanvasToolbarView().environmentObject(appState))
            let panel = CanvasToolbarPanel(
                contentRect: NSRect(x: 0, y: 0, width: 330, height: 56),
                styleMask: [.nonactivatingPanel, .hudWindow],
                backing: .buffered,
                defer: false
            )
            panel.contentView = hostingView
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isMovableByWindowBackground = true
            panel.title = "Syn Canvas"
            self.panel = panel
            positionPanelBelowRecordingHUD()
        }

        panel?.orderFrontRegardless()
    }

    func update(appState: AppState) {
        guard panel != nil else {
            if appState.isCanvasModeEnabled {
                show(appState: appState)
            }
            return
        }
        self.appState = appState
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func close() {
        panel?.close()
        panel = nil
    }

    private func positionPanelBelowRecordingHUD() {
        guard let panel else { return }
        let size = panel.frame.size
        if let hudFrame = RecordingHUDController.shared.currentFrame {
            let origin = NSPoint(
                x: hudFrame.midX - size.width / 2,
                y: hudFrame.minY - size.height - 8
            )
            panel.setFrameOrigin(origin)
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let recordingHUDHeight: CGFloat = 72
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - recordingHUDHeight - size.height - 34
        )
        panel.setFrameOrigin(origin)
    }
}

private final class CanvasToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
