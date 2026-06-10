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
    private var keyMonitor: Any?

    private init() {}

    func begin(
        initialSelection: CGRect? = nil,
        initialDisplayID: CGDirectDisplayID? = nil,
        completion: @escaping (RegionSelection?) -> Void
    ) {
        cancel()
        self.completion = completion
        fixtureSelection = nil
        fixtureMovedSelection = false

        let prefillScreen = initialDisplayID.flatMap { id in
            NSScreen.screens.first(where: { $0.displayID == id })
        } ?? NSScreen.main ?? NSScreen.screens.first

        for screen in NSScreen.screens {
            var screenInitialSelection: CGRect?
            if let initialSelection, screen == prefillScreen {
                let local = CGRect(
                    x: min(max(initialSelection.minX, 0), max(0, screen.frame.width - initialSelection.width)),
                    y: min(max(initialSelection.minY, 0), max(0, screen.frame.height - initialSelection.height)),
                    width: min(initialSelection.width, screen.frame.width),
                    height: min(initialSelection.height, screen.frame.height)
                )
                screenInitialSelection = local
                fixtureSelection = RegionSelection(
                    rect: local,
                    globalRect: CGRect(
                        x: screen.frame.minX + local.minX,
                        y: screen.frame.minY + local.minY,
                        width: local.width,
                        height: local.height
                    ),
                    displayID: screen.displayID
                )
            }
            let view = RegionSelectionView(
                screen: screen,
                initialSelection: screenInitialSelection,
                onFixtureMove: { [weak self] moved in
                    self?.fixtureMovedSelection = self?.fixtureMovedSelection == true || moved
                },
                completion: { [weak self] selection in
                    self?.finish(selection)
                }
            )
            let window = RegionSelectionPanelWindow(
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
        completion = nil
        fixtureSelection = nil
        fixtureMovedSelection = false
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        // A local key monitor delivers keys regardless of which display's
        // borderless overlay window is key. Escape cancels; Enter confirms
        // whichever overlay currently holds a drawn selection; arrows nudge
        // (move) or resize (with Option) that selection.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }
            switch event.keyCode {
            case 53: // Escape
                self.finish(nil)
                return nil
            case 36, 76: // Return / keypad Enter
                for window in self.windows {
                    if let view = window.contentView as? RegionSelectionView,
                       view.confirmSelectionIfPresent() {
                        return nil
                    }
                }
                return event
            case 123, 124, 125, 126: // Arrow keys
                let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
                let resize = event.modifierFlags.contains(.option)
                let dx: CGFloat = event.keyCode == 123 ? -step : (event.keyCode == 124 ? step : 0)
                let dy: CGFloat = event.keyCode == 125 ? -step : (event.keyCode == 126 ? step : 0)
                for window in self.windows {
                    if let view = window.contentView as? RegionSelectionView,
                       view.nudgeSelection(dx: dx, dy: dy, resize: resize) {
                        return nil
                    }
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
        removeKeyMonitor()
        let handler = completion
        windows.forEach { $0.orderOut(nil) }
        windows = []
        completion = nil
        fixtureSelection = nil
        handler?(selection)
    }
}

private final class RegionSelectionPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class RegionSelectionView: NSView {
    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private enum DragMode {
        case drawing
        case moving
        case resizing(Handle)
    }

    private static let minimumSelectionEdge: CGFloat = 20
    private static let handleVisualSize: CGFloat = 8
    private static let handleHitSize: CGFloat = 18

    private let screen: NSScreen
    private let onFixtureMove: (Bool) -> Void
    private let completion: (RegionSelection?) -> Void
    private var dragMode: DragMode?
    private var dragStartPoint: CGPoint?
    private var dragStartRect: CGRect?
    private var currentDragRect: CGRect?
    private var selectedRect: CGRect?

    private var barItems: [SynOverlayChrome.BarItem] {
        [
            .init(title: "Confirm", keycap: "⏎", style: .primary),
            .init(title: "Cancel", keycap: "esc", style: .neutral)
        ]
    }

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

    var hasSelection: Bool { selectedRect != nil }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        SynOverlayInk.scrim.setFill()
        bounds.fill()

        let visibleRect = currentDragRect ?? selectedRect

        if let visibleRect {
            NSColor.clear.setFill()
            visibleRect.fill(using: .clear)

            if isActivelyShaping {
                drawThirdsGrid(in: visibleRect)
            }

            // White halo behind the rose stroke keeps the frame legible on dark content.
            let haloPath = NSBezierPath(rect: visibleRect.insetBy(dx: -1.5, dy: -1.5))
            haloPath.lineWidth = 3
            SynOverlayInk.halo.setStroke()
            haloPath.stroke()

            let path = NSBezierPath(rect: visibleRect)
            path.lineWidth = 2
            SynOverlayInk.accent.setStroke()
            path.stroke()

            if selectedRect != nil, !isDrawingNewRect {
                drawHandles(for: visibleRect)
            }

            drawDimensionChip(for: visibleRect)
        } else {
            SynOverlayChrome.drawMessageCard(
                title: "Drag to select a region",
                subtitle: "Return confirms · Esc cancels · Arrows nudge · ⌥ Arrows resize",
                center: CGPoint(x: bounds.midX, y: bounds.midY)
            )
        }

        if selectedRect != nil, dragMode == nil {
            SynOverlayChrome.drawBar(controlBarLayout(), items: barItems)
        }
    }

    private var isDrawingNewRect: Bool {
        if case .drawing = dragMode { return true }
        return false
    }

    private var isActivelyShaping: Bool {
        switch dragMode {
        case .drawing, .resizing: return true
        default: return false
        }
    }

    private func drawThirdsGrid(in rect: CGRect) {
        guard rect.width > 90, rect.height > 90 else {
            return
        }
        let path = NSBezierPath()
        let fractions: [CGFloat] = [1.0 / 3.0, 2.0 / 3.0]
        for fraction in fractions {
            path.move(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.minY))
            path.line(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * fraction))
            path.line(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * fraction))
        }
        path.lineWidth = 1
        SynOverlayInk.grid.setStroke()
        path.stroke()
    }

    private func drawHandles(for rect: CGRect) {
        for handle in Handle.allCases {
            let center = handleCenter(handle, in: rect)
            let visual = CGRect(
                x: center.x - Self.handleVisualSize / 2,
                y: center.y - Self.handleVisualSize / 2,
                width: Self.handleVisualSize,
                height: Self.handleVisualSize
            )
            let path = NSBezierPath(roundedRect: visual, xRadius: 2, yRadius: 2)
            NSColor.white.setFill()
            path.fill()
            SynOverlayInk.accent.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func drawDimensionChip(for rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let chipSize = SynOverlayChrome.chipSize(text: text)
        var chipY = rect.maxY + 10
        if chipY + chipSize.height > bounds.maxY - 4 {
            chipY = rect.maxY - chipSize.height - 10
        }
        SynOverlayChrome.drawChip(text: text, centerX: rect.midX, minY: chipY)
    }

    private func controlBarLayout() -> SynOverlayChrome.BarLayout {
        SynOverlayChrome.barLayout(items: barItems, centerX: bounds.midX, bottomY: bounds.minY + 56)
    }

    // MARK: Geometry

    private func handleCenter(_ handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    private func handleHitRect(_ handle: Handle, in rect: CGRect) -> CGRect {
        let center = handleCenter(handle, in: rect)
        return CGRect(
            x: center.x - Self.handleHitSize / 2,
            y: center.y - Self.handleHitSize / 2,
            width: Self.handleHitSize,
            height: Self.handleHitSize
        )
    }

    private func handle(at point: CGPoint) -> Handle? {
        guard let selectedRect else {
            return nil
        }
        return Handle.allCases.first { handleHitRect($0, in: selectedRect).contains(point) }
    }

    private func resizedRect(from rect: CGRect, handle: Handle, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch handle {
        case .topLeft: minX += dx; maxY += dy
        case .top: maxY += dy
        case .topRight: maxX += dx; maxY += dy
        case .right: maxX += dx
        case .bottomRight: maxX += dx; minY += dy
        case .bottom: minY += dy
        case .bottomLeft: minX += dx; minY += dy
        case .left: minX += dx
        }

        return CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let selectedRect {
            if dragMode == nil {
                let layout = controlBarLayout()
                if layout.frame.contains(point) {
                    let rects = layout.itemRects
                    if rects.indices.contains(0), rects[0].insetBy(dx: -6, dy: -6).contains(point) {
                        complete(with: selectedRect)
                        return
                    }
                    if rects.indices.contains(1), rects[1].insetBy(dx: -6, dy: -6).contains(point) {
                        completion(nil)
                        return
                    }
                    return // swallow clicks on the bar background
                }
            }

            if let handle = handle(at: point) {
                dragMode = .resizing(handle)
                dragStartPoint = point
                dragStartRect = selectedRect
                currentDragRect = nil
                needsDisplay = true
                return
            }

            if selectedRect.contains(point) {
                if event.clickCount >= 2 {
                    complete(with: selectedRect)
                    return
                }
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
        case .resizing(let handle):
            guard let dragStartRect else {
                return
            }
            var rect = resizedRect(
                from: dragStartRect,
                handle: handle,
                dx: point.x - dragStartPoint.x,
                dy: point.y - dragStartPoint.y
            )
            rect.size.width = max(Self.minimumSelectionEdge, rect.width)
            rect.size.height = max(Self.minimumSelectionEdge, rect.height)
            selectedRect = clamped(rect)
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
        switch dragMode {
        case .moving, .resizing:
            dragMode = nil
            dragStartPoint = nil
            dragStartRect = nil
            currentDragRect = nil
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        case .drawing, nil:
            break
        }

        guard let rect = currentDragRect,
              rect.width > Self.minimumSelectionEdge,
              rect.height > Self.minimumSelectionEdge else {
            dragMode = nil
            dragStartPoint = nil
            dragStartRect = nil
            currentDragRect = nil
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }

        selectedRect = rect
        dragMode = nil
        currentDragRect = nil
        dragStartPoint = nil
        dragStartRect = nil
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
        guard let selectedRect else {
            return
        }
        addCursorRect(selectedRect, cursor: .openHand)
        for handle in Handle.allCases {
            addCursorRect(handleHitRect(handle, in: selectedRect), cursor: resizeCursor(for: handle))
        }
        let layout = controlBarLayout()
        addCursorRect(layout.frame, cursor: .arrow)
        for rect in layout.itemRects where !rect.isNull {
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    private func resizeCursor(for handle: Handle) -> NSCursor {
        switch handle {
        case .topLeft: return .frameResize(position: .topLeft, directions: .all)
        case .top: return .frameResize(position: .top, directions: .all)
        case .topRight: return .frameResize(position: .topRight, directions: .all)
        case .right: return .frameResize(position: .right, directions: .all)
        case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
        case .bottom: return .frameResize(position: .bottom, directions: .all)
        case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
        case .left: return .frameResize(position: .left, directions: .all)
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            completion(nil)
        } else if event.keyCode == 36, let selectedRect {
            complete(with: selectedRect)
        }
    }

    func confirmSelectionIfPresent() -> Bool {
        guard let selectedRect else {
            return false
        }
        complete(with: selectedRect)
        return true
    }

    /// Arrow-key nudge: moves the selection (or resizes it with Option).
    /// Returns false when this overlay holds no selection.
    func nudgeSelection(dx: CGFloat, dy: CGFloat, resize: Bool) -> Bool {
        guard let rect = selectedRect else {
            return false
        }
        if resize {
            var next = rect
            next.size.width = max(Self.minimumSelectionEdge, rect.width + dx)
            next.size.height = max(Self.minimumSelectionEdge, rect.height + dy)
            selectedRect = clamped(next)
        } else {
            selectedRect = clamped(rect.offsetBy(dx: dx, dy: dy))
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        return true
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

    // MARK: Fixtures

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
