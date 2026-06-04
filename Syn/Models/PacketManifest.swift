import Foundation

struct PacketManifest: Codable {
    var schemaVersion: Int
    var appVersion: String
    var createdAt: Date
    var duration: TimeInterval
    var capture: CaptureSourceMetadata
    var files: PacketFiles
    var processing: PacketProcessing
    var pauses: [PauseInterval]
    var pointerEventCount: Int
    var pointerMapping: PointerMappingMetadata?
    var annotationCount: Int?
    var annotationMapping: AnnotationMappingMetadata?
    var agentPromptProfile: String?
}

struct RawCaptureSession: Codable {
    var schemaVersion: Int
    var packetID: UUID
    var title: String
    var createdAt: Date
    var capture: CaptureSourceMetadata
    var pauses: [PauseInterval]
}

struct PacketFiles: Codable {
    var recording: String
    var transcript: String
    var summary: String
    var agentPrompt: String
    var agentPrompts: String?
    var framesFull: String
    var framesCompressed: String
    var candidateMetadata: String
    var rawRecording: String
    var rawCaptureSession: String?
    var pointerEvents: String
    var annotations: String?
    var activeWindowSamples: String?
    var zip: String
    var rawZip: String?
    var editedRecording: String?
    var compactZip: String?
    var projectContext: String?
    var semanticSegments: String?
    var semanticTimeline: String?
}

struct PacketProcessing: Codable {
    var transcriptionProvider: String
    var transcriptionModel: String
    var frameSelectionProvider: String
    var frameSelectionModel: String?
    var summaryProvider: String
    var summaryModel: String
    var status: String
    var notes: [String]
    var stageTimings: [ProcessingStageTiming]? = nil
    /// "pending" while the shareable zip is still being created in the background after the
    /// packet is otherwise complete, "ready" once it exists. nil for older/partial packets.
    var zipStatus: String? = nil
    /// "pending" while the layered summary is still generating in the background, "ready" once
    /// the best tier has landed, "local-fallback" if every tier failed. nil for older packets.
    var summaryStatus: String? = nil
}

struct ProcessingStageTiming: Codable {
    var name: String
    var durationSeconds: Double
}

struct PointerMappingMetadata: Codable {
    var sourceCoordinateSpace: String
    var videoCoordinateSpace: String
    var renderSize: CodableSize
    var mappedEventCount: Int
    var unmappedEventCount: Int
    var renderedClickCount: Int
    var staticPadding: Double
    var usesActiveWindowTimeline: Bool
}
