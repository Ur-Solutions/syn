import Foundation

struct ActiveWindowSample: Codable, Sendable {
    var timestamp: TimeInterval
    var windowID: UInt32
    var appName: String?
    var windowTitle: String?
    var bounds: CodableRect
}
