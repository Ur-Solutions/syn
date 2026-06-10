import AppKit
import CoreGraphics

@MainActor
final class WindowSelectionController {
    static let shared = WindowSelectionController()

    private var windows: [NSWindow] = []
    private var completion: ((CGWindowID?) -> Void)?
    private var candidates: [WindowSelectionCandidate] = []
    private var fixtureSelectedWindowID: CGWindowID?
    private var currentSelectedID: CGWindowID?
    private var keyMonitor: Any?

    private init() {}

    func begin(preselectFirstCandidate: Bool = false, completion: @escaping (CGWindowID?) -> Void) {
        cancel()
        self.completion = completion
        candidates = eligibleWindowCandidates()

        // Highlight the window already under the cursor so Enter (or one click)
        // starts immediately; fixtures can force the first candidate instead.
        let initialSelectedID = preselectFirstCandidate
            ? candidates.first?.id
            : candidateUnderMouse()?.id
        fixtureSelectedWindowID = preselectFirstCandidate ? initialSelectedID : nil
        currentSelectedID = initialSelectedID

        for screen in NSScreen.screens {
            let view = WindowSelectionOverlayView(
                screen: screen,
                candidates: candidates,
                initialSelectedID: initialSelectedID,
                onConfirm: { [weak self] windowID in
                    self?.finish(windowID)
                },
                onCancel: { [weak self] in
                    self?.finish(nil)
                },
                onHighlight: { [weak self] windowID in
                    self?.currentSelectedID = windowID
                }
            )
            let window = WindowSelectionPanelWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.title = containsSelectedCandidate(on: screen, selectedID: initialSelectedID)
                ? "Syn Window Selection Target"
                : "Syn Window Selection"
            window.contentView = view
            window.backgroundColor = .clear
            window.isOpaque = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.acceptsMouseMovedEvents = true
            window.orderFrontRegardless()
            window.makeKey()
            window.makeFirstResponder(view)
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
    }

    func cancel() {
        removeKeyMonitor()
        windows.forEach { $0.orderOut(nil) }
        windows = []
        candidates = []
        completion = nil
        fixtureSelectedWindowID = nil
        currentSelectedID = nil
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        // A local key monitor handles keys regardless of which display's overlay
        // window is key (only one borderless window can be key at a time).
        // Escape cancels, Enter starts the highlighted window, Tab/arrows cycle
        // the highlight through the candidate list.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }
            switch event.keyCode {
            case 53: // Escape
                self.finish(nil)
                return nil
            case 36, 76: // Return / keypad Enter
                if let id = self.currentSelectedID {
                    self.finish(id)
                    return nil
                }
                return event
            case 48: // Tab
                self.cycleHighlight(forward: !event.modifierFlags.contains(.shift))
                return nil
            case 124, 125: // Right / Down arrows
                self.cycleHighlight(forward: true)
                return nil
            case 123, 126: // Left / Up arrows
                self.cycleHighlight(forward: false)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func cycleHighlight(forward: Bool) {
        guard !candidates.isEmpty else {
            return
        }
        let nextIndex: Int
        if let currentSelectedID,
           let index = candidates.firstIndex(where: { $0.id == currentSelectedID }) {
            nextIndex = (index + (forward ? 1 : -1) + candidates.count) % candidates.count
        } else {
            nextIndex = forward ? 0 : candidates.count - 1
        }
        setHighlight(candidates[nextIndex].id)
    }

    private func setHighlight(_ windowID: CGWindowID?) {
        currentSelectedID = windowID
        for window in windows {
            (window.contentView as? WindowSelectionOverlayView)?.updateHighlight(windowID)
        }
    }

    private func candidateUnderMouse() -> WindowSelectionCandidate? {
        let mouse = NSEvent.mouseLocation
        let primaryHeight = (NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.screens.first)?.frame.height ?? 0
        let quartzPoint = CGPoint(x: mouse.x, y: primaryHeight - mouse.y)
        return candidates.first { $0.rect.contains(quartzPoint) }
    }

    func confirmFixtureSelection() {
        finish(fixtureSelectedWindowID)
    }

    func driveFixtureClickAndConfirm() {
        guard let candidate = candidates.first,
              let view = windows.first?.contentView as? WindowSelectionOverlayView else {
            return
        }
        view.performFixtureClickAndConfirm(candidateRect: candidate.rect)
    }

    private func finish(_ windowID: CGWindowID?) {
        removeKeyMonitor()
        let handler = completion
        windows.forEach { $0.orderOut(nil) }
        windows = []
        candidates = []
        completion = nil
        fixtureSelectedWindowID = nil
        currentSelectedID = nil
        handler?(windowID)
    }

    private func eligibleWindowCandidates() -> [WindowSelectionCandidate] {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ownPID = getpid()
        return infoList.compactMap { info -> WindowSelectionCandidate? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != ownPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let number = info[kCGWindowNumber as String] as? UInt32 else {
                return nil
            }

            let rect = CGRect(
                x: bounds["X"] as? CGFloat ?? 0,
                y: bounds["Y"] as? CGFloat ?? 0,
                width: bounds["Width"] as? CGFloat ?? 0,
                height: bounds["Height"] as? CGFloat ?? 0
            )
            guard rect.width > 80, rect.height > 60 else {
                return nil
            }

            return WindowSelectionCandidate(
                id: CGWindowID(number),
                rect: rect,
                appName: info[kCGWindowOwnerName as String] as? String,
                title: info[kCGWindowName as String] as? String
            )
        }
    }

    private func containsSelectedCandidate(on screen: NSScreen, selectedID: CGWindowID?) -> Bool {
        guard let selectedID,
              let candidate = candidates.first(where: { $0.id == selectedID }) else {
            return false
        }

        return candidate.rect.intersects(screen.frame)
    }
}

private struct WindowSelectionCandidate {
    var id: CGWindowID
    var rect: CGRect
    var appName: String?
    var title: String?
}

private final class WindowSelectionPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class WindowSelectionOverlayView: NSView {
    private let screen: NSScreen
    private let candidates: [WindowSelectionCandidate]
    private let onConfirm: (CGWindowID) -> Void
    private let onCancel: () -> Void
    private let onHighlight: (CGWindowID?) -> Void
    private var highlightedID: CGWindowID?

    private var barItems: [SynOverlayChrome.BarItem] {
        [
            .init(title: "Click a window to start · ⇥ cycles · ⏎ starts", keycap: nil, style: .hint),
            .init(title: "Cancel", keycap: "esc", style: .neutral)
        ]
    }

    init(
        screen: NSScreen,
        candidates: [WindowSelectionCandidate],
        initialSelectedID: CGWindowID?,
        onConfirm: @escaping (CGWindowID) -> Void,
        onCancel: @escaping () -> Void,
        onHighlight: @escaping (CGWindowID?) -> Void
    ) {
        self.screen = screen
        self.candidates = candidates
        self.highlightedID = initialSelectedID
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onHighlight = onHighlight
        super.init(frame: screen.frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    func updateHighlight(_ windowID: CGWindowID?) {
        highlightedID = windowID
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        SynOverlayInk.scrim.setFill()
        bounds.fill()

        for candidate in candidates {
            guard let localRect = localRect(for: candidate.rect), localRect.intersects(bounds) else {
                continue
            }

            let isHighlighted = candidate.id == highlightedID

            if isHighlighted {
                // Punch the highlighted window out of the scrim so it reads at
                // full brightness — "this is what you'll record".
                NSColor.clear.setFill()
                localRect.fill(using: .clear)
                SynOverlayInk.accentTint.withAlphaComponent(0.14).setFill()
                localRect.fill()

                let haloPath = NSBezierPath(rect: localRect.insetBy(dx: -1.5, dy: -1.5))
                haloPath.lineWidth = 3
                SynOverlayInk.halo.setStroke()
                haloPath.stroke()

                let path = NSBezierPath(rect: localRect)
                path.lineWidth = 2.5
                SynOverlayInk.accent.setStroke()
                path.stroke()

                drawLabel(for: candidate, in: localRect)
            } else {
                let path = NSBezierPath(rect: localRect)
                path.lineWidth = 1
                NSColor.white.withAlphaComponent(0.4).setStroke()
                path.stroke()
            }
        }

        if candidates.isEmpty {
            SynOverlayChrome.drawMessageCard(
                title: "No windows to capture",
                subtitle: "Open the window you want to record, then try again · Esc cancels",
                center: CGPoint(x: bounds.midX, y: bounds.midY)
            )
        } else {
            SynOverlayChrome.drawBar(controlBarLayout(), items: barItems)
        }
    }

    private func controlBarLayout() -> SynOverlayChrome.BarLayout {
        SynOverlayChrome.barLayout(items: barItems, centerX: bounds.midX, bottomY: bounds.minY + 56)
    }

    override func mouseMoved(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let hovered = candidate(atLocalPoint: localPoint)?.id
        if hovered != highlightedID {
            highlightedID = hovered
            onHighlight(hovered)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)

        let layout = controlBarLayout()
        if layout.frame.contains(localPoint) {
            if let cancelRect = layout.itemRects.last,
               !cancelRect.isNull,
               cancelRect.insetBy(dx: -6, dy: -6).contains(localPoint) {
                onCancel()
            }
            return
        }

        // One click starts the recording — no separate confirm step.
        if let candidate = candidate(atLocalPoint: localPoint) {
            onConfirm(candidate.id)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else if event.keyCode == 36,
                  let highlightedID {
            onConfirm(highlightedID)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let layout = controlBarLayout()
        addCursorRect(layout.frame, cursor: .arrow)
        for rect in layout.itemRects where !rect.isNull {
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    private func candidate(atLocalPoint localPoint: CGPoint) -> WindowSelectionCandidate? {
        candidates.first { candidate in
            guard let rect = localRect(for: candidate.rect) else {
                return false
            }
            return rect.contains(localPoint)
        }
    }

    private func localRect(for globalRect: CGRect) -> CGRect? {
        // candidate.rect comes from CGWindowListCopyWindowInfo in Quartz coordinates:
        // top-left origin, Y grows DOWN, global across the display arrangement.
        // This view is a Cocoa NSView (bottom-left origin, Y grows UP) whose local space
        // is offset by the screen's Cocoa frame. Flip Y against the primary display height,
        // then subtract this screen's Cocoa origin to land in view-local space.
        let primaryHeight = (NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.screens.first)?.frame.height ?? screen.frame.height
        let cocoaGlobalY = primaryHeight - globalRect.maxY
        return CGRect(
            x: globalRect.minX - screen.frame.minX,
            y: cocoaGlobalY - screen.frame.minY,
            width: globalRect.width,
            height: globalRect.height
        )
    }

    private func drawLabel(for candidate: WindowSelectionCandidate, in rect: CGRect) {
        let title = [candidate.appName, candidate.title]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " — ")
        guard !title.isEmpty else {
            return
        }

        var labelY = rect.maxY + 10
        if labelY + 24 > bounds.maxY - 4 {
            labelY = rect.maxY - 24 - 10
        }
        SynOverlayChrome.drawLabelCard(
            text: title,
            centerX: rect.midX,
            minY: labelY,
            maxWidth: min(rect.width + 80, bounds.width - 24)
        )
    }

    func performFixtureClickAndConfirm(candidateRect: CGRect) {
        guard let localRect = localRect(for: candidateRect) else {
            return
        }
        let localPoint = CGPoint(x: localRect.midX, y: localRect.midY)
        if let event = mouseEvent(type: .mouseMoved, point: localPoint) {
            mouseMoved(with: event)
        }
        if let event = mouseEvent(type: .leftMouseUp, point: localPoint) {
            mouseUp(with: event)
        }
        if let event = returnKeyEvent() {
            keyDown(with: event)
        }
    }

    private func mouseEvent(type: NSEvent.EventType, point: CGPoint) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        )
    }

    private func returnKeyEvent() -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )
    }
}
