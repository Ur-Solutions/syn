import Foundation

enum PointerEventKind: String, Codable, Sendable {
    case move
    case leftMouseDown
    case leftMouseUp
    case rightMouseDown
    case rightMouseUp
    case otherMouseDown
    case otherMouseUp
}

struct PointerEvent: Codable, Sendable {
    var kind: PointerEventKind
    var timestamp: TimeInterval
    var sourceCoordinates: CodablePoint
    var videoCoordinates: CodablePoint?
    var buttonNumber: Int?
}

struct CodablePoint: Codable, Sendable {
    var x: Double
    var y: Double
}
