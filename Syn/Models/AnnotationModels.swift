import Foundation

enum AnnotationTool: String, Codable, Sendable, CaseIterable, Identifiable {
    case pen
    case line
    case rectangle
    case ellipse
    case arrow

    var id: String { rawValue }

    static let canvasTools: [AnnotationTool] = [.pen, .line, .rectangle, .ellipse]

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
        case .arrow:
            "arrow.up.right"
        }
    }

    var shortcutLabel: String? {
        switch self {
        case .pen:
            "1"
        case .line:
            "2"
        case .rectangle:
            "3"
        case .ellipse:
            "4"
        case .arrow:
            nil
        }
    }
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

    var duration: TimeInterval {
        max(0, endTimestamp - startTimestamp)
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
