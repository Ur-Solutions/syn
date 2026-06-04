import Foundation

enum AnnotationTool: String, Codable, Sendable, CaseIterable, Identifiable {
    case pen
    case rectangle
    case arrow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen:
            "Pen"
        case .rectangle:
            "Rectangle"
        case .arrow:
            "Arrow"
        }
    }

    var symbolName: String {
        switch self {
        case .pen:
            "pencil"
        case .rectangle:
            "rectangle"
        case .arrow:
            "arrow.up.right"
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
