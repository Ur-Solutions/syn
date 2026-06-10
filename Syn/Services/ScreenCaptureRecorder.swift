import AVFoundation
import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenCaptureRecorderError: LocalizedError {
    case noShareableContent
    case noDisplay
    case noWindow
    case unsupportedOS
    case recordingDidNotStart
    case recordingDidNotStop

    var errorDescription: String? {
        switch self {
        case .noShareableContent:
            "No shareable screen content is available."
        case .noDisplay:
            "No display is available for capture."
        case .noWindow:
            "No eligible window is available for capture."
        case .unsupportedOS:
            "Screen recording output requires macOS 15 or newer."
        case .recordingDidNotStart:
            "Screen recording did not start."
        case .recordingDidNotStop:
            "Screen recording did not stop."
        }
    }
}

/// The live-rendered (clicks burned during capture) sibling of the raw recording.
/// When usable, stop-time finalize is a passthrough remux instead of a re-encode.
struct LiveRenderArtifact {
    var segmentURLs: [URL]
    var renderedClickCount: Int
    var usable: Bool
}

final class ScreenCaptureRecorder {
    private var request: CaptureRequest?
    private var activeSegment: CaptureSegment?
    private var segmentURLs: [URL] = []
    private var segmentIndex = 0
    private(set) var sourceMetadata: CaptureSourceMetadata?
    private var clickFeed: LiveClickFeed?
    private var frameSampler: LiveFrameSampler?
    private(set) var liveFrameArtifact: LiveFrameSamplingArtifact?
    private var liveSegmentURLs: [URL] = []
    private var liveRenderedClickCount = 0
    private var liveRenderFailed = false
    private(set) var liveRenderArtifact: LiveRenderArtifact?

    /// Modes whose final framing equals the raw capture framing (plus overlays), so click
    /// bubbles can be burned live into a parallel encode. Dynamic-crop and multi-stream
    /// modes keep the offline render.
    private static let liveRenderModes: Set<CaptureMode> = [.screen, .region, .selectedWindow, .chromeTab]

    func start(request: CaptureRequest) async throws {
        guard #available(macOS 15.0, *) else {
            throw ScreenCaptureRecorderError.unsupportedOS
        }

        self.request = request
        segmentURLs = []
        segmentIndex = 0
        liveSegmentURLs = []
        liveRenderedClickCount = 0
        liveRenderFailed = false
        liveRenderArtifact = nil
        liveFrameArtifact = nil
        if Self.liveRenderModes.contains(request.mode) {
            let feed = LiveClickFeed()
            await MainActor.run { feed.startMonitoring() }
            clickFeed = feed
            frameSampler = LiveFrameSampler(
                stagingDirectory: request.packet.rawSegmentsURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("live-frames", isDirectory: true)
            )
        }
        try await startNewSegment()
    }

    func pause() async throws {
        guard let activeSegment else {
            return
        }

        try await activeSegment.stop()
        collectLiveRenderOutcome(from: activeSegment)
        frameSampler?.endSegment()
        self.activeSegment = nil
    }

    func resume() async throws {
        guard activeSegment == nil else {
            return
        }

        try await startNewSegment()
    }

    func stop() async throws -> [URL] {
        if let activeSegment {
            try await activeSegment.stop()
            collectLiveRenderOutcome(from: activeSegment)
            self.activeSegment = nil
        }

        if let clickFeed {
            await MainActor.run { clickFeed.stopMonitoring() }
        }
        if let frameSampler {
            liveFrameArtifact = await frameSampler.finish()
        }
        frameSampler = nil
        if clickFeed != nil {
            liveRenderArtifact = LiveRenderArtifact(
                segmentURLs: liveSegmentURLs,
                renderedClickCount: liveRenderedClickCount,
                usable: !liveRenderFailed && !liveSegmentURLs.isEmpty && liveSegmentURLs.count == segmentURLs.count
            )
        }
        clickFeed = nil

        let urls = segmentURLs
        request = nil
        return urls
    }

    private func collectLiveRenderOutcome(from segment: CaptureSegment) {
        guard #available(macOS 15.0, *),
              let screenSegment = segment as? ScreenCaptureSegment,
              let outcome = screenSegment.liveRenderOutcome else {
            return
        }
        if outcome.succeeded, let url = outcome.url {
            liveSegmentURLs.append(url)
            liveRenderedClickCount += outcome.renderedClickCount
        } else {
            liveRenderFailed = true
        }
    }

    @available(macOS 15.0, *)
    private func startNewSegment() async throws {
        guard let request else {
            return
        }

        segmentIndex += 1
        let outputURL = request.packet.rawSegmentsURL
            .appendingPathComponent(String(format: "segment-%03d.mp4", segmentIndex))

        let resolved = try await CaptureSourceResolver.resolve(request: request)
        sourceMetadata = resolved.metadata

        let segment: CaptureSegment
        switch resolved.source {
        case .single(let filter, let configuration):
            var liveRenderer: LiveOverlayRecorder?
            if let clickFeed {
                // Live segments live OUTSIDE raw/segments/ so retry's raw-segment merge
                // never picks them up by accident.
                let liveDirectory = request.packet.rawSegmentsURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("live-render", isDirectory: true)
                try? FileManager.default.createDirectory(at: liveDirectory, withIntermediateDirectories: true)
                liveRenderer = LiveOverlayRecorder(
                    outputURL: liveDirectory.appendingPathComponent(String(format: "segment-%03d.mp4", segmentIndex)),
                    width: configuration.width,
                    height: configuration.height,
                    capture: resolved.metadata,
                    clickFeed: clickFeed,
                    frameSampler: frameSampler
                )
            }
            segment = ScreenCaptureSegment(
                filter: filter,
                configuration: configuration,
                outputURL: outputURL,
                liveRenderer: liveRenderer
            )
        case .allScreens(let displays):
            segment = AllScreensCaptureSegment(displaySources: displays, outputURL: outputURL)
        }
        try await segment.start()
        activeSegment = segment
        segmentURLs.append(outputURL)
    }

    @MainActor
    @available(macOS 15.0, *)
    static func runCaptureConfigurationFixture(outputRoot: URL) async throws -> CaptureConfigurationFixtureResult {
        let panel = NSPanel(
            contentRect: NSRect(x: 20, y: 20, width: 120, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Syn Capture Configuration Fixture"
        panel.alphaValue = 0.02
        panel.level = .floating
        panel.orderFrontRegardless()
        defer {
            panel.orderOut(nil)
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        let folderURL = outputRoot.appendingPathComponent("capture-configuration-fixture", isDirectory: true)
        let context = PacketContext(
            id: UUID(),
            title: "Capture configuration fixture",
            createdAt: .now,
            folderURL: folderURL,
            zipURL: folderURL.appendingPathExtension("zip")
        )
        try context.ensureDerivedDirectories()

        let request = CaptureRequest(
            mode: .screen,
            createdAt: .now,
            packet: context,
            preferredDisplayID: nil,
            region: nil,
            regionGlobalRect: nil,
            selectedWindowID: nil
        )
        let resolved = try await CaptureSourceResolver.resolve(request: request)
        let configuration: SCStreamConfiguration
        switch resolved.source {
        case .single(_, let resolvedConfiguration):
            configuration = resolvedConfiguration
        case .allScreens(let sources):
            guard let first = sources.first else {
                throw ScreenCaptureRecorderError.noDisplay
            }
            configuration = first.configuration
        }
        let currentAppExcluded = resolved.metadata.notes.contains { note in
            note.contains("excluded from display capture.")
        }

        let regionFolderURL = outputRoot.appendingPathComponent("capture-configuration-region-fixture", isDirectory: true)
        let regionContext = PacketContext(
            id: UUID(),
            title: "Capture configuration region fixture",
            createdAt: .now,
            folderURL: regionFolderURL,
            zipURL: regionFolderURL.appendingPathExtension("zip")
        )
        try regionContext.ensureDerivedDirectories()
        let regionDisplayID = CGMainDisplayID()
        let regionDisplayHeight = CGDisplayBounds(regionDisplayID).height
        let inputRegion = CGRect(x: 123, y: 77, width: 321, height: 211)
        let expectedCaptureSourceRect = CGRect(
            x: inputRegion.minX,
            y: regionDisplayHeight - inputRegion.maxY,
            width: inputRegion.width,
            height: inputRegion.height
        )
        let regionRequest = CaptureRequest(
            mode: .region,
            createdAt: .now,
            packet: regionContext,
            preferredDisplayID: regionDisplayID,
            region: inputRegion,
            regionGlobalRect: inputRegion,
            selectedWindowID: nil
        )
        let regionResolved = try await CaptureSourceResolver.resolve(request: regionRequest)
        let regionConfiguration: SCStreamConfiguration
        switch regionResolved.source {
        case .single(_, let resolvedConfiguration):
            regionConfiguration = resolvedConfiguration
        case .allScreens(let sources):
            guard let first = sources.first else {
                throw ScreenCaptureRecorderError.noDisplay
            }
            regionConfiguration = first.configuration
        }
        let metadataSourceRect = regionResolved.metadata.sourceRect.map {
            CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
        } ?? .null

        return CaptureConfigurationFixtureResult(
            showsCursor: configuration.showsCursor,
            showMouseClicks: configuration.showMouseClicks,
            captureMicrophone: configuration.captureMicrophone,
            capturesAudio: configuration.capturesAudio,
            excludesCurrentProcessAudio: configuration.excludesCurrentProcessAudio,
            currentAppExcluded: currentAppExcluded,
            outputWidth: configuration.width,
            outputHeight: configuration.height,
            inputRegion: inputRegion,
            regionCaptureSourceRect: regionConfiguration.sourceRect,
            expectedRegionCaptureSourceRect: expectedCaptureSourceRect,
            regionMetadataSourceRect: metadataSourceRect
        )
    }
}

struct CaptureConfigurationFixtureResult {
    var showsCursor: Bool
    var showMouseClicks: Bool
    var captureMicrophone: Bool
    var capturesAudio: Bool
    var excludesCurrentProcessAudio: Bool
    var currentAppExcluded: Bool
    var outputWidth: Int
    var outputHeight: Int
    var inputRegion: CGRect
    var regionCaptureSourceRect: CGRect
    var expectedRegionCaptureSourceRect: CGRect
    var regionMetadataSourceRect: CGRect

    var passed: Bool {
        showsCursor
            && !showMouseClicks
            && captureMicrophone
            && !capturesAudio
            && excludesCurrentProcessAudio
            && currentAppExcluded
            && outputWidth >= 640
            && outputHeight >= 360
            && rectsNearlyEqual(regionCaptureSourceRect, expectedRegionCaptureSourceRect)
            && rectsNearlyEqual(regionMetadataSourceRect, inputRegion)
    }

    private func rectsNearlyEqual(_ left: CGRect, _ right: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(left.minX - right.minX) <= tolerance
            && abs(left.minY - right.minY) <= tolerance
            && abs(left.width - right.width) <= tolerance
            && abs(left.height - right.height) <= tolerance
    }
}

@available(macOS 15.0, *)
private struct ResolvedCaptureSource {
    var source: ResolvedCaptureSourceKind
    var metadata: CaptureSourceMetadata
}

@available(macOS 15.0, *)
private enum ResolvedCaptureSourceKind {
    case single(filter: SCContentFilter, configuration: SCStreamConfiguration)
    case allScreens([ResolvedDisplayCaptureSource])
}

@available(macOS 15.0, *)
private struct ResolvedDisplayCaptureSource {
    var displayID: CGDirectDisplayID
    var frame: CGRect
    var filter: SCContentFilter
    var configuration: SCStreamConfiguration
}

@available(macOS 15.0, *)
private enum CaptureSourceResolver {
    static func resolve(request: CaptureRequest) async throws -> ResolvedCaptureSource {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = display(for: request, content: content) else {
            throw ScreenCaptureRecorderError.noDisplay
        }

        switch request.mode {
        case .screen:
            return displaySource(display: display, content: content, mode: request.mode, region: nil, metadataSourceRect: nil)
        case .allScreens:
            return allScreensSource(content: content)
        case .region:
            return displaySource(
                display: display,
                content: content,
                mode: request.mode,
                region: request.region,
                metadataSourceRect: request.regionGlobalRect
            )
        case .smartRegion:
            return displaySource(
                display: display,
                content: content,
                mode: request.mode,
                region: nil,
                metadataSourceRect: nil,
                smartRegion: request.regionGlobalRect,
                notes: ["Smart Region records the full display and renders a fixed-size cursor-following crop during processing."]
            )
        case .activeWindowFollow:
            let initialWindow = window(for: request, content: content)
            let activeDisplay = initialWindow.flatMap { displayContaining(window: $0, content: content) } ?? display
            return displaySource(
                display: activeDisplay,
                content: content,
                mode: request.mode,
                region: nil,
                metadataSourceRect: nil,
                notes: ["Active-window-follow records the initial display and crops to the foreground-window timeline during processing."]
            )
        case .selectedWindow, .chromeTab:
            guard let window = window(for: request, content: content) else {
                throw ScreenCaptureRecorderError.noWindow
            }
            return windowSource(window: window, mode: request.mode, chromeTab: request.chromeTab)
        }
    }

    private static func display(for request: CaptureRequest, content: SCShareableContent) -> SCDisplay? {
        if let preferredDisplayID = request.preferredDisplayID,
           let display = content.displays.first(where: { $0.displayID == preferredDisplayID }) {
            return display
        }

        if let main = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) {
            return main
        }

        return content.displays.first
    }

    private static func displayContaining(window: SCWindow, content: SCShareableContent) -> SCDisplay? {
        content.displays.first { display in
            CGDisplayBounds(display.displayID).intersects(window.frame)
        }
    }

    private static func window(for request: CaptureRequest, content: SCShareableContent) -> SCWindow? {
        let ownPID = getpid()
        let eligibleWindows = content.windows
            .filter { $0.isOnScreen }
            .filter { $0.owningApplication?.processID != ownPID }
            .filter { $0.windowLayer == 0 }

        if let selectedWindowID = request.selectedWindowID,
           let selected = eligibleWindows.first(where: { $0.windowID == selectedWindowID }) {
            return selected
        }

        if let active = eligibleWindows.first(where: { $0.isActive }) {
            return active
        }

        return eligibleWindows.first
    }

    private static func displaySource(
        display: SCDisplay,
        content: SCShareableContent,
        mode: CaptureMode,
        region: CGRect?,
        metadataSourceRect: CGRect?,
        smartRegion: CGRect? = nil,
        notes: [String] = []
    ) -> ResolvedCaptureSource {
        let currentApp = content.applications.first(where: { $0.processID == getpid() })
        let currentWindows = content.windows.filter { $0.owningApplication?.processID == getpid() }
        var resolvedNotes = notes
        let filter: SCContentFilter
        if let currentApp {
            filter = SCContentFilter(display: display, excludingApplications: [currentApp], exceptingWindows: [])
            resolvedNotes.append("Syn application windows are excluded from display capture.")
        } else if !currentWindows.isEmpty {
            filter = SCContentFilter(display: display, excludingWindows: currentWindows)
            resolvedNotes.append("Syn owned windows are excluded from display capture.")
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
            resolvedNotes.append("Syn application could not be resolved in shareable content; display capture could not explicitly exclude Syn windows.")
        }

        let scale = CGFloat(CGDisplayPixelsWide(display.displayID)) / max(CGFloat(display.width), 1)
        let sourceRect = region.map { screenCaptureSourceRect(displayLocalAppKitRect: $0, display: display) }
        let outputSizeRect = region ?? CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
        let outputWidth = Int(outputSizeRect.width * scale)
        let outputHeight = Int(outputSizeRect.height * scale)

        let configuration = baseConfiguration(width: outputWidth, height: outputHeight)
        if let sourceRect {
            configuration.sourceRect = sourceRect
        }

        let metadata = CaptureSourceMetadata(
            mode: mode.rawValue,
            displayID: display.displayID,
            windowID: nil,
            appName: nil,
            windowTitle: nil,
            smartRegion: smartRegion.map(CodableRect.init),
            sourceRect: (metadataSourceRect ?? region).map(CodableRect.init),
            outputSize: CodableSize(width: Double(outputWidth), height: Double(outputHeight)),
            notes: resolvedNotes + (sourceRect == nil && mode == .region ? ["Region was not selected; captured the main display."] : [])
        )

        return ResolvedCaptureSource(source: .single(filter: filter, configuration: configuration), metadata: metadata)
    }

    private static func screenCaptureSourceRect(
        displayLocalAppKitRect region: CGRect,
        display: SCDisplay
    ) -> CGRect {
        let standardized = region.standardized
        let displayBounds = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(display.width),
            height: CGFloat(display.height)
        )
        let flipped = CGRect(
            x: standardized.minX,
            y: CGFloat(display.height) - standardized.maxY,
            width: standardized.width,
            height: standardized.height
        )
        let clipped = flipped.intersection(displayBounds)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else {
            return flipped
        }
        return clipped
    }

    private static func windowSource(
        window: SCWindow,
        mode: CaptureMode,
        chromeTab: ChromeTabTarget? = nil
    ) -> ResolvedCaptureSource {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2
        let outputWidth = Int(window.frame.width * scale)
        let outputHeight = Int(window.frame.height * scale)
        let configuration = baseConfiguration(width: outputWidth, height: outputHeight)
        configuration.ignoreShadowsSingleWindow = false
        configuration.ignoreGlobalClipSingleWindow = true

        var notes: [String] = []
        if let chromeTab {
            notes.append("Chrome tab capture activated tab \(chromeTab.tabIndex) in Chrome window \(chromeTab.windowIndex) before recording.")
            notes.append("Chrome tab URL: \(chromeTab.url)")
        }

        let metadata = CaptureSourceMetadata(
            mode: mode.rawValue,
            displayID: nil,
            windowID: window.windowID,
            appName: window.owningApplication?.applicationName,
            windowTitle: window.title,
            chromeTab: chromeTab,
            smartRegion: nil,
            sourceRect: CodableRect(window.frame),
            outputSize: CodableSize(width: Double(outputWidth), height: Double(outputHeight)),
            notes: notes
        )

        return ResolvedCaptureSource(source: .single(filter: filter, configuration: configuration), metadata: metadata)
    }

    private static func allScreensSource(content: SCShareableContent) -> ResolvedCaptureSource {
        let currentApp = content.applications.first(where: { $0.processID == getpid() })
        let currentWindows = content.windows.filter { $0.owningApplication?.processID == getpid() }
        let sortedDisplays = content.displays.sorted { left, right in
            let leftFrame = screenFrame(for: left)
            let rightFrame = screenFrame(for: right)
            if leftFrame.minX == rightFrame.minX {
                return leftFrame.minY < rightFrame.minY
            }
            return leftFrame.minX < rightFrame.minX
        }

        var notes: [String] = []
        let displaySources = sortedDisplays.enumerated().map { index, display in
            let frame = screenFrame(for: display)
            let filter: SCContentFilter
            if let currentApp {
                filter = SCContentFilter(display: display, excludingApplications: [currentApp], exceptingWindows: [])
            } else if !currentWindows.isEmpty {
                filter = SCContentFilter(display: display, excludingWindows: currentWindows)
            } else {
                filter = SCContentFilter(display: display, excludingWindows: [])
            }

            let scale = CGFloat(CGDisplayPixelsWide(display.displayID)) / max(frame.width, 1)
            let configuration = baseConfiguration(
                width: Int(frame.width * scale),
                height: Int(frame.height * scale),
                captureMicrophone: index == 0
            )
            return ResolvedDisplayCaptureSource(
                displayID: display.displayID,
                frame: frame,
                filter: filter,
                configuration: configuration
            )
        }

        if currentApp != nil || !currentWindows.isEmpty {
            notes.append("Syn application windows are excluded from each display capture.")
        } else {
            notes.append("Syn application could not be resolved in shareable content; display capture could not explicitly exclude Syn windows.")
        }
        notes.append("All-screens capture records \(displaySources.count) display stream\(displaySources.count == 1 ? "" : "s") into one virtual desktop canvas.")

        let unionRect = displaySources
            .map(\.frame)
            .reduce(CGRect.null) { partial, frame in
                partial.isNull ? frame : partial.union(frame)
            }
        let maxScale = displaySources
            .map { CGFloat(CGDisplayPixelsWide($0.displayID)) / max($0.frame.width, 1) }
            .max() ?? 1
        let renderSize = unionRect.isNull ? nil : VideoUtilities.allScreensRenderSize(
            unionRect: unionRect,
            nativeScale: maxScale
        )
        if let renderSize {
            notes.append("All-screens virtual desktop is rendered at \(Int(renderSize.width))x\(Int(renderSize.height)) to stay within the H.264 compatibility envelope.")
        }

        let metadata = CaptureSourceMetadata(
            mode: CaptureMode.allScreens.rawValue,
            displayID: nil,
            windowID: nil,
            appName: nil,
            windowTitle: nil,
            smartRegion: nil,
            sourceRect: unionRect.isNull ? nil : CodableRect(unionRect),
            outputSize: renderSize.map(CodableSize.init),
            notes: notes
        )

        return ResolvedCaptureSource(source: .allScreens(displaySources), metadata: metadata)
    }

    private static func screenFrame(for display: SCDisplay) -> CGRect {
        if let screen = NSScreen.screens.first(where: { $0.synDisplayID == display.displayID }) {
            return screen.frame
        }

        let bounds = CGDisplayBounds(display.displayID)
        if bounds.width > 0, bounds.height > 0 {
            return bounds
        }

        return display.frame
    }

    private static func baseConfiguration(width: Int, height: Int, captureMicrophone: Bool = true) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(width, 640)
        configuration.height = max(height, 360)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 8
        configuration.showsCursor = true
        configuration.showMouseClicks = false
        configuration.captureMicrophone = captureMicrophone
        configuration.capturesAudio = false
        configuration.excludesCurrentProcessAudio = true
        return configuration
    }
}

private extension NSScreen {
    var synDisplayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
    }
}

@available(macOS 15.0, *)
private protocol CaptureSegment: AnyObject {
    var outputURL: URL { get }
    func start() async throws
    func stop() async throws
}

@available(macOS 15.0, *)
private final class ScreenCaptureSegment: NSObject, @unchecked Sendable, CaptureSegment, SCStreamDelegate, SCRecordingOutputDelegate {
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration
    let outputURL: URL
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?
    private let callbackTimeout: TimeInterval = 5
    private let liveRenderer: LiveOverlayRecorder?
    private(set) var liveRenderOutcome: LiveOverlayRecorder.Outcome?

    init(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration,
        outputURL: URL,
        liveRenderer: LiveOverlayRecorder? = nil
    ) {
        self.filter = filter
        self.configuration = configuration
        self.outputURL = outputURL
        self.liveRenderer = liveRenderer
    }

    func start() async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mp4
        recordingConfiguration.videoCodecType = .h264

        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addRecordingOutput(recordingOutput)

        // The live overlay renderer taps the same stream's frames; the raw recording
        // output above is untouched. If the tap cannot be attached, the segment simply
        // records raw and the offline render runs as before.
        if let liveRenderer {
            do {
                try liveRenderer.prepare()
                try stream.addStreamOutput(liveRenderer, type: .screen, sampleHandlerQueue: liveRenderer.handlerQueue)
            } catch {
                liveRenderer.markFailed("Could not attach live overlay output: \(error.localizedDescription)")
            }
        }

        self.stream = stream
        self.recordingOutput = recordingOutput

        let timeout = DispatchWorkItem { [weak self] in
            guard let self,
                  let startContinuation = self.startContinuation else {
                return
            }

            self.startContinuation = nil
            startContinuation.resume(throwing: ScreenCaptureRecorderError.recordingDidNotStart)
            self.stream?.stopCapture { _ in }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + callbackTimeout, execute: timeout)

        do {
            try await withCheckedThrowingContinuation { continuation in
                startContinuation = continuation
                stream.startCapture { [weak self] error in
                    if let error {
                        self?.startContinuation?.resume(throwing: error)
                        self?.startContinuation = nil
                    }
                }
            }
            timeout.cancel()
        } catch {
            timeout.cancel()
            throw error
        }
    }

    func stop() async throws {
        guard let stream else {
            return
        }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self,
                  let finishContinuation = self.finishContinuation else {
                return
            }

            self.finishContinuation = nil
            finishContinuation.resume(throwing: ScreenCaptureRecorderError.recordingDidNotStop)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + callbackTimeout, execute: timeout)

        do {
            try await withCheckedThrowingContinuation { continuation in
                finishContinuation = continuation
                stream.stopCapture { [weak self] error in
                    if let error {
                        self?.finishContinuation?.resume(throwing: error)
                        self?.finishContinuation = nil
                    }
                }
            }
            timeout.cancel()
        } catch {
            timeout.cancel()
            if let liveRenderer {
                liveRenderOutcome = await liveRenderer.finish()
            }
            throw error
        }

        if let liveRenderer {
            liveRenderOutcome = await liveRenderer.finish()
        }

        self.stream = nil
        recordingOutput = nil
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        startContinuation?.resume()
        startContinuation = nil
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        if let startContinuation {
            startContinuation.resume(throwing: error)
            self.startContinuation = nil
        }

        if let finishContinuation {
            finishContinuation.resume(throwing: error)
            self.finishContinuation = nil
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finishContinuation?.resume()
        finishContinuation = nil
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        if let startContinuation {
            startContinuation.resume(throwing: error)
            self.startContinuation = nil
        }

        if let finishContinuation {
            finishContinuation.resume(throwing: error)
            self.finishContinuation = nil
        }
    }
}

/// Records left mouse-downs (global screen point + host-clock time) while a capture runs.
/// Host-clock times compare directly against ScreenCaptureKit sample-buffer timestamps,
/// so the live renderer knows exactly which frames a click bubble spans.
final class LiveClickFeed {
    struct Click {
        var hostSeconds: Double
        var globalPoint: CGPoint
    }

    private var monitors: [Any] = []
    private let lock = NSLock()
    private var clicks: [Click] = []

    @MainActor
    func startMonitoring() {
        stopMonitoringLocked()
        let record: (NSEvent) -> Void = { [weak self] _ in
            guard let self else { return }
            let click = Click(hostSeconds: CACurrentMediaTime(), globalPoint: NSEvent.mouseLocation)
            self.lock.lock()
            self.clicks.append(click)
            if self.clicks.count > 4096 {
                self.clicks.removeFirst(self.clicks.count - 4096)
            }
            self.lock.unlock()
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: record) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown], handler: { event in
            record(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    @MainActor
    func stopMonitoring() {
        stopMonitoringLocked()
    }

    private func stopMonitoringLocked() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }

    /// Clicks whose bubble animation is still active at the given frame time.
    func activeClicks(atHostSeconds time: Double, window: Double) -> [Click] {
        lock.lock()
        defer { lock.unlock() }
        return clicks.filter { time - $0.hostSeconds >= 0 && time - $0.hostSeconds <= window }
    }
}

/// Burns Syn's click bubbles into a parallel H.264 encode WHILE the capture runs, so
/// stopping a recording only needs a passthrough remux instead of a full re-encode.
///
/// Frames with no active bubble are forwarded to the hardware encoder untouched
/// (zero-copy); only the ~20 frames around each click are copied and composited.
/// The raw SCRecordingOutput recording is completely unaffected — on any failure the
/// offline render runs exactly as before.
@available(macOS 15.0, *)
final class LiveOverlayRecorder: NSObject, @unchecked Sendable, SCStreamOutput {
    struct Outcome {
        var url: URL?
        var renderedClickCount: Int
        var succeeded: Bool
        var note: String?
    }

    private static let bubbleWindowSeconds: Double = 0.65

    let handlerQueue = DispatchQueue(label: "syn.live-overlay-recorder", qos: .userInitiated)

    private let outputURL: URL
    private let width: Int
    private let height: Int
    private let capture: CaptureSourceMetadata
    private let clickFeed: LiveClickFeed
    private let frameSampler: LiveFrameSampler?

    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var appendedFrameCount = 0
    private var renderedClickKeys = Set<Int>()
    private var failureNote: String?
    private var finished = false
    private var pixelBufferPool: CVPixelBufferPool?
    // ScreenCaptureKit only delivers frames when the screen CHANGES, so on a quiet screen
    // the last appended frame can be far in the past. Keeping it lets finish() re-append it
    // at stop time so the video track spans the whole recording like the raw file does.
    private var lastAppendedPixelBuffer: CVPixelBuffer?
    private var lastAppendedPTS = CMTime.invalid

    init(
        outputURL: URL,
        width: Int,
        height: Int,
        capture: CaptureSourceMetadata,
        clickFeed: LiveClickFeed,
        frameSampler: LiveFrameSampler? = nil
    ) {
        self.outputURL = outputURL
        self.width = width
        self.height = height
        self.capture = capture
        self.clickFeed = clickFeed
        self.frameSampler = frameSampler
    }

    func prepare() throws {
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw VideoUtilitiesError.noExportSession
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? VideoUtilitiesError.exportFailed("Live overlay writer could not start.")
        }
        self.writer = writer
        self.writerInput = input
    }

    func markFailed(_ note: String) {
        handlerQueue.async {
            self.failureNote = note
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              failureNote == nil,
              !finished,
              let writer,
              let writerInput,
              sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Only complete frames carry display content.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        frameSampler?.ingest(pixelBuffer: pixelBuffer, ptsSeconds: presentationTime.seconds)
        if !sessionStarted {
            guard CVPixelBufferGetWidth(pixelBuffer) == width,
                  CVPixelBufferGetHeight(pixelBuffer) == height,
                  CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
                failureNote = "Live overlay frames did not match the expected size/format."
                return
            }
            writer.startSession(atSourceTime: presentationTime)
            sessionStarted = true
        }

        guard writerInput.isReadyForMoreMediaData else {
            return // drop a frame rather than stall ScreenCaptureKit's buffer pool
        }

        let frameHostSeconds = presentationTime.seconds
        let activeClicks = clickFeed.activeClicks(atHostSeconds: frameHostSeconds, window: Self.bubbleWindowSeconds)

        if activeClicks.isEmpty {
            if writerInput.append(sampleBuffer) {
                appendedFrameCount += 1
                lastAppendedPixelBuffer = pixelBuffer
                lastAppendedPTS = presentationTime
            } else {
                failureNote = "Live overlay writer rejected a frame: \(writer.error?.localizedDescription ?? "unknown error")"
            }
            return
        }

        guard let composited = compositeBubbles(
            onto: pixelBuffer,
            clicks: activeClicks,
            frameHostSeconds: frameHostSeconds
        ) else {
            // Compositing failed; keep the unmodified frame so the video stays continuous.
            if writerInput.append(sampleBuffer) {
                appendedFrameCount += 1
            }
            return
        }

        var timing = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timing)
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: composited,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else {
            return
        }
        var compositedSample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: composited,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &compositedSample
        )
        if let compositedSample, writerInput.append(compositedSample) {
            appendedFrameCount += 1
            lastAppendedPixelBuffer = composited
            lastAppendedPTS = presentationTime
            for click in activeClicks {
                renderedClickKeys.insert(Int((click.hostSeconds * 1000).rounded()))
            }
        }
    }

    /// Re-appends the last frame at stop time so the video track covers the full recording
    /// even when the screen was static at the end (ScreenCaptureKit emits no frames then).
    private func extendFinalFrameToStopTime() {
        guard let writerInput,
              writerInput.isReadyForMoreMediaData,
              let lastAppendedPixelBuffer,
              lastAppendedPTS.isValid else {
            return
        }
        let stopSeconds = CACurrentMediaTime()
        guard stopSeconds - lastAppendedPTS.seconds > 0.05 else {
            return
        }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(seconds: stopSeconds, preferredTimescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: lastAppendedPixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else {
            return
        }
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: lastAppendedPixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sample
        )
        if let sample {
            _ = writerInput.append(sample)
        }
    }

    private func compositeBubbles(
        onto source: CVPixelBuffer,
        clicks: [LiveClickFeed.Click],
        frameHostSeconds: Double
    ) -> CVPixelBuffer? {
        if pixelBufferPool == nil {
            let poolAttributes: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3]
            let bufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            CVPixelBufferPoolCreate(nil, poolAttributes as CFDictionary, bufferAttributes as CFDictionary, &pixelBufferPool)
        }
        guard let pixelBufferPool else {
            return nil
        }

        var destination: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &destination)
        guard let destination else {
            return nil
        }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destination, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }

        guard let sourceBase = CVPixelBufferGetBaseAddress(source),
              let destinationBase = CVPixelBufferGetBaseAddress(destination) else {
            return nil
        }

        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(source)
        let destinationBytesPerRow = CVPixelBufferGetBytesPerRow(destination)
        if sourceBytesPerRow == destinationBytesPerRow {
            memcpy(destinationBase, sourceBase, destinationBytesPerRow * height)
        } else {
            let rowBytes = min(sourceBytesPerRow, destinationBytesPerRow)
            for row in 0..<height {
                memcpy(
                    destinationBase + row * destinationBytesPerRow,
                    sourceBase + row * sourceBytesPerRow,
                    rowBytes
                )
            }
        }

        guard let context = CGContext(
            data: destinationBase,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: destinationBytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        let presentationSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        for click in clicks {
            guard let videoPoint = VideoUtilities.mapGlobalPointToVideo(
                click.globalPoint,
                capture: capture,
                presentationSize: presentationSize,
                padding: 0
            ) else {
                continue
            }
            let progress = min(1, max(0, (frameHostSeconds - click.hostSeconds) / Self.bubbleWindowSeconds))
            drawBubble(in: context, at: videoPoint, progress: progress)
        }

        return destination
    }

    private func drawBubble(in context: CGContext, at videoPoint: CGPoint, progress: Double) {
        // videoPoint is top-left-origin video pixels; CGContext origin is bottom-left.
        let center = CGPoint(x: videoPoint.x, y: CGFloat(height) - videoPoint.y)
        let scale = max(1, CGFloat(width) / 1920)
        let baseRadius = 9 * scale
        let radius = baseRadius + CGFloat(progress) * 14 * scale
        let alpha = CGFloat(1 - progress)

        // Syn rose (#EC6579) ring with a soft fill — the same visual as the offline bubbles.
        let ring = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.setFillColor(CGColor(srgbRed: 236 / 255, green: 101 / 255, blue: 121 / 255, alpha: 0.18 * alpha))
        context.fillEllipse(in: ring)
        context.setStrokeColor(CGColor(srgbRed: 236 / 255, green: 101 / 255, blue: 121 / 255, alpha: alpha))
        context.setLineWidth(3 * scale)
        context.strokeEllipse(in: ring)
    }

    func finish() async -> Outcome {
        await withCheckedContinuation { continuation in
            handlerQueue.async {
                self.finished = true
                guard let writer = self.writer else {
                    continuation.resume(returning: Outcome(
                        url: nil,
                        renderedClickCount: 0,
                        succeeded: false,
                        note: self.failureNote ?? "Live overlay writer was never created."
                    ))
                    return
                }
                guard self.failureNote == nil, self.sessionStarted, self.appendedFrameCount > 0 else {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: self.outputURL)
                    continuation.resume(returning: Outcome(
                        url: nil,
                        renderedClickCount: 0,
                        succeeded: false,
                        note: self.failureNote ?? "Live overlay writer received no frames."
                    ))
                    return
                }
                self.extendFinalFrameToStopTime()
                self.writerInput?.markAsFinished()
                writer.finishWriting {
                    let succeeded = writer.status == .completed
                    continuation.resume(returning: Outcome(
                        url: succeeded ? self.outputURL : nil,
                        renderedClickCount: self.renderedClickKeys.count,
                        succeeded: succeeded,
                        note: succeeded ? nil : (writer.error?.localizedDescription ?? "Live overlay writer failed to finish.")
                    ))
                }
            }
        }
    }
}

@available(macOS 15.0, *)
private final class AllScreensCaptureSegment: CaptureSegment {
    let outputURL: URL
    private let displaySources: [ResolvedDisplayCaptureSource]
    private var displaySegments: [(source: ResolvedDisplayCaptureSource, segment: ScreenCaptureSegment)] = []

    init(displaySources: [ResolvedDisplayCaptureSource], outputURL: URL) {
        self.displaySources = displaySources
        self.outputURL = outputURL
    }

    func start() async throws {
        displaySegments = []
        let baseURL = outputURL.deletingPathExtension()

        do {
            for source in displaySources {
                let displayURL = baseURL
                    .appendingPathExtension("display-\(source.displayID)")
                    .appendingPathExtension("mp4")
                let segment = ScreenCaptureSegment(
                    filter: source.filter,
                    configuration: source.configuration,
                    outputURL: displayURL
                )
                try await segment.start()
                displaySegments.append((source, segment))
            }
        } catch {
            for item in displaySegments.reversed() {
                try? await item.segment.stop()
            }
            displaySegments = []
            throw error
        }
    }

    func stop() async throws {
        var stopErrors: [Error] = []
        for item in displaySegments.reversed() {
            do {
                try await item.segment.stop()
            } catch {
                stopErrors.append(error)
            }
        }

        if let firstError = stopErrors.first {
            displaySegments = []
            throw firstError
        }

        let recordings = displaySegments.map { item in
            AllScreensDisplayRecording(
                url: item.segment.outputURL,
                displayID: item.source.displayID,
                frame: item.source.frame
            )
        }
        displaySegments = []
        _ = try await VideoUtilities.composeAllScreensRecordings(recordings, outputURL: outputURL)
    }
}
