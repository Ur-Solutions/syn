import AppKit

struct RegionSelection: Codable, Equatable, Sendable {
    /// Display-local AppKit rectangle from the selector. ScreenCaptureKit flips this at the capture boundary.
    var rect: CGRect
    /// Global macOS screen-space rectangle used for pointer mapping and metadata.
    var globalRect: CGRect?
    var displayID: CGDirectDisplayID
}

@MainActor
final class RegionSelectionController {
    static let shared = RegionSelectionController()

    private var windows: [NSWindow] = []
    private var completion: ((RegionSelection?) -> Void)?
    private var fixtureSelection: RegionSelection?
    private var fixtureMovedSelection = false

    private init() {}

    func begin(initialSelection: CGRect? = nil, completion: @escaping (RegionSelection?) -> Void) {
        cancel()
        self.completion = completion
        fixtureSelection = nil
        fixtureMovedSelection = false

        for screen in NSScreen.screens {
            if let initialSelection, screen == (NSScreen.main ?? NSScreen.screens.first) {
                fixtureSelection = RegionSelection(
                    rect: initialSelection,
                    globalRect: CGRect(
                        x: screen.frame.minX + initialSelection.minX,
                        y: screen.frame.minY + initialSelection.minY,
                        width: initialSelection.width,
                        height: initialSelection.height
                    ),
                    displayID: screen.displayID
                )
            }
            let view = RegionSelectionView(
                screen: screen,
                initialSelection: initialSelection,
                onFixtureMove: { [weak self] moved in
                    self?.fixtureMovedSelection = self?.fixtureMovedSelection == true || moved
                },
                completion: { [weak self] selection in
                    self?.finish(selection)
                }
            )
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.title = "Syn Region Selection"
            window.contentView = view
            window.backgroundColor = .clear
            window.isOpaque = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.makeFirstResponder(view)
            window.orderFrontRegardless()
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func cancel() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        completion = nil
        fixtureSelection = nil
        fixtureMovedSelection = false
    }

    func confirmFixtureSelection() {
        finish(fixtureSelection)
    }

    func driveFixtureDragAndConfirm() {
        guard let window = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
              let view = window.contentView as? RegionSelectionView else {
            return
        }
        view.performFixtureDragAndConfirm()
    }

    func consumeFixtureMoveFlagForTesting() -> Bool {
        let moved = fixtureMovedSelection
        fixtureMovedSelection = false
        return moved
    }

    private func finish(_ selection: RegionSelection?) {
        let handler = completion
        windows.forEach { $0.orderOut(nil) }
        windows = []
        completion = nil
        fixtureSelection = nil
        handler?(selection)
    }
}

private final class RegionSelectionView: NSView {
    private enum DragMode {
        case drawing
        case moving
    }

    private let screen: NSScreen
    private let onFixtureMove: (Bool) -> Void
    private let completion: (RegionSelection?) -> Void
    private var dragMode: DragMode?
    private var dragStartPoint: CGPoint?
    private var dragStartRect: CGRect?
    private var currentDragRect: CGRect?
    private var selectedRect: CGRect?

    init(
        screen: NSScreen,
        initialSelection: CGRect?,
        onFixtureMove: @escaping (Bool) -> Void,
        completion: @escaping (RegionSelection?) -> Void
    ) {
        self.screen = screen
        self.onFixtureMove = onFixtureMove
        self.completion = completion
        self.selectedRect = initialSelection
        super.init(frame: screen.frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        let visibleRect = currentDragRect ?? selectedRect

        if let visibleRect {
            NSColor.clear.setFill()
            visibleRect.fill(using: .clear)
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: visibleRect)
            path.lineWidth = 2
            path.stroke()

            let label = "\(Int(visibleRect.width)) x \(Int(visibleRect.height))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            label.draw(at: CGPoint(x: visibleRect.minX + 8, y: visibleRect.maxY + 8), withAttributes: attributes)

            if let selectedRect, currentDragRect == nil {
                drawButtons(for: selectedRect)
            }
        } else {
            let label = "Drag a region. Confirm to start. Esc cancels."
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
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let selectedRect {
            let buttons = buttonRects(for: selectedRect)
            if buttons.confirm.contains(point) {
                complete(with: selectedRect)
                return
            }
            if buttons.cancel.contains(point) {
                completion(nil)
                return
            }
            if selectedRect.contains(point) {
                dragMode = .moving
                dragStartPoint = point
                dragStartRect = selectedRect
                currentDragRect = nil
                needsDisplay = true
                return
            }
        }

        dragMode = .drawing
        dragStartPoint = point
        dragStartRect = nil
        currentDragRect = nil
        selectedRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartPoint else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)

        switch dragMode {
        case .moving:
            guard let dragStartRect else {
                return
            }
            let delta = CGSize(width: point.x - dragStartPoint.x, height: point.y - dragStartPoint.y)
            selectedRect = clamped(
                CGRect(
                    x: dragStartRect.minX + delta.width,
                    y: dragStartRect.minY + delta.height,
                    width: dragStartRect.width,
                    height: dragStartRect.height
                )
            )
        case .drawing, nil:
            currentDragRect = CGRect(
                x: min(dragStartPoint.x, point.x),
                y: min(dragStartPoint.y, point.y),
                width: abs(dragStartPoint.x - point.x),
                height: abs(dragStartPoint.y - point.y)
            )
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if dragMode == .moving {
            dragMode = nil
            dragStartPoint = nil
            dragStartRect = nil
            currentDragRect = nil
            needsDisplay = true
            return
        }

        guard let rect = currentDragRect, rect.width > 20, rect.height > 20 else {
            dragMode = nil
            dragStartPoint = nil
            dragStartRect = nil
            currentDragRect = nil
            needsDisplay = true
            return
        }

        selectedRect = rect
        dragMode = nil
        currentDragRect = nil
        dragStartPoint = nil
        dragStartRect = nil
        needsDisplay = true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if let selectedRect {
            let buttons = buttonRects(for: selectedRect)
            addCursorRect(selectedRect, cursor: .openHand)
            addCursorRect(buttons.confirm, cursor: .pointingHand)
            addCursorRect(buttons.cancel, cursor: .pointingHand)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            completion(nil)
        } else if event.keyCode == 36, let selectedRect {
            complete(with: selectedRect)
        }
    }

    private func complete(with rect: CGRect) {
        let windowRect = convert(rect, to: nil)
        let globalRect = CGRect(
            x: screen.frame.minX + windowRect.minX,
            y: screen.frame.minY + windowRect.minY,
            width: windowRect.width,
            height: windowRect.height
        )
        completion(RegionSelection(rect: windowRect, globalRect: globalRect, displayID: screen.displayID))
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

    private func clamped(_ rect: CGRect) -> CGRect {
        let maxX = max(bounds.minX, bounds.maxX - rect.width)
        let maxY = max(bounds.minY, bounds.maxY - rect.height)
        return CGRect(
            x: min(max(rect.minX, bounds.minX), maxX),
            y: min(max(rect.minY, bounds.minY), maxY),
            width: min(rect.width, bounds.width),
            height: min(rect.height, bounds.height)
        )
    }

    func performFixtureDragAndConfirm() {
        let insetX = min(max(bounds.width * 0.08, 180), 260)
        let insetY = min(max(bounds.height * 0.08, 120), 180)
        let start = CGPoint(x: bounds.midX - insetX, y: bounds.midY - insetY)
        let end = CGPoint(x: bounds.midX + insetX, y: bounds.midY + insetY)

        if let event = mouseEvent(type: .leftMouseDown, point: start) {
            mouseDown(with: event)
        }

        for step in 1...8 {
            let t = CGFloat(step) / 8
            let point = CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t
            )
            if let event = mouseEvent(type: .leftMouseDragged, point: point) {
                mouseDragged(with: event)
            }
        }

        if let event = mouseEvent(type: .leftMouseUp, point: end) {
            mouseUp(with: event)
        }

        let beforeMove = selectedRect
        if let selectedRect {
            let moveStart = CGPoint(x: selectedRect.midX, y: selectedRect.midY)
            let moveEnd = CGPoint(
                x: min(bounds.maxX - 16, moveStart.x + min(96, bounds.width * 0.06)),
                y: min(bounds.maxY - 16, moveStart.y + min(72, bounds.height * 0.06))
            )
            if let event = mouseEvent(type: .leftMouseDown, point: moveStart) {
                mouseDown(with: event)
            }
            for step in 1...6 {
                let t = CGFloat(step) / 6
                let point = CGPoint(
                    x: moveStart.x + (moveEnd.x - moveStart.x) * t,
                    y: moveStart.y + (moveEnd.y - moveStart.y) * t
                )
                if let event = mouseEvent(type: .leftMouseDragged, point: point) {
                    mouseDragged(with: event)
                }
            }
            if let event = mouseEvent(type: .leftMouseUp, point: moveEnd) {
                mouseUp(with: event)
            }
        }
        let moved = beforeMove.map { before in
            guard let selectedRect else { return false }
            return abs(before.minX - selectedRect.minX) > 0.5
                || abs(before.minY - selectedRect.minY) > 0.5
        } ?? false
        onFixtureMove(moved)

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

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
    }
}
