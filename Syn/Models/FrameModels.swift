import Foundation

struct OCRTextObservation: Codable, Sendable {
    var text: String
    var confidence: Double
    var boundingBox: CodableRect
}

struct FrameOCRRecognitionResult: Sendable {
    var text: String?
    var meanConfidence: Double?
    var observations: [OCRTextObservation]
}

struct CandidateFrameMetadata: Codable, Sendable {
    var timestamp: TimeInterval
    var fullPath: String?
    var compressedPath: String?
    var candidatePath: String? = nil
    var fullSize: CodableSize? = nil
    var compressedSize: CodableSize? = nil
    var candidateSize: CodableSize? = nil
    var fullBytes: Int? = nil
    var compressedBytes: Int? = nil
    var candidateBytes: Int? = nil
    var perceptualHash: String
    var pixelDifferenceFromPrevious: Double?
    var appName: String?
    var windowTitle: String?
    var captureBounds: CodableRect?
    var ocrText: String? = nil
    var ocrMeanConfidence: Double? = nil
    var ocrObservations: [OCRTextObservation]? = nil
    var selected: Bool
    var reason: String
}

struct FrameExtractionResult: Sendable {
    var candidateFrames: [CandidateFrameMetadata]
    var selectedFrames: [CandidateFrameMetadata]
    var duration: TimeInterval
}

struct SemanticSegment: Codable, Sendable {
    var index: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var title: String
    var summary: String
    var representativeFrameTimestamp: TimeInterval?
    var framePaths: [String]
    var source: String
}
