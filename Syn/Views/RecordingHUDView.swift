import SwiftUI

struct RecordingHUDView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isDiscardArmed = false
    @State private var disarmTask: Task<Void, Never>?

    var body: some View {
        pill
            .frame(maxWidth: .infinity, maxHeight: .infinity) // center within the transparent panel
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: appState.completionFlash)
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isProcessing)
    }

    private var pillShape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    private var pill: some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: pillShape)
            .overlay(pillShape.strokeBorder(SynColor.materialBorder, lineWidth: 1))
            .synShadow(0)
            .fixedSize()
    }

    @ViewBuilder private var content: some View {
        if appState.completionFlash {
            completionContent
        } else if isProcessing {
            processingContent
        } else {
            recordingContent
        }
    }

    // MARK: Recording / paused

    private var recordingContent: some View {
        HStack(spacing: 14) {
            SynStatusDot(state: dotState, pulse: dotState == .recording, size: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(phaseTitle)
                    .synFont(.subhead)
                    .foregroundStyle(SynColor.text2)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    HStack(spacing: 8) {
                        Text(elapsedText(at: timeline.date))
                            .font(SynFont.mono(17, weight: .medium))
                            .foregroundStyle(SynColor.text1)
                        if showWarning(at: timeline.date) {
                            Text(RecordingDurationWarning.shortLabel)
                                .synFont(.footnote)
                                .foregroundStyle(SynColor.warning)
                        }
                    }
                }
            }
            .frame(minWidth: 92, alignment: .leading)

            HUDMicMeter(level: appState.micLevel, isActive: appState.isMicMeterActive)

            Rectangle()
                .fill(SynColor.hairline)
                .frame(width: 1, height: 26)
                .padding(.horizontal, 2)

            HStack(spacing: 8) {
                hudButton(
                    system: "paintpalette",
                    help: "Canvas Mode",
                    kind: appState.isCanvasModeEnabled ? .active : .neutral,
                    disabled: isProcessing || appState.activeRecording?.phase != .recording
                ) { appState.toggleCanvasMode() }

                hudButton(
                    system: appState.activeRecording?.isPaused == true ? "play.fill" : "pause.fill",
                    help: appState.activeRecording?.isPaused == true ? "Resume" : "Pause",
                    kind: .neutral,
                    disabled: isProcessing
                ) { appState.pauseOrResumeRecording() }

                hudButton(
                    system: isDiscardArmed ? "trash.fill" : "trash",
                    help: isDiscardArmed ? "Click again to discard recording" : "Discard recording",
                    kind: isDiscardArmed ? .armed : .neutral,
                    disabled: isProcessing
                ) { handleDiscard() }

                hudButton(system: "stop.fill", help: "Stop", kind: .stop, disabled: isProcessing) {
                    appState.stopRecording()
                }
            }
        }
    }

    // MARK: Processing

    private var processingContent: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(SynColor.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Building packet…")
                    .synFont(.headline)
                    .foregroundStyle(SynColor.text1)
                Text("Transcribing, summarizing, packaging…")
                    .synFont(.footnote)
                    .foregroundStyle(SynColor.text2)
            }
            .frame(minWidth: 168, alignment: .leading)
        }
    }

    // MARK: Completion — one calm beat

    private var completionContent: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(SynColor.successTint).frame(width: 34, height: 34)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(SynColor.success)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Packet ready")
                    .synFont(.headline)
                    .foregroundStyle(SynColor.text1)
                Text("Copied to clipboard")
                    .synFont(.footnote)
                    .foregroundStyle(SynColor.text2)
            }
            .frame(minWidth: 150, alignment: .leading)
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    // MARK: HUD icon button

    private enum HUDButtonKind { case neutral, active, armed, stop }

    private func hudButton(
        system: String,
        help: String,
        kind: HUDButtonKind,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let bg: Color
        let border: Color
        let fg: Color
        switch kind {
        case .neutral: bg = SynColor.surface2; border = SynColor.hairline; fg = SynColor.text2
        case .active:  bg = SynColor.accentTint; border = SynColor.accentRing; fg = SynColor.accentDeep
        case .armed:   bg = SynColor.destructive.opacity(0.14); border = SynColor.destructive.opacity(0.5); fg = SynColor.destructive
        case .stop:    bg = SynColor.destructive; border = .clear; fg = .white
        }
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(fg)
                .frame(width: 38, height: 34)
                .background(bg, in: shape)
                .overlay(shape.strokeBorder(border, lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .help(help)
    }

    private func handleDiscard() {
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
    }

    // MARK: Derived

    private var dotState: SynState {
        switch appState.activeRecording?.phase {
        case .paused: return .paused
        default: return .recording
        }
    }

    private var phaseTitle: String {
        switch appState.activeRecording?.phase {
        case .paused: return "Paused"
        default: return appState.activeRecording?.mode.title ?? "Recording"
        }
    }

    private var isProcessing: Bool {
        appState.activeRecording?.phase == .processing
    }

    private func showWarning(at date: Date) -> Bool {
        appState.activeRecording?.hasDurationWarning == true
            || elapsed(at: date) >= RecordingDurationWarning.threshold
    }

    private func elapsedText(at date: Date) -> String {
        let seconds = Int(elapsed(at: date).rounded())
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func elapsed(at date: Date) -> TimeInterval {
        appState.activeRecording?.elapsed(at: date) ?? 0
    }
}

/// Continuous mic meter: a small green→gray waveform that fills with the level.
private struct HUDMicMeter: View {
    let level: Double
    let isActive: Bool
    private let bars = 11

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<bars, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(color(for: i))
                    .frame(width: 3, height: height(for: i))
            }
        }
        .frame(height: 18)
        .help("Microphone level")
    }

    private func height(for i: Int) -> CGFloat {
        let t = Double(i) / Double(bars - 1)   // 0…1
        let hump = sin(.pi * t)                // 0…1…0
        return 5 + CGFloat(hump) * 12          // 5…17pt
    }

    private func color(for i: Int) -> Color {
        let clamped = min(max(level, 0), 1)
        let activeCount = Int((Double(bars) * clamped).rounded())
        if isActive && i < activeCount { return SynColor.success }
        return SynColor.text3.opacity(0.35)
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
        if appState.isCanvasModeEnabled {
            AnnotationOverlayController.shared.update(appState: appState)
        }

        if panel == nil {
            let hostingView = NSHostingView(rootView: RecordingHUDView().environmentObject(appState))
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 104),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = hostingView
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isFloatingPanel = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
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
            y: visibleFrame.maxY - size.height - 8
        )
        panel.setFrameOrigin(origin)
    }
}

private struct CanvasToolbarView: View {
    @EnvironmentObject private var appState: AppState
    private let colorSwatches = ["#EC6579", "#0A84FF", "#34C759", "#FF9F0A", "#1C1C1E"]

    var body: some View {
        HStack(spacing: 7) {
            dragHandle

            HStack(spacing: 4) {
                ForEach(AnnotationTool.canvasTools) { tool in
                    toolbarButton(
                        system: tool.symbolName,
                        help: toolHelp(tool),
                        isActive: appState.selectedAnnotationTool == tool
                    ) {
                        appState.selectCanvasTool(tool)
                    }
                }
            }

            separator

            HStack(spacing: 5) {
                ForEach(colorSwatches, id: \.self) { hex in
                    colorSwatch(hex)
                }
                CanvasColorWell(colorHex: Binding(
                    get: { appState.canvasColorHex },
                    set: { appState.selectCanvasColor(hex: $0) }
                ))
                .frame(width: 28, height: 28)
                .help("Choose annotation color")
            }

            separator

            toolbarButton(
                system: "trash",
                help: "Delete selected annotation",
                isEnabled: appState.selectedAnnotationStrokeID != nil
            ) {
                appState.deleteSelectedAnnotation()
            }

            toolbarButton(
                system: "eraser",
                help: "Clear canvas",
                isEnabled: !appState.visibleAnnotationStrokes.isEmpty
            ) {
                appState.clearAnnotations()
            }

            toolbarButton(system: "xmark", help: "Exit canvas mode") {
                appState.setCanvasMode(false)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(SynColor.materialBorder, lineWidth: 1)
        )
        .synShadow(0)
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(SynColor.text3)
            .frame(width: 24, height: 28)
            .contentShape(Rectangle())
            .help("Drag canvas toolbar")
    }

    private var separator: some View {
        Rectangle()
            .fill(SynColor.hairline)
            .frame(width: 1, height: 24)
            .padding(.horizontal, 2)
    }

    private func toolbarButton(
        system: String,
        help: String,
        isActive: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let fill = isActive ? SynColor.accentTint : SynColor.surface2
        let stroke = isActive ? SynColor.accentRing : SynColor.hairline
        let foreground = isActive ? SynColor.accentDeep : SynColor.text2

        return Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 30, height: 28)
                .background(fill, in: shape)
                .overlay(shape.strokeBorder(stroke, lineWidth: isActive ? 1.5 : 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .help(help)
    }

    private func colorSwatch(_ hex: String) -> some View {
        let selected = appState.canvasColorHex.uppercased() == hex
        let swatch = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let color = Color(nsColor: NSColor(hex: hex))

        return Button {
            appState.selectCanvasColor(hex: hex)
        } label: {
            swatch
                .fill(color)
                .frame(width: 20, height: 20)
                .overlay(swatch.strokeBorder(SynColor.materialBorder, lineWidth: 1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? SynColor.accentDeep : .clear, lineWidth: 2)
                        .frame(width: 26, height: 26)
                )
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("Use \(hex)")
    }

    private func toolHelp(_ tool: AnnotationTool) -> String {
        if let shortcut = tool.shortcutLabel {
            return "\(tool.title) (Right Shift + \(shortcut))"
        }
        return tool.title
    }
}

private struct CanvasColorWell: NSViewRepresentable {
    @Binding var colorHex: String

    func makeCoordinator() -> Coordinator {
        Coordinator(colorHex: $colorHex)
    }

    func makeNSView(context: Context) -> CanvasColorWellContainer {
        let container = CanvasColorWellContainer()
        container.colorWell.isBordered = false
        container.colorWell.target = context.coordinator
        container.colorWell.action = #selector(Coordinator.colorChanged(_:))
        return container
    }

    func updateNSView(_ container: CanvasColorWellContainer, context: Context) {
        let color = NSColor(hex: colorHex)
        if container.colorWell.color != color {
            container.colorWell.color = color
        }
    }

    final class Coordinator: NSObject {
        @Binding private var colorHex: String

        init(colorHex: Binding<String>) {
            _colorHex = colorHex
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            colorHex = sender.color.synToolbarHexString
        }
    }
}

private final class CanvasColorWellContainer: NSView {
    let colorWell = NSColorWell(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(colorWell)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 28, height: 28)
    }

    override func layout() {
        super.layout()
        colorWell.frame = bounds.insetBy(dx: 4, dy: 4)
    }
}

private extension NSColor {
    var synToolbarHexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        let red = max(0, min(255, Int(round(color.redComponent * 255))))
        let green = max(0, min(255, Int(round(color.greenComponent * 255))))
        let blue = max(0, min(255, Int(round(color.blueComponent * 255))))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

@MainActor
final class CanvasToolbarController {
    static let shared = CanvasToolbarController()

    private var panel: NSPanel?
    private weak var appState: AppState?

    private init() {}

    func show(appState: AppState) {
        guard appState.isCanvasModeEnabled else {
            hide()
            return
        }
        self.appState = appState
        AnnotationOverlayController.shared.update(appState: appState)

        if panel == nil {
            let hostingView = NSHostingView(rootView: CanvasToolbarView().environmentObject(appState))
            let panel = CanvasToolbarPanel(
                contentRect: NSRect(x: 0, y: 0, width: 548, height: 52),
                styleMask: [.nonactivatingPanel, .hudWindow],
                backing: .buffered,
                defer: false
            )
            panel.contentView = hostingView
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
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
        guard appState.isCanvasModeEnabled else {
            hide()
            return
        }
        AnnotationOverlayController.shared.update(appState: appState)
        guard panel != nil else {
            show(appState: appState)
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
