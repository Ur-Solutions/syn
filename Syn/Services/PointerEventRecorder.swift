import AppKit

final class PointerEventRecorder {
    private var monitors: [Any] = []
    private var startedAt: Date?
    private var pauseStartedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private var events: [PointerEvent] = []
    private let lock = NSLock()

    func start() {
        stop()
        startedAt = .now
        pauseStartedAt = nil
        pausedDuration = 0
        events = []

        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseUp
        ]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.record(event)
        }) {
            monitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.record(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func pause() {
        lock.lock()
        defer { lock.unlock() }
        guard pauseStartedAt == nil else { return }
        pauseStartedAt = .now
    }

    func resume() {
        lock.lock()
        defer { lock.unlock() }
        guard let pauseStartedAt else { return }
        pausedDuration += Date().timeIntervalSince(pauseStartedAt)
        self.pauseStartedAt = nil
    }

    func stop() -> [PointerEvent] {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []

        lock.lock()
        defer { lock.unlock() }
        let snapshot = events
        events = []
        startedAt = nil
        pauseStartedAt = nil
        pausedDuration = 0
        return snapshot
    }

    private func record(_ event: NSEvent) {
        let kind: PointerEventKind
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            kind = .move
        case .leftMouseDown:
            kind = .leftMouseDown
        case .leftMouseUp:
            kind = .leftMouseUp
        case .rightMouseDown:
            kind = .rightMouseDown
        case .rightMouseUp:
            kind = .rightMouseUp
        case .otherMouseDown:
            kind = .otherMouseDown
        case .otherMouseUp:
            kind = .otherMouseUp
        default:
            return
        }

        lock.lock()
        guard let startedAt, pauseStartedAt == nil else {
            lock.unlock()
            return
        }
        let timestamp = max(0, Date().timeIntervalSince(startedAt) - pausedDuration)
        lock.unlock()

        let location = NSEvent.mouseLocation
        let point = CodablePoint(x: location.x, y: location.y)
        let pointerEvent = PointerEvent(
            kind: kind,
            timestamp: timestamp,
            sourceCoordinates: point,
            videoCoordinates: nil,
            buttonNumber: event.buttonNumber
        )

        lock.lock()
        events.append(pointerEvent)
        lock.unlock()
    }
}
