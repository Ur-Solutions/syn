import AVFoundation
import AppKit
import Foundation
import QuartzCore

enum VideoUtilitiesError: LocalizedError {
    case noExportSession
    case exportFailed(String)
    case noAudioTrack
    case noVideoTrack

    var errorDescription: String? {
        switch self {
        case .noExportSession:
            "Could not create an export session."
        case .exportFailed(let message):
            "Export failed: \(message)"
        case .noAudioTrack:
            "The recording does not contain an audio track."
        case .noVideoTrack:
            "The recording does not contain a video track."
        }
    }
}

struct ProcessedVideoResult {
    var duration: TimeInterval
    var renderSize: CodableSize
    var pointerEvents: [PointerEvent]
    var renderedClickCount: Int
    var annotations: [AnnotationStroke]
    var renderedAnnotationCount: Int
    var notes: [String]
}

struct AllScreensDisplayRecording {
    var url: URL
    var displayID: CGDirectDisplayID
    var frame: CGRect
}

enum VideoUtilities {
    private static let allScreensMaximumWidth: CGFloat = 3840
    private static let allScreensMaximumHeight: CGFloat = 2160

    static func allScreensOutputScale(unionRect: CGRect, nativeScale: CGFloat) -> CGFloat {
        guard !unionRect.isNull, unionRect.width > 0, unionRect.height > 0 else {
            return 1
        }

        return min(
            max(nativeScale, 0.1),
            allScreensMaximumWidth / unionRect.width,
            allScreensMaximumHeight / unionRect.height
        )
    }

    static func allScreensRenderSize(unionRect: CGRect, nativeScale: CGFloat) -> CGSize {
        let scale = allScreensOutputScale(unionRect: unionRect, nativeScale: nativeScale)
        return CGSize(
            width: evenCeil(unionRect.width * scale),
            height: evenCeil(unionRect.height * scale)
        )
    }

    static func mergeSegments(_ segments: [URL], outputURL: URL) async throws -> TimeInterval {
        try? FileManager.default.removeItem(at: outputURL)

        guard segments.count > 1 else {
            guard let first = segments.first else {
                return 0
            }
            try FileManager.default.copyItem(at: first, to: outputURL)
            let asset = AVURLAsset(url: outputURL)
            return try await asset.durationSeconds()
        }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoUtilitiesError.noExportSession
        }

        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor = CMTime.zero

        for segmentURL in segments {
            let asset = AVURLAsset(url: segmentURL)
            let duration = try await asset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: duration)

            if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: cursor)
                compositionVideoTrack.preferredTransform = try await videoTrack.load(.preferredTransform)
            }

            if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
               let compositionAudioTrack {
                try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: cursor)
            }

            cursor = cursor + duration
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoUtilitiesError.noExportSession
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        try await exportSession.exportAsync()
        return cursor.seconds
    }

    static func copyFinalRecording(rawURL: URL, finalURL: URL) throws {
        try? FileManager.default.removeItem(at: finalURL)
        try FileManager.default.copyItem(at: rawURL, to: finalURL)
    }

    /// Maps one global screen point into final-video pixels using the exact same formula as
    /// the offline `mapPointerEvents`, so live-burned bubbles land where the offline render
    /// would have put them. Returns nil when the point falls outside the video canvas.
    static func mapGlobalPointToVideo(
        _ point: CGPoint,
        capture: CaptureSourceMetadata,
        presentationSize: CGSize,
        padding: CGFloat
    ) -> CGPoint? {
        guard let sourceRect = pointerSourceRect(for: capture, presentationSize: presentationSize) else {
            return nil
        }
        let scaleX = presentationSize.width / max(sourceRect.width, 1)
        let scaleY = presentationSize.height / max(sourceRect.height, 1)
        let x = (point.x - sourceRect.minX) * scaleX + padding
        let y = (sourceRect.maxY - point.y) * scaleY + padding
        let renderSize = CGSize(width: presentationSize.width + padding * 2, height: presentationSize.height + padding * 2)
        guard x >= 0, y >= 0, x <= renderSize.width, y <= renderSize.height else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    /// Stop-time finalize for recordings whose click bubbles were already burned live during
    /// capture: stitches the live-rendered video segments with the raw recording's audio
    /// track through a PASSTHROUGH export (no re-encode), then maps pointer/annotation
    /// metadata exactly like the offline render would. Throws if anything is off — the
    /// caller falls back to the full offline render.
    static func fastFinalizeLiveRender(
        liveSegmentURLs: [URL],
        rawURL: URL,
        finalURL: URL,
        capture: CaptureSourceMetadata,
        pointerEvents: [PointerEvent],
        renderedClickCount: Int
    ) async throws -> ProcessedVideoResult {
        try? FileManager.default.removeItem(at: finalURL)
        guard !liveSegmentURLs.isEmpty else {
            throw VideoUtilitiesError.noVideoTrack
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoUtilitiesError.noExportSession
        }

        var cursor = CMTime.zero
        var presentationSize = CGSize.zero
        for segmentURL in liveSegmentURLs {
            let asset = AVURLAsset(url: segmentURL)
            guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw VideoUtilitiesError.noVideoTrack
            }
            let duration = try await asset.load(.duration)
            try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceTrack, at: cursor)
            if presentationSize == .zero {
                presentationSize = try await sourceTrack.load(.naturalSize)
            }
            cursor = cursor + duration
        }

        let rawAsset = AVURLAsset(url: rawURL)
        let rawDuration = try await rawAsset.load(.duration)
        // If the live encode missed a meaningful chunk of the recording (frame delivery
        // stalls, dropped segments), reject it — the offline render is the safe fallback.
        guard abs(rawDuration.seconds - cursor.seconds) <= max(1.5, rawDuration.seconds * 0.05) else {
            throw VideoUtilitiesError.exportFailed(String(
                format: "Live render duration %.2fs diverges from raw %.2fs.",
                cursor.seconds,
                rawDuration.seconds
            ))
        }
        if let audioTrack = try await rawAsset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: min(rawDuration, cursor)),
                of: audioTrack,
                at: .zero
            )
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw VideoUtilitiesError.noExportSession
        }
        exportSession.outputURL = finalURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        try await exportSession.exportAsync()

        let mapped = mapPointerEvents(
            pointerEvents,
            capture: capture,
            presentationSize: presentationSize,
            renderSize: presentationSize,
            padding: 0,
            activeWindowPlan: nil
        )

        var notes = mapped.notes
        notes.append("recording.mp4 was rendered live during capture; stop-time finalize was a passthrough remux without re-encoding.")
        if capture.mode == CaptureMode.selectedWindow.rawValue {
            notes.append("Live-rendered window capture does not add the 24 px padding used by the offline render.")
        }

        return ProcessedVideoResult(
            duration: cursor.seconds,
            renderSize: CodableSize(presentationSize),
            pointerEvents: mapped.events,
            renderedClickCount: renderedClickCount,
            annotations: [],
            renderedAnnotationCount: 0,
            notes: notes
        )
    }

    /// True when the processed render is a moving crop of the raw capture (Active Window
    /// follow / Smart Region), i.e. the final video's framing differs structurally from the
    /// raw recording. Conservative over-approximation of the internal render-plan guards:
    /// callers use it to decide whether raw-recording frames are representative of the final
    /// video (when false, frame extraction can run in parallel with the render).
    static func usesDynamicCropRender(
        capture: CaptureSourceMetadata,
        activeWindowSamples: [ActiveWindowSample]
    ) -> Bool {
        if capture.mode == CaptureMode.activeWindowFollow.rawValue, !activeWindowSamples.isEmpty {
            return true
        }
        if capture.mode == CaptureMode.smartRegion.rawValue, capture.smartRegion != nil {
            return true
        }
        return false
    }

    static func composeAllScreensRecordings(
        _ recordings: [AllScreensDisplayRecording],
        outputURL: URL
    ) async throws -> TimeInterval {
        try? FileManager.default.removeItem(at: outputURL)

        guard recordings.count > 1 else {
            guard let recording = recordings.first else {
                return 0
            }
            try FileManager.default.copyItem(at: recording.url, to: outputURL)
            return try await AVURLAsset(url: outputURL).durationSeconds()
        }

        let composition = AVMutableComposition()
        let unionRect = recordings
            .map(\.frame)
            .reduce(CGRect.null) { partial, frame in
                partial.isNull ? frame : partial.union(frame)
            }

        var displayAssets: [(recording: AllScreensDisplayRecording, asset: AVURLAsset, videoTrack: AVAssetTrack, presentationSize: CGSize, duration: CMTime)] = []
        var maxDuration = CMTime.zero
        var maxScale: CGFloat = 1

        for recording in recordings {
            let asset = AVURLAsset(url: recording.url)
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw VideoUtilitiesError.noVideoTrack
            }

            let duration = try await asset.load(.duration)
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
            let presentationSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
            maxScale = max(maxScale, presentationSize.width / max(recording.frame.width, 1))
            maxDuration = max(maxDuration, duration)
            displayAssets.append((recording, asset, videoTrack, presentationSize, duration))
        }

        let outputScale = allScreensOutputScale(unionRect: unionRect, nativeScale: maxScale)
        let renderSize = allScreensRenderSize(unionRect: unionRect, nativeScale: maxScale)

        var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []
        for item in displayAssets {
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw VideoUtilitiesError.noExportSession
            }

            let timeRange = CMTimeRange(start: .zero, duration: item.duration)
            try compositionTrack.insertTimeRange(timeRange, of: item.videoTrack, at: .zero)

            let preferredTransform = try await item.videoTrack.load(.preferredTransform)
            let naturalSize = try await item.videoTrack.load(.naturalSize)
            let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
            let normalizedTransform = preferredTransform.concatenating(
                CGAffineTransform(translationX: -transformedRect.minX, y: -transformedRect.minY)
            )
            let targetWidth = item.recording.frame.width * outputScale
            let targetHeight = item.recording.frame.height * outputScale
            let scaleX = targetWidth / max(item.presentationSize.width, 1)
            let scaleY = targetHeight / max(item.presentationSize.height, 1)
            let x = (item.recording.frame.minX - unionRect.minX) * outputScale
            let y = (unionRect.maxY - item.recording.frame.maxY) * outputScale

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
            layerInstruction.setTransform(
                normalizedTransform
                    .concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
                    .concatenating(CGAffineTransform(translationX: x, y: y)),
                at: .zero
            )
            layerInstructions.append(layerInstruction)
        }

        if let primary = displayAssets.first,
           let audioTrack = try await primary.asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: primary.duration),
                of: audioTrack,
                at: .zero
            )
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: maxDuration)
        instruction.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1).cgColor
        instruction.layerInstructions = layerInstructions

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoUtilitiesError.noExportSession
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition
        try await exportSession.exportAsync()
        return maxDuration.seconds
    }

    static func renderProcessedRecording(
        rawURL: URL,
        finalURL: URL,
        capture: CaptureSourceMetadata,
        pointerEvents: [PointerEvent],
        annotations: [AnnotationStroke] = [],
        activeWindowSamples: [ActiveWindowSample] = []
    ) async throws -> ProcessedVideoResult {
        try? FileManager.default.removeItem(at: finalURL)

        let asset = AVURLAsset(url: rawURL)
        let duration = try await asset.load(.duration)
        guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoUtilitiesError.noVideoTrack
        }

        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let presentationSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))

        let activeWindowPlan = makeActiveWindowRenderPlan(
            capture: capture,
            presentationSize: presentationSize,
            duration: duration.seconds,
            samples: activeWindowSamples
        )
        let smartRegionPlan = activeWindowPlan == nil
            ? makeSmartRegionRenderPlan(
                capture: capture,
                presentationSize: presentationSize,
                duration: duration.seconds,
                pointerEvents: pointerEvents
            )
            : nil
        let dynamicCropPlan = activeWindowPlan ?? smartRegionPlan
        let padding = dynamicCropPlan == nil && shouldPadStaticWindowCapture(capture) ? CGFloat(24) : CGFloat(0)
        let renderSize = dynamicCropPlan?.renderSize ?? CGSize(
            width: evenCeil(presentationSize.width + padding * 2),
            height: evenCeil(presentationSize.height + padding * 2)
        )

        // Fast-path: when there is no dynamic crop, no padding, and nothing to draw
        // (no click bubbles, no annotations), the processed recording is identical to the
        // raw capture. Copy it instead of re-encoding the whole video through
        // AVAssetExportSession + Core Animation, which is the dominant processing cost.
        let hasClicks = pointerEvents.contains { $0.kind.isMouseDown }
        let hasAnnotations = !annotations.isEmpty
        if dynamicCropPlan == nil, padding == 0, !hasClicks, !hasAnnotations {
            try FileManager.default.copyItem(at: rawURL, to: finalURL)
            let mapped = mapPointerEvents(
                pointerEvents,
                capture: capture,
                presentationSize: presentationSize,
                renderSize: renderSize,
                padding: 0,
                activeWindowPlan: nil
            )
            let mappedAnnotations = mapAnnotationStrokes(
                annotations,
                capture: capture,
                presentationSize: presentationSize,
                renderSize: renderSize,
                padding: 0,
                activeWindowPlan: nil
            )
            return ProcessedVideoResult(
                duration: duration.seconds,
                renderSize: CodableSize(renderSize),
                pointerEvents: mapped.events,
                renderedClickCount: 0,
                annotations: mappedAnnotations.strokes,
                renderedAnnotationCount: 0,
                notes: ["No overlays, crop, or padding required; copied raw recording without re-encoding."]
            )
        }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoUtilitiesError.noExportSession
        }

        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try compositionVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)

        if let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compositionAudioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
        }

        var notes: [String] = []
        notes.append(contentsOf: dynamicCropPlan?.notes ?? [])
        let mapped = mapPointerEvents(
            pointerEvents,
            capture: capture,
            presentationSize: presentationSize,
            renderSize: renderSize,
            padding: padding,
            activeWindowPlan: dynamicCropPlan
        )
        notes.append(contentsOf: mapped.notes)
        let mappedAnnotations = mapAnnotationStrokes(
            annotations,
            capture: capture,
            presentationSize: presentationSize,
            renderSize: renderSize,
            padding: padding,
            activeWindowPlan: dynamicCropPlan
        )
        notes.append(contentsOf: mappedAnnotations.notes)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let normalizedTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -transformedRect.minX, y: -transformedRect.minY)
        )
        if let dynamicCropPlan {
            videoComposition.instructions = dynamicCropPlan.windows.map { window in
                makeVideoInstruction(
                    track: compositionVideoTrack,
                    timeRange: CMTimeRange(
                        start: CMTime(seconds: window.start, preferredTimescale: 600),
                        duration: CMTime(seconds: max(0, window.end - window.start), preferredTimescale: 600)
                    ),
                    transform: normalizedTransform.concatenating(
                        CGAffineTransform(translationX: window.translation.x, y: window.translation.y)
                    )
                )
            }
        } else {
            let renderTransform = normalizedTransform.concatenating(
                CGAffineTransform(translationX: padding, y: padding)
            )
            videoComposition.instructions = [
                makeVideoInstruction(track: compositionVideoTrack, timeRange: timeRange, transform: renderTransform)
            ]
        }

        let overlayResult = addTimedOverlays(
            to: videoComposition,
            renderSize: renderSize,
            pointerEvents: mapped.events,
            annotations: mappedAnnotations.strokes,
            duration: duration.seconds
        )

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoUtilitiesError.noExportSession
        }
        exportSession.outputURL = finalURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition
        try await exportSession.exportAsync()

        if padding > 0 || activeWindowPlan != nil {
            notes.append("Processed recording uses a 24 px padded canvas for window capture.")
        }
        if overlayResult.clickCount == 0, pointerEvents.contains(where: \.kind.isMouseDown) {
            notes.append("Click events were captured, but none could be mapped into the rendered video canvas.")
        }
        if overlayResult.annotationCount == 0, !annotations.isEmpty {
            notes.append("Annotation strokes were captured, but none could be mapped into the rendered video canvas.")
        }
        if overlayResult.offCanvasAnnotationCount > 0 {
            notes.append("\(overlayResult.offCanvasAnnotationCount) annotation stroke(s) mapped outside the rendered video canvas and were not drawn into recording.mp4.")
        }

        return ProcessedVideoResult(
            duration: duration.seconds,
            renderSize: CodableSize(renderSize),
            pointerEvents: mapped.events,
            renderedClickCount: overlayResult.clickCount,
            annotations: mappedAnnotations.strokes,
            renderedAnnotationCount: overlayResult.annotationCount,
            notes: notes
        )
    }

    static func extractAudioWAV(from videoURL: URL, to audioURL: URL) async throws {
        try? FileManager.default.removeItem(at: audioURL)

        let asset = AVURLAsset(url: videoURL)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw VideoUtilitiesError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: audioURL, fileType: .wav)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: .zero)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "syn.audio.extract")
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let sample = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sample)
                    } else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            if let error = writer.error {
                                continuation.resume(throwing: error)
                            } else if let error = reader.error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                        return
                    }
                }
            }
        }
    }

    private static func shouldPadStaticWindowCapture(_ capture: CaptureSourceMetadata) -> Bool {
        capture.mode == CaptureMode.selectedWindow.rawValue
    }

    private static func evenCeil(_ value: CGFloat) -> CGFloat {
        let integer = Int(ceil(value))
        return CGFloat(integer.isMultiple(of: 2) ? integer : integer + 1)
    }

    private static func addTimedOverlays(
        to videoComposition: AVMutableVideoComposition,
        renderSize: CGSize,
        pointerEvents: [PointerEvent],
        annotations: [AnnotationStroke],
        duration: TimeInterval
    ) -> (clickCount: Int, annotationCount: Int, offCanvasAnnotationCount: Int) {
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds

        let overlayLayer = CALayer()
        overlayLayer.frame = parentLayer.bounds

        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)

        var clickCount = 0
        for event in pointerEvents where event.kind.isMouseDown {
            guard event.timestamp >= 0,
                  event.timestamp <= duration,
                  let point = event.videoCoordinates else {
                continue
            }

            addClickBubble(
                to: overlayLayer,
                center: CGPoint(x: point.x, y: Double(renderSize.height) - point.y),
                timestamp: event.timestamp
            )
            clickCount += 1
        }

        var annotationCount = 0
        var offCanvasAnnotationCount = 0
        let canvasRect = CGRect(origin: .zero, size: renderSize)
        for annotation in annotations {
            guard annotation.startTimestamp >= 0,
                  annotation.startTimestamp <= duration,
                  let points = annotation.videoPoints,
                  points.count >= (annotation.tool == .text ? 1 : 2) else {
                continue
            }

            let layerPoints = points.map { CGPoint(x: $0.x, y: Double(renderSize.height) - $0.y) }
            // Strokes whose mapped coordinates fall entirely outside the canvas would
            // export an empty overlay while still being reported as rendered; skip them
            // and surface the count to the processing notes instead.
            let xs = layerPoints.map(\.x)
            let ys = layerPoints.map(\.y)
            let inflate = max(CGFloat(annotation.lineWidth), 8)
            let strokeBounds = CGRect(
                x: xs.min() ?? 0,
                y: ys.min() ?? 0,
                width: (xs.max() ?? 0) - (xs.min() ?? 0),
                height: (ys.max() ?? 0) - (ys.min() ?? 0)
            ).insetBy(dx: -inflate, dy: -inflate)
            guard strokeBounds.intersects(canvasRect) else {
                offCanvasAnnotationCount += 1
                continue
            }

            addAnnotation(
                annotation,
                points: layerPoints,
                to: overlayLayer,
                renderDuration: duration
            )
            annotationCount += 1
        }

        // Only attach the Core Animation tool when there is something to draw. It forces
        // the entire export to be composited frame-by-frame through Core Animation (the
        // slowest AVFoundation export path), so crop-only renders skip it.
        guard clickCount > 0 || annotationCount > 0 else {
            return (0, 0, offCanvasAnnotationCount)
        }
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        return (clickCount, annotationCount, offCanvasAnnotationCount)
    }

    private static func addClickBubble(to layer: CALayer, center: CGPoint, timestamp: TimeInterval) {
        let bubble = CALayer()
        bubble.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
        bubble.position = center
        bubble.cornerRadius = 8
        bubble.borderWidth = 3
        bubble.borderColor = NSColor.controlAccentColor.cgColor
        bubble.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        bubble.opacity = 0

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.35
        scale.toValue = 3.4

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 0.9, 0]
        opacity.keyTimes = [0, 0.08, 1]

        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.beginTime = AVCoreAnimationBeginTimeAtZero + timestamp
        group.duration = 0.55
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false

        bubble.add(group, forKey: "syn-click-bubble")
        layer.addSublayer(bubble)
    }

    private static func addAnnotation(
        _ annotation: AnnotationStroke,
        points: [CGPoint],
        to layer: CALayer,
        renderDuration: TimeInterval
    ) {
        if annotation.tool == .text {
            addTextAnnotation(
                annotation,
                point: points[0],
                to: layer,
                renderDuration: renderDuration
            )
            return
        }

        let shape = CAShapeLayer()
        shape.frame = layer.bounds
        shape.fillColor = NSColor.clear.cgColor
        shape.strokeColor = NSColor(hex: annotation.colorHex)?.cgColor ?? NSColor.controlAccentColor.cgColor
        shape.lineWidth = annotation.lineWidth
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.opacity = 0
        shape.path = annotationPath(tool: annotation.tool, points: points, lineWidth: CGFloat(annotation.lineWidth))

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1]
        opacity.keyTimes = [0, 0.08, 1]

        let group = CAAnimationGroup()
        group.animations = [opacity]
        group.beginTime = AVCoreAnimationBeginTimeAtZero + annotation.startTimestamp
        group.duration = max(0.2, renderDuration - annotation.startTimestamp)
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false

        shape.add(group, forKey: "syn-annotation")
        layer.addSublayer(shape)
    }

    private static func addTextAnnotation(
        _ annotation: AnnotationStroke,
        point: CGPoint,
        to layer: CALayer,
        renderDuration: TimeInterval
    ) {
        guard let text = annotation.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }

        let fontSize = max(20, CGFloat(annotation.lineWidth) * 4.8)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor(hex: annotation.colorHex) ?? .controlAccentColor
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)

        let textLayer = CATextLayer()
        textLayer.frame = CGRect(
            x: point.x,
            y: point.y,
            width: max(1, textSize.width + 8),
            height: max(1, textSize.height + 8)
        )
        textLayer.string = NSAttributedString(string: text, attributes: attributes)
        textLayer.contentsScale = 2
        textLayer.alignmentMode = .left
        textLayer.truncationMode = .end
        textLayer.opacity = 0

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1]
        opacity.keyTimes = [0, 0.08, 1]

        let group = CAAnimationGroup()
        group.animations = [opacity]
        group.beginTime = AVCoreAnimationBeginTimeAtZero + annotation.startTimestamp
        group.duration = max(0.2, renderDuration - annotation.startTimestamp)
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false

        textLayer.add(group, forKey: "syn-text-annotation")
        layer.addSublayer(textLayer)
    }

    private static func annotationPath(tool: AnnotationTool, points: [CGPoint], lineWidth: CGFloat) -> CGPath {
        let path = CGMutablePath()
        switch tool {
        case .pen:
            path.move(to: points[0])
            points.dropFirst().forEach { path.addLine(to: $0) }
        case .line:
            let start = points[0]
            let end = points[points.count - 1]
            path.move(to: start)
            path.addLine(to: end)
        case .rectangle:
            let start = points[0]
            let end = points[points.count - 1]
            path.addRect(CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            ))
        case .ellipse:
            let start = points[0]
            let end = points[points.count - 1]
            path.addEllipse(in: CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            ))
        case .text:
            break
        case .arrow:
            let start = points[0]
            let end = points[points.count - 1]
            path.move(to: start)
            path.addLine(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength = max(16, lineWidth * 5)
            let spread = CGFloat.pi / 7
            let p1 = CGPoint(
                x: end.x - headLength * cos(angle - spread),
                y: end.y - headLength * sin(angle - spread)
            )
            let p2 = CGPoint(
                x: end.x - headLength * cos(angle + spread),
                y: end.y - headLength * sin(angle + spread)
            )
            path.move(to: p1)
            path.addLine(to: end)
            path.addLine(to: p2)
        }
        return path
    }

    private static func mapPointerEvents(
        _ events: [PointerEvent],
        capture: CaptureSourceMetadata,
        presentationSize: CGSize,
        renderSize: CGSize,
        padding: CGFloat,
        activeWindowPlan: ActiveWindowRenderPlan?
    ) -> (events: [PointerEvent], notes: [String]) {
        if let activeWindowPlan {
            return mapActiveWindowPointerEvents(
                events,
                capture: capture,
                presentationSize: presentationSize,
                renderSize: renderSize,
                activeWindowPlan: activeWindowPlan
            )
        }

        guard let sourceRect = pointerSourceRect(for: capture, presentationSize: presentationSize) else {
            return (events, ["Pointer events were stored, but coordinate mapping was unavailable for this capture."])
        }

        let scaleX = presentationSize.width / max(sourceRect.width, 1)
        let scaleY = presentationSize.height / max(sourceRect.height, 1)
        var unmappedCount = 0

        let mappedEvents = events.map { event -> PointerEvent in
            var mapped = event
            let sourcePoint = CGPoint(x: event.sourceCoordinates.x, y: event.sourceCoordinates.y)
            let x = (sourcePoint.x - sourceRect.minX) * scaleX + padding
            let y = (sourceRect.maxY - sourcePoint.y) * scaleY + padding

            if x >= 0, y >= 0, x <= renderSize.width, y <= renderSize.height {
                mapped.videoCoordinates = CodablePoint(x: x, y: y)
            } else {
                mapped.videoCoordinates = nil
                unmappedCount += 1
            }
            return mapped
        }

        var notes: [String] = []
        if unmappedCount > 0 {
            notes.append("\(unmappedCount) pointer events fell outside the rendered video canvas and were kept as raw metadata only.")
        }
        return (mappedEvents, notes)
    }

    private static func mapAnnotationStrokes(
        _ strokes: [AnnotationStroke],
        capture: CaptureSourceMetadata,
        presentationSize: CGSize,
        renderSize: CGSize,
        padding: CGFloat,
        activeWindowPlan: ActiveWindowRenderPlan?
    ) -> (strokes: [AnnotationStroke], notes: [String]) {
        if let activeWindowPlan {
            return mapActiveWindowAnnotationStrokes(
                strokes,
                capture: capture,
                presentationSize: presentationSize,
                activeWindowPlan: activeWindowPlan
            )
        }

        guard let sourceRect = pointerSourceRect(for: capture, presentationSize: presentationSize) else {
            return (strokes, ["Annotation strokes were stored, but coordinate mapping was unavailable for this capture."])
        }

        let scaleX = presentationSize.width / max(sourceRect.width, 1)
        let scaleY = presentationSize.height / max(sourceRect.height, 1)
        var unmappedCount = 0

        let mapped = strokes.map { stroke -> AnnotationStroke in
            var mappedStroke = stroke
            let videoPoints = stroke.sourcePoints.map { point in
                CodablePoint(
                    x: (point.x - sourceRect.minX) * scaleX + padding,
                    y: (sourceRect.maxY - point.y) * scaleY + padding
                )
            }

            if videoPoints.count >= (stroke.tool == .text ? 1 : 2) {
                mappedStroke.videoPoints = videoPoints
            } else {
                mappedStroke.videoPoints = nil
                unmappedCount += 1
            }
            return mappedStroke
        }

        var notes: [String] = []
        if unmappedCount > 0 {
            notes.append("\(unmappedCount) annotation strokes could not be mapped into the rendered video canvas and were kept as raw metadata only.")
        }
        return (mapped, notes)
    }

    private static func pointerSourceRect(for capture: CaptureSourceMetadata, presentationSize: CGSize) -> CGRect? {
        if let sourceRect = capture.sourceRect {
            return CGRect(x: sourceRect.x, y: sourceRect.y, width: sourceRect.width, height: sourceRect.height)
        }

        if let displayID = capture.displayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) {
            return screen.frame
        }

        return CGRect(origin: .zero, size: presentationSize)
    }

    private static func makeVideoInstruction(
        track: AVCompositionTrack,
        timeRange: CMTimeRange,
        transform: CGAffineTransform
    ) -> AVMutableVideoCompositionInstruction {
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        instruction.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1).cgColor

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        return instruction
    }

    private static func makeSmartRegionRenderPlan(
        capture: CaptureSourceMetadata,
        presentationSize: CGSize,
        duration: TimeInterval,
        pointerEvents: [PointerEvent]
    ) -> ActiveWindowRenderPlan? {
        guard capture.mode == CaptureMode.smartRegion.rawValue,
              let selected = capture.smartRegion,
              duration > 0,
              let rawSourceRect = pointerSourceRect(for: capture, presentationSize: presentationSize) else {
            return nil
        }

        let selectedRegion = CGRect(
            x: selected.x,
            y: selected.y,
            width: selected.width,
            height: selected.height
        ).intersection(rawSourceRect)
        guard !selectedRegion.isNull,
              selectedRegion.width >= 40,
              selectedRegion.height >= 40 else {
            return nil
        }

        let scaleX = presentationSize.width / max(rawSourceRect.width, 1)
        let scaleY = presentationSize.height / max(rawSourceRect.height, 1)
        let cropSize = CGSize(
            width: evenCeil(selectedRegion.width * scaleX),
            height: evenCeil(selectedRegion.height * scaleY)
        )
        guard cropSize.width >= 40, cropSize.height >= 40 else {
            return nil
        }

        let initialCenter = CGPoint(
            x: selectedRegion.midX,
            y: selectedRegion.midY
        )
        var samples: [ActiveWindowRenderSample] = [
            ActiveWindowRenderSample(
                timestamp: 0,
                videoRect: cropRect(
                    centeredAt: videoPoint(
                        for: initialCenter,
                        sourceRect: rawSourceRect,
                        scaleX: scaleX,
                        scaleY: scaleY
                    ),
                    cropSize: cropSize,
                    presentationSize: presentationSize
                )
            )
        ]

        var lastTimestamp: TimeInterval = 0
        var lastCenter = samples[0].videoRect.center
        let sortedEvents = pointerEvents
            .filter { $0.timestamp >= 0 && $0.timestamp <= duration }
            .sorted { $0.timestamp < $1.timestamp }

        for event in sortedEvents {
            let center = videoPoint(
                for: CGPoint(x: event.sourceCoordinates.x, y: event.sourceCoordinates.y),
                sourceRect: rawSourceRect,
                scaleX: scaleX,
                scaleY: scaleY
            )
            let elapsed = event.timestamp - lastTimestamp
            let distance = hypot(center.x - lastCenter.x, center.y - lastCenter.y)
            guard elapsed >= 0.25 || distance >= 24 else {
                continue
            }

            samples.append(
                ActiveWindowRenderSample(
                    timestamp: event.timestamp,
                    videoRect: cropRect(
                        centeredAt: center,
                        cropSize: cropSize,
                        presentationSize: presentationSize
                    )
                )
            )
            lastTimestamp = event.timestamp
            lastCenter = center
        }

        var windows: [ActiveWindowRenderWindow] = []
        for index in samples.indices {
            let sample = samples[index]
            let start = index == samples.startIndex ? 0 : min(sample.timestamp, duration)
            let end = index == samples.index(before: samples.endIndex)
                ? duration
                : min(samples[samples.index(after: index)].timestamp, duration)
            guard end > start else {
                continue
            }

            windows.append(
                ActiveWindowRenderWindow(
                    start: start,
                    end: end,
                    videoRect: sample.videoRect,
                    translation: CGPoint(x: -sample.videoRect.minX, y: -sample.videoRect.minY)
                )
            )
        }

        guard !windows.isEmpty else {
            return nil
        }

        return ActiveWindowRenderPlan(
            renderSize: cropSize,
            windows: windows,
            notes: ["Smart Region rendered \(windows.count) cursor-following crop intervals from \(pointerEvents.count) pointer events."]
        )
    }

    private static func videoPoint(
        for sourcePoint: CGPoint,
        sourceRect: CGRect,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: (sourcePoint.x - sourceRect.minX) * scaleX,
            y: (sourceRect.maxY - sourcePoint.y) * scaleY
        )
    }

    private static func cropRect(
        centeredAt center: CGPoint,
        cropSize: CGSize,
        presentationSize: CGSize
    ) -> CGRect {
        let maxX = max(0, presentationSize.width - cropSize.width)
        let maxY = max(0, presentationSize.height - cropSize.height)
        return CGRect(
            x: min(max(center.x - cropSize.width / 2, 0), maxX),
            y: min(max(center.y - cropSize.height / 2, 0), maxY),
            width: min(cropSize.width, presentationSize.width),
            height: min(cropSize.height, presentationSize.height)
        )
    }

    private static func makeActiveWindowRenderPlan(
        capture: CaptureSourceMetadata,
        presentationSize: CGSize,
        duration: TimeInterval,
        samples: [ActiveWindowSample]
    ) -> ActiveWindowRenderPlan? {
        guard capture.mode == CaptureMode.activeWindowFollow.rawValue,
              !samples.isEmpty,
              duration > 0,
              let displayID = capture.displayID else {
            return nil
        }

        let displayBounds = CGDisplayBounds(displayID)
        guard displayBounds.width > 0, displayBounds.height > 0 else {
            return nil
        }

        let scaleX = presentationSize.width / displayBounds.width
        let scaleY = presentationSize.height / displayBounds.height
        let mappedSamples = samples
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { sample -> ActiveWindowRenderSample? in
                let bounds = CGRect(
                    x: sample.bounds.x,
                    y: sample.bounds.y,
                    width: sample.bounds.width,
                    height: sample.bounds.height
                )
                let visibleBounds = bounds.intersection(displayBounds)
                guard !visibleBounds.isNull, visibleBounds.width > 20, visibleBounds.height > 20 else {
                    return nil
                }

                let videoRect = CGRect(
                    x: (visibleBounds.minX - displayBounds.minX) * scaleX,
                    y: (visibleBounds.minY - displayBounds.minY) * scaleY,
                    width: visibleBounds.width * scaleX,
                    height: visibleBounds.height * scaleY
                )

                return ActiveWindowRenderSample(timestamp: max(0, sample.timestamp), videoRect: videoRect)
            }

        guard !mappedSamples.isEmpty else {
            return nil
        }

        let largestWidth = mappedSamples.map(\.videoRect.width).max() ?? presentationSize.width
        let largestHeight = mappedSamples.map(\.videoRect.height).max() ?? presentationSize.height
        let renderSize = CGSize(width: evenCeil(largestWidth + 48), height: evenCeil(largestHeight + 48))

        var windows: [ActiveWindowRenderWindow] = []
        for index in mappedSamples.indices {
            let sample = mappedSamples[index]
            let start = index == mappedSamples.startIndex ? 0 : min(sample.timestamp, duration)
            let end = index == mappedSamples.index(before: mappedSamples.endIndex)
                ? duration
                : min(mappedSamples[mappedSamples.index(after: index)].timestamp, duration)
            guard end > start else {
                continue
            }

            let translation = CGPoint(
                x: (renderSize.width - sample.videoRect.width) / 2 - sample.videoRect.minX,
                y: (renderSize.height - sample.videoRect.height) / 2 - sample.videoRect.minY
            )
            windows.append(
                ActiveWindowRenderWindow(
                    start: start,
                    end: end,
                    videoRect: sample.videoRect,
                    translation: translation
                )
            )
        }

        guard !windows.isEmpty else {
            return nil
        }

        return ActiveWindowRenderPlan(
            renderSize: renderSize,
            windows: windows,
            notes: ["Active-window-follow rendered \(windows.count) foreground-window intervals from \(samples.count) timeline samples."]
        )
    }

    private static func mapActiveWindowPointerEvents(
        _ events: [PointerEvent],
        capture: CaptureSourceMetadata,
        presentationSize: CGSize,
        renderSize: CGSize,
        activeWindowPlan: ActiveWindowRenderPlan
    ) -> (events: [PointerEvent], notes: [String]) {
        guard let rawSourceRect = pointerSourceRect(for: capture, presentationSize: presentationSize) else {
            return (events, ["Active-window pointer events were stored, but source coordinate mapping was unavailable."])
        }

        let scaleX = presentationSize.width / max(rawSourceRect.width, 1)
        let scaleY = presentationSize.height / max(rawSourceRect.height, 1)
        var unmappedCount = 0

        let mappedEvents = events.map { event -> PointerEvent in
            var mapped = event
            let sourcePoint = CGPoint(x: event.sourceCoordinates.x, y: event.sourceCoordinates.y)
            let rawPoint = CGPoint(
                x: (sourcePoint.x - rawSourceRect.minX) * scaleX,
                y: (rawSourceRect.maxY - sourcePoint.y) * scaleY
            )

            guard let window = activeWindowPlan.windows.last(where: { event.timestamp >= $0.start && event.timestamp <= $0.end }) else {
                mapped.videoCoordinates = nil
                unmappedCount += 1
                return mapped
            }

            let videoPoint = CGPoint(x: rawPoint.x + window.translation.x, y: rawPoint.y + window.translation.y)
            if videoPoint.x >= 0, videoPoint.y >= 0, videoPoint.x <= renderSize.width, videoPoint.y <= renderSize.height {
                mapped.videoCoordinates = CodablePoint(x: videoPoint.x, y: videoPoint.y)
            } else {
                mapped.videoCoordinates = nil
                unmappedCount += 1
            }
            return mapped
        }

        var notes: [String] = []
        if unmappedCount > 0 {
            notes.append("\(unmappedCount) active-window pointer events fell outside the rendered video canvas and were kept as raw metadata only.")
        }
        return (mappedEvents, notes)
    }

    private static func mapActiveWindowAnnotationStrokes(
        _ strokes: [AnnotationStroke],
        capture: CaptureSourceMetadata,
        presentationSize: CGSize,
        activeWindowPlan: ActiveWindowRenderPlan
    ) -> (strokes: [AnnotationStroke], notes: [String]) {
        guard let rawSourceRect = pointerSourceRect(for: capture, presentationSize: presentationSize) else {
            return (strokes, ["Active-window annotation strokes were stored, but source coordinate mapping was unavailable."])
        }

        let scaleX = presentationSize.width / max(rawSourceRect.width, 1)
        let scaleY = presentationSize.height / max(rawSourceRect.height, 1)
        var unmappedCount = 0

        let mapped = strokes.map { stroke -> AnnotationStroke in
            var mappedStroke = stroke
            guard let window = activeWindowPlan.windows.last(where: { stroke.startTimestamp >= $0.start && stroke.startTimestamp <= $0.end }) else {
                mappedStroke.videoPoints = nil
                unmappedCount += 1
                return mappedStroke
            }

            let videoPoints = stroke.sourcePoints.map { point in
                let rawPoint = CGPoint(
                    x: (point.x - rawSourceRect.minX) * scaleX,
                    y: (rawSourceRect.maxY - point.y) * scaleY
                )
                return CodablePoint(
                    x: rawPoint.x + window.translation.x,
                    y: rawPoint.y + window.translation.y
                )
            }

            if videoPoints.count >= (stroke.tool == .text ? 1 : 2) {
                mappedStroke.videoPoints = videoPoints
            } else {
                mappedStroke.videoPoints = nil
                unmappedCount += 1
            }
            return mappedStroke
        }

        var notes: [String] = []
        if unmappedCount > 0 {
            notes.append("\(unmappedCount) active-window annotation strokes could not be mapped into the rendered video canvas and were kept as raw metadata only.")
        }
        return (mapped, notes)
    }
}

private struct ActiveWindowRenderPlan {
    var renderSize: CGSize
    var windows: [ActiveWindowRenderWindow]
    var notes: [String]
}

private struct ActiveWindowRenderSample {
    var timestamp: TimeInterval
    var videoRect: CGRect
}

private struct ActiveWindowRenderWindow {
    var start: TimeInterval
    var end: TimeInterval
    var videoRect: CGRect
    var translation: CGPoint
}

private extension PointerEventKind {
    var isMouseDown: Bool {
        switch self {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            true
        case .move, .leftMouseUp, .rightMouseUp, .otherMouseUp:
            false
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private extension AVAssetExportSession {
    func exportAsync() async throws {
        await export()
        if status != .completed {
            let message = error?.localizedDescription ?? "status \(status.rawValue)"
            throw VideoUtilitiesError.exportFailed(message)
        }
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let intValue = Int(value, radix: 16) else {
            return nil
        }

        let red = CGFloat((intValue >> 16) & 0xFF) / 255
        let green = CGFloat((intValue >> 8) & 0xFF) / 255
        let blue = CGFloat(intValue & 0xFF) / 255
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}

extension AVURLAsset {
    func durationSeconds() async throws -> TimeInterval {
        try await load(.duration).seconds
    }
}
