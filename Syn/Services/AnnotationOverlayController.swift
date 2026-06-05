import AppKit
import Foundation

@MainActor
final class AnnotationRecorder {
    private var startedAt: Date?
    private var pauseStartedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private var strokes: [AnnotationStroke] = []
    private var draft: AnnotationStroke?
    private let defaultColorHex = "#0A84FF"
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

    func begin(tool: AnnotationTool, at point: CGPoint) {
        guard pauseStartedAt == nil else { return }
        let timestamp = currentTimestamp()
        draft = AnnotationStroke(
            id: UUID(),
            tool: tool,
            startTimestamp: timestamp,
            endTimestamp: timestamp,
            sourcePoints: [CodablePoint(x: point.x, y: point.y)],
            videoPoints: nil,
            colorHex: defaultColorHex,
            lineWidth: defaultLineWidth
        )
    }

    func update(at point: CGPoint) {
        guard var current = draft else { return }
        current.endTimestamp = currentTimestamp()
        let codablePoint = CodablePoint(x: point.x, y: point.y)
        switch current.tool {
        case .pen:
            if current.sourcePoints.last?.distance(to: codablePoint) ?? .infinity >= 2 {
                current.sourcePoints.append(codablePoint)
            }
        case .line, .rectangle, .ellipse, .arrow:
            if current.sourcePoints.count == 1 {
                current.sourcePoints.append(codablePoint)
            } else {
                current.sourcePoints[current.sourcePoints.count - 1] = codablePoint
            }
        }
        draft = current
    }

    func finishDraft() {
        guard var current = draft else { return }
        current.endTimestamp = max(current.endTimestamp, current.startTimestamp + 0.2)
        if current.sourcePoints.count >= 2 {
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
        windows.forEach { $0.annotationView.needsDisplay = true }
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
            }
            return
        }

        close()
        windows = screens.map { screen in
            let view = AnnotationOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.appState = appState
            view.screenFrame = screen.frame

            let window = AnnotationOverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.contentView = view
            window.annotationView = view
            window.screenFrame = screen.frame
            window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.acceptsMouseMovedEvents = true
            window.ignoresMouseEvents = !appState.isCanvasModeEnabled
            window.title = "Syn Annotation Overlay"
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

    override var isFlipped: Bool { false }

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
        if let strokeID = hitStroke(at: globalPoint, in: appState.visibleAnnotationStrokes) {
            appState.selectAnnotationStroke(id: strokeID)
            needsDisplay = true
            return
        }
        guard let tool = appState.selectedAnnotationTool else { return }
        appState.beginAnnotationStroke(tool: tool, at: NSEvent.mouseLocation)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        appState?.updateAnnotationStroke(at: NSEvent.mouseLocation)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        appState?.updateAnnotationStroke(at: NSEvent.mouseLocation)
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
    }

    private func selectionBounds(for stroke: AnnotationStroke, points: [CGPoint]) -> CGRect? {
        guard !points.isEmpty else { return nil }
        switch stroke.tool {
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
            guard points.count >= 2 else { continue }
            if strokeContains(localPoint, stroke: stroke, points: points) {
                return stroke.id
            }
        }
        return nil
    }

    private func strokeContains(_ point: CGPoint, stroke: AnnotationStroke, points: [CGPoint]) -> Bool {
        let tolerance = max(CGFloat(stroke.lineWidth) + 8, 12)
        switch stroke.tool {
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
