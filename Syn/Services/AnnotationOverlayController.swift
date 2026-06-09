import AppKit
import Foundation

@MainActor
final class AnnotationRecorder {
    private var startedAt: Date?
    private var pauseStartedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private var strokes: [AnnotationStroke] = []
    private var draft: AnnotationStroke?
    private let defaultLineWidth = 5.0

    var visibleStrokes: [AnnotationStroke] {
        strokes + [draft].compactMap { $0 }
    }

    var committedStrokes: [AnnotationStroke] {
        strokes
    }

    func start() {
        startedAt = .now
        pauseStartedAt = nil
        pausedDuration = 0
        strokes = []
        draft = nil
    }

    func pause() {
        guard pauseStartedAt == nil else { return }
        pauseStartedAt = .now
        finishDraft()
    }

    func resume() {
        guard let pauseStartedAt else { return }
        pausedDuration += Date().timeIntervalSince(pauseStartedAt)
        self.pauseStartedAt = nil
    }

    func stop() -> [AnnotationStroke] {
        finishDraft()
        let snapshot = strokes
        startedAt = nil
        pauseStartedAt = nil
        pausedDuration = 0
        strokes = []
        return snapshot
    }

    func clear() {
        strokes = []
        draft = nil
    }

    func deleteStroke(id: UUID) {
        strokes.removeAll { $0.id == id }
        if draft?.id == id {
            draft = nil
        }
    }

    func begin(tool: AnnotationTool, at point: CGPoint, colorHex: String) {
        guard pauseStartedAt == nil else { return }
        let timestamp = currentTimestamp()
        draft = AnnotationStroke(
            id: UUID(),
            tool: tool,
            startTimestamp: timestamp,
            endTimestamp: timestamp,
            sourcePoints: [CodablePoint(x: point.x, y: point.y)],
            videoPoints: nil,
            colorHex: colorHex,
            lineWidth: defaultLineWidth
        )
    }

    func update(at point: CGPoint, constrained: Bool = false) {
        guard var current = draft else { return }
        current.endTimestamp = currentTimestamp()
        let codablePoint = CodablePoint(x: point.x, y: point.y)
        switch current.tool {
        case .pen:
            if current.sourcePoints.last?.distance(to: codablePoint) ?? .infinity >= 2 {
                current.sourcePoints.append(codablePoint)
            }
        case .line, .rectangle, .ellipse, .arrow:
            current.updateDraftEndpoint(to: point, constrained: constrained)
        case .text:
            break
        }
        draft = current
    }

    func addText(_ text: String, at point: CGPoint, colorHex: String) {
        guard pauseStartedAt == nil else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let timestamp = currentTimestamp()
        strokes.append(AnnotationStroke(
            id: UUID(),
            tool: .text,
            startTimestamp: timestamp,
            endTimestamp: timestamp + 0.2,
            sourcePoints: [CodablePoint(x: point.x, y: point.y)],
            videoPoints: nil,
            colorHex: colorHex,
            lineWidth: defaultLineWidth,
            text: trimmed
        ))
    }

    func moveStroke(id: UUID, by delta: CGSize) {
        guard pauseStartedAt == nil else { return }
        if let index = strokes.firstIndex(where: { $0.id == id }) {
            strokes[index].moveSourcePoints(by: delta)
        }
        if draft?.id == id {
            draft?.moveSourcePoints(by: delta)
        }
    }

    func resizeStroke(id: UUID, handle: AnnotationResizeHandle, to point: CGPoint, constrained: Bool) {
        guard pauseStartedAt == nil else { return }
        if let index = strokes.firstIndex(where: { $0.id == id }) {
            strokes[index].resizeSourcePoints(handle: handle, to: point, constrained: constrained)
        }
        if draft?.id == id {
            draft?.resizeSourcePoints(handle: handle, to: point, constrained: constrained)
        }
    }

    func setStrokeColor(id: UUID, colorHex: String) {
        if let index = strokes.firstIndex(where: { $0.id == id }) {
            strokes[index].colorHex = colorHex
        }
        if draft?.id == id {
            draft?.colorHex = colorHex
        }
    }

    func finishDraft() {
        guard var current = draft else { return }
        current.endTimestamp = max(current.endTimestamp, current.startTimestamp + 0.2)
        if current.tool == .text {
            if current.sourcePoints.count >= 1, current.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                strokes.append(current)
            }
        } else if current.sourcePoints.count >= 2 {
            strokes.append(current)
        }
        draft = nil
    }

    private func currentTimestamp() -> TimeInterval {
        guard let startedAt else {
            return 0
        }
        return max(0, Date().timeIntervalSince(startedAt) - pausedDuration)
    }
}

@MainActor
final class AnnotationOverlayController {
    static let shared = AnnotationOverlayController()

    private var windows: [AnnotationOverlayWindow] = []
    private weak var appState: AppState?

    private init() {}

    func show(appState: AppState) {
        self.appState = appState
        rebuildWindowsIfNeeded(appState: appState)
        windows.forEach { $0.orderFrontRegardless() }
    }

    func update(appState: AppState) {
        show(appState: appState)
        windows.forEach { $0.annotationView.refreshDisplayNow() }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
    }

    func close() {
        windows.forEach { $0.close() }
        windows = []
    }

    private func rebuildWindowsIfNeeded(appState: AppState) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        if windows.count == screens.count {
            zip(windows, screens).forEach { window, screen in
                window.screenFrame = screen.frame
                window.setFrame(screen.frame, display: true)
                window.annotationView.screenFrame = screen.frame
                window.annotationView.appState = appState
                window.ignoresMouseEvents = !appState.isCanvasModeEnabled
                window.annotationView.refreshDisplayNow()
            }
            return
        }

        close()
        windows = screens.map { screen in
            let view = AnnotationOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.appState = appState
            view.screenFrame = screen.frame
            view.autoresizingMask = [.width, .height]
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layerContentsRedrawPolicy = .onSetNeedsDisplay

            let window = AnnotationOverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.contentView = view
            window.annotationView = view
            window.screenFrame = screen.frame
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            window.ignoresMouseEvents = !appState.isCanvasModeEnabled
            window.title = "Syn Annotation Overlay"
            view.refreshDisplayNow()
            return window
        }
    }
}

final class AnnotationOverlayWindow: NSPanel {
    weak var annotationView: AnnotationOverlayView!
    var screenFrame: CGRect = .zero

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        ignoresMouseEvents = annotationView?.appState?.isCanvasModeEnabled != true
        super.sendEvent(event)
    }
}

final class AnnotationOverlayView: NSView {
    weak var appState: AppState?
    var screenFrame: CGRect = .zero
    private enum ActiveDrag {
        case move(strokeID: UUID, lastGlobalPoint: CGPoint)
        case resize(strokeID: UUID, handle: AnnotationResizeHandle)
    }

    private var activeDrag: ActiveDrag?
    private let resizeHandleSize: CGFloat = 10

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    func refreshDisplayNow() {
        needsDisplay = true
        displayIfNeeded()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let appState else { return }
        draw(strokes: appState.visibleAnnotationStrokes)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        appState?.isCanvasModeEnabled == true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        appState?.isCanvasModeEnabled == true ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let appState, appState.isCanvasModeEnabled else { return }
        let globalPoint = NSEvent.mouseLocation
        if let selectedID = appState.selectedAnnotationStrokeID,
           let handle = hitResizeHandle(at: globalPoint, selectedStrokeID: selectedID, in: appState.visibleAnnotationStrokes) {
            activeDrag = .resize(strokeID: selectedID, handle: handle)
            needsDisplay = true
            return
        }

        if let strokeID = hitStroke(at: globalPoint, in: appState.visibleAnnotationStrokes) {
            activeDrag = .move(strokeID: strokeID, lastGlobalPoint: globalPoint)
            appState.selectAnnotationStroke(id: strokeID)
            needsDisplay = true
            return
        }
        activeDrag = nil
        guard let tool = appState.selectedAnnotationTool else { return }
        if tool == .text {
            appState.beginAnnotationText(at: globalPoint)
            needsDisplay = true
            return
        }
        appState.beginAnnotationStroke(tool: tool, at: NSEvent.mouseLocation)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let globalPoint = NSEvent.mouseLocation
        switch activeDrag {
        case let .move(strokeID, lastGlobalPoint):
            let delta = CGSize(
                width: globalPoint.x - lastGlobalPoint.x,
                height: globalPoint.y - lastGlobalPoint.y
            )
            appState?.moveAnnotationStroke(id: strokeID, by: delta)
            activeDrag = .move(strokeID: strokeID, lastGlobalPoint: globalPoint)
            needsDisplay = true
            return
        case let .resize(strokeID, handle):
            appState?.resizeAnnotationStroke(
                id: strokeID,
                handle: handle,
                to: globalPoint,
                constrained: event.modifierFlags.contains(.shift)
            )
            needsDisplay = true
            return
        case nil:
            break
        }

        appState?.updateAnnotationStroke(at: globalPoint, constrained: event.modifierFlags.contains(.shift))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if activeDrag != nil {
            activeDrag = nil
            needsDisplay = true
            return
        }

        appState?.updateAnnotationStroke(at: NSEvent.mouseLocation, constrained: event.modifierFlags.contains(.shift))
        appState?.endAnnotationStroke()
        needsDisplay = true
    }

    private func draw(strokes: [AnnotationStroke]) {
        for stroke in strokes {
            let points = stroke.sourcePoints.map { point in
                CGPoint(x: point.x - screenFrame.minX, y: point.y - screenFrame.minY)
            }
            guard !points.isEmpty else { continue }
            let isSelected = stroke.id == appState?.selectedAnnotationStrokeID
            if isSelected {
                drawSelectionIndicator(for: stroke, points: points)
            }
            NSColor(cgColor: stroke.cgColor)?.setStroke()
            let path = NSBezierPath()
            path.lineWidth = stroke.lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            switch stroke.tool {
            case .pen:
                path.move(to: points[0])
                points.dropFirst().forEach { path.line(to: $0) }
                path.stroke()
            case .text:
                guard let point = points.first else { continue }
                drawText(stroke, at: point)
            case .line:
                guard let start = points.first, let end = points.last else { continue }
                path.move(to: start)
                path.line(to: end)
                path.stroke()
            case .rectangle:
                guard let start = points.first, let end = points.last else { continue }
                path.appendRect(CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                ))
                path.stroke()
            case .ellipse:
                guard let start = points.first, let end = points.last else { continue }
                path.appendOval(in: CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                ))
                path.stroke()
            case .arrow:
                guard let start = points.first, let end = points.last else { continue }
                drawArrow(from: start, to: end, lineWidth: stroke.lineWidth)
            }
        }
    }

    private func drawSelectionIndicator(for stroke: AnnotationStroke, points: [CGPoint]) {
        guard let bounds = selectionBounds(for: stroke, points: points) else { return }
        let indicator = bounds.insetBy(dx: -10, dy: -10)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: indicator, xRadius: 8, yRadius: 8).fill()
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(roundedRect: indicator, xRadius: 8, yRadius: 8)
        outline.lineWidth = 2
        outline.setLineDash([6, 4], count: 2, phase: 0)
        outline.stroke()
        drawResizeHandles(for: stroke, points: points, bounds: bounds)
    }

    private func drawResizeHandles(for stroke: AnnotationStroke, points: [CGPoint], bounds: CGRect) {
        for (_, center) in resizeHandleCenters(for: stroke, points: points, bounds: bounds) {
            let rect = CGRect(
                x: center.x - resizeHandleSize / 2,
                y: center.y - resizeHandleSize / 2,
                width: resizeHandleSize,
                height: resizeHandleSize
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func selectionBounds(for stroke: AnnotationStroke, points: [CGPoint]) -> CGRect? {
        guard !points.isEmpty else { return nil }
        switch stroke.tool {
        case .text:
            guard let point = points.first else { return nil }
            return textBounds(for: stroke, at: point)
        case .rectangle, .ellipse:
            guard let start = points.first, let end = points.last else { return nil }
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        default:
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
                return nil
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    private func hitStroke(at globalPoint: CGPoint, in strokes: [AnnotationStroke]) -> UUID? {
        let localPoint = CGPoint(x: globalPoint.x - screenFrame.minX, y: globalPoint.y - screenFrame.minY)
        for stroke in strokes.reversed() {
            let points = stroke.sourcePoints.map { CGPoint(x: $0.x - screenFrame.minX, y: $0.y - screenFrame.minY) }
            guard (stroke.tool == .text ? points.count >= 1 : points.count >= 2) else { continue }
            if strokeContains(localPoint, stroke: stroke, points: points) {
                return stroke.id
            }
        }
        return nil
    }

    private func hitResizeHandle(
        at globalPoint: CGPoint,
        selectedStrokeID: UUID,
        in strokes: [AnnotationStroke]
    ) -> AnnotationResizeHandle? {
        guard let stroke = strokes.first(where: { $0.id == selectedStrokeID }) else { return nil }
        let points = stroke.sourcePoints.map { CGPoint(x: $0.x - screenFrame.minX, y: $0.y - screenFrame.minY) }
        guard let bounds = selectionBounds(for: stroke, points: points) else { return nil }
        let localPoint = CGPoint(x: globalPoint.x - screenFrame.minX, y: globalPoint.y - screenFrame.minY)
        let hitSize = resizeHandleSize + 10
        for (handle, center) in resizeHandleCenters(for: stroke, points: points, bounds: bounds).reversed() {
            let hitRect = CGRect(
                x: center.x - hitSize / 2,
                y: center.y - hitSize / 2,
                width: hitSize,
                height: hitSize
            )
            if hitRect.contains(localPoint) {
                return handle
            }
        }
        return nil
    }

    private func resizeHandleCenters(
        for stroke: AnnotationStroke,
        points: [CGPoint],
        bounds: CGRect
    ) -> [(AnnotationResizeHandle, CGPoint)] {
        switch stroke.tool {
        case .line, .arrow:
            guard let start = points.first, let end = points.last else { return [] }
            return [(.startPoint, start), (.endPoint, end)]
        case .pen, .rectangle, .ellipse, .text:
            return [
                (.topLeft, CGPoint(x: bounds.minX, y: bounds.maxY)),
                (.topRight, CGPoint(x: bounds.maxX, y: bounds.maxY)),
                (.bottomRight, CGPoint(x: bounds.maxX, y: bounds.minY)),
                (.bottomLeft, CGPoint(x: bounds.minX, y: bounds.minY))
            ]
        }
    }

    private func strokeContains(_ point: CGPoint, stroke: AnnotationStroke, points: [CGPoint]) -> Bool {
        let tolerance = max(CGFloat(stroke.lineWidth) + 8, 12)
        switch stroke.tool {
        case .text:
            guard let point = points.first,
                  let bounds = textBounds(for: stroke, at: point) else {
                return false
            }
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .pen:
            return minimumDistance(from: point, toPolyline: points) <= tolerance
        case .line, .arrow:
            guard let start = points.first, let end = points.last else { return false }
            return distance(from: point, toSegmentStart: start, end: end) <= tolerance
        case .rectangle:
            guard let bounds = selectionBounds(for: stroke, points: points) else { return false }
            let outer = bounds.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = bounds.insetBy(dx: tolerance, dy: tolerance)
            return outer.contains(point) && !inner.contains(point)
        case .ellipse:
            guard let bounds = selectionBounds(for: stroke, points: points), bounds.width > 0, bounds.height > 0 else {
                return false
            }
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let outerX = bounds.width / 2 + tolerance
            let outerY = bounds.height / 2 + tolerance
            let innerX = max(1, bounds.width / 2 - tolerance)
            let innerY = max(1, bounds.height / 2 - tolerance)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let outer = (dx * dx) / (outerX * outerX) + (dy * dy) / (outerY * outerY)
            let inner = (dx * dx) / (innerX * innerX) + (dy * dy) / (innerY * innerY)
            return outer <= 1 && inner >= 1
        }
    }

    private func minimumDistance(from point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return .greatestFiniteMagnitude }
        return zip(points, points.dropFirst())
            .map { distance(from: point, toSegmentStart: $0.0, end: $0.1) }
            .min() ?? .greatestFiniteMagnitude
    }

    private func distance(from point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func drawText(_ stroke: AnnotationStroke, at point: CGPoint) {
        guard let text = stroke.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }
        NSAttributedString(string: text, attributes: textAttributes(for: stroke)).draw(at: point)
    }

    private func textBounds(for stroke: AnnotationStroke, at point: CGPoint) -> CGRect? {
        guard let text = stroke.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        let size = (text as NSString).size(withAttributes: textAttributes(for: stroke))
        return CGRect(x: point.x, y: point.y, width: size.width, height: size.height)
            .insetBy(dx: -4, dy: -4)
    }

    private func textAttributes(for stroke: AnnotationStroke) -> [NSAttributedString.Key: Any] {
        let fontSize = max(20, CGFloat(stroke.lineWidth) * 4.8)
        let color = NSColor(hex: stroke.colorHex) ?? .controlAccentColor
        return [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color
        ]
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.move(to: start)
        path.line(to: end)
        path.stroke()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(16, lineWidth * 5)
        let spread = CGFloat.pi / 7
        let p1 = CGPoint(
            x: end.x - headLength * cos(angle - spread),
            y: end.y - headLength * sin(angle - spread)
        )
        let p2 = CGPoint(
            x: end.x - headLength * cos(angle + spread),
            y: end.y - headLength * sin(angle + spread)
        )

        let head = NSBezierPath()
        head.lineWidth = lineWidth
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.move(to: p1)
        head.line(to: end)
        head.line(to: p2)
        head.stroke()
    }
}

@MainActor
final class TextAnnotationInputController {
    static let shared = TextAnnotationInputController()

    private var panel: TextAnnotationPanel?
    private var delegate: TextAnnotationFieldDelegate?
    private weak var appState: AppState?
    private var point: CGPoint = .zero

    private init() {}

    func show(at point: CGPoint, appState: AppState) {
        cancel()
        self.point = point
        self.appState = appState

        let size = NSSize(width: 260, height: 42)
        let contentView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        contentView.material = .hudWindow
        contentView.blendingMode = .behindWindow
        contentView.state = .active

        let textField = NSTextField(frame: NSRect(x: 8, y: 7, width: size.width - 16, height: 28))
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.font = .systemFont(ofSize: 18, weight: .regular)
        textField.lineBreakMode = .byTruncatingTail
        textField.usesSingleLineMode = true

        let delegate = TextAnnotationFieldDelegate(
            onCommit: { [weak self] text in
                self?.commit(text)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )
        textField.delegate = delegate
        self.delegate = delegate

        contentView.addSubview(textField)

        let panel = TextAnnotationPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentView = contentView
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.title = "Syn Text Annotation"
        panel.setFrameOrigin(clampedOrigin(for: point, size: size))
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(textField)
        self.panel = panel
    }

    func cancel() {
        panel?.close()
        panel = nil
        delegate = nil
        appState = nil
        point = .zero
    }

    private func commit(_ text: String) {
        let targetPoint = point
        let targetAppState = appState
        cancel()
        targetAppState?.commitAnnotationText(text, at: targetPoint)
    }

    private func clampedOrigin(for point: CGPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            return NSPoint(x: point.x, y: point.y - size.height)
        }
        let frame = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        return NSPoint(
            x: min(max(point.x, frame.minX), frame.maxX - size.width),
            y: min(max(point.y - size.height, frame.minY), frame.maxY - size.height)
        )
    }
}

private final class TextAnnotationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class TextAnnotationFieldDelegate: NSObject, NSTextFieldDelegate {
    private let onCommit: (String) -> Void
    private let onCancel: () -> Void

    init(onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onCommit(control.stringValue)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel()
            return true
        }
        return false
    }
}

private extension CodablePoint {
    func distance(to other: CodablePoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

private extension AnnotationStroke {
    var cgColor: CGColor {
        NSColor(hex: colorHex)?.cgColor ?? NSColor.controlAccentColor.cgColor
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let intValue = Int(value, radix: 16) else {
            return nil
        }

        let red = CGFloat((intValue >> 16) & 0xFF) / 255
        let green = CGFloat((intValue >> 8) & 0xFF) / 255
        let blue = CGFloat(intValue & 0xFF) / 255
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}
