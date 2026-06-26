import Foundation
import os

enum DurationFormatter {
    static func string(from duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return "\(minutes)m \(seconds)s"
    }
}

/// Lightweight, always-on performance logging. Writes to two channels:
///
/// 1. A plain text file at `~/Library/Logs/Syn/perf.log` — the reliable channel for debugging
///    a slow finalize. Read it with:
///       tail -f ~/Library/Logs/Syn/perf.log
///       cat ~/Library/Logs/Syn/perf.log
///
/// 2. os_log under subsystem `com.trmdy.syn` / category `perf`, for live streaming:
///       ./script/build_and_run.sh --telemetry
///       log stream --info --predicate 'subsystem == "com.trmdy.syn" && category == "perf"'
enum SynPerf {
    static let logger = Logger(subsystem: "com.trmdy.syn", category: "perf")

    /// `~/Library/Logs/Syn/perf.log` (the app is not sandboxed, so this is writable).
    static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Syn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("perf.log")
    }()

    private static let lock = NSLock()
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Log a labeled duration in seconds.
    static func log(_ name: String, seconds: Double) {
        emit("\(name): \(String(format: "%.3f", seconds))s")
    }

    /// Log a free-form perf event (e.g. which code path was taken, provider names).
    static func event(_ message: String) {
        emit(message)
    }

    private static func emit(_ message: String) {
        logger.log("⏱ \(message, privacy: .public)")
        // Write synchronously (lock-guarded) rather than dispatching async: short-lived fixture
        // processes can exit before an async write flushes, dropping the line. Perf logging is
        // infrequent and the writes are tiny, so the brief synchronous I/O is acceptable.
        let line = "\(timestampFormatter.string(from: Date())) ⏱ \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    /// Measure an async throwing block, log its duration (even if it throws), and return its result.
    @discardableResult
    static func measure<T>(_ name: String, _ work: () async throws -> T) async rethrows -> T {
        let start = Date()
        defer { log(name, seconds: Date().timeIntervalSince(start)) }
        return try await work()
    }
}
