import CoreGraphics
import Foundation

enum AnnotationTool: String, Codable, Sendable, CaseIterable, Identifiable {
    case pen
    case line
    case rectangle
    case ellipse
    case text
    case arrow

    var id: String { rawValue }

    static let canvasTools: [AnnotationTool] = [.arrow, .rectangle, .ellipse, .text, .line, .pen]

    var title: String {
        switch self {
        case .pen:
            "Pen"
        case .line:
            "Line"
        case .rectangle:
            "Rectangle"
        case .ellipse:
            "Ellipse"
        case .text:
            "Text"
        case .arrow:
            "Arrow"
        }
    }

    var symbolName: String {
        switch self {
        case .pen:
            "pencil"
        case .line:
            "line.diagonal"
        case .rectangle:
            "rectangle"
        case .ellipse:
            "circle"
        case .text:
            "textformat"
        case .arrow:
            "arrow.up.right"
        }
    }

    var shortcutLabel: String? {
        switch self {
        case .arrow:
            "1"
        case .rectangle:
            "2"
        case .ellipse:
            "3"
        case .text:
            "4"
        case .line:
            "5"
        case .pen:
            "6"
        }
    }
}

enum AnnotationResizeHandle: String, Sendable, CaseIterable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft
    case startPoint
    case endPoint
}

struct AnnotationStroke: Codable, Sendable, Identifiable {
    var id: UUID
    var tool: AnnotationTool
    var startTimestamp: TimeInterval
    var endTimestamp: TimeInterval
    var sourcePoints: [CodablePoint]
    var videoPoints: [CodablePoint]?
    var colorHex: String
    var lineWidth: Double
    var text: String? = nil

    var duration: TimeInterval {
        max(0, endTimestamp - startTimestamp)
    }

    mutating func moveSourcePoints(by delta: CGSize) {
        sourcePoints = sourcePoints.map {
            CodablePoint(x: $0.x + delta.width, y: $0.y + delta.height)
        }
        videoPoints = nil
    }

    mutating func resizeSourcePoints(handle: AnnotationResizeHandle, to point: CGPoint, constrained: Bool) {
        switch tool {
        case .line, .arrow:
            resizeLinearSourcePoints(handle: handle, to: point, constrained: constrained)
        case .text:
            resizeTextSourcePoint(handle: handle, to: point, constrained: constrained)
        case .rectangle, .ellipse, .pen:
            resizeBoundedSourcePoints(handle: handle, to: point, constrained: constrained)
        }
        videoPoints = nil
    }

    mutating func updateDraftEndpoint(to point: CGPoint, constrained: Bool) {
        guard sourcePoints.count >= 1 else { return }
        let start = sourcePoints[0].cgPoint
        let resolvedPoint: CGPoint
        switch tool {
        case .rectangle, .ellipse:
            resolvedPoint = constrained ? Self.squarePoint(from: start, to: point) : point
        case .line, .arrow:
            resolvedPoint = constrained ? Self.snappedPoint(from: start, to: point) : point
        case .pen, .text:
            resolvedPoint = point
        }

        let codablePoint = CodablePoint(x: resolvedPoint.x, y: resolvedPoint.y)
        if sourcePoints.count == 1 {
            sourcePoints.append(codablePoint)
        } else {
            sourcePoints[sourcePoints.count - 1] = codablePoint
        }
    }

    private mutating func resizeLinearSourcePoints(handle: AnnotationResizeHandle, to point: CGPoint, constrained: Bool) {
        guard sourcePoints.count >= 2 else { return }
        let movingIndex = handle == .startPoint ? 0 : sourcePoints.count - 1
        let anchorIndex = movingIndex == 0 ? sourcePoints.count - 1 : 0
        let anchor = sourcePoints[anchorIndex].cgPoint
        let resolvedPoint = constrained ? Self.snappedPoint(from: anchor, to: point) : point
        sourcePoints[movingIndex] = CodablePoint(x: resolvedPoint.x, y: resolvedPoint.y)
    }

    private mutating func resizeBoundedSourcePoints(handle: AnnotationResizeHandle, to point: CGPoint, constrained: Bool) {
        guard let bounds = sourceBounds, bounds.width > 0 || bounds.height > 0 else { return }
        let anchor = Self.anchorPoint(for: handle, bounds: bounds)
        let resolvedPoint = constrained ? Self.squarePoint(from: anchor, to: point) : point
        let newBounds = CGRect(
            x: min(anchor.x, resolvedPoint.x),
            y: min(anchor.y, resolvedPoint.y),
            width: abs(resolvedPoint.x - anchor.x),
            height: abs(resolvedPoint.y - anchor.y)
        )
        guard newBounds.width >= 1 || newBounds.height >= 1 else { return }

        sourcePoints = sourcePoints.map { sourcePoint in
            let point = sourcePoint.cgPoint
            let xRatio = bounds.width == 0 ? 0.5 : (point.x - bounds.minX) / bounds.width
            let yRatio = bounds.height == 0 ? 0.5 : (point.y - bounds.minY) / bounds.height
            return CodablePoint(
                x: newBounds.minX + xRatio * newBounds.width,
                y: newBounds.minY + yRatio * newBounds.height
            )
        }
    }

    private mutating func resizeTextSourcePoint(handle: AnnotationResizeHandle, to point: CGPoint, constrained: Bool) {
        guard let origin = sourcePoints.first?.cgPoint else { return }
        let bounds = approximateTextBounds(at: origin)
        let anchor = Self.anchorPoint(for: handle, bounds: bounds)
        let resolvedPoint = constrained ? Self.squarePoint(from: anchor, to: point) : point
        let newWidth = max(18, abs(resolvedPoint.x - anchor.x))
        let currentWidth = max(18, bounds.width)
        lineWidth = max(2.5, min(24, lineWidth * Double(newWidth / currentWidth)))
        let newBounds = CGRect(
            x: min(anchor.x, resolvedPoint.x),
            y: min(anchor.y, resolvedPoint.y),
            width: newWidth,
            height: max(18, abs(resolvedPoint.y - anchor.y))
        )
        sourcePoints[0] = CodablePoint(x: newBounds.minX, y: newBounds.minY)
    }

    var sourceBounds: CGRect? {
        guard !sourcePoints.isEmpty else { return nil }
        let points = sourcePoints.map(\.cgPoint)
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return nil
        }
        if tool == .text, let origin = points.first {
            return approximateTextBounds(at: origin)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func approximateTextBounds(at origin: CGPoint) -> CGRect {
        let fontSize = max(20, CGFloat(lineWidth) * 4.8)
        let glyphCount = max(1, text?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 1)
        let width = max(28, CGFloat(glyphCount) * fontSize * 0.58)
        let height = fontSize * 1.25
        return CGRect(x: origin.x, y: origin.y, width: width, height: height)
    }

    private static func anchorPoint(for handle: AnnotationResizeHandle, bounds: CGRect) -> CGPoint {
        switch handle {
        case .topLeft:
            CGPoint(x: bounds.maxX, y: bounds.minY)
        case .topRight:
            CGPoint(x: bounds.minX, y: bounds.minY)
        case .bottomRight:
            CGPoint(x: bounds.minX, y: bounds.maxY)
        case .bottomLeft:
            CGPoint(x: bounds.maxX, y: bounds.maxY)
        case .startPoint:
            CGPoint(x: bounds.maxX, y: bounds.maxY)
        case .endPoint:
            CGPoint(x: bounds.minX, y: bounds.minY)
        }
    }

    private static func squarePoint(from start: CGPoint, to point: CGPoint) -> CGPoint {
        let dx = point.x - start.x
        let dy = point.y - start.y
        let side = max(abs(dx), abs(dy))
        return CGPoint(
            x: start.x + (dx < 0 ? -side : side),
            y: start.y + (dy < 0 ? -side : side)
        )
    }

    private static func snappedPoint(from start: CGPoint, to point: CGPoint) -> CGPoint {
        let dx = point.x - start.x
        let dy = point.y - start.y
        let length = max(1, hypot(dx, dy))
        let angle = atan2(dy, dx)
        let increment = CGFloat.pi / 4
        let snappedAngle = (angle / increment).rounded() * increment
        return CGPoint(
            x: start.x + cos(snappedAngle) * length,
            y: start.y + sin(snappedAngle) * length
        )
    }
}

private extension CodablePoint {
    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct AnnotationMappingMetadata: Codable {
    var sourceCoordinateSpace: String
    var videoCoordinateSpace: String
    var renderSize: CodableSize
    var mappedStrokeCount: Int
    var unmappedStrokeCount: Int
    var renderedStrokeCount: Int
}
