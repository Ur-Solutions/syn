import AppKit
import SwiftUI

/// Hosts the capture picker in its own floating, frosted panel — a quick
/// command-palette-style window that pops over whatever the user is doing,
/// independent of the main Overview window.
@MainActor
final class CapturePickerPanelController {
    static let shared = CapturePickerPanelController()

    private var panel: NSPanel?
    private var resignKeyObserver: Any?

    private init() {}

    func show(appState: AppState) {
        guard !FixtureProcessingRunner.isRequested else {
            return
        }

        if panel == nil {
            let hostingView = NSHostingView(
                rootView: CapturePickerView()
                    .environmentObject(appState)
                    .frame(width: 660)
            )
            let panel = CapturePickerPanel(
                contentRect: NSRect(x: 0, y: 0, width: 660, height: 420),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = hostingView
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isFloatingPanel = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isMovableByWindowBackground = true
            panel.title = "Syn Capture Picker"
            self.panel = panel
        }

        positionPanel()
        panel?.makeKeyAndOrderFront(nil)
        panel?.orderFrontRegardless()
        panel?.makeFirstResponder(panel?.contentView)
        NSApp.activate(ignoringOtherApps: true)
        installResignKeyObserver(appState: appState)
    }

    func hide() {
        removeResignKeyObserver()
        panel?.orderOut(nil)
    }

    /// Center the picker on the screen the cursor is on — that's where the
    /// user is working and where the capture will most likely happen.
    private func positionPanel() {
        guard let panel else {
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else {
            return
        }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2 + visibleFrame.height * 0.06
        ))
    }

    /// Clicking anywhere outside the picker dismisses it, like a popover.
    private func installResignKeyObserver(appState: AppState) {
        removeResignKeyObserver()
        guard let panel else {
            return
        }
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if appState.isCapturePickerPresented {
                    appState.isCapturePickerPresented = false
                }
            }
        }
    }

    private func removeResignKeyObserver() {
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
        }
        resignKeyObserver = nil
    }
}

private final class CapturePickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct CapturePickerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Visual layout per the capture-picker mockup: three intent sections.
    /// Number shortcuts follow this visual order, top-left to bottom-right.
    private static let sections: [(title: String, modes: [CaptureMode])] = [
        ("Displays", [.screen, .allScreens]),
        ("Windows", [.activeWindowFollow, .selectedWindow]),
        ("Targeted", [.region, .smartRegion, .chromeTab])
    ]

    private static let orderedModes: [CaptureMode] = sections.flatMap(\.modes)

    var body: some View {
        VStack(alignment: .leading, spacing: SynSpace.s5) {
            header

            ForEach(Self.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: SynSpace.s2) {
                    Text(section.title)
                        .synFont(.caption)
                        .foregroundStyle(SynColor.text3)

                    HStack(alignment: .top, spacing: SynSpace.s3) {
                        ForEach(section.modes) { mode in
                            modeTile(mode, compact: section.modes.count > 2)
                        }
                    }
                }
            }

            footer
        }
        .padding(SynSpace.s6)
        // Frosted pass-through panel chrome, matching the recording HUD.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SynRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SynRadius.xl, style: .continuous)
                .strokeBorder(SynColor.materialBorder, lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Start Recording")
                    .synFont(.title2)
                    .foregroundStyle(SynColor.text1)

                Text(appState.lastCaptureMode.map { "Return repeats \($0.title)" } ?? "Choose a capture mode")
                    .synFont(.subhead)
                    .foregroundStyle(SynColor.text2)
            }

            Spacer()

            Button {
                appState.isCapturePickerPresented = false
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SynColor.text2)
                    .frame(width: 28, height: 28)
                    .background(SynColor.surface2, in: Circle())
                    .overlay(Circle().strokeBorder(SynColor.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
        }
    }

    private func modeTile(_ mode: CaptureMode, compact: Bool) -> some View {
        let isLast = appState.lastCaptureMode == mode
        let shortcutIndex = Self.orderedModes.firstIndex(of: mode).map { $0 + 1 }
        return Button {
            appState.prepareCapture(mode)
            dismiss()
        } label: {
            CaptureModeTile(mode: mode, isLast: isLast, shortcutNumber: shortcutIndex, compact: compact)
        }
        .buttonStyle(.plain)
        .ifLet(shortcutIndex) { view, index in
            view.keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: [])
        }
    }

    private var footer: some View {
        HStack(spacing: SynSpace.s3) {
            SynStatusBadge(
                state: appState.microphoneStatusText == "Mic ready" ? .success : .warning,
                label: appState.microphoneStatusText
            )

            Spacer()

            Text("1–7 quick start · ⏎ repeat last · esc close")
                .synFont(.footnote)
                .foregroundStyle(SynColor.text3)

            Button {
                appState.showSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SynColor.text2)
                    .frame(width: 28, height: 28)
                    .background(SynColor.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(SynColor.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Settings")

            // Hidden Return handler: repeats the last capture (mode + remembered
            // window/region/tab) without reaching for the mouse.
            if appState.lastCaptureMode != nil {
                Button("") { appState.repeatLastCapture() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.plain)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

private struct CaptureModeTile: View {
    let mode: CaptureMode
    let isLast: Bool
    let shortcutNumber: Int?
    var compact: Bool = false
    @State private var hover = false

    var body: some View {
        Group {
            if compact {
                compactLayout
            } else {
                wideLayout
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(SynSpace.s3)
        .background(
            hover ? SynColor.surface2 : SynColor.card,
            in: RoundedRectangle(cornerRadius: SynRadius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SynRadius.md, style: .continuous)
                .strokeBorder(
                    isLast ? SynColor.accentRing : (hover ? SynColor.hairlineStrong : SynColor.hairline),
                    lineWidth: isLast ? 1.5 : 1
                )
        )
        .synShadow(hover ? 2 : 1)
        .contentShape(RoundedRectangle(cornerRadius: SynRadius.md, style: .continuous))
        .onHover { hover = $0 }
        .animation(SynMotion.out, value: hover)
    }

    /// Two-per-row tile: icon left of text.
    private var wideLayout: some View {
        HStack(alignment: .top, spacing: SynSpace.s3) {
            iconSquare

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    title
                    if isLast { lastChip }
                }
                detail
            }

            Spacer(minLength: 0)

            keycap
        }
    }

    /// Three-per-row tile: icon row on top, text below, so narrow columns
    /// never truncate the mode title.
    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: SynSpace.s2) {
            HStack(spacing: 6) {
                iconSquare
                if isLast { lastChip }
                Spacer(minLength: 0)
                keycap
            }
            VStack(alignment: .leading, spacing: 2) {
                title
                detail
            }
        }
    }

    private var iconSquare: some View {
        Image(systemName: mode.systemImage)
            .font(.system(size: compact ? 14 : 16, weight: .medium))
            .foregroundStyle(isLast ? SynColor.accentDeep : SynColor.text2)
            .frame(width: compact ? 30 : 34, height: compact ? 30 : 34)
            .background(
                isLast ? SynColor.accentTint : SynColor.surface2,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
    }

    private var title: some View {
        Text(mode.title)
            .synFont(.headline)
            .foregroundStyle(SynColor.text1)
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var detail: some View {
        Text(mode.detail)
            .synFont(.footnote)
            .foregroundStyle(SynColor.text2)
            .lineLimit(2, reservesSpace: compact)
            .multilineTextAlignment(.leading)
    }

    private var lastChip: some View {
        Text("Last")
            .synFont(.caption)
            .foregroundStyle(SynColor.accentDeep)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(SynColor.accentTint, in: Capsule())
            .overlay(Capsule().strokeBorder(SynColor.accentRing, lineWidth: 1))
    }

    @ViewBuilder
    private var keycap: some View {
        if let shortcutNumber {
            SynKeyCap(label: "\(shortcutNumber)")
                .opacity(hover ? 1 : 0.55)
        }
    }
}

struct ChromeTabPickerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: SynSpace.s4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Select Chrome Tab")
                        .synFont(.title2)
                        .foregroundStyle(SynColor.text1)
                    Text("Google Chrome")
                        .synFont(.subhead)
                        .foregroundStyle(SynColor.text2)
                }

                Spacer()

                Button {
                    appState.cancelChromeTabSelection()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SynColor.text2)
                        .frame(width: 28, height: 28)
                        .background(SynColor.surface2, in: Circle())
                        .overlay(Circle().strokeBorder(SynColor.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            if appState.isLoadingChromeTabs {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading tabs…")
                        .synFont(.subhead)
                        .foregroundStyle(SynColor.text2)
                }
            }

            if let error = appState.chromeTabSelectionError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .synFont(.subhead)
                    .foregroundStyle(SynColor.destructive)
            }

            if appState.chromeTabCandidates.isEmpty, !appState.isLoadingChromeTabs {
                VStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(SynColor.text3)
                    Text("No Chrome tabs")
                        .synFont(.title3)
                        .foregroundStyle(SynColor.text1)
                    Text("Readable Google Chrome tabs will appear here.")
                        .synFont(.subhead)
                        .foregroundStyle(SynColor.text2)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: SynSpace.s2) {
                        ForEach(appState.chromeTabCandidates) { tab in
                            Button {
                                appState.selectChromeTab(tab)
                            } label: {
                                ChromeTabRow(tab: tab)
                            }
                            .buttonStyle(.plain)
                            .disabled(appState.isLoadingChromeTabs)
                        }
                    }
                }
                .frame(minHeight: 260, maxHeight: 430)
            }

            HStack {
                Button {
                    appState.refreshChromeTabs()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.synSecondary)
                .disabled(appState.isLoadingChromeTabs)

                Spacer()

                Button("Cancel") {
                    appState.cancelChromeTabSelection()
                }
                .buttonStyle(.synSecondary)
            }
        }
        .padding(SynSpace.s6)
        .background(SynColor.card, in: RoundedRectangle(cornerRadius: SynRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SynRadius.xl, style: .continuous)
                .strokeBorder(SynColor.hairline, lineWidth: 1)
        )
        .synShadow(2)
    }
}

private struct ChromeTabRow: View {
    let tab: ChromeTabTarget
    @State private var hover = false

    var body: some View {
        HStack(spacing: SynSpace.s3) {
            Image(systemName: "globe")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SynColor.text2)
                .frame(width: 32, height: 32)
                .background(SynColor.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.displayTitle)
                    .synFont(.headline)
                    .foregroundStyle(SynColor.text1)
                    .lineLimit(1)

                Text(tab.url)
                    .synFont(.footnote)
                    .foregroundStyle(SynColor.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text("W\(tab.windowIndex) · T\(tab.tabIndex)")
                .font(SynFont.mono(10.5))
                .foregroundStyle(SynColor.text3)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SynColor.text3)
        }
        .padding(.horizontal, SynSpace.s3)
        .padding(.vertical, 10)
        .background(
            hover ? SynColor.surface2 : SynColor.card,
            in: RoundedRectangle(cornerRadius: SynRadius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SynRadius.md, style: .continuous)
                .strokeBorder(hover ? SynColor.hairlineStrong : SynColor.hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: SynRadius.md, style: .continuous))
        .onHover { hover = $0 }
        .animation(SynMotion.out, value: hover)
    }
}
