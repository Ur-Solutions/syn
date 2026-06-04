import AppKit
import Foundation

@MainActor
final class ActiveWindowTracker {
    private var timer: Timer?
    private var startedAt: Date?
    private var pauseStartedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private var samples: [ActiveWindowSample] = []

    func start() {
        _ = stop()
        startedAt = .now
        pauseStartedAt = nil
        pausedDuration = 0
        samples = []
        recordSample()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordSample()
            }
        }
    }

    func pause() {
        guard pauseStartedAt == nil else { return }
        pauseStartedAt = .now
    }

    func resume() {
        guard let pauseStartedAt else { return }
        pausedDuration += Date().timeIntervalSince(pauseStartedAt)
        self.pauseStartedAt = nil
    }

    func stop() -> [ActiveWindowSample] {
        timer?.invalidate()
        timer = nil
        let snapshot = samples
        startedAt = nil
        pauseStartedAt = nil
        pausedDuration = 0
        samples = []
        return snapshot
    }

    private func recordSample() {
        guard pauseStartedAt == nil,
              let timestamp = currentTimestamp(),
              let sample = currentWindowSample(timestamp: timestamp) else {
            return
        }

        if let last = samples.last,
           last.windowID == sample.windowID,
           last.bounds.x == sample.bounds.x,
           last.bounds.y == sample.bounds.y,
           last.bounds.width == sample.bounds.width,
           last.bounds.height == sample.bounds.height {
            return
        }

        samples.append(sample)
    }

    private func currentTimestamp() -> TimeInterval? {
        guard let startedAt else { return nil }
        return max(0, Date().timeIntervalSince(startedAt) - pausedDuration)
    }

    private func currentWindowSample(timestamp: TimeInterval) -> ActiveWindowSample? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        return Self.sample(from: infoList, timestamp: timestamp, ownPID: getpid())
    }

    static func sample(from infoList: [[String: Any]], timestamp: TimeInterval, ownPID: pid_t) -> ActiveWindowSample? {
        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != ownPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let number = info[kCGWindowNumber as String] as? UInt32 else {
                continue
            }

            let rect = CGRect(
                x: bounds["X"] as? CGFloat ?? 0,
                y: bounds["Y"] as? CGFloat ?? 0,
                width: bounds["Width"] as? CGFloat ?? 0,
                height: bounds["Height"] as? CGFloat ?? 0
            )

            guard rect.width > 80, rect.height > 60 else {
                continue
            }

            return ActiveWindowSample(
                timestamp: timestamp,
                windowID: number,
                appName: info[kCGWindowOwnerName as String] as? String,
                windowTitle: info[kCGWindowName as String] as? String,
                bounds: CodableRect(rect)
            )
        }

        return nil
    }
}
