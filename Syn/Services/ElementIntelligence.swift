import AppKit
import ApplicationServices

// MARK: - Element Intelligence (PRD MVP 1: macOS Accessibility element picker)
//
// `Right Shift + E` during a recording toggles element picker mode: the accessibility
// element under the cursor gets a live hover highlight, a click flags it (click again to
// unflag), and flagged elements are stored in the packet (`elements/flagged-elements.json`),
// listed in the agent prompts, and burned into the processed video as numbered callouts.
// See docs/ELEMENT_INTELLIGENCE_PRD.md.

/// Normalized record of a flagged UI element (provider-dependent fields optional).
struct FlaggedElementSnapshot: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    var index: Int
    /// Seconds into the recording when the element was flagged.
    var timestamp: TimeInterval
    var provider: String
    var role: String?
    var label: String?
    var value: String?
    var identifier: String?
    var appName: String?
    var appBundleID: String?
    var windowTitle: String?
    /// Global Cocoa screen coordinates (bottom-left origin), matching pointer events.
    var screenBounds: CodableRect
    /// Final-video pixel coordinates (top-left origin); filled during processing.
    var videoBounds: CodableRect?
    /// DOM-level identity when a `browser.*` provider supplied the snapshot.
    var web: WebElementBlock? = nil
    /// Component identity from a dev-mode framework resolver (React/Svelte).
    var framework: FrameworkElementBlock? = nil
    /// Lower-priority provider snapshots preserved through a merge (e.g. AX under browser).
    var rawProviders: [RawProviderSnapshot]? = nil
}

/// Hover lookup + flagging overlay driven by the macOS Accessibility tree.
@MainActor
final class ElementPickerController {
    static let shared = ElementPickerController()

    private(set) var isActive = false
    private weak var appState: AppState?
    private var windows: [NSWindow] = []
    private var mouseMonitors: [Any] = []
    private var lastLookupAt = Date.distantPast
    private var hover: (bounds: CGRect, title: String)?
    /// The full snapshot behind the current highlight; clicks flag exactly this.
    private var hoverSnapshot: FlaggedElementSnapshot?
    /// Discards bridge answers that arrive after the cursor has moved on.
    private var hoverGeneration = 0

    /// Windows owned by these apps get a web-element bridge lookup before AX wins.
    static let browserBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "org.chromium.Chromium", "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "org.mozilla.firefox",
        "app.zen-browser.zen"
    ]

    private init() {}

    func setActive(_ active: Bool, appState: AppState) {
        guard active != isActive else { return }
        self.appState = appState
        isActive = active
        GlobalHotkeyService.shared.setCanvasModeActive(active || appState.isCanvasModeEnabled)
        if active {
            showOverlays()
            installMonitors()
            refreshHover(at: NSEvent.mouseLocation)
        } else {
            removeMonitors()
            hover = nil
            hoverSnapshot = nil
            windows.forEach { $0.orderOut(nil) }
            windows = []
        }
    }

    private func showOverlays() {
        windows = NSScreen.screens.map { screen in
            let view = ElementPickerOverlayView(screen: screen, controller: self)
            let window = ElementPickerWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.title = "Syn Element Picker"
            window.contentView = view
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.acceptsMouseMovedEvents = true
            window.orderFrontRegardless()
            return window
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    private func installMonitors() {
        removeMonitors()
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.refreshHover(at: NSEvent.mouseLocation)
            return event
        } {
            mouseMonitors.append(monitor)
        }
    }

    private func removeMonitors() {
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
        mouseMonitors = []
    }

    /// AX lookup with a small debounce; bounds returned in global Cocoa coordinates.
    /// Over a connected `@syn/web-elements` page the bridge answer is authoritative;
    /// the previous hover stays on screen until it lands (a few ms locally). Drawing
    /// the AX rect first and replacing it alternates two rects on every mouse move,
    /// and Chrome's lazily built AX tree intermittently returns nil — both read as
    /// flicker.
    private func refreshHover(at cocoaPoint: CGPoint) {
        guard isActive, Date().timeIntervalSince(lastLookupAt) > 0.05 else { return }
        lastLookupAt = Date()
        hoverGeneration += 1
        let generation = hoverGeneration

        let ax = Self.accessibilitySnapshot(atCocoaPoint: cocoaPoint)
        guard Self.shouldConsultBridge(for: ax) else {
            apply(hoverSnapshot: ax, at: cocoaPoint)
            return
        }
        Task { [weak self] in
            let merged = await WebElementBridge.shared.snapshot(atCocoaPoint: cocoaPoint, merging: ax)
            guard let self, self.isActive, self.hoverGeneration == generation else { return }
            self.apply(hoverSnapshot: merged ?? ax, at: cocoaPoint)
        }
    }

    private func apply(hoverSnapshot snapshot: FlaggedElementSnapshot?, at point: CGPoint) {
        guard let snapshot else {
            // Nil is usually the hit-test landing on our own highlight (excluded as a
            // self-hit) or a transient AX failure, not an empty spot. Keep the current
            // highlight while the cursor is still inside it; clear once it leaves.
            if let hover, !hover.bounds.contains(point) {
                self.hover = nil
                self.hoverSnapshot = nil
                redraw()
            }
            return
        }
        hoverSnapshot = snapshot
        var title = [snapshot.role, snapshot.label ?? snapshot.value]
            .compactMap { $0 }
            .joined(separator: " — ")
        if let component = snapshot.framework?.componentName {
            title += " · <\(component)>"
        }
        let bounds = snapshot.screenBounds.rect
        if let hover, hover.bounds == bounds, hover.title == title { return }
        hover = (bounds, title)
        redraw()
    }

    /// Consult connected pages when the cursor is over a browser window — or when AX
    /// has no answer at all (Chrome's AX hit-test fails intermittently; pages verify
    /// the point against their own viewport, so a stray non-browser match is unlikely).
    private static func shouldConsultBridge(for ax: FlaggedElementSnapshot?) -> Bool {
        guard WebElementBridge.shared.hasClients else { return false }
        guard let bundleID = ax?.appBundleID else { return true }
        return browserBundleIDs.contains(bundleID)
    }

    fileprivate func handleClick(atCocoaPoint point: CGPoint) {
        guard let appState else { return }
        // Clicking an already-flagged element unflags it.
        if let existing = appState.flaggedElements.last(where: { $0.screenBounds.rect.contains(point) }) {
            appState.removeFlaggedElement(id: existing.id)
            redraw()
            return
        }
        // Flag what the user sees: the snapshot behind the current highlight. A fresh
        // lookup at click time can self-hit the overlay fill or race the bridge.
        if let snapshot = hoverSnapshot, snapshot.screenBounds.rect.contains(point) {
            flag(snapshot: snapshot)
            return
        }
        let ax = Self.accessibilitySnapshot(atCocoaPoint: point)
        if Self.shouldConsultBridge(for: ax) {
            Task { [weak self] in
                let merged = await WebElementBridge.shared.snapshot(atCocoaPoint: point, merging: ax)
                self?.flag(snapshot: merged ?? ax)
            }
        } else {
            flag(snapshot: ax)
        }
    }

    /// No isActive guard: the click happened while the picker was active; a flag must
    /// not be lost because the bridge answered just after Esc/stop deactivated it.
    private func flag(snapshot: FlaggedElementSnapshot?) {
        guard var snapshot, let appState else { return }
        snapshot.index = appState.flaggedElements.count + 1
        snapshot.timestamp = appState.activeRecording?.elapsed(at: Date()) ?? 0
        appState.appendFlaggedElement(snapshot)
        redraw()
    }

    fileprivate func currentHover() -> (bounds: CGRect, title: String)? { hover }
    fileprivate func currentFlags() -> [FlaggedElementSnapshot] { appState?.flaggedElements ?? [] }

    fileprivate func requestExit() {
        appState?.setElementPicker(false)
    }

    private func redraw() {
        windows.forEach { $0.contentView?.needsDisplay = true }
    }

    /// One Accessibility hit-test, normalized. Cocoa point in, Cocoa bounds out.
    static func accessibilitySnapshot(atCocoaPoint cocoaPoint: CGPoint) -> FlaggedElementSnapshot? {
        let primaryHeight = (NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.screens.first)?.frame.height ?? 0
        let axPoint = CGPoint(x: cocoaPoint.x, y: primaryHeight - cocoaPoint.y)

        var element: AXUIElement?
        let systemWide = AXUIElementCreateSystemWide()
        guard AXUIElementCopyElementAtPosition(systemWide, Float(axPoint.x), Float(axPoint.y), &element) == .success,
              let element else {
            return nil
        }

        // The picker overlay draws a translucent fill under the cursor, so the
        // hit-test regularly lands on Syn's own window. Treating that as a result
        // flips the highlight between the element and our overlay — feedback flicker.
        var hitPid: pid_t = 0
        AXUIElementGetPid(element, &hitPid)
        guard hitPid != ProcessInfo.processInfo.processIdentifier else { return nil }

        func string(_ attribute: String) -> String? {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            if let text = value as? String, !text.isEmpty { return String(text.prefix(200)) }
            return nil
        }

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        var axOrigin = CGPoint.zero
        var axSize = CGSize.zero
        if let positionRef { AXValueGetValue(positionRef as! AXValue, .cgPoint, &axOrigin) }
        if let sizeRef { AXValueGetValue(sizeRef as! AXValue, .cgSize, &axSize) }
        guard axSize.width > 1, axSize.height > 1, axSize.width < 4000, axSize.height < 3000 else {
            return nil
        }

        // AX coordinates are top-left global; convert to Cocoa (bottom-left).
        let cocoaBounds = CGRect(
            x: axOrigin.x,
            y: primaryHeight - axOrigin.y - axSize.height,
            width: axSize.width,
            height: axSize.height
        )

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let app = NSRunningApplication(processIdentifier: pid)

        return FlaggedElementSnapshot(
            index: 0,
            timestamp: 0,
            provider: "macos.accessibility",
            role: string(kAXRoleAttribute as String),
            label: string(kAXTitleAttribute as String) ?? string(kAXDescriptionAttribute as String),
            value: string(kAXValueAttribute as String),
            identifier: string(kAXIdentifierAttribute as String),
            appName: app?.localizedName,
            appBundleID: app?.bundleIdentifier,
            windowTitle: nil,
            screenBounds: CodableRect(cocoaBounds),
            videoBounds: nil
        )
    }
}

private final class ElementPickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Per-screen overlay: hover outline + numbered flags, drawn with the Syn overlay ink.
private final class ElementPickerOverlayView: NSView {
    private let screen: NSScreen
    private weak var controller: ElementPickerController?

    init(screen: NSScreen, controller: ElementPickerController) {
        self.screen = screen
        self.controller = controller
        super.init(frame: screen.frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    private func localRect(_ globalCocoa: CGRect) -> CGRect {
        CGRect(
            x: globalCocoa.minX - screen.frame.minX,
            y: globalCocoa.minY - screen.frame.minY,
            width: globalCocoa.width,
            height: globalCocoa.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let controller else { return }

        if let hover = controller.currentHover() {
            let rect = localRect(hover.bounds)
            if rect.intersects(bounds) {
                SynOverlayInk.accentTint.withAlphaComponent(0.16).setFill()
                rect.fill()
                let path = NSBezierPath(rect: rect)
                path.lineWidth = 1.5
                SynOverlayInk.accent.setStroke()
                path.stroke()
                if !hover.title.isEmpty {
                    SynOverlayChrome.drawLabelCard(
                        text: hover.title,
                        centerX: rect.midX,
                        minY: min(rect.maxY + 8, bounds.maxY - 30),
                        maxWidth: 560
                    )
                }
            }
        }

        for flag in controller.currentFlags() {
            let rect = localRect(flag.screenBounds.rect)
            guard rect.intersects(bounds) else { continue }
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2.5
            SynOverlayInk.accentDeep.setStroke()
            path.stroke()
            let badge = CGRect(x: rect.minX - 11, y: rect.maxY - 11, width: 22, height: 22)
            let badgePath = NSBezierPath(ovalIn: badge)
            SynOverlayInk.accentDeep.setFill()
            badgePath.fill()
            let text = "\(flag.index)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2),
                withAttributes: attributes
            )
        }

        let layout = SynOverlayChrome.barLayout(
            items: barItems,
            centerX: bounds.midX,
            bottomY: bounds.minY + 56
        )
        SynOverlayChrome.drawBar(layout, items: barItems)
    }

    private var barItems: [SynOverlayChrome.BarItem] {
        [
            .init(title: "Click an element to flag it · click again to unflag", keycap: nil, style: .hint),
            .init(title: "Done", keycap: "esc", style: .neutral)
        ]
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let layout = SynOverlayChrome.barLayout(items: barItems, centerX: bounds.midX, bottomY: bounds.minY + 56)
        if layout.frame.contains(local) {
            if let doneRect = layout.itemRects.last, !doneRect.isNull, doneRect.insetBy(dx: -6, dy: -6).contains(local) {
                controller?.requestExit()
            }
            return
        }
        controller?.handleClick(atCocoaPoint: NSEvent.mouseLocation)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            controller?.requestExit()
        }
    }
}

extension CodableRect {
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

extension FlaggedElementSnapshot {
    /// Bridges a flagged element into the existing annotation render pipeline so the
    /// highlight burns into recording.mp4 with the same mapping as canvas rectangles.
    /// Synthetic strokes are excluded from annotation metadata by ID after rendering.
    func syntheticStroke(recordingDuration: TimeInterval) -> AnnotationStroke {
        let bounds = screenBounds.rect
        return AnnotationStroke(
            id: id,
            tool: .rectangle,
            startTimestamp: max(0, timestamp - 0.2),
            endTimestamp: min(recordingDuration, timestamp + 2.6),
            sourcePoints: [
                CodablePoint(x: bounds.minX, y: bounds.minY),
                CodablePoint(x: bounds.maxX, y: bounds.maxY)
            ],
            videoPoints: nil,
            colorHex: "#D63850",
            lineWidth: 3,
            text: nil
        )
    }
}
