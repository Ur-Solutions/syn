import AVFoundation
import Foundation

struct VideoTrimResult {
    var outputURL: URL
    var sourceDuration: TimeInterval
    var trimmedDuration: TimeInterval
}

enum VideoTrimServiceError: LocalizedError {
    case invalidRange
    case noExportSession
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRange:
            "Choose an end time that is after the start time and within the recording duration."
        case .noExportSession:
            "Could not create a video export session."
        case .exportFailed(let message):
            "Video trim export failed: \(message)"
        }
    }
}

enum VideoTrimService {
    static func createTrimmedCopy(
        sourceURL: URL,
        outputURL: URL,
        start: TimeInterval,
        end: TimeInterval
    ) async throws -> VideoTrimResult {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration).seconds
        let clampedStart = max(0, min(start, duration))
        let clampedEnd = max(0, min(end, duration))
        guard clampedEnd > clampedStart else {
            throw VideoTrimServiceError.invalidRange
        }

        let startTime = CMTime(seconds: clampedStart, preferredTimescale: 600)
        let endTime = CMTime(seconds: clampedEnd, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startTime, end: endTime)

        try? FileManager.default.removeItem(at: outputURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoTrimServiceError.noExportSession
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = timeRange
        exportSession.shouldOptimizeForNetworkUse = true
        try await exportSession.exportAsyncForTrim()

        return VideoTrimResult(
            outputURL: outputURL,
            sourceDuration: duration,
            trimmedDuration: clampedEnd - clampedStart
        )
    }
}

private extension AVAssetExportSession {
    func exportAsyncForTrim() async throws {
        await export()
        if status != .completed {
            let message = error?.localizedDescription ?? "status \(status.rawValue)"
            throw VideoTrimServiceError.exportFailed(message)
        }
    }
}
