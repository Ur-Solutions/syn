import Foundation

enum DurationFormatter {
    static func string(from duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return "\(minutes)m \(seconds)s"
    }
}
