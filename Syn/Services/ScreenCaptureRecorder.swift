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

final class ScreenCaptureRecorder {
    private var request: CaptureRequest?
    private var activeSegment: CaptureSegment?
    private var segmentURLs: [URL] = []
    private var segmentIndex = 0
    private(set) var sourceMetadata: CaptureSourceMetadata?

    func start(request: CaptureRequest) async throws {
        guard #available(macOS 15.0, *) else {
            throw ScreenCaptureRecorderError.unsupportedOS
        }

        self.request = request
        segmentURLs = []
        segmentIndex = 0
        try await startNewSegment()
    }

    func pause() async throws {
        guard let activeSegment else {
            return
        }

        try await activeSegment.stop()
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
            self.activeSegment = nil
        }

        let urls = segmentURLs
        request = nil
        return urls
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
            segment = ScreenCaptureSegment(filter: filter, configuration: configuration, outputURL: outputURL)
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

    init(filter: SCContentFilter, configuration: SCStreamConfiguration, outputURL: URL) {
        self.filter = filter
        self.configuration = configuration
        self.outputURL = outputURL
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
            throw error
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
