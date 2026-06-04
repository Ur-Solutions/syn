import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit
import Vision

enum FrameExtractorError: LocalizedError {
    case couldNotCreateDestination
    case couldNotEncodeImage

    var errorDescription: String? {
        switch self {
        case .couldNotCreateDestination:
            "Could not create an image destination."
        case .couldNotEncodeImage:
            "Could not encode an extracted frame."
        }
    }
}

final class FrameExtractor {
    static func recognizeText(in image: CGImage) -> FrameOCRRecognitionResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.012

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return FrameOCRRecognitionResult(text: nil, meanConfidence: nil, observations: [])
        }

        let observations = (request.results ?? [])
            .compactMap { observation -> OCRTextObservation? in
                guard let candidate = observation.topCandidates(1).first else {
                    return nil
                }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    return nil
                }
                return OCRTextObservation(
                    text: text,
                    confidence: Double(candidate.confidence),
                    boundingBox: CodableRect(observation.boundingBox)
                )
            }
            .filter { $0.confidence >= 0.2 }

        guard !observations.isEmpty else {
            return FrameOCRRecognitionResult(text: nil, meanConfidence: nil, observations: [])
        }

        let text = observations.map(\.text).joined(separator: "\n")
        let meanConfidence = observations.map(\.confidence).reduce(0, +) / Double(observations.count)
        return FrameOCRRecognitionResult(
            text: text,
            meanConfidence: meanConfidence,
            observations: Array(observations.prefix(24))
        )
    }

    func extractFrames(
        from videoURL: URL,
        context: PacketContext,
        capture: CaptureSourceMetadata,
        activeWindowSamples: [ActiveWindowSample]
    ) async throws -> FrameExtractionResult {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.durationSeconds()
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 3)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 3)

        let interval = 3.0
        let times = stride(from: 0.0, through: max(duration, 0), by: interval)
            .map { CMTime(seconds: $0, preferredTimescale: 600) }

        var previousPixelSample: [UInt8]?
        var metadata: [CandidateFrameMetadata] = []
        let keepCandidateFrames = getenv("SYN_KEEP_CANDIDATE_FRAMES").map { String(cString: $0) } == "1"

        for time in times {
            let image = try generator.copyCGImage(at: time, actualTime: nil)
            let timestamp = time.seconds
            let hash = perceptualHash(for: image)
            let pixelSample = grayscaleSample(for: image, width: 64, height: 36)
            let diff = previousPixelSample.map { normalizedMeanAbsoluteDifference($0, pixelSample) }
            let ocr = Self.recognizeText(in: image)
            let selected = diff == nil || (diff ?? 0) > 0.006
            let filename = timestampFilename(timestamp)

            var fullPath: String?
            var compressedPath: String?
            var candidatePath: String?
            var fullSize: CodableSize?
            var compressedSize: CodableSize?
            var candidateSize: CodableSize?
            var fullBytes: Int?
            var compressedBytes: Int?
            var candidateBytes: Int?

            if keepCandidateFrames {
                let candidateURL = context.candidateMetadataURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("\(filename).jpg")
                candidateSize = try writeCompressedJPEG(image, to: candidateURL)
                candidatePath = relativePath(candidateURL, base: context.folderURL)
                candidateBytes = fileSize(candidateURL)
            }

            if selected {
                let fullURL = context.fullFramesURL.appendingPathComponent("\(filename).png")
                let compressedURL = context.compressedFramesURL.appendingPathComponent("\(filename).jpg")
                try writePNG(image, to: fullURL)
                let compressedImageSize = try writeCompressedJPEG(image, to: compressedURL)
                fullPath = relativePath(fullURL, base: context.folderURL)
                compressedPath = relativePath(compressedURL, base: context.folderURL)
                fullSize = CodableSize(width: Double(image.width), height: Double(image.height))
                compressedSize = compressedImageSize
                fullBytes = fileSize(fullURL)
                compressedBytes = fileSize(compressedURL)
            }

            let frameContext = frameContext(at: timestamp, capture: capture, activeWindowSamples: activeWindowSamples)
            metadata.append(
                CandidateFrameMetadata(
                    timestamp: timestamp,
                    fullPath: fullPath,
                    compressedPath: compressedPath,
                    candidatePath: candidatePath,
                    fullSize: fullSize,
                    compressedSize: compressedSize,
                    candidateSize: candidateSize,
                    fullBytes: fullBytes,
                    compressedBytes: compressedBytes,
                    candidateBytes: candidateBytes,
                    perceptualHash: String(format: "%016llx", hash),
                    pixelDifferenceFromPrevious: diff,
                    appName: frameContext.appName,
                    windowTitle: frameContext.windowTitle,
                    captureBounds: frameContext.captureBounds,
                    ocrText: ocr.text,
                    ocrMeanConfidence: ocr.meanConfidence,
                    ocrObservations: ocr.observations.isEmpty ? nil : ocr.observations,
                    selected: selected,
                    reason: selected ? "visual-change-pixel-diff" : "pixel-dedupe"
                )
            )

            if selected {
                previousPixelSample = pixelSample
            }
        }

        let data = try JSONEncoder.synEncoder.encode(metadata)
        try data.write(to: context.candidateMetadataURL)

        return FrameExtractionResult(
            candidateFrames: metadata,
            selectedFrames: metadata.filter(\.selected),
            duration: duration
        )
    }

    private func frameContext(
        at timestamp: TimeInterval,
        capture: CaptureSourceMetadata,
        activeWindowSamples: [ActiveWindowSample]
    ) -> (appName: String?, windowTitle: String?, captureBounds: CodableRect?) {
        let sample = activeWindowSamples.last(where: { $0.timestamp <= timestamp }) ?? activeWindowSamples.first
        if capture.mode == CaptureMode.activeWindowFollow.rawValue,
           let sample {
            return (sample.appName, sample.windowTitle, sample.bounds)
        }

        return (
            sample?.appName ?? capture.appName,
            sample?.windowTitle ?? capture.windowTitle,
            capture.sourceRect
        )
    }

    private func timestampFilename(_ timestamp: TimeInterval) -> String {
        let totalMilliseconds = Int((timestamp * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1000
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d-%02d-%02d.%03d", hours, minutes, seconds, milliseconds)
    }

    private func relativePath(_ url: URL, base: URL) -> String {
        let path = url.path
        let basePath = base.path + "/"
        if path.hasPrefix(basePath) {
            return String(path.dropFirst(basePath.count))
        }
        return path
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw FrameExtractorError.couldNotCreateDestination
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FrameExtractorError.couldNotEncodeImage
        }
    }

    private func writeCompressedJPEG(_ image: CGImage, to url: URL) throws -> CodableSize {
        let maxDimension: CGFloat = 1600
        let originalSize = CGSize(width: image.width, height: image.height)
        let scale = min(1, maxDimension / max(originalSize.width, originalSize.height))
        let targetSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)

        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: image, size: originalSize).draw(in: CGRect(origin: .zero, size: targetSize))
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else {
            throw FrameExtractorError.couldNotEncodeImage
        }

        try data.write(to: url)
        return CodableSize(width: Double(targetSize.width), height: Double(targetSize.height))
    }

    private func fileSize(_ url: URL) -> Int? {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }

    private func perceptualHash(for image: CGImage) -> UInt64 {
        let size = 8
        let width = size
        let height = size
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return 0
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let average = pixels.map(Int.init).reduce(0, +) / max(pixels.count, 1)
        return pixels.enumerated().reduce(UInt64(0)) { hash, item in
            let bit: UInt64 = Int(item.element) >= average ? 1 : 0
            return hash | (bit << UInt64(item.offset))
        }
    }

    private func grayscaleSample(for image: CGImage, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return pixels
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private func normalizedMeanAbsoluteDifference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else {
            return 0
        }

        var total = 0
        for index in 0..<count {
            total += abs(Int(lhs[index]) - Int(rhs[index]))
        }

        return Double(total) / Double(count * 255)
    }
}
