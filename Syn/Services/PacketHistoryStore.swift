import Foundation

enum PacketHistoryStore {
    private static var historyURL: URL {
        if let override = ProcessInfo.processInfo.environment["SYN_HISTORY_STORE_PATH"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Syn", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    static func load() -> [PacketSummary] {
        guard let data = try? Data(contentsOf: historyURL),
              let packets = try? JSONDecoder.synDecoder.decode([PacketSummary].self, from: data) else {
            return []
        }

        return packets
            .filter { FileManager.default.fileExists(atPath: $0.folderURL.path) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func save(_ packets: [PacketSummary]) {
        do {
            let url = historyURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.synEncoder.encode(packets)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Syn failed to save packet history: \(error.localizedDescription)")
        }
    }
}
