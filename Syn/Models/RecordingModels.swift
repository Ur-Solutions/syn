import Foundation

enum RecordingDurationWarning {
    static let threshold: TimeInterval = 30 * 60
    static let shortLabel = "30 min warning"
    static let message = "Recording has passed 30 minutes. Syn will keep recording until you stop it."

    static func shouldIssue(elapsed: TimeInterval, alreadyIssued: Bool) -> Bool {
        !alreadyIssued && elapsed >= threshold
    }
}

enum RecordingPhase: String, Codable {
    case idle
    case starting
    case recording
    case paused
    case processing
}

struct ActiveRecording: Identifiable, Equatable {
    var id: UUID
    var mode: CaptureMode
    var packetTitle: String
    var startedAt: Date
    var elapsedBeforeCurrentRun: TimeInterval
    var currentRunStartedAt: Date?
    var pauseStartedAt: Date?
    var phase: RecordingPhase
    var durationWarningIssuedAt: Date? = nil

    var isPaused: Bool {
        phase == .paused
    }

    var hasDurationWarning: Bool {
        durationWarningIssuedAt != nil
    }

    func elapsed(at date: Date = .now) -> TimeInterval {
        guard phase != .idle else {
            return 0
        }

        let currentRunElapsed = currentRunStartedAt.map { date.timeIntervalSince($0) } ?? 0
        return elapsedBeforeCurrentRun + max(currentRunElapsed, 0)
    }
}

struct PauseInterval: Codable, Sendable {
    var startedAt: Date
    var endedAt: Date
}
