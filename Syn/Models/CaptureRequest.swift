import CoreGraphics
import Foundation

struct CaptureRequest: Sendable {
    var mode: CaptureMode
    var createdAt: Date
    var packet: PacketContext
    var preferredDisplayID: CGDirectDisplayID?
    var region: CGRect?
    var regionGlobalRect: CGRect?
    var selectedWindowID: CGWindowID?
    var chromeTab: ChromeTabTarget? = nil
}

struct ChromeTabTarget: Codable, Sendable, Identifiable, Equatable {
    var windowIndex: Int
    var tabIndex: Int
    var title: String
    var url: String
    var windowID: UInt32?

    var id: String {
        "\(windowIndex):\(tabIndex):\(url)"
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? url : title
    }
}

struct CaptureSourceMetadata: Codable, Sendable {
    var mode: String
    var displayID: UInt32?
    var windowID: UInt32?
    var appName: String?
    var windowTitle: String?
    var chromeTab: ChromeTabTarget? = nil
    var smartRegion: CodableRect? = nil
    var sourceRect: CodableRect?
    var outputSize: CodableSize?
    var notes: [String]
}

struct CodableRect: Codable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }
}

struct CodableSize: Codable, Sendable {
    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    init(_ size: CGSize) {
        width = size.width
        height = size.height
    }
}

struct PacketContext: Sendable {
    var id: UUID
    var title: String
    var createdAt: Date
    var folderURL: URL
    var zipURL: URL

    var rawZipURL: URL { PacketLayout.rawZipURL(for: folderURL) }
    var rawURL: URL { folderURL.appendingPathComponent("raw", isDirectory: true) }
    var rawSegmentsURL: URL { rawURL.appendingPathComponent("segments", isDirectory: true) }
    var rawRecordingURL: URL { rawURL.appendingPathComponent("recording-source.mp4") }
    var rawAudioURL: URL { rawURL.appendingPathComponent("audio-source.wav") }
    var rawCaptureSessionURL: URL { rawURL.appendingPathComponent("capture-session.json") }
    var activeWindowSamplesURL: URL { rawURL.appendingPathComponent("active-window-samples.json") }
    var finalRecordingURL: URL { folderURL.appendingPathComponent("recording.mp4") }
    var transcriptURL: URL { folderURL.appendingPathComponent("transcript.md") }
    var summaryURL: URL { folderURL.appendingPathComponent("summary.md") }
    var agentPromptURL: URL { folderURL.appendingPathComponent("agent-prompt.md") }
    var agentPromptsURL: URL { folderURL.appendingPathComponent("agent-prompts", isDirectory: true) }
    var projectContextURL: URL { folderURL.appendingPathComponent("project-context.md") }
    var semanticSegmentsURL: URL { folderURL.appendingPathComponent("semantic-segments.json") }
    var semanticTimelineURL: URL { folderURL.appendingPathComponent("semantic-timeline.md") }
    var manifestURL: URL { folderURL.appendingPathComponent("manifest.json") }
    var pointerEventsURL: URL { rawURL.appendingPathComponent("pointer-events.json") }
    var annotationEventsURL: URL { rawURL.appendingPathComponent("annotations.json") }
    var fullFramesURL: URL { folderURL.appendingPathComponent("frames/full", isDirectory: true) }
    var compressedFramesURL: URL { folderURL.appendingPathComponent("frames/compressed", isDirectory: true) }
    var candidateMetadataURL: URL { folderURL.appendingPathComponent("frames/candidates/metadata.json") }

    static func create(mode: CaptureMode, createdAt: Date = .now) throws -> PacketContext {
        let title = "\(mode.title) recording"
        let folderURL = PacketLayout.packetFolderURL(title: title, createdAt: createdAt)
        let zipURL = PacketLayout.zipURL(for: folderURL)
        let context = PacketContext(
            id: UUID(),
            title: title,
            createdAt: createdAt,
            folderURL: folderURL,
            zipURL: zipURL
        )

        try FileManager.default.createDirectory(at: context.rawSegmentsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: context.agentPromptsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: context.fullFramesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: context.compressedFramesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: context.candidateMetadataURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        return context
    }

    static func existing(packet: PacketSummary) -> PacketContext {
        PacketContext(
            id: packet.id,
            title: packet.title,
            createdAt: packet.createdAt,
            folderURL: packet.folderURL,
            zipURL: packet.zipURL ?? PacketLayout.zipURL(for: packet.folderURL)
        )
    }

    func ensureDerivedDirectories() throws {
        try FileManager.default.createDirectory(at: rawURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rawSegmentsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentPromptsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fullFramesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: compressedFramesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: candidateMetadataURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
