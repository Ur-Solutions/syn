import Foundation

enum PacketStatus: String, Codable, CaseIterable {
    case processing
    case succeeded
    case partial
    case failed

    var title: String {
        switch self {
        case .processing:
            "Processing"
        case .succeeded:
            "Succeeded"
        case .partial:
            "Partial"
        case .failed:
            "Failed"
        }
    }
}

struct PacketSummary: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var status: PacketStatus
    var folderURL: URL
    var zipURL: URL?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date,
        duration: TimeInterval,
        status: PacketStatus,
        folderURL: URL,
        zipURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.status = status
        self.folderURL = folderURL
        self.zipURL = zipURL
    }

    var availableZipURL: URL? {
        guard let zipURL,
              FileManager.default.fileExists(atPath: zipURL.path) else {
            return nil
        }
        return zipURL
    }

    var rawZipURL: URL {
        PacketLayout.rawZipURL(for: folderURL)
    }

    var availableRawZipURL: URL? {
        let url = rawZipURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    var compactZipURL: URL {
        let folderName = folderURL.lastPathComponent
        return folderURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(folderName)-compact.zip")
    }

    var availableCompactZipURL: URL? {
        let url = compactZipURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    var editedRecordingURL: URL {
        folderURL.appendingPathComponent("recording-edited.mp4")
    }

    var availableEditedRecordingURL: URL? {
        let url = editedRecordingURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }
}

enum RepeatCapturePolicy {
    static func hasCompletedRecording(_ packets: [PacketSummary]) -> Bool {
        packets.contains { packet in
            packet.status == .succeeded || packet.status == .partial
        }
    }
}
