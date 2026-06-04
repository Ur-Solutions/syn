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
        let initialSelectedID = preselectFirstCandidate ? candidates.first?.id : nil
        fixtureSelectedWindowID = initialSelectedID
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
                onSelect: { [weak self] windowID in
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
        // A local key monitor handles Enter/Escape regardless of which display's
        // overlay window is key (only one borderless window can be key at a time),
        // using the controller-level selection so confirm works on any screen.
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
    private let onSelect: (CGWindowID) -> Void
    private var hoveredID: CGWindowID?
    private var selectedID: CGWindowID?

    init(
        screen: NSScreen,
        candidates: [WindowSelectionCandidate],
        initialSelectedID: CGWindowID?,
        onConfirm: @escaping (CGWindowID) -> Void,
        onCancel: @escaping () -> Void,
        onSelect: @escaping (CGWindowID) -> Void
    ) {
        self.screen = screen
        self.candidates = candidates
        self.selectedID = initialSelectedID
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onSelect = onSelect
        super.init(frame: screen.frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        for candidate in candidates {
            guard let localRect = localRect(for: candidate.rect), localRect.intersects(bounds) else {
                continue
            }

            let isHovered = candidate.id == hoveredID
            let isSelected = candidate.id == selectedID
            let fillAlpha: CGFloat = isSelected ? 0.24 : (isHovered ? 0.18 : 0.06)
            NSColor.controlAccentColor.withAlphaComponent(fillAlpha).setFill()
            localRect.fill()

            let path = NSBezierPath(rect: localRect)
            path.lineWidth = isSelected || isHovered ? 3 : 1.5
            NSColor.controlAccentColor.withAlphaComponent(isSelected || isHovered ? 1 : 0.72).setStroke()
            path.stroke()

            if isHovered || isSelected {
                drawLabel(for: candidate, in: localRect)
            }

            if isSelected {
                drawButtons(for: localRect)
            }
        }

        let label = selectedID == nil
            ? "Click a window to select it. Esc cancels."
            : "Confirm selected window. Enter starts. Esc cancels."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = label.size(withAttributes: attributes)
        label.draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    override func mouseMoved(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        hoveredID = candidate(atLocalPoint: localPoint)?.id
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)

        if let selected = selectedCandidate(),
           let localRect = localRect(for: selected.rect) {
            let buttons = buttonRects(for: localRect)
            if buttons.confirm.contains(localPoint) {
                onConfirm(selected.id)
                return
            }
            if buttons.cancel.contains(localPoint) {
                onCancel()
                return
            }
        }

        if let candidate = candidate(atLocalPoint: localPoint) {
            selectedID = candidate.id
            onSelect(candidate.id)
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else if event.keyCode == 36,
                  let selectedID {
            onConfirm(selectedID)
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

    private func selectedCandidate() -> WindowSelectionCandidate? {
        guard let selectedID else {
            return nil
        }
        return candidates.first { $0.id == selectedID }
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

    private func buttonRects(for rect: CGRect) -> (confirm: CGRect, cancel: CGRect) {
        let buttonSize = CGSize(width: 86, height: 30)
        let gap: CGFloat = 8
        let y = max(12, rect.minY - buttonSize.height - 12)
        let confirm = CGRect(x: rect.minX, y: y, width: buttonSize.width, height: buttonSize.height)
        let cancel = CGRect(x: confirm.maxX + gap, y: y, width: 74, height: buttonSize.height)
        return (confirm, cancel)
    }

    private func drawButtons(for rect: CGRect) {
        let buttons = buttonRects(for: rect)
        drawButton(title: "Confirm", rect: buttons.confirm, fill: .controlAccentColor)
        drawButton(title: "Cancel", rect: buttons.cancel, fill: .darkGray)
    }

    private func drawButton(title: String, rect: CGRect, fill: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        fill.withAlphaComponent(0.95).setFill()
        path.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = title.size(withAttributes: attributes)
        title.draw(
            at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawLabel(for candidate: WindowSelectionCandidate, in rect: CGRect) {
        let title = [candidate.appName, candidate.title]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " - ")
        guard !title.isEmpty else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let truncated = title.count > 72 ? "\(title.prefix(69))..." : title
        let size = truncated.size(withAttributes: attributes)
        let labelRect = CGRect(x: rect.minX, y: rect.maxY + 6, width: size.width + 14, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        truncated.draw(
            at: CGPoint(x: labelRect.minX + 7, y: labelRect.midY - size.height / 2),
            withAttributes: attributes
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
