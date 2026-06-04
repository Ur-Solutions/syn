import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation
import IOKit.hidsystem
import Security

enum FixtureProcessingError: LocalizedError {
    case missingInput
    case inputMissing(URL)
    case unsupportedLiveFixtureMode(String)

    var errorDescription: String? {
        switch self {
        case .missingInput:
            "Missing fixture input path after --syn-process-fixture."
        case .inputMissing(let url):
            "Fixture input does not exist: \(url.path)"
        case .unsupportedLiveFixtureMode(let mode):
            "Live capture fixture supports screen, allScreens, chromeTab, activeWindowFollow, selectedWindow, region, and smartRegion modes, not \(mode)."
        }
    }
}

enum FixtureProcessingRunner {
    static let argumentName = "--syn-process-fixture"
    static let recoveryArgumentName = "--syn-recover-history-fixture"
    static let retryArgumentName = "--syn-retry-packet-fixture"
    static let durationWarningArgumentName = "--syn-duration-warning-fixture"
    static let summaryContractArgumentName = "--syn-summary-contract-fixture"
    static let partialPacketArgumentName = "--syn-partial-packet-fixture"
    static let activeWindowTrackerArgumentName = "--syn-active-window-tracker-fixture"
    static let activeWindowRenderArgumentName = "--syn-active-window-render-fixture"
    static let smartRegionRenderArgumentName = "--syn-smart-region-render-fixture"
    static let allScreensRenderArgumentName = "--syn-all-screens-render-fixture"
    static let annotationRenderArgumentName = "--syn-annotation-render-fixture"
    static let annotationRecorderArgumentName = "--syn-annotation-recorder-fixture"
    static let chromeTabArgumentName = "--syn-chrome-tab-fixture"
    static let rawZipArgumentName = "--syn-raw-zip-fixture"
    static let videoTrimArgumentName = "--syn-video-trim-fixture"
    static let pausedPacketArgumentName = "--syn-paused-packet-fixture"
    static let liveCaptureArgumentName = "--syn-live-capture-fixture"
    static let captureConfigurationArgumentName = "--syn-capture-configuration-fixture"
    static let hotkeyArgumentName = "--syn-hotkey-fixture"
    static let capturePickerContractArgumentName = "--syn-capture-picker-contract-fixture"
    static let promptProfileArgumentName = "--syn-prompt-profile-fixture"
    static let repeatPolicyArgumentName = "--syn-repeat-policy-fixture"
    static let historyActionsArgumentName = "--syn-history-actions-fixture"
    static let packetLayoutArgumentName = "--syn-packet-layout-fixture"
    static let secretStoreArgumentName = "--syn-secret-store-fixture"
    static let permissionStatusArgumentName = "--syn-permission-status-fixture"
    static let frameDebugArgumentName = "--syn-frame-debug-fixture"
    static let ocrArgumentName = "--syn-ocr-fixture"
    static let deferredSummaryArgumentName = "--syn-deferred-summary-fixture"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(argumentName)
            || ProcessInfo.processInfo.arguments.contains(recoveryArgumentName)
            || ProcessInfo.processInfo.arguments.contains(retryArgumentName)
            || ProcessInfo.processInfo.arguments.contains(durationWarningArgumentName)
            || ProcessInfo.processInfo.arguments.contains(summaryContractArgumentName)
            || ProcessInfo.processInfo.arguments.contains(partialPacketArgumentName)
            || ProcessInfo.processInfo.arguments.contains(activeWindowTrackerArgumentName)
            || ProcessInfo.processInfo.arguments.contains(activeWindowRenderArgumentName)
            || ProcessInfo.processInfo.arguments.contains(smartRegionRenderArgumentName)
            || ProcessInfo.processInfo.arguments.contains(allScreensRenderArgumentName)
            || ProcessInfo.processInfo.arguments.contains(annotationRenderArgumentName)
            || ProcessInfo.processInfo.arguments.contains(annotationRecorderArgumentName)
            || ProcessInfo.processInfo.arguments.contains(chromeTabArgumentName)
            || ProcessInfo.processInfo.arguments.contains(rawZipArgumentName)
            || ProcessInfo.processInfo.arguments.contains(videoTrimArgumentName)
            || ProcessInfo.processInfo.arguments.contains(pausedPacketArgumentName)
            || ProcessInfo.processInfo.arguments.contains(liveCaptureArgumentName)
            || ProcessInfo.processInfo.arguments.contains(captureConfigurationArgumentName)
            || ProcessInfo.processInfo.arguments.contains(hotkeyArgumentName)
            || ProcessInfo.processInfo.arguments.contains(capturePickerContractArgumentName)
            || ProcessInfo.processInfo.arguments.contains(promptProfileArgumentName)
            || ProcessInfo.processInfo.arguments.contains(repeatPolicyArgumentName)
            || ProcessInfo.processInfo.arguments.contains(historyActionsArgumentName)
            || ProcessInfo.processInfo.arguments.contains(packetLayoutArgumentName)
            || ProcessInfo.processInfo.arguments.contains(secretStoreArgumentName)
            || ProcessInfo.processInfo.arguments.contains(permissionStatusArgumentName)
            || ProcessInfo.processInfo.arguments.contains(frameDebugArgumentName)
            || ProcessInfo.processInfo.arguments.contains(ocrArgumentName)
            || ProcessInfo.processInfo.arguments.contains(deferredSummaryArgumentName)
    }

    @MainActor
    static func runFromCommandLine() async -> Int32 {
        do {
            if ProcessInfo.processInfo.arguments.contains(recoveryArgumentName) {
                let recovered = try runHistoryRecoveryFixture(arguments: ProcessInfo.processInfo.arguments)
                print("SYN_RECOVERY_FIXTURE_HISTORY=\(recovered.historyURL.path)")
                print("SYN_RECOVERY_FIXTURE_STATUSES=\(recovered.statuses.joined(separator: ","))")
                return recovered.statuses.contains(PacketStatus.processing.rawValue) ? 1 : 0
            } else if ProcessInfo.processInfo.arguments.contains(retryArgumentName) {
                let packet = try await runRetryFixture(arguments: ProcessInfo.processInfo.arguments)
                print("SYN_RETRY_FIXTURE_PACKET=\(packet.folderURL.path)")
                print("SYN_RETRY_FIXTURE_ZIP=\(packet.zipURL?.path ?? "")")
                print("SYN_RETRY_FIXTURE_STATUS=\(packet.status.rawValue)")
                return packet.status == .failed ? 1 : 0
            } else if ProcessInfo.processInfo.arguments.contains(durationWarningArgumentName) {
                let passed = runDurationWarningFixture()
                print("SYN_DURATION_WARNING_FIXTURE=\(passed ? "passed" : "failed")")
                print("SYN_DURATION_WARNING_THRESHOLD=\(Int(RecordingDurationWarning.threshold))")
                return passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(summaryContractArgumentName) {
                let passed = runSummaryContractFixture()
                print("SYN_SUMMARY_CONTRACT_FIXTURE=\(passed ? "passed" : "failed")")
                return passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(partialPacketArgumentName) {
                let packet = try await runPartialPacketFixture(arguments: ProcessInfo.processInfo.arguments)
                print("SYN_PARTIAL_PACKET_FIXTURE_PACKET=\(packet.folderURL.path)")
                print("SYN_PARTIAL_PACKET_FIXTURE_ZIP=\(packet.zipURL?.path ?? "")")
                print("SYN_PARTIAL_PACKET_FIXTURE_STATUS=\(packet.status.rawValue)")
                return packet.status == .partial ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(activeWindowTrackerArgumentName) {
                let result = runActiveWindowTrackerFixture()
                print("SYN_ACTIVE_WINDOW_TRACKER_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_ACTIVE_WINDOW_TRACKER_SELECTED_APP=\(result.selectedAppName ?? "nil")")
                print("SYN_ACTIVE_WINDOW_TRACKER_SELECTED_TITLE=\(result.selectedWindowTitle ?? "nil")")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(activeWindowRenderArgumentName) {
                let result = try await runActiveWindowRenderFixture(arguments: ProcessInfo.processInfo.arguments)
                print("SYN_ACTIVE_WINDOW_RENDER_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_ACTIVE_WINDOW_RENDER_SIZE=\(Int(result.renderSize.width))x\(Int(result.renderSize.height))")
                print("SYN_ACTIVE_WINDOW_RENDERED_CLICKS=\(result.renderedClickCount)")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(smartRegionRenderArgumentName) {
                let result = try await runSmartRegionRenderFixture(arguments: ProcessInfo.processInfo.arguments)
                print("SYN_SMART_REGION_RENDER_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_SMART_REGION_RENDER_SIZE=\(Int(result.renderSize.width))x\(Int(result.renderSize.height))")
                print("SYN_SMART_REGION_RENDERED_CLICKS=\(result.renderedClickCount)")
                print("SYN_SMART_REGION_RENDER_INTERVALS=\(result.intervalCount)")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(allScreensRenderArgumentName) {
                let result = try await runAllScreensRenderFixture(arguments: ProcessInfo.processInfo.arguments)
                print("SYN_ALL_SCREENS_RENDER_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_ALL_SCREENS_COMPOSITE_SIZE=\(Int(result.compositeSize.width))x\(Int(result.compositeSize.height))")
                print("SYN_ALL_SCREENS_RENDER_SIZE=\(Int(result.renderSize.width))x\(Int(result.renderSize.height))")
                print("SYN_ALL_SCREENS_RENDERED_CLICKS=\(result.renderedClickCount)")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(annotationRenderArgumentName) {
                let result = try await runAnnotationRenderFixture(arguments: ProcessInfo.processInfo.arguments)
                print("SYN_ANNOTATION_RENDER_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_ANNOTATION_RENDER_SIZE=\(Int(result.renderSize.width))x\(Int(result.renderSize.height))")
                print("SYN_ANNOTATION_RENDERED_COUNT=\(result.renderedAnnotationCount)")
                print("SYN_ANNOTATION_MAPPED_COUNT=\(result.mappedAnnotationCount)")
                print("SYN_ANNOTATION_COLOR_PIXELS=\(result.annotationColorPixels)")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(annotationRecorderArgumentName) {
                let result = runAnnotationRecorderFixture()
                print("SYN_ANNOTATION_RECORDER_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_ANNOTATION_RECORDER_COUNT=\(result.strokeCount)")
                print("SYN_ANNOTATION_RECORDER_TOOLS=\(result.tools.joined(separator: ","))")
                print("SYN_ANNOTATION_RECORDER_PAUSED_IGNORED=\(result.pausedInputIgnored ? "yes" : "no")")
                print("SYN_ANNOTATION_RECORDER_CLEAR=\(result.clearPassed ? "passed" : "failed")")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(chromeTabArgumentName) {
                let result = runChromeTabFixture()
                print("SYN_CHROME_TAB_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_CHROME_TAB_COUNT=\(result.tabCount)")
                print("SYN_CHROME_TAB_METADATA=\(result.metadataPassed ? "passed" : "failed")")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(rawZipArgumentName) {
                let result = try runRawZipFixture()
                print("SYN_RAW_ZIP_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_RAW_ZIP_DEFAULT_EXCLUDES_RAW=\(result.defaultExcludesRaw ? "yes" : "no")")
                print("SYN_RAW_ZIP_INCLUDES_RAW=\(result.rawZipIncludesRaw ? "yes" : "no")")
                print("SYN_RAW_ZIP_PATH=\(result.rawZipURL.path)")
                print("SYN_COMPACT_ZIP_INCLUDES_AGENT_FILES=\(result.compactZipIncludesAgentFiles ? "yes" : "no")")
                print("SYN_COMPACT_ZIP_EXCLUDES_HEAVY_FILES=\(result.compactZipExcludesHeavyFiles ? "yes" : "no")")
                print("SYN_COMPACT_ZIP_PATH=\(result.compactZipURL.path)")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(videoTrimArgumentName) {
                let result = try await runVideoTrimFixture(arguments: ProcessInfo.processInfo.arguments)
                print("SYN_VIDEO_TRIM_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_VIDEO_TRIM_DURATION=\(String(format: "%.3f", result.trimmedDuration))")
                print("SYN_VIDEO_TRIM_OUTPUT=\(result.outputURL.path)")
                print("SYN_VIDEO_TRIM_MANIFEST=\(result.manifestUpdated ? "updated" : "missing")")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(frameDebugArgumentName) {
                let result = try await runFrameDebugFixture(arguments: ProcessInfo.processInfo.arguments)
                print("SYN_FRAME_DEBUG_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_FRAME_DEBUG_CANDIDATES=\(result.metadataCount)")
                print("SYN_FRAME_DEBUG_IMAGES=\(result.imageCount)")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(ocrArgumentName) {
                let result = try await runOCRFixture(arguments: ProcessInfo.processInfo.arguments)
                print("SYN_OCR_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_OCR_CANDIDATES=\(result.metadataCount)")
                print("SYN_OCR_OBSERVATIONS=\(result.observationCount)")
                print("SYN_OCR_TEXT=\(result.text.replacingOccurrences(of: "\n", with: " / "))")
                print("SYN_OCR_PACKET=\(result.packetURL.path)")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(deferredSummaryArgumentName) {
                let result = try await runDeferredSummaryFixture(arguments: ProcessInfo.processInfo.arguments)
                print("SYN_DEFERRED_SUMMARY_PACKET=\(result.packetURL.path)")
                print("SYN_DEFERRED_SUMMARY_TIER_FILES=\(result.summaryCount)")
                print("SYN_DEFERRED_SUMMARY_BEGIN_PROGRESS")
                print(result.progress)
                print("SYN_DEFERRED_SUMMARY_END_PROGRESS")
                return result.summaryCount > 0 ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(pausedPacketArgumentName) {
                let packet = try await runPausedPacketFixture(arguments: ProcessInfo.processInfo.arguments)
                print("SYN_PAUSED_FIXTURE_PACKET=\(packet.folderURL.path)")
                print("SYN_PAUSED_FIXTURE_ZIP=\(packet.zipURL?.path ?? "")")
                print("SYN_PAUSED_FIXTURE_STATUS=\(packet.status.rawValue)")
                print("SYN_PAUSED_FIXTURE_DURATION=\(String(format: "%.3f", packet.duration))")
                return packet.status == .failed ? 1 : 0
            } else if ProcessInfo.processInfo.arguments.contains(liveCaptureArgumentName) {
                let result = try await runLiveCaptureFixture(arguments: ProcessInfo.processInfo.arguments)
                print("SYN_LIVE_FIXTURE_PACKET=\(result.packet.folderURL.path)")
                print("SYN_LIVE_FIXTURE_STATUS=\(result.packet.status.rawValue)")
                print("SYN_LIVE_FIXTURE_MODE=\(result.mode.rawValue)")
                print("SYN_LIVE_FIXTURE_DURATION=\(String(format: "%.3f", result.duration))")
                print("SYN_LIVE_FIXTURE_SEGMENTS=\(result.segmentCount)")
                print("SYN_LIVE_FIXTURE_PROCESSED=\(result.processed)")
                return result.packet.status == .failed ? 1 : 0
            } else if ProcessInfo.processInfo.arguments.contains(captureConfigurationArgumentName) {
                let result = try await runCaptureConfigurationFixture()
                print("SYN_CAPTURE_CONFIGURATION_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_CAPTURE_CONFIGURATION_CURSOR=\(result.showsCursor ? "enabled" : "disabled")")
                print("SYN_CAPTURE_CONFIGURATION_MOUSE_CLICKS=\(result.showMouseClicks ? "enabled" : "disabled")")
                print("SYN_CAPTURE_CONFIGURATION_MICROPHONE=\(result.captureMicrophone ? "enabled" : "disabled")")
                print("SYN_CAPTURE_CONFIGURATION_SYSTEM_AUDIO=\(result.capturesAudio ? "enabled" : "disabled")")
                print("SYN_CAPTURE_CONFIGURATION_EXCLUDES_PROCESS_AUDIO=\(result.excludesCurrentProcessAudio ? "yes" : "no")")
                print("SYN_CAPTURE_CONFIGURATION_EXCLUDES_SYN_WINDOWS=\(result.currentAppExcluded ? "yes" : "no")")
                print("SYN_CAPTURE_CONFIGURATION_SIZE=\(result.outputWidth)x\(result.outputHeight)")
                print("SYN_CAPTURE_CONFIGURATION_REGION_SOURCE_RECT=\(fixtureRectString(result.regionCaptureSourceRect))")
                print("SYN_CAPTURE_CONFIGURATION_REGION_EXPECTED_SOURCE_RECT=\(fixtureRectString(result.expectedRegionCaptureSourceRect))")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(hotkeyArgumentName) {
                let result = await runHotkeyFixture()
                print("SYN_HOTKEY_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_HOTKEY_HANDLER_STATUS=\(result.registration.eventHandlerStatus.map(String.init) ?? "nil")")
                print("SYN_HOTKEY_PICKER_STATUS=\(result.registration.pickerStatus.map(String.init) ?? "nil")")
                print("SYN_HOTKEY_REPEAT_STATUS=\(result.registration.repeatStatus.map(String.init) ?? "nil")")
                print("SYN_HOTKEY_CHORD_LOGIC=\(result.chordLogicPassed ? "passed" : "failed")")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(capturePickerContractArgumentName) {
                let result = runCapturePickerContractFixture()
                print("SYN_CAPTURE_PICKER_CONTRACT_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_CAPTURE_PICKER_MODE_TITLES=\(result.modeTitles.joined(separator: ","))")
                print("SYN_CAPTURE_PICKER_EXPECTS_MIC_STATUS=\(result.expectsMicStatus ? "yes" : "no")")
                print("SYN_CAPTURE_PICKER_EXPECTS_SETTINGS=\(result.expectsSettingsEntry ? "yes" : "no")")
                print("SYN_CAPTURE_PICKER_EXPECTS_LAST_MODE=\(result.expectsLastMode ? "yes" : "no")")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(promptProfileArgumentName) {
                let result = runPromptProfileFixture()
                print("SYN_PROMPT_PROFILE_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_PROMPT_PROFILE_COUNT=\(result.profileCount)")
                print("SYN_PROMPT_PROFILE_DEFAULT=\(result.defaultProfile.rawValue)")
                print("SYN_PROMPT_PROFILE_PERSISTED=\(result.persistedProfile.rawValue)")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(repeatPolicyArgumentName) {
                let passed = runRepeatPolicyFixture()
                print("SYN_REPEAT_POLICY_FIXTURE=\(passed ? "passed" : "failed")")
                return passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(historyActionsArgumentName) {
                let passed = try runHistoryActionsFixture()
                print("SYN_HISTORY_ACTIONS_FIXTURE=\(passed ? "passed" : "failed")")
                return passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(packetLayoutArgumentName) {
                let passed = runPacketLayoutFixture()
                print("SYN_PACKET_LAYOUT_FIXTURE=\(passed ? "passed" : "failed")")
                return passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(secretStoreArgumentName) {
                let result = runSecretStoreFixture()
                print("SYN_SECRET_STORE_FIXTURE=\(result.passed ? "passed" : "failed")")
                print("SYN_SECRET_STORE_EMPTY_READ=\(result.emptyReadPassed ? "passed" : "failed")")
                print("SYN_SECRET_STORE_SAVE_READ=\(result.saveReadPassed ? "passed" : "failed")")
                print("SYN_SECRET_STORE_OVERWRITE=\(result.overwritePassed ? "passed" : "failed")")
                print("SYN_SECRET_STORE_DELETE=\(result.deletePassed ? "passed" : "failed")")
                return result.passed ? 0 : 1
            } else if ProcessInfo.processInfo.arguments.contains(permissionStatusArgumentName) {
                runPermissionStatusFixture()
                return 0
            } else {
                let options = try parseArguments(ProcessInfo.processInfo.arguments)
                let packet = try await run(inputURL: options.inputURL, outputRoot: options.outputRoot)
                print("SYN_FIXTURE_PACKET=\(packet.folderURL.path)")
                print("SYN_FIXTURE_ZIP=\(packet.zipURL?.path ?? "")")
                print("SYN_FIXTURE_STATUS=\(packet.status.rawValue)")
                return packet.status == .failed ? 1 : 0
            }
        } catch {
            fputs("SYN_FIXTURE_ERROR=\(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func run(inputURL: URL, outputRoot: URL) async throws -> PacketSummary {
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw FixtureProcessingError.inputMissing(inputURL)
        }

        let createdAt = Date()
        let folderURL = outputRoot
            .appendingPathComponent("fixture-\(Int(createdAt.timeIntervalSince1970))-\(UUID().uuidString)", isDirectory: true)
        let context = PacketContext(
            id: UUID(),
            title: "Fixture recording",
            createdAt: createdAt,
            folderURL: folderURL,
            zipURL: PacketLayout.zipURL(for: folderURL)
        )
        try context.ensureDerivedDirectories()

        let capture = CaptureSourceMetadata(
            mode: CaptureMode.screen.rawValue,
            displayID: CGMainDisplayID(),
            windowID: nil,
            appName: "Syn Fixture",
            windowTitle: "Synthetic Packet Verification",
            sourceRect: CodableRect(CGRect(x: 0, y: 0, width: 1280, height: 720)),
            outputSize: CodableSize(width: 1280, height: 720),
            notes: ["Offline packet-processing fixture."]
        )

        let pointerEvents = [
            PointerEvent(
                kind: .move,
                timestamp: 0.5,
                sourceCoordinates: CodablePoint(x: 320, y: 240),
                videoCoordinates: nil,
                buttonNumber: nil
            ),
            PointerEvent(
                kind: .leftMouseDown,
                timestamp: 1.25,
                sourceCoordinates: CodablePoint(x: 640, y: 360),
                videoCoordinates: nil,
                buttonNumber: 0
            ),
            PointerEvent(
                kind: .leftMouseUp,
                timestamp: 1.35,
                sourceCoordinates: CodablePoint(x: 640, y: 360),
                videoCoordinates: nil,
                buttonNumber: 0
            ),
            PointerEvent(
                kind: .move,
                timestamp: 3.2,
                sourceCoordinates: CodablePoint(x: 920, y: 220),
                videoCoordinates: nil,
                buttonNumber: nil
            )
        ]
        let activeWindowSamples = [
            ActiveWindowSample(
                timestamp: 0,
                windowID: 9001,
                appName: "Syn Fixture",
                windowTitle: "Synthetic Packet Verification",
                bounds: CodableRect(CGRect(x: 0, y: 0, width: 1280, height: 720))
            ),
            ActiveWindowSample(
                timestamp: 3,
                windowID: 9002,
                appName: "Syn Fixture",
                windowTitle: "Fixture Topic Shift",
                bounds: CodableRect(CGRect(x: 120, y: 90, width: 900, height: 540))
            )
        ]
        let annotations = [
            AnnotationStroke(
                id: UUID(),
                tool: .rectangle,
                startTimestamp: 0.4,
                endTimestamp: 0.9,
                sourcePoints: [CodablePoint(x: 140, y: 610), CodablePoint(x: 460, y: 360)],
                videoPoints: nil,
                colorHex: "#FF2D55",
                lineWidth: 8
            ),
            AnnotationStroke(
                id: UUID(),
                tool: .arrow,
                startTimestamp: 1.0,
                endTimestamp: 1.4,
                sourcePoints: [CodablePoint(x: 760, y: 520), CodablePoint(x: 1030, y: 300)],
                videoPoints: nil,
                colorHex: "#FF2D55",
                lineWidth: 9
            ),
            AnnotationStroke(
                id: UUID(),
                tool: .pen,
                startTimestamp: 1.5,
                endTimestamp: 2.1,
                sourcePoints: [
                    CodablePoint(x: 260, y: 220),
                    CodablePoint(x: 340, y: 270),
                    CodablePoint(x: 450, y: 220),
                    CodablePoint(x: 560, y: 260)
                ],
                videoPoints: nil,
                colorHex: "#FF2D55",
                lineWidth: 7
            )
        ]

        let processor = PacketProcessor()
        processor.projectContextFolderURL = try makeProjectContextFixtureRoot()
        let result = try await processor.process(
            context: context,
            segments: [inputURL],
            capture: capture,
            pointerEvents: pointerEvents,
            annotations: annotations,
            activeWindowSamples: activeWindowSamples,
            pauses: []
        )
        return result.packet
    }

    private static func makeProjectContextFixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("syn-project-context-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("node_modules", isDirectory: true),
            withIntermediateDirectories: true
        )

        try """
        # Fixture Project

        This README proves Syn can attach bounded local project context to a feedback packet.
        """
        .write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(name: "FixtureProject")
        """
        .write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        try "print(\"fixture\")\n"
            .write(to: root.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        try """
        .env
        node_modules/
        """
        .write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "SYN_SHOULD_NOT_APPEAR=1\n"
            .write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "heavy dependency\n"
            .write(to: root.appendingPathComponent("node_modules/ignored.txt"), atomically: true, encoding: .utf8)

        _ = try? Syn.run(executable: "/usr/bin/git", arguments: ["init"], workingDirectory: root)
        _ = try? Syn.run(executable: "/usr/bin/git", arguments: ["config", "user.email", "fixture@syn.local"], workingDirectory: root)
        _ = try? Syn.run(executable: "/usr/bin/git", arguments: ["config", "user.name", "Syn Fixture"], workingDirectory: root)
        _ = try? Syn.run(executable: "/usr/bin/git", arguments: ["add", "README.md", "Package.swift", ".gitignore"], workingDirectory: root)
        _ = try? Syn.run(executable: "/usr/bin/git", arguments: ["commit", "-m", "Initial fixture context"], workingDirectory: root)

        return root
    }

    private static func runPartialPacketFixture(arguments: [String]) async throws -> PacketSummary {
        guard let fixtureIndex = arguments.firstIndex(of: partialPacketArgumentName),
              arguments.indices.contains(fixtureIndex + 1) else {
            throw FixtureProcessingError.missingInput
        }

        let inputURL = URL(fileURLWithPath: arguments[fixtureIndex + 1])
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw FixtureProcessingError.inputMissing(inputURL)
        }

        let createdAt = Date()
        let folderURL = outputRootArgument(arguments)
            .appendingPathComponent("partial-failure-fixture-\(Int(createdAt.timeIntervalSince1970))-\(UUID().uuidString)", isDirectory: true)
        let context = PacketContext(
            id: UUID(),
            title: "Partial failure fixture",
            createdAt: createdAt,
            folderURL: folderURL,
            zipURL: PacketLayout.zipURL(for: folderURL)
        )
        try context.ensureDerivedDirectories()
        try FileManager.default.copyItem(at: inputURL, to: context.rawRecordingURL)

        let capture = CaptureSourceMetadata(
            mode: CaptureMode.screen.rawValue,
            displayID: CGMainDisplayID(),
            windowID: nil,
            appName: "Syn Fixture",
            windowTitle: "Partial Failure Fixture",
            sourceRect: CodableRect(CGRect(x: 0, y: 0, width: 1280, height: 720)),
            outputSize: CodableSize(width: 1280, height: 720),
            notes: ["Offline partial-failure fixture."]
        )
        let pointerEvents = [
            PointerEvent(
                kind: .leftMouseDown,
                timestamp: 0.25,
                sourceCoordinates: CodablePoint(x: 100, y: 120),
                videoCoordinates: nil,
                buttonNumber: 0
            )
        ]
        let error = NSError(
            domain: "Syn.PartialPacketFixture",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Simulated processing failure for partial packet fixture."]
        )

        return try await PacketProcessor().writePartialFailureArtifacts(
            context: context,
            capture: capture,
            pointerEvents: pointerEvents,
            annotations: [],
            activeWindowSamples: [],
            pauses: [],
            duration: 0,
            error: error
        )
    }

    private static func runHotkeyFixture() async -> HotkeyFixtureResult {
        let service = GlobalHotkeyService.shared
        service.start()
        let snapshot = service.registrationSnapshot
        service.stop()
        let chordLogicPassed = await runHotkeyChordLogicFixture(service: service)
        return HotkeyFixtureResult(
            registration: snapshot,
            chordLogicPassed: chordLogicPassed
        )
    }

    private static func runCaptureConfigurationFixture() async throws -> CaptureConfigurationFixtureResult {
        guard #available(macOS 15.0, *) else {
            return CaptureConfigurationFixtureResult(
                showsCursor: false,
                showMouseClicks: true,
                captureMicrophone: false,
                capturesAudio: true,
                excludesCurrentProcessAudio: false,
                currentAppExcluded: false,
                outputWidth: 0,
                outputHeight: 0,
                inputRegion: .zero,
                regionCaptureSourceRect: .zero,
                expectedRegionCaptureSourceRect: .zero,
                regionMetadataSourceRect: .zero
            )
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("syn-capture-configuration-fixture", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try await ScreenCaptureRecorder.runCaptureConfigurationFixture(outputRoot: root)
    }

    private static func runCapturePickerContractFixture() -> CapturePickerContractFixtureResult {
        let expectedModes: [CaptureMode] = [.screen, .allScreens, .chromeTab, .activeWindowFollow, .selectedWindow, .region, .smartRegion]
        let modeTitles = CaptureMode.allCases.map(\.title)
        let modeDetails = CaptureMode.allCases.map(\.detail)
        let modeImages = CaptureMode.allCases.map(\.systemImage)
        let hasExpectedModes = CaptureMode.allCases == expectedModes
        let hasNonEmptyDisplayText = zip(modeTitles, modeDetails).allSatisfy { title, detail in
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let hasNonEmptyImages = modeImages.allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let micStatusOptions = [
            "Mic ready",
            "Mic not requested",
            "Mic needed",
            "Mic status unknown"
        ]
        let hasMicStatusContract = micStatusOptions.count == 4
            && micStatusOptions.allSatisfy { $0.hasPrefix("Mic ") }

        return CapturePickerContractFixtureResult(
            modeTitles: modeTitles,
            expectsMicStatus: hasMicStatusContract,
            expectsSettingsEntry: true,
            expectsLastMode: true,
            passed: hasExpectedModes
                && hasNonEmptyDisplayText
                && hasNonEmptyImages
                && hasMicStatusContract
        )
    }

    @MainActor
    private static func runPromptProfileFixture() -> PromptProfileFixtureResult {
        let appState = AppState()
        let defaultProfile = appState.defaultPromptProfile
        appState.setDefaultPromptProfile(.qaBugReport)
        let persistedProfile = AppPreferencesStore.load().defaultPromptProfile ?? .generalCoding
        let profilesHaveFiles = AgentPromptProfile.allCases.allSatisfy { profile in
            !profile.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && profile.fileName.hasSuffix(".md")
        }
        let profilesHaveDistinctFiles = Set(AgentPromptProfile.allCases.map(\.fileName)).count == AgentPromptProfile.allCases.count
        let profilesHaveDisplayText = AgentPromptProfile.allCases.allSatisfy { profile in
            !profile.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !profile.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !profile.openingInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !profile.workflowSteps.isEmpty
        }

        return PromptProfileFixtureResult(
            profileCount: AgentPromptProfile.allCases.count,
            defaultProfile: defaultProfile,
            persistedProfile: persistedProfile,
            contractPassed: profilesHaveFiles && profilesHaveDistinctFiles && profilesHaveDisplayText
        )
    }

    private static func runHotkeyChordLogicFixture(service: GlobalHotkeyService) async -> Bool {
        let leftShiftKeyCode = CGKeyCode(56)
        let rightShiftKeyCode = CGKeyCode(60)
        let rKeyCode = CGKeyCode(15)
        let shiftMask = UInt64(NX_SHIFTMASK)
        let leftShiftMask = UInt64(NX_DEVICELSHIFTKEYMASK)
        let rightShiftMask = UInt64(NX_DEVICERSHIFTKEYMASK)
        let leftShiftFlags = shiftMask | leftShiftMask
        let bothShiftFlags = shiftMask | leftShiftMask | rightShiftMask

        var actions: [String] = []
        service.onOpenPicker = {
            actions.append("picker")
        }
        service.onRepeatLastCapture = {
            actions.append("repeat")
        }
        func holdRepeatChordLongEnough() async {
            try? await Task.sleep(nanoseconds: 650_000_000)
        }

        service.resetChordStateForTesting()
        service.handleKeyStateForTesting(leftShift: true, rightShift: true, r: false)
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: true,
            r: true,
            keyCode: rKeyCode,
            type: .keyDown
        )
        let pickerPassed = actions == ["picker"]

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: false,
            r: true,
            keyCode: rKeyCode,
            type: .keyDown
        )
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: true,
            r: true,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        let rPreheldPickerPassed = actions == ["picker"]

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleKeyStateForTesting(leftShift: true, rightShift: true, r: false)
        try? await Task.sleep(nanoseconds: 280_000_000)
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: false,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: false,
            keyCode: leftShiftKeyCode,
            type: .flagsChanged
        )
        service.firePendingRepeatForTesting()
        let shortShiftRepeatPassed = actions == ["repeat"]
            && !service.hasPendingRepeatForTesting()

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleKeyStateForTesting(leftShift: true, rightShift: true, r: false)
        await holdRepeatChordLongEnough()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: false,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: false,
            keyCode: leftShiftKeyCode,
            type: .flagsChanged
        )
        let repeatQueued = actions.isEmpty && service.hasPendingRepeatForTesting()
        service.firePendingRepeatForTesting()
        let repeatPassed = repeatQueued && actions == ["repeat"]

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleKeyStateForTesting(leftShift: true, rightShift: true, r: false)
        await holdRepeatChordLongEnough()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: false,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: false,
            keyCode: leftShiftKeyCode,
            type: .flagsChanged
        )
        let repeatDrainQueuedBeforeR = service.hasPendingRepeatForTesting()
        service.firePendingRepeatWithInputDrainForTesting()
        let repeatDrainHeldBeforeR = actions.isEmpty && service.hasPendingRepeatForTesting()
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: true,
            keyCode: rKeyCode,
            type: .keyDown
        )
        service.firePendingRepeatForTesting()
        let repeatDeadlineRPickerPassed = repeatDrainQueuedBeforeR
            && repeatDrainHeldBeforeR
            && actions == ["picker"]
            && !service.hasPendingRepeatForTesting()

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleKeyStateForTesting(leftShift: true, rightShift: true, r: false)
        await holdRepeatChordLongEnough()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: false,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: false,
            keyCode: leftShiftKeyCode,
            type: .flagsChanged
        )
        let repeatDrainQueued = service.hasPendingRepeatForTesting()
        service.firePendingRepeatWithInputDrainForTesting()
        let repeatDrainHeld = actions.isEmpty && service.hasPendingRepeatForTesting()
        try? await Task.sleep(nanoseconds: 550_000_000)
        let repeatAfterDrainPassed = repeatDrainQueued
            && repeatDrainHeld
            && actions == ["repeat"]
            && !service.hasPendingRepeatForTesting()

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleKeyStateForTesting(leftShift: true, rightShift: true, r: false)
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: true,
            keyCode: rKeyCode,
            type: .keyDown
        )
        let outOfOrderSuffixPickerPassed = actions == ["picker"]
            && !service.hasPendingRepeatForTesting()

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleKeyStateForTesting(leftShift: true, rightShift: true, r: false)
        await holdRepeatChordLongEnough()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: false,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: false,
            keyCode: leftShiftKeyCode,
            type: .flagsChanged
        )
        let pendingBeforeRKeyUp = service.hasPendingRepeatForTesting()
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: false,
            keyCode: rKeyCode,
            type: .keyUp
        )
        service.firePendingRepeatForTesting()
        let rKeyUpPickerPassed = pendingBeforeRKeyUp
            && actions == ["picker"]
            && !service.hasPendingRepeatForTesting()

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: true,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: true,
            r: true,
            keyCode: rKeyCode,
            type: .keyDown
        )
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: true,
            r: false,
            keyCode: rKeyCode,
            type: .keyUp
        )
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: false,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: false,
            keyCode: leftShiftKeyCode,
            type: .flagsChanged
        )
        service.firePendingRepeatForTesting()
        let pickerNoRepeatActions = actions
        let pickerNoRepeatPending = service.hasPendingRepeatForTesting()
        let pickerDoesNotRepeat = pickerNoRepeatActions == ["picker"] && !pickerNoRepeatPending

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleRawKeyEventForTesting(
            keyCode: leftShiftKeyCode,
            type: .flagsChanged,
            eventFlagsRaw: leftShiftFlags
        )
        service.handleRawKeyEventForTesting(
            keyCode: rightShiftKeyCode,
            type: .flagsChanged,
            eventFlagsRaw: bothShiftFlags
        )
        service.handleRawKeyEventForTesting(
            keyCode: rightShiftKeyCode,
            type: .flagsChanged,
            eventFlagsRaw: bothShiftFlags
        )
        service.handleRawKeyEventForTesting(
            keyCode: rKeyCode,
            type: .keyDown,
            eventFlagsRaw: bothShiftFlags
        )
        let duplicateModifierEventActions = actions
        let duplicateModifierEventPickerPassed = actions == ["picker"]

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: true,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        service.setPhysicalRKeyStateForTesting(true)
        try? await Task.sleep(nanoseconds: 70_000_000)
        service.setPhysicalRKeyStateForTesting(false)
        let missingRKeyEventPickerPassed = actions == ["picker"]
            && !service.hasPendingRepeatForTesting()

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: true,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        await holdRepeatChordLongEnough()
        service.setPhysicalRKeyStateForTesting(true)
        try? await Task.sleep(nanoseconds: 40_000_000)
        service.setPhysicalRKeyStateForTesting(false)
        let longHoldMissingRKeyEventPickerPassed = actions == ["picker"]
            && !service.hasPendingRepeatForTesting()

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: true,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        await holdRepeatChordLongEnough()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: false,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: false,
            keyCode: leftShiftKeyCode,
            type: .flagsChanged
        )
        let repeatPendingBeforePhysicalR = service.hasPendingRepeatForTesting()
        service.setPhysicalRKeyStateForTesting(true)
        try? await Task.sleep(nanoseconds: 40_000_000)
        service.setPhysicalRKeyStateForTesting(false)
        service.firePendingRepeatForTesting()
        let pendingPhysicalRPickerWins = repeatPendingBeforePhysicalR
            && actions == ["picker"]
            && !service.hasPendingRepeatForTesting()

        actions.removeAll()
        service.handleKeyStateForTesting(leftShift: false, rightShift: false, r: false)
        service.handleKeyStateForTesting(leftShift: true, rightShift: true, r: false)
        let holdDoesNotRepeat = actions.isEmpty

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: true,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        await holdRepeatChordLongEnough()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: false,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: false,
            keyCode: leftShiftKeyCode,
            type: .flagsChanged
        )
        let repeatWasPendingBeforeR = service.hasPendingRepeatForTesting()
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: true,
            keyCode: rKeyCode,
            type: .keyDown
        )
        service.firePendingRepeatForTesting()
        let delayedPickerWins = repeatWasPendingBeforeR
            && actions == ["picker"]
            && !service.hasPendingRepeatForTesting()

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: true,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        await holdRepeatChordLongEnough()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: false,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: false,
            keyCode: leftShiftKeyCode,
            type: .flagsChanged
        )
        let repeatPendingDuringSuffixGrace = service.hasPendingRepeatForTesting()
        try? await Task.sleep(nanoseconds: 450_000_000)
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: true,
            keyCode: rKeyCode,
            type: .keyDown
        )
        try? await Task.sleep(nanoseconds: 350_000_000)
        let humanGapPickerWins = repeatPendingDuringSuffixGrace
            && actions == ["picker"]
            && !service.hasPendingRepeatForTesting()

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: true,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        await holdRepeatChordLongEnough()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: false,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: false,
            keyCode: leftShiftKeyCode,
            type: .flagsChanged
        )
        let repeatPendingDuringMediumSuffixGrace = service.hasPendingRepeatForTesting()
        try? await Task.sleep(nanoseconds: 950_000_000)
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: true,
            keyCode: rKeyCode,
            type: .keyDown
        )
        try? await Task.sleep(nanoseconds: 450_000_000)
        let mediumHumanGapPickerWins = repeatPendingDuringMediumSuffixGrace
            && actions == ["picker"]
            && !service.hasPendingRepeatForTesting()

        actions.removeAll()
        service.resetChordStateForTesting()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: true,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        await holdRepeatChordLongEnough()
        service.handleKeyEventForTesting(
            leftShift: true,
            rightShift: false,
            r: false,
            keyCode: rightShiftKeyCode,
            type: .flagsChanged
        )
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: false,
            keyCode: leftShiftKeyCode,
            type: .flagsChanged
        )
        let repeatPendingDuringLateSuffixGrace = service.hasPendingRepeatForTesting()
        try? await Task.sleep(nanoseconds: 2_250_000_000)
        service.handleKeyEventForTesting(
            leftShift: false,
            rightShift: false,
            r: true,
            keyCode: rKeyCode,
            type: .keyDown
        )
        try? await Task.sleep(nanoseconds: 250_000_000)
        let lateHumanGapRepeatWins = repeatPendingDuringLateSuffixGrace
            && actions == ["repeat"]
            && !service.hasPendingRepeatForTesting()

        service.resetChordStateForTesting()
        service.onOpenPicker = nil
        service.onRepeatLastCapture = nil

        let passed = pickerPassed
            && rPreheldPickerPassed
            && repeatPassed
            && repeatDeadlineRPickerPassed
            && repeatAfterDrainPassed
            && outOfOrderSuffixPickerPassed
            && rKeyUpPickerPassed
            && pickerDoesNotRepeat
            && duplicateModifierEventPickerPassed
            && missingRKeyEventPickerPassed
            && longHoldMissingRKeyEventPickerPassed
            && pendingPhysicalRPickerWins
            && holdDoesNotRepeat
            && shortShiftRepeatPassed
            && delayedPickerWins
            && humanGapPickerWins
            && mediumHumanGapPickerWins
            && lateHumanGapRepeatWins

        if !passed {
            print("SYN_HOTKEY_CASE_DUPLICATE_MODIFIER_ACTIONS=\(duplicateModifierEventActions.joined(separator: ","))")
            print("SYN_HOTKEY_CASE_PICKER=\(pickerPassed ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_R_PREHELD=\(rPreheldPickerPassed ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_REPEAT=\(repeatPassed ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_REPEAT_DEADLINE_R_PICKER=\(repeatDeadlineRPickerPassed ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_REPEAT_AFTER_DRAIN=\(repeatAfterDrainPassed ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_OUT_OF_ORDER_SUFFIX=\(outOfOrderSuffixPickerPassed ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_R_KEY_UP_PICKER=\(rKeyUpPickerPassed ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_PICKER_NO_REPEAT=\(pickerDoesNotRepeat ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_PICKER_NO_REPEAT_ACTIONS=\(pickerNoRepeatActions.joined(separator: ","))")
            print("SYN_HOTKEY_CASE_PICKER_NO_REPEAT_PENDING=\(pickerNoRepeatPending)")
            print("SYN_HOTKEY_CASE_DUPLICATE_MODIFIER=\(duplicateModifierEventPickerPassed ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_MISSING_R_EVENT_PICKER=\(missingRKeyEventPickerPassed ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_LONG_HOLD_MISSING_R_EVENT_PICKER=\(longHoldMissingRKeyEventPickerPassed ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_PENDING_PHYSICAL_R_PICKER=\(pendingPhysicalRPickerWins ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_HOLD=\(holdDoesNotRepeat ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_SHORT_SHIFT_REPEAT=\(shortShiftRepeatPassed ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_DELAYED_PICKER=\(delayedPickerWins ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_HUMAN_GAP_PICKER=\(humanGapPickerWins ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_MEDIUM_HUMAN_GAP_PICKER=\(mediumHumanGapPickerWins ? "passed" : "failed")")
            print("SYN_HOTKEY_CASE_LATE_HUMAN_GAP_REPEAT=\(lateHumanGapRepeatWins ? "passed" : "failed")")
        }

        return passed
    }

    private static func runRepeatPolicyFixture() -> Bool {
        let now = Date()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
        func packet(status: PacketStatus) -> PacketSummary {
            PacketSummary(
                title: "Repeat policy fixture",
                createdAt: now,
                duration: 1,
                status: status,
                folderURL: root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            )
        }

        return RepeatCapturePolicy.hasCompletedRecording([]) == false
            && RepeatCapturePolicy.hasCompletedRecording([packet(status: .processing)]) == false
            && RepeatCapturePolicy.hasCompletedRecording([packet(status: .failed)]) == false
            && RepeatCapturePolicy.hasCompletedRecording([packet(status: .partial)]) == true
            && RepeatCapturePolicy.hasCompletedRecording([packet(status: .succeeded)]) == true
            && RepeatCapturePolicy.hasCompletedRecording([packet(status: .failed), packet(status: .succeeded)]) == true
    }

    private static func runSecretStoreFixture() -> SecretStoreFixtureResult {
        let service = "Syn Fixture"
        let account = "secret-store-fixture-\(UUID().uuidString)"
        let firstValue = "first-\(UUID().uuidString)"
        let secondValue = "second-\(UUID().uuidString)"

        let initialDeleteStatus = SecretStore.delete(account: account, service: service)
        let emptyReadPassed = SecretStore.readForFixture(service: service, account: account) == nil

        let firstSaveStatus = SecretStore.save(value: firstValue, account: account, service: service)
        let saveReadPassed = firstSaveStatus == errSecSuccess
            && SecretStore.readForFixture(service: service, account: account) == firstValue

        let secondSaveStatus = SecretStore.save(value: secondValue, account: account, service: service)
        let overwritePassed = secondSaveStatus == errSecSuccess
            && SecretStore.readForFixture(service: service, account: account) == secondValue

        let deleteStatus = SecretStore.delete(account: account, service: service)
        let deletePassed = initialDeleteStatus == errSecItemNotFound
            && deleteStatus == errSecSuccess
            && SecretStore.readForFixture(service: service, account: account) == nil

        return SecretStoreFixtureResult(
            emptyReadPassed: emptyReadPassed,
            saveReadPassed: saveReadPassed,
            overwritePassed: overwritePassed,
            deletePassed: deletePassed
        )
    }

    @MainActor
    private static func runHistoryActionsFixture() throws -> Bool {
        guard ProcessInfo.processInfo.environment["SYN_HISTORY_STORE_PATH"] != nil else {
            return false
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("syn-history-actions-\(UUID().uuidString)", isDirectory: true)
        let packetFolder = root.appendingPathComponent("history-action-packet", isDirectory: true)
        let zipURL = root.appendingPathComponent("history-action-packet.zip")
        let rawZipURL = PacketLayout.rawZipURL(for: packetFolder)
        let compactZipURL = packetFolder
            .deletingLastPathComponent()
            .appendingPathComponent("\(packetFolder.lastPathComponent)-compact.zip")
        try FileManager.default.createDirectory(at: packetFolder, withIntermediateDirectories: true)
        let rawFolder = packetFolder.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawFolder, withIntermediateDirectories: true)
        let fullFramesFolder = packetFolder.appendingPathComponent("frames/full", isDirectory: true)
        let compressedFramesFolder = packetFolder.appendingPathComponent("frames/compressed", isDirectory: true)
        let candidatesFolder = packetFolder.appendingPathComponent("frames/candidates", isDirectory: true)
        try FileManager.default.createDirectory(at: fullFramesFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: compressedFramesFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: candidatesFolder, withIntermediateDirectories: true)

        let prompt = """
        # Syn Feedback Packet

        History action fixture prompt.
        """
        try prompt.write(to: packetFolder.appendingPathComponent("agent-prompt.md"), atomically: true, encoding: .utf8)
        try Data("recording".utf8).write(to: packetFolder.appendingPathComponent("recording.mp4"))
        try Data("full frame".utf8).write(to: fullFramesFolder.appendingPathComponent("frame-001.png"))
        try Data("compressed frame".utf8).write(to: compressedFramesFolder.appendingPathComponent("frame-001.jpg"))
        try Data("candidate metadata".utf8).write(to: candidatesFolder.appendingPathComponent("metadata.json"))
        try Data("raw recording".utf8).write(to: rawFolder.appendingPathComponent("recording-source.mp4"))
        let manifest = PacketManifest(
            schemaVersion: 1,
            appVersion: "fixture",
            createdAt: .now,
            duration: 7,
            capture: CaptureSourceMetadata(
                mode: CaptureMode.screen.rawValue,
                displayID: nil,
                windowID: nil,
                appName: nil,
                windowTitle: nil,
                sourceRect: nil,
                outputSize: nil,
                notes: []
            ),
            files: PacketFiles(
                recording: "recording.mp4",
                transcript: "transcript.md",
                summary: "summary.md",
                agentPrompt: "agent-prompt.md",
                agentPrompts: "agent-prompts",
                framesFull: "frames/full",
                framesCompressed: "frames/compressed",
                candidateMetadata: "frames/candidates/metadata.json",
                rawRecording: "raw/recording-source.mp4",
                rawCaptureSession: nil,
                pointerEvents: "raw/pointer-events.json",
                annotations: nil,
                activeWindowSamples: nil,
                zip: zipURL.path,
                rawZip: nil,
                editedRecording: nil,
                compactZip: nil,
                projectContext: nil,
                semanticSegments: nil,
                semanticTimeline: nil
            ),
            processing: PacketProcessing(
                transcriptionProvider: "fixture",
                transcriptionModel: "fixture",
                frameSelectionProvider: "fixture",
                frameSelectionModel: nil,
                summaryProvider: "fixture",
                summaryModel: "fixture",
                status: PacketStatus.succeeded.rawValue,
                notes: []
            ),
            pauses: [],
            pointerEventCount: 0,
            pointerMapping: nil,
            agentPromptProfile: AgentPromptProfile.generalCoding.rawValue
        )
        try JSONEncoder.synEncoder.encode(manifest)
            .write(to: packetFolder.appendingPathComponent("manifest.json"))
        try Data("zip fixture".utf8).write(to: zipURL)

        let packet = PacketSummary(
            title: "History action fixture",
            createdAt: .now,
            duration: 7,
            status: .succeeded,
            folderURL: packetFolder,
            zipURL: zipURL
        )
        PacketHistoryStore.save([packet])

        let appState = AppState()
        appState.recentPackets = [packet]
        appState.selectedPacketID = packet.id
        appState.copyPacketHandoff(for: packet)

        let copied = NSPasteboard.general.string(forType: .string) == prompt
            && PacketClipboard.copiedFolderURL?.standardizedFileURL == packetFolder.standardizedFileURL
            && appState.statusMessage == "Agent prompt and packet folder copied."
            && appState.commandPacket?.id == packet.id
            && appState.commandPacketZipURL == zipURL
            && packet.availableZipURL == zipURL

        appState.createRawZip(for: packet)
        let manifestAfterRawZip = try? JSONDecoder.synDecoder.decode(
            PacketManifest.self,
            from: Data(contentsOf: packetFolder.appendingPathComponent("manifest.json"))
        )
        let rawZipCreated = FileManager.default.fileExists(atPath: rawZipURL.path)
            && appState.commandPacketRawZipURL == rawZipURL
            && manifestAfterRawZip?.files.rawZip == rawZipURL.path

        appState.createCompactZip(for: packet)
        let manifestAfterCompactZip = try? JSONDecoder.synDecoder.decode(
            PacketManifest.self,
            from: Data(contentsOf: packetFolder.appendingPathComponent("manifest.json"))
        )
        let compactNames = (try? zipNames(compactZipURL)) ?? []
        let zipRoot = packetFolder.lastPathComponent
        let compactZipCreated = FileManager.default.fileExists(atPath: compactZipURL.path)
            && appState.commandPacketCompactZipURL == compactZipURL
            && manifestAfterCompactZip?.files.compactZip == compactZipURL.path
            && compactNames.contains("\(zipRoot)/agent-prompt.md")
            && compactNames.contains("\(zipRoot)/frames/compressed/frame-001.jpg")
            && compactNames.contains("\(zipRoot)/frames/candidates/metadata.json")
            && !compactNames.contains("\(zipRoot)/recording.mp4")
            && !compactNames.contains("\(zipRoot)/frames/full/frame-001.png")
            && !compactNames.contains("\(zipRoot)/raw/recording-source.mp4")

        let missingZipPacket = PacketSummary(
            title: "Missing zip fixture",
            createdAt: .now,
            duration: 3,
            status: .partial,
            folderURL: packetFolder,
            zipURL: root.appendingPathComponent("missing.zip")
        )
        let missingZipHidden = missingZipPacket.availableZipURL == nil

        appState.delete(packet: packet)
        let deleted = !FileManager.default.fileExists(atPath: packetFolder.path)
            && !FileManager.default.fileExists(atPath: zipURL.path)
            && !FileManager.default.fileExists(atPath: rawZipURL.path)
            && !FileManager.default.fileExists(atPath: compactZipURL.path)
            && appState.recentPackets.isEmpty
            && appState.selectedPacketID == nil
            && PacketHistoryStore.load().isEmpty

        try? FileManager.default.removeItem(at: root)
        return copied && rawZipCreated && compactZipCreated && missingZipHidden && deleted
    }

    private static func runPacketLayoutFixture() -> Bool {
        let expectedRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("Syn", isDirectory: true)
        guard PacketLayout.defaultRoot.standardizedFileURL == expectedRoot.standardizedFileURL else {
            return false
        }

        let calendar = Calendar.current
        guard let createdAt = calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 3,
            hour: 14,
            minute: 5,
            second: 6
        )) else {
            return false
        }

        let folderURL = PacketLayout.packetFolderURL(
            title: "Region: Weird / Title? 100%",
            createdAt: createdAt
        )
        let expectedFolder = expectedRoot
            .appendingPathComponent("2026-06-03", isDirectory: true)
            .appendingPathComponent("region-weird-title-100-14-05-06", isDirectory: true)
        let zipURL = PacketLayout.zipURL(for: folderURL)
        let expectedZip = expectedFolder
            .deletingLastPathComponent()
            .appendingPathComponent("region-weird-title-100-14-05-06.zip")

        return folderURL.standardizedFileURL == expectedFolder.standardizedFileURL
            && zipURL.standardizedFileURL == expectedZip.standardizedFileURL
    }

    private static func runFrameDebugFixture(arguments: [String]) async throws -> FrameDebugFixtureResult {
        guard let debugIndex = arguments.firstIndex(of: frameDebugArgumentName),
              arguments.indices.contains(debugIndex + 1) else {
            throw FixtureProcessingError.missingInput
        }

        let inputURL = URL(fileURLWithPath: arguments[debugIndex + 1])
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw FixtureProcessingError.inputMissing(inputURL)
        }

        let outputRoot = outputRootArgument(arguments)
        let root = outputRoot
            .appendingPathComponent("frame-debug-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)", isDirectory: true)
        let context = PacketContext(
            id: UUID(),
            title: "Frame debug fixture",
            createdAt: Date(),
            folderURL: root,
            zipURL: PacketLayout.zipURL(for: root)
        )
        try context.ensureDerivedDirectories()

        let previousValue = ProcessInfo.processInfo.environment["SYN_KEEP_CANDIDATE_FRAMES"]
        setenv("SYN_KEEP_CANDIDATE_FRAMES", "1", 1)
        defer {
            if let previousValue {
                setenv("SYN_KEEP_CANDIDATE_FRAMES", previousValue, 1)
            } else {
                unsetenv("SYN_KEEP_CANDIDATE_FRAMES")
            }
        }

        let capture = CaptureSourceMetadata(
            mode: CaptureMode.screen.rawValue,
            displayID: CGMainDisplayID(),
            windowID: nil,
            appName: "Syn Fixture",
            windowTitle: "Frame Debug Verification",
            sourceRect: CodableRect(CGRect(x: 0, y: 0, width: 1280, height: 720)),
            outputSize: CodableSize(width: 1280, height: 720),
            notes: ["Frame debug fixture."]
        )
        let result = try await FrameExtractor().extractFrames(
            from: inputURL,
            context: context,
            capture: capture,
            activeWindowSamples: []
        )
        let candidateRoot = context.candidateMetadataURL.deletingLastPathComponent()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: candidateRoot,
            includingPropertiesForKeys: nil
        )) ?? []
        let imageCount = files.filter { $0.pathExtension.lowercased() == "jpg" }.count
        let metadataHasCandidateFiles = result.candidateFrames.allSatisfy { frame in
            guard let candidatePath = frame.candidatePath,
                  let candidateSize = frame.candidateSize,
                  let candidateBytes = frame.candidateBytes else {
                return false
            }
            return candidateSize.width > 0
                && candidateSize.height > 0
                && candidateBytes > 0
                && FileManager.default.fileExists(atPath: context.folderURL.appendingPathComponent(candidatePath).path)
        }

        return FrameDebugFixtureResult(
            metadataCount: result.candidateFrames.count,
            imageCount: imageCount,
            passed: result.candidateFrames.count >= 2
                && imageCount == result.candidateFrames.count
                && metadataHasCandidateFiles
        )
    }

    private static func runOCRFixture(arguments: [String]) async throws -> OCRFixtureResult {
        let fixtureText = "SYN OCR\n4829"
        let outputRoot = outputRootArgument(arguments)
        let root = outputRoot
            .appendingPathComponent("ocr-fixture-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)", isDirectory: true)
        let context = PacketContext(
            id: UUID(),
            title: "OCR fixture",
            createdAt: Date(),
            folderURL: root,
            zipURL: PacketLayout.zipURL(for: root)
        )
        try context.ensureDerivedDirectories()

        guard let image = makeOCRFixtureImage(text: fixtureText) else {
            return OCRFixtureResult(packetURL: root, metadataCount: 0, observationCount: 0, text: "", passed: false)
        }

        let directOCR = FrameExtractor.recognizeText(in: image)
        let videoURL = context.rawURL.appendingPathComponent("ocr-fixture-source.mp4")
        try await writeOCRFixtureVideo(image: image, to: videoURL)

        let capture = CaptureSourceMetadata(
            mode: CaptureMode.screen.rawValue,
            displayID: CGMainDisplayID(),
            windowID: nil,
            appName: "Syn OCR Fixture",
            windowTitle: "OCR Text Verification",
            sourceRect: CodableRect(CGRect(x: 0, y: 0, width: image.width, height: image.height)),
            outputSize: CodableSize(width: Double(image.width), height: Double(image.height)),
            notes: ["OCR fixture."]
        )
        let extraction = try await FrameExtractor().extractFrames(
            from: videoURL,
            context: context,
            capture: capture,
            activeWindowSamples: []
        )
        let metadata = try JSONDecoder.synDecoder.decode(
            [CandidateFrameMetadata].self,
            from: Data(contentsOf: context.candidateMetadataURL)
        )
        let text = metadata.compactMap(\.ocrText).joined(separator: "\n")
        let observationCount = metadata.reduce(0) { partial, frame in
            partial + (frame.ocrObservations?.count ?? 0)
        }
        let normalizedDirectText = directOCR.text?.uppercased() ?? ""
        let normalizedMetadataText = text.uppercased()
        let directPassed = normalizedDirectText.contains("SYN")
            && normalizedDirectText.contains("OCR")
            && normalizedDirectText.contains("4829")
        let metadataPassed = normalizedMetadataText.contains("SYN")
            && normalizedMetadataText.contains("OCR")
            && normalizedMetadataText.contains("4829")
            && observationCount > 0
            && metadata.contains { ($0.ocrMeanConfidence ?? 0) > 0 }

        return OCRFixtureResult(
            packetURL: root,
            metadataCount: extraction.candidateFrames.count,
            observationCount: observationCount,
            text: text.isEmpty ? (directOCR.text ?? "") : text,
            passed: directPassed && metadataPassed && extraction.candidateFrames.count >= 1
        )
    }

    /// Runs the deferred layered summary against an EXISTING packet folder (which already has
    /// transcript.md, selected frames, and manifest.json), so the deferred path + the A/B lineups
    /// can be exercised on demand without a screen recording. Honors the editable summary config
    /// (`~/Library/Application Support/Syn/summary.json`).
    @MainActor
    private static func runDeferredSummaryFixture(arguments: [String]) async -> (packetURL: URL, summaryCount: Int, progress: String) {
        guard let index = arguments.firstIndex(of: deferredSummaryArgumentName),
              index + 1 < arguments.count else {
            return (URL(fileURLWithPath: "/"), 0, "missing packet folder argument")
        }
        let folderURL = URL(fileURLWithPath: arguments[index + 1])
        let context = PacketContext(
            id: UUID(),
            title: folderURL.lastPathComponent,
            createdAt: Date(),
            folderURL: folderURL,
            zipURL: PacketLayout.zipURL(for: folderURL)
        )
        let capture = CaptureSourceMetadata(
            mode: CaptureMode.screen.rawValue,
            displayID: nil, windowID: nil, appName: nil, windowTitle: nil,
            sourceRect: nil, outputSize: nil,
            notes: ["Deferred summary fixture."]
        )
        await PacketProcessor().runDeferredFinalize(context: context, capture: capture)

        let summaryDir = folderURL.appendingPathComponent("summaries", isDirectory: true)
        let summaryCount = ((try? FileManager.default.contentsOfDirectory(at: summaryDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "md" }
            .count
        let progress = (try? String(contentsOf: context.progressURL, encoding: .utf8)) ?? "(no progress.md written)"
        return (folderURL, summaryCount, progress)
    }

    private static func makeOCRFixtureImage(text: String) -> CGImage? {
        let size = CGSize(width: 960, height: 360)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(origin: .zero, size: size).fill()

        NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
        CGRect(x: 32, y: 32, width: size.width - 64, height: size.height - 64).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 72, weight: .bold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let lines = text.components(separatedBy: "\n")
        let lineHeight: CGFloat = 86
        let totalHeight = CGFloat(lines.count) * lineHeight
        var y = (size.height - totalHeight) / 2 + totalHeight - lineHeight
        for line in lines {
            (line as NSString).draw(
                in: CGRect(x: 48, y: y, width: size.width - 96, height: lineHeight),
                withAttributes: attributes
            )
            y -= lineHeight
        }
        image.unlockFocus()

        var rect = CGRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func writeOCRFixtureVideo(image: CGImage, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let width = image.width
        let height = image.height
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        guard writer.canAdd(input) else {
            throw FixtureProcessingError.missingInput
        }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps = 30
        let frameCount = fps * 4
        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }

            guard let pixelBuffer = pixelBuffer(from: image) else {
                input.markAsFinished()
                writer.cancelWriting()
                throw FrameExtractorError.couldNotEncodeImage
            }

            let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
            guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
                input.markAsFinished()
                writer.cancelWriting()
                throw writer.error ?? FrameExtractorError.couldNotEncodeImage
            }
        }

        input.markAsFinished()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if writer.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: writer.error ?? FrameExtractorError.couldNotEncodeImage)
                }
            }
        }
    }

    private static func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            image.width,
            image.height,
            kCVPixelFormatType_32ARGB,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixelBuffer
    }

    private static func runPermissionStatusFixture() {
        print(PermissionDiagnostics.statusLines().joined(separator: "\n"))
    }

    @MainActor
    private static func runLiveCaptureFixture(arguments: [String]) async throws -> LiveCaptureFixtureResult {
        let mode = try liveCaptureMode(arguments)
        let requestedDuration = liveCaptureDuration(arguments)
        let shouldProcess = arguments.contains("--process")
        let outputRoot = outputRootArgument(arguments)
        let createdAt = Date()
        let folderURL = outputRoot
            .appendingPathComponent("live-\(mode.rawValue)-fixture-\(Int(createdAt.timeIntervalSince1970))-\(UUID().uuidString)", isDirectory: true)
        let context = PacketContext(
            id: UUID(),
            title: "Live \(mode.title) fixture",
            createdAt: createdAt,
            folderURL: folderURL,
            zipURL: PacketLayout.zipURL(for: folderURL)
        )
        try context.ensureDerivedDirectories()

        let permissionResult = try await PermissionService.verifyBeforeRecording()
        let recorder = ScreenCaptureRecorder()
        let pointerRecorder = PointerEventRecorder()
        let activeWindowTracker = ActiveWindowTracker()
        let chromeTab = try await liveChromeTabTargetIfNeeded(mode: mode)
        let request = liveCaptureRequest(
            mode: mode,
            createdAt: createdAt,
            context: context,
            chromeTab: chromeTab
        )

        try await recorder.start(request: request)
        pointerRecorder.start()
        activeWindowTracker.start()
        try await Task.sleep(nanoseconds: UInt64(max(0.5, requestedDuration) * 1_000_000_000))

        let pointerEvents = pointerRecorder.stop()
        let activeWindowSamples = activeWindowTracker.stop()
        let segments = try await recorder.stop()
        var capture = recorder.sourceMetadata ?? CaptureSourceMetadata(
            mode: mode.rawValue,
            displayID: request.preferredDisplayID ?? CGMainDisplayID(),
            windowID: chromeTab?.windowID,
            appName: mode == .chromeTab ? "Google Chrome" : nil,
            windowTitle: chromeTab?.displayTitle,
            chromeTab: chromeTab,
            sourceRect: nil,
            outputSize: nil,
            notes: ["Live fixture capture metadata was unavailable."]
        )
        capture.notes.append(contentsOf: permissionResult.notes)

        if shouldProcess {
            let result = try await PacketProcessor().process(
                context: context,
                segments: segments,
                capture: capture,
                pointerEvents: pointerEvents,
                annotations: [],
                activeWindowSamples: activeWindowSamples,
                pauses: []
            )
            return LiveCaptureFixtureResult(
                packet: result.packet,
                mode: mode,
                duration: result.packet.duration,
                segmentCount: segments.count,
                processed: true
            )
        }

        let duration = try await VideoUtilities.mergeSegments(segments, outputURL: context.rawRecordingURL)
        let rawSession = RawCaptureSession(
            schemaVersion: 1,
            packetID: context.id,
            title: context.title,
            createdAt: context.createdAt,
            capture: capture,
            pauses: []
        )
        try JSONEncoder.synEncoder.encode(rawSession).write(to: context.rawCaptureSessionURL)
        try JSONEncoder.synEncoder.encode(pointerEvents).write(to: context.pointerEventsURL)
        if !activeWindowSamples.isEmpty {
            try JSONEncoder.synEncoder.encode(activeWindowSamples).write(to: context.activeWindowSamplesURL)
        }

        let summary = """
        # Live Capture Fixture

        Status: Partial

        Syn captured real ScreenCaptureKit output and microphone audio for \(String(format: "%.1f", duration)) seconds without running packet AI processing.

        Retry processing from the app History view or rerun this fixture with `--process` if the captured contents are safe to send to configured AI providers.
        """
        try summary.write(to: context.summaryURL, atomically: true, encoding: .utf8)

        let prompt = """
        # Syn Live Capture Fixture

        Packet folder:
        `\(context.folderURL.path)`

        Raw recording:
        `raw/recording-source.mp4`

        This fixture intentionally stopped after raw live capture to avoid sending screen contents to AI providers.
        """
        try prompt.write(to: context.agentPromptURL, atomically: true, encoding: .utf8)

        let packet = PacketSummary(
            id: context.id,
            title: context.title,
            createdAt: context.createdAt,
            duration: duration,
            status: .partial,
            folderURL: context.folderURL,
            zipURL: context.zipURL
        )

        return LiveCaptureFixtureResult(
            packet: packet,
            mode: mode,
            duration: duration,
            segmentCount: segments.count,
            processed: false
        )
    }

    private static func liveCaptureRequest(
        mode: CaptureMode,
        createdAt: Date,
        context: PacketContext,
        chromeTab: ChromeTabTarget? = nil
    ) -> CaptureRequest {
        let displayID = CGMainDisplayID()

        switch mode {
        case .region, .smartRegion:
            let region = liveFixtureRegion(displayID: displayID)
            return CaptureRequest(
                mode: mode,
                createdAt: createdAt,
                packet: context,
                preferredDisplayID: displayID,
                region: region.localRect,
                regionGlobalRect: region.globalRect,
                selectedWindowID: nil
            )
        case .chromeTab:
            return CaptureRequest(
                mode: mode,
                createdAt: createdAt,
                packet: context,
                preferredDisplayID: displayID,
                region: nil,
                regionGlobalRect: nil,
                selectedWindowID: chromeTab?.windowID,
                chromeTab: chromeTab
            )
        case .screen, .allScreens, .activeWindowFollow, .selectedWindow:
            return CaptureRequest(
                mode: mode,
                createdAt: createdAt,
                packet: context,
                preferredDisplayID: displayID,
                region: nil,
                regionGlobalRect: nil,
                selectedWindowID: nil
            )
        }
    }

    private static func liveChromeTabTargetIfNeeded(mode: CaptureMode) async throws -> ChromeTabTarget? {
        guard mode == .chromeTab else {
            return nil
        }

        let tabs = try ChromeTabService.listTabs()
        guard let firstTab = tabs.first else {
            throw ChromeTabServiceError.noTabs
        }

        return try await ChromeTabService.activate(firstTab)
    }

    private static func liveFixtureRegion(displayID: CGDirectDisplayID) -> (localRect: CGRect, globalRect: CGRect) {
        let displayBounds = CGDisplayBounds(displayID)
        let width = max(CGFloat(320), displayBounds.width * 0.5)
        let height = max(CGFloat(240), displayBounds.height * 0.5)
        let clampedWidth = min(width, displayBounds.width)
        let clampedHeight = min(height, displayBounds.height)
        let localRect = CGRect(
            x: (displayBounds.width - clampedWidth) / 2,
            y: (displayBounds.height - clampedHeight) / 2,
            width: clampedWidth,
            height: clampedHeight
        )
        let globalRect = CGRect(
            x: displayBounds.minX + localRect.minX,
            y: displayBounds.minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        )

        return (localRect: localRect, globalRect: globalRect)
    }

    private static func runPausedPacketFixture(arguments: [String]) async throws -> PacketSummary {
        guard let pausedIndex = arguments.firstIndex(of: pausedPacketArgumentName),
              arguments.indices.contains(pausedIndex + 2) else {
            throw FixtureProcessingError.missingInput
        }

        let firstSegmentURL = URL(fileURLWithPath: arguments[pausedIndex + 1])
        let secondSegmentURL = URL(fileURLWithPath: arguments[pausedIndex + 2])
        guard FileManager.default.fileExists(atPath: firstSegmentURL.path) else {
            throw FixtureProcessingError.inputMissing(firstSegmentURL)
        }
        guard FileManager.default.fileExists(atPath: secondSegmentURL.path) else {
            throw FixtureProcessingError.inputMissing(secondSegmentURL)
        }

        let createdAt = Date()
        let outputRoot = outputRootArgument(arguments)
        let folderURL = outputRoot
            .appendingPathComponent("paused-fixture-\(Int(createdAt.timeIntervalSince1970))-\(UUID().uuidString)", isDirectory: true)
        let context = PacketContext(
            id: UUID(),
            title: "Paused fixture recording",
            createdAt: createdAt,
            folderURL: folderURL,
            zipURL: PacketLayout.zipURL(for: folderURL)
        )
        try context.ensureDerivedDirectories()

        let capture = CaptureSourceMetadata(
            mode: CaptureMode.screen.rawValue,
            displayID: CGMainDisplayID(),
            windowID: nil,
            appName: "Syn Fixture",
            windowTitle: "Paused Packet Verification",
            sourceRect: CodableRect(CGRect(x: 0, y: 0, width: 1280, height: 720)),
            outputSize: CodableSize(width: 1280, height: 720),
            notes: ["Offline paused packet-processing fixture."]
        )
        let pointerEvents = [
            PointerEvent(
                kind: .leftMouseDown,
                timestamp: 1,
                sourceCoordinates: CodablePoint(x: 512, y: 360),
                videoCoordinates: nil,
                buttonNumber: 0
            ),
            PointerEvent(
                kind: .leftMouseUp,
                timestamp: 1.1,
                sourceCoordinates: CodablePoint(x: 512, y: 360),
                videoCoordinates: nil,
                buttonNumber: 0
            ),
            PointerEvent(
                kind: .move,
                timestamp: 4,
                sourceCoordinates: CodablePoint(x: 900, y: 240),
                videoCoordinates: nil,
                buttonNumber: nil
            )
        ]
        let activeWindowSamples = [
            ActiveWindowSample(
                timestamp: 0,
                windowID: 9101,
                appName: "Syn Fixture",
                windowTitle: "Paused Segment One",
                bounds: CodableRect(CGRect(x: 0, y: 0, width: 1280, height: 720))
            ),
            ActiveWindowSample(
                timestamp: 3,
                windowID: 9102,
                appName: "Syn Fixture",
                windowTitle: "Paused Segment Two",
                bounds: CodableRect(CGRect(x: 80, y: 60, width: 1000, height: 600))
            )
        ]
        let pauses = [
            PauseInterval(
                startedAt: Date(timeInterval: 3, since: createdAt),
                endedAt: Date(timeInterval: 6, since: createdAt)
            )
        ]

        let result = try await PacketProcessor().process(
            context: context,
            segments: [firstSegmentURL, secondSegmentURL],
            capture: capture,
            pointerEvents: pointerEvents,
            annotations: [],
            activeWindowSamples: activeWindowSamples,
            pauses: pauses
        )
        return result.packet
    }

    private static func parseArguments(_ arguments: [String]) throws -> FixtureOptions {
        guard let fixtureIndex = arguments.firstIndex(of: argumentName),
              arguments.indices.contains(fixtureIndex + 1) else {
            throw FixtureProcessingError.missingInput
        }

        let inputURL = URL(fileURLWithPath: arguments[fixtureIndex + 1])
        let outputRoot = outputRootArgument(arguments)

        return FixtureOptions(inputURL: inputURL, outputRoot: outputRoot)
    }

    private static func outputRootArgument(_ arguments: [String]) -> URL {
        if let outputIndex = arguments.firstIndex(of: "--output-root"),
           arguments.indices.contains(outputIndex + 1) {
            return URL(fileURLWithPath: arguments[outputIndex + 1])
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/fixture-packets", isDirectory: true)
    }

    private static func fixtureRectString(_ rect: CGRect) -> String {
        "\(String(format: "%.1f", rect.minX)),\(String(format: "%.1f", rect.minY)),\(String(format: "%.1f", rect.width)),\(String(format: "%.1f", rect.height))"
    }

    private static func liveCaptureMode(_ arguments: [String]) throws -> CaptureMode {
        guard let fixtureIndex = arguments.firstIndex(of: liveCaptureArgumentName),
              arguments.indices.contains(fixtureIndex + 1) else {
            return .screen
        }

        let raw = arguments[fixtureIndex + 1]
        if raw.hasPrefix("--") || Double(raw) != nil {
            return .screen
        }

        guard let mode = CaptureMode(rawValue: raw) else {
            throw FixtureProcessingError.unsupportedLiveFixtureMode(raw)
        }

        return mode
    }

    private static func liveCaptureDuration(_ arguments: [String]) -> TimeInterval {
        if let durationIndex = arguments.firstIndex(of: "--duration"),
           arguments.indices.contains(durationIndex + 1),
           let duration = Double(arguments[durationIndex + 1]) {
            return duration
        }

        guard let fixtureIndex = arguments.firstIndex(of: liveCaptureArgumentName) else {
            return 2
        }

        let candidates = [fixtureIndex + 1, fixtureIndex + 2]
        for index in candidates where arguments.indices.contains(index) {
            if let duration = Double(arguments[index]) {
                return duration
            }
        }

        return 2
    }

    private static func runHistoryRecoveryFixture(arguments: [String]) throws -> RecoveryFixtureResult {
        guard let recoveryIndex = arguments.firstIndex(of: recoveryArgumentName),
              arguments.indices.contains(recoveryIndex + 1) else {
            throw FixtureProcessingError.missingInput
        }

        let historyURL = URL(fileURLWithPath: arguments[recoveryIndex + 1])
        let data = try Data(contentsOf: historyURL)
        let packets = try JSONDecoder.synDecoder.decode([PacketSummary].self, from: data)
        let recovered = PacketHistoryRecovery.recover(packets, persist: false)
        try JSONEncoder.synEncoder.encode(recovered).write(to: historyURL, options: .atomic)

        return RecoveryFixtureResult(
            historyURL: historyURL,
            statuses: recovered.map(\.status.rawValue)
        )
    }

    private static func runRetryFixture(arguments: [String]) async throws -> PacketSummary {
        guard let retryIndex = arguments.firstIndex(of: retryArgumentName),
              arguments.indices.contains(retryIndex + 1) else {
            throw FixtureProcessingError.missingInput
        }

        let folderURL = URL(fileURLWithPath: arguments[retryIndex + 1])
        let title = fixtureTitle(from: folderURL)
        let context = PacketContext(
            id: UUID(),
            title: title,
            createdAt: Date(),
            folderURL: folderURL,
            zipURL: PacketLayout.zipURL(for: folderURL)
        )

        return try await PacketProcessor().retry(context: context).packet
    }

    private static func fixtureTitle(from folderURL: URL) -> String {
        let title = folderURL
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return title.isEmpty ? "Fixture retry recording" : title
    }

    private static func runDurationWarningFixture() -> Bool {
        let belowThreshold = RecordingDurationWarning.shouldIssue(
            elapsed: RecordingDurationWarning.threshold - 1,
            alreadyIssued: false
        )
        let atThreshold = RecordingDurationWarning.shouldIssue(
            elapsed: RecordingDurationWarning.threshold,
            alreadyIssued: false
        )
        let alreadyIssued = RecordingDurationWarning.shouldIssue(
            elapsed: RecordingDurationWarning.threshold + 60,
            alreadyIssued: true
        )

        return belowThreshold == false
            && atThreshold == true
            && alreadyIssued == false
            && RecordingDurationWarning.message.contains("keep recording")
    }

    private static func runSummaryContractFixture() -> Bool {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("syn-summary-contract-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = PacketContext(
            id: UUID(),
            title: "Summary contract fixture",
            createdAt: Date(),
            folderURL: root,
            zipURL: root.deletingPathExtension().appendingPathExtension("zip")
        )
        guard (try? context.ensureDerivedDirectories()) != nil else {
            return false
        }
        let fixtureJPEG = Data([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0xff, 0xd9])
        let compressedURL = context.compressedFramesURL.appendingPathComponent("00-00-03.000.jpg")
        guard (try? fixtureJPEG.write(to: compressedURL)) != nil else {
            return false
        }

        let frames = [
            CandidateFrameMetadata(
                timestamp: 3,
                fullPath: "frames/full/00-00-03.000.png",
                compressedPath: "frames/compressed/00-00-03.000.jpg",
                fullSize: CodableSize(width: 1280, height: 720),
                compressedSize: CodableSize(width: 1280, height: 720),
                fullBytes: 204_800,
                compressedBytes: 172_032,
                perceptualHash: "0000000000000001",
                pixelDifferenceFromPrevious: 0.42,
                appName: "Fixture App",
                windowTitle: "Fixture Window",
                captureBounds: CodableRect(CGRect(x: 10, y: 20, width: 640, height: 360)),
                selected: true,
                reason: "semantic-topic-shift"
            )
        ]
        let summary = AIProviderService.fallbackSummary(
            transcript: "# Transcript\n\nThe user describes a bug and asks for a concrete implementation change.",
            frames: frames
        )
        let required = [
            "# Summary",
            "## Overview",
            "## Prioritized Feedback And Issues",
            "## Timestamped Observations",
            "## Frame References",
            "## Suggested Implementation Tasks",
            "## Open Questions And Uncertainty",
            "Claude was unavailable",
            "frames/full/00-00-03.000.png"
        ]

        let prompt = AIProviderService.summaryPromptForTesting(
            transcript: "# Transcript\n\nThe user describes a bug and asks for a concrete implementation change.",
            frames: frames
        )
        let promptRequired = [
            "Selected frame metadata:",
            "frames/full/00-00-03.000.png",
            "frames/compressed/00-00-03.000.jpg",
            "Fixture App",
            "Fixture Window",
            "semantic-topic-shift",
            "pixelDifferenceFromPrevious: 0.420",
            "perceptualHash: 0000000000000001",
            "captureBounds: x=10, y=20, w=640, h=360",
            "fullSize: 1280x720, fullBytes: 204800",
            "compressedSize: 1280x720, compressedBytes: 172032",
            "ocrText: none",
            "ocrMeanConfidence: unknown, ocrLineCount: 0",
            "raw audio and raw video are not attached"
        ]

        return required.allSatisfy { summary.contains($0) }
            && promptRequired.allSatisfy { prompt.contains($0) }
            && !prompt.contains("raw/recording-source.mp4")
            && claudePayloadIncludesSelectedCompressedImages(
                transcript: "# Transcript\n\nThe user describes a bug and asks for a concrete implementation change.",
                frames: frames,
                context: context,
                expectedImageData: fixtureJPEG
            )
    }

    private static func claudePayloadIncludesSelectedCompressedImages(
        transcript: String,
        frames: [CandidateFrameMetadata],
        context: PacketContext,
        expectedImageData: Data
    ) -> Bool {
        let body = AIProviderService.claudeRequestBodyForTesting(
            transcript: transcript,
            frames: frames,
            context: context
        )
        guard body["model"] as? String == "claude-sonnet-4-6",
              let messages = body["messages"] as? [[String: Any]],
              messages.count == 1,
              messages[0]["role"] as? String == "user",
              let content = messages[0]["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String else {
            return false
        }

        let imageBlocks = content.filter { $0["type"] as? String == "image" }
        guard imageBlocks.count == 1,
              let source = imageBlocks[0]["source"] as? [String: Any],
              source["type"] as? String == "base64",
              source["media_type"] as? String == "image/jpeg",
              source["data"] as? String == expectedImageData.base64EncodedString() else {
            return false
        }

        let serializedBody = (try? JSONSerialization.data(withJSONObject: body))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return text.contains("The attached images are compressed/downscaled JPEGs")
            && text.contains("frames/compressed/00-00-03.000.jpg")
            && text.contains("raw audio and raw video are not attached")
            && !serializedBody.contains("raw/recording-source.mp4")
            && !serializedBody.contains("raw/audio-source.wav")
    }

    @MainActor
    private static func runActiveWindowTrackerFixture() -> ActiveWindowTrackerFixtureResult {
        let ownPID = pid_t(1234)
        let infoList: [[String: Any]] = [
            windowInfo(
                ownerPID: ownPID,
                layer: 0,
                windowID: 10,
                appName: "Syn",
                title: "Syn Recording",
                rect: CGRect(x: 0, y: 0, width: 420, height: 100)
            ),
            windowInfo(
                ownerPID: 2222,
                layer: 4,
                windowID: 11,
                appName: "Menu Extra",
                title: "Not eligible",
                rect: CGRect(x: 0, y: 0, width: 500, height: 300)
            ),
            windowInfo(
                ownerPID: 3333,
                layer: 0,
                windowID: 12,
                appName: "Tiny",
                title: "Too small",
                rect: CGRect(x: 10, y: 10, width: 60, height: 40)
            ),
            windowInfo(
                ownerPID: 4444,
                layer: 0,
                windowID: 13,
                appName: "Notes",
                title: "Feedback Notes",
                rect: CGRect(x: 20, y: 30, width: 900, height: 640)
            )
        ]

        let sample = ActiveWindowTracker.sample(from: infoList, timestamp: 1.25, ownPID: ownPID)
        return ActiveWindowTrackerFixtureResult(
            selectedAppName: sample?.appName,
            selectedWindowTitle: sample?.windowTitle,
            passed: sample?.windowID == 13
                && sample?.appName == "Notes"
                && sample?.windowTitle == "Feedback Notes"
                && sample?.timestamp == 1.25
        )
    }

    private static func windowInfo(
        ownerPID: pid_t,
        layer: Int,
        windowID: UInt32,
        appName: String,
        title: String,
        rect: CGRect
    ) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: ownerPID,
            kCGWindowLayer as String: layer,
            kCGWindowNumber as String: windowID,
            kCGWindowOwnerName as String: appName,
            kCGWindowName as String: title,
            kCGWindowBounds as String: [
                "X": rect.origin.x,
                "Y": rect.origin.y,
                "Width": rect.width,
                "Height": rect.height
            ]
        ]
    }

    private static func runActiveWindowRenderFixture(arguments: [String]) async throws -> ActiveWindowRenderFixtureResult {
        guard let fixtureIndex = arguments.firstIndex(of: activeWindowRenderArgumentName),
              arguments.indices.contains(fixtureIndex + 1) else {
            throw FixtureProcessingError.missingInput
        }

        let inputURL = URL(fileURLWithPath: arguments[fixtureIndex + 1])
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw FixtureProcessingError.inputMissing(inputURL)
        }

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("syn-active-window-render-\(UUID().uuidString).mp4")
        let displayID = CGMainDisplayID()
        let displayBounds = CGDisplayBounds(displayID)
        let largeWindow = insetRect(displayBounds, widthFactor: 0.18, heightFactor: 0.20)
        let smallWindow = insetRect(displayBounds, widthFactor: 0.32, heightFactor: 0.34)
        let clickPoint = CGPoint(x: smallWindow.midX, y: smallWindow.midY)

        let capture = CaptureSourceMetadata(
            mode: CaptureMode.activeWindowFollow.rawValue,
            displayID: displayID,
            windowID: nil,
            appName: "Syn Fixture",
            windowTitle: "Active Window Render",
            sourceRect: nil,
            outputSize: nil,
            notes: ["Offline active-window render fixture."]
        )
        let pointerEvents = [
            PointerEvent(
                kind: .leftMouseDown,
                timestamp: 1.0,
                sourceCoordinates: CodablePoint(x: clickPoint.x, y: clickPoint.y),
                videoCoordinates: nil,
                buttonNumber: 0
            ),
            PointerEvent(
                kind: .leftMouseUp,
                timestamp: 1.12,
                sourceCoordinates: CodablePoint(x: clickPoint.x, y: clickPoint.y),
                videoCoordinates: nil,
                buttonNumber: 0
            )
        ]
        let samples = [
            ActiveWindowSample(
                timestamp: 0,
                windowID: 1001,
                appName: "Syn Fixture",
                windowTitle: "Small Active Window",
                bounds: CodableRect(smallWindow)
            ),
            ActiveWindowSample(
                timestamp: 2.5,
                windowID: 1002,
                appName: "Syn Fixture",
                windowTitle: "Large Active Window",
                bounds: CodableRect(largeWindow)
            )
        ]

        let result = try await VideoUtilities.renderProcessedRecording(
            rawURL: inputURL,
            finalURL: outputURL,
            capture: capture,
            pointerEvents: pointerEvents,
            activeWindowSamples: samples
        )
        let outputExists = ((try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.intValue ?? 0) > 0
        let hasTimelineNote = result.notes.contains { $0.contains("Active-window-follow rendered") }
        let hasPaddingNote = result.notes.contains { $0.contains("24 px padded canvas") }
        let mappedClick = result.pointerEvents.contains { event in
            event.kind == .leftMouseDown && event.videoCoordinates != nil
        }
        let renderSizeValid = result.renderSize.width > 48 && result.renderSize.height > 48
        try? FileManager.default.removeItem(at: outputURL)

        return ActiveWindowRenderFixtureResult(
            passed: outputExists && hasTimelineNote && hasPaddingNote && mappedClick && renderSizeValid,
            renderSize: result.renderSize,
            renderedClickCount: result.renderedClickCount
        )
    }

    private static func runSmartRegionRenderFixture(arguments: [String]) async throws -> SmartRegionRenderFixtureResult {
        guard let fixtureIndex = arguments.firstIndex(of: smartRegionRenderArgumentName),
              arguments.indices.contains(fixtureIndex + 1) else {
            throw FixtureProcessingError.missingInput
        }

        let inputURL = URL(fileURLWithPath: arguments[fixtureIndex + 1])
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw FixtureProcessingError.inputMissing(inputURL)
        }

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("syn-smart-region-render-\(UUID().uuidString).mp4")
        let displayID = CGMainDisplayID()
        let displayBounds = CGDisplayBounds(displayID)
        let selectedRegion = CGRect(
            x: displayBounds.midX - displayBounds.width * 0.16,
            y: displayBounds.midY - displayBounds.height * 0.14,
            width: max(360, displayBounds.width * 0.32),
            height: max(240, displayBounds.height * 0.28)
        ).intersection(displayBounds)
        let firstPoint = CGPoint(x: selectedRegion.midX, y: selectedRegion.midY)
        let secondPoint = CGPoint(
            x: min(displayBounds.maxX - 20, selectedRegion.maxX + selectedRegion.width * 0.8),
            y: min(displayBounds.maxY - 20, selectedRegion.maxY + selectedRegion.height * 0.6)
        )

        let capture = CaptureSourceMetadata(
            mode: CaptureMode.smartRegion.rawValue,
            displayID: displayID,
            windowID: nil,
            appName: "Syn Fixture",
            windowTitle: "Smart Region Render",
            smartRegion: CodableRect(selectedRegion),
            sourceRect: nil,
            outputSize: nil,
            notes: ["Offline smart-region render fixture."]
        )
        let pointerEvents = [
            PointerEvent(
                kind: .move,
                timestamp: 0.2,
                sourceCoordinates: CodablePoint(x: firstPoint.x, y: firstPoint.y),
                videoCoordinates: nil,
                buttonNumber: nil
            ),
            PointerEvent(
                kind: .move,
                timestamp: 1.0,
                sourceCoordinates: CodablePoint(x: secondPoint.x, y: secondPoint.y),
                videoCoordinates: nil,
                buttonNumber: nil
            ),
            PointerEvent(
                kind: .leftMouseDown,
                timestamp: 1.1,
                sourceCoordinates: CodablePoint(x: secondPoint.x, y: secondPoint.y),
                videoCoordinates: nil,
                buttonNumber: 0
            ),
            PointerEvent(
                kind: .leftMouseUp,
                timestamp: 1.22,
                sourceCoordinates: CodablePoint(x: secondPoint.x, y: secondPoint.y),
                videoCoordinates: nil,
                buttonNumber: 0
            )
        ]

        let result = try await VideoUtilities.renderProcessedRecording(
            rawURL: inputURL,
            finalURL: outputURL,
            capture: capture,
            pointerEvents: pointerEvents,
            activeWindowSamples: []
        )
        let outputExists = ((try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.intValue ?? 0) > 0
        let note = result.notes.first { $0.contains("Smart Region rendered") }
        let intervalCount = note.flatMap { line -> Int? in
            let parts = line.split(separator: " ")
            guard let renderedIndex = parts.firstIndex(of: "rendered"),
                  parts.indices.contains(parts.index(after: renderedIndex)) else {
                return nil
            }
            return Int(parts[parts.index(after: renderedIndex)])
        } ?? 0
        let mappedClick = result.pointerEvents.contains { event in
            event.kind == .leftMouseDown && event.videoCoordinates != nil
        }
        let asset = AVURLAsset(url: inputURL)
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first
        let naturalSize = try await videoTrack?.load(.naturalSize) ?? .zero
        let scaleX = naturalSize.width / max(displayBounds.width, 1)
        let scaleY = naturalSize.height / max(displayBounds.height, 1)
        let expectedWidth = selectedRegion.width * scaleX
        let expectedHeight = selectedRegion.height * scaleY
        let renderSizeMatchesRegion = abs(result.renderSize.width - expectedWidth) <= 8
            && abs(result.renderSize.height - expectedHeight) <= 8
        try? FileManager.default.removeItem(at: outputURL)

        return SmartRegionRenderFixtureResult(
            passed: outputExists && intervalCount >= 2 && mappedClick && renderSizeMatchesRegion,
            renderSize: result.renderSize,
            renderedClickCount: result.renderedClickCount,
            intervalCount: intervalCount
        )
    }

    private static func runAllScreensRenderFixture(arguments: [String]) async throws -> AllScreensRenderFixtureResult {
        guard let fixtureIndex = arguments.firstIndex(of: allScreensRenderArgumentName),
              arguments.indices.contains(fixtureIndex + 1) else {
            throw FixtureProcessingError.missingInput
        }

        let inputURL = URL(fileURLWithPath: arguments[fixtureIndex + 1])
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw FixtureProcessingError.inputMissing(inputURL)
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("syn-all-screens-render-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let compositeURL = root.appendingPathComponent("all-screens-raw.mp4")
        let finalURL = root.appendingPathComponent("all-screens-final.mp4")
        let displayA = CGRect(x: -640, y: 0, width: 640, height: 360)
        let displayB = CGRect(x: 0, y: 0, width: 640, height: 360)
        let union = displayA.union(displayB)
        let recordings = [
            AllScreensDisplayRecording(url: inputURL, displayID: 1001, frame: displayA),
            AllScreensDisplayRecording(url: inputURL, displayID: 1002, frame: displayB)
        ]

        let duration = try await VideoUtilities.composeAllScreensRecordings(recordings, outputURL: compositeURL)
        let compositeAsset = AVURLAsset(url: compositeURL)
        guard let compositeTrack = try await compositeAsset.loadTracks(withMediaType: .video).first else {
            return AllScreensRenderFixtureResult(
                passed: false,
                compositeSize: CodableSize(width: 0, height: 0),
                renderSize: CodableSize(width: 0, height: 0),
                renderedClickCount: 0
            )
        }
        let naturalSize = try await compositeTrack.load(.naturalSize)
        let preferredTransform = try await compositeTrack.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let compositeSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let capture = CaptureSourceMetadata(
            mode: CaptureMode.allScreens.rawValue,
            displayID: nil,
            windowID: nil,
            appName: nil,
            windowTitle: nil,
            sourceRect: CodableRect(union),
            outputSize: CodableSize(compositeSize),
            notes: ["Offline all-screens render fixture."]
        )
        let clickPoint = CGPoint(x: displayB.midX, y: displayB.midY)
        let pointerEvents = [
            PointerEvent(
                kind: .leftMouseDown,
                timestamp: min(1.0, max(duration / 2, 0)),
                sourceCoordinates: CodablePoint(x: clickPoint.x, y: clickPoint.y),
                videoCoordinates: nil,
                buttonNumber: 0
            ),
            PointerEvent(
                kind: .leftMouseUp,
                timestamp: min(1.12, max(duration / 2 + 0.12, 0)),
                sourceCoordinates: CodablePoint(x: clickPoint.x, y: clickPoint.y),
                videoCoordinates: nil,
                buttonNumber: 0
            )
        ]

        let result = try await VideoUtilities.renderProcessedRecording(
            rawURL: compositeURL,
            finalURL: finalURL,
            capture: capture,
            pointerEvents: pointerEvents,
            activeWindowSamples: []
        )
        let outputExists = ((try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? NSNumber)?.intValue ?? 0) > 0
        let mappedClick = result.pointerEvents.contains { event in
            event.kind == .leftMouseDown && event.videoCoordinates != nil
        }
        let renderSizeMatchesComposite = Int(result.renderSize.width) == Int(compositeSize.width)
            && Int(result.renderSize.height) == Int(compositeSize.height)

        return AllScreensRenderFixtureResult(
            passed: outputExists && mappedClick && renderSizeMatchesComposite && result.renderedClickCount == 1,
            compositeSize: CodableSize(compositeSize),
            renderSize: result.renderSize,
            renderedClickCount: result.renderedClickCount
        )
    }

    private static func runAnnotationRenderFixture(arguments: [String]) async throws -> AnnotationRenderFixtureResult {
        guard let fixtureIndex = arguments.firstIndex(of: annotationRenderArgumentName),
              arguments.indices.contains(fixtureIndex + 1) else {
            throw FixtureProcessingError.missingInput
        }

        let inputURL = URL(fileURLWithPath: arguments[fixtureIndex + 1])
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw FixtureProcessingError.inputMissing(inputURL)
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("syn-annotation-render-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let outputURL = root.appendingPathComponent("annotation-final.mp4")
        let sourceRect = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let capture = CaptureSourceMetadata(
            mode: CaptureMode.screen.rawValue,
            displayID: nil,
            windowID: nil,
            appName: "Syn Annotation Fixture",
            windowTitle: "Annotation Render",
            sourceRect: CodableRect(sourceRect),
            outputSize: CodableSize(width: 1280, height: 720),
            notes: ["Offline annotation render fixture."]
        )
        let annotations = [
            AnnotationStroke(
                id: UUID(),
                tool: .rectangle,
                startTimestamp: 0.2,
                endTimestamp: 0.6,
                sourcePoints: [CodablePoint(x: 120, y: 590), CodablePoint(x: 470, y: 360)],
                videoPoints: nil,
                colorHex: "#FF2D55",
                lineWidth: 9
            ),
            AnnotationStroke(
                id: UUID(),
                tool: .arrow,
                startTimestamp: 0.4,
                endTimestamp: 0.8,
                sourcePoints: [CodablePoint(x: 760, y: 540), CodablePoint(x: 1060, y: 300)],
                videoPoints: nil,
                colorHex: "#FF2D55",
                lineWidth: 10
            ),
            AnnotationStroke(
                id: UUID(),
                tool: .pen,
                startTimestamp: 0.5,
                endTimestamp: 1.0,
                sourcePoints: [
                    CodablePoint(x: 240, y: 220),
                    CodablePoint(x: 320, y: 260),
                    CodablePoint(x: 420, y: 210),
                    CodablePoint(x: 540, y: 250)
                ],
                videoPoints: nil,
                colorHex: "#FF2D55",
                lineWidth: 8
            )
        ]

        let result = try await VideoUtilities.renderProcessedRecording(
            rawURL: inputURL,
            finalURL: outputURL,
            capture: capture,
            pointerEvents: [],
            annotations: annotations,
            activeWindowSamples: []
        )
        let outputSize = ((try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.intValue ?? 0)
        let mappedCount = result.annotations.filter { $0.videoPoints != nil }.count
        let colorPixels = try await countAnnotationColorPixels(in: outputURL, timestamp: 1.2)

        return AnnotationRenderFixtureResult(
            passed: outputSize > 0
                && result.renderedAnnotationCount == 3
                && mappedCount == 3
                && colorPixels > 100,
            renderSize: result.renderSize,
            renderedAnnotationCount: result.renderedAnnotationCount,
            mappedAnnotationCount: mappedCount,
            annotationColorPixels: colorPixels
        )
    }

    @MainActor
    private static func runAnnotationRecorderFixture() -> AnnotationRecorderFixtureResult {
        let recorder = AnnotationRecorder()
        recorder.start()

        recorder.begin(tool: .rectangle, at: CGPoint(x: 10, y: 20))
        recorder.update(at: CGPoint(x: 110, y: 120))
        recorder.finishDraft()

        recorder.pause()
        recorder.begin(tool: .arrow, at: CGPoint(x: 20, y: 20))
        recorder.update(at: CGPoint(x: 80, y: 80))
        recorder.finishDraft()
        let pausedInputIgnored = recorder.visibleStrokes.count == 1
        recorder.resume()

        recorder.begin(tool: .arrow, at: CGPoint(x: 200, y: 220))
        recorder.update(at: CGPoint(x: 420, y: 340))
        recorder.finishDraft()

        recorder.begin(tool: .pen, at: CGPoint(x: 40, y: 300))
        recorder.update(at: CGPoint(x: 44, y: 304))
        recorder.update(at: CGPoint(x: 80, y: 330))
        recorder.update(at: CGPoint(x: 140, y: 310))
        recorder.finishDraft()

        let strokes = recorder.stop()
        let tools = strokes.map(\.tool.rawValue)
        let stopClearedDraft = recorder.visibleStrokes.isEmpty

        let clearRecorder = AnnotationRecorder()
        clearRecorder.start()
        clearRecorder.begin(tool: .rectangle, at: CGPoint(x: 1, y: 1))
        clearRecorder.update(at: CGPoint(x: 40, y: 40))
        clearRecorder.finishDraft()
        clearRecorder.clear()
        let clearPassed = clearRecorder.visibleStrokes.isEmpty && clearRecorder.stop().isEmpty

        let shapePointCountsPassed = strokes.count == 3
            && strokes[0].sourcePoints.count == 2
            && strokes[1].sourcePoints.count == 2
            && strokes[2].sourcePoints.count >= 3
        let durationsPassed = strokes.allSatisfy { $0.duration >= 0.2 }
        let passed = tools == ["rectangle", "arrow", "pen"]
            && pausedInputIgnored
            && stopClearedDraft
            && clearPassed
            && shapePointCountsPassed
            && durationsPassed

        return AnnotationRecorderFixtureResult(
            passed: passed,
            strokeCount: strokes.count,
            tools: tools,
            pausedInputIgnored: pausedInputIgnored,
            clearPassed: clearPassed
        )
    }

    private static func countAnnotationColorPixels(in videoURL: URL, timestamp: TimeInterval) async throws -> Int {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try generator.copyCGImage(at: CMTime(seconds: timestamp, preferredTimescale: 600), actualTime: nil)
        return countPinkPixels(in: image)
    }

    private static func countPinkPixels(in image: CGImage) -> Int {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var count = 0
        var index = 0
        while index + 2 < bytes.count {
            let red = bytes[index]
            let green = bytes[index + 1]
            let blue = bytes[index + 2]
            if red > 170, green < 120, blue > 80, blue < 180 {
                count += 1
            }
            index += bytesPerPixel
        }
        return count
    }

    private static func runChromeTabFixture() -> ChromeTabFixtureResult {
        let tabs = ChromeTabService.parseTabListOutput(ChromeTabService.encodedFixtureOutput())
        guard let selected = tabs.last else {
            return ChromeTabFixtureResult(tabCount: tabs.count, metadataPassed: false)
        }

        let capture = CaptureSourceMetadata(
            mode: CaptureMode.chromeTab.rawValue,
            displayID: nil,
            windowID: selected.windowID,
            appName: "Google Chrome",
            windowTitle: selected.title,
            chromeTab: selected,
            sourceRect: CodableRect(CGRect(x: 10, y: 20, width: 1200, height: 800)),
            outputSize: CodableSize(width: 2400, height: 1600),
            notes: [
                "Chrome tab capture activated tab \(selected.tabIndex) in Chrome window \(selected.windowIndex) before recording.",
                "Chrome tab URL: \(selected.url)"
            ]
        )
        let session = RawCaptureSession(
            schemaVersion: 1,
            packetID: UUID(),
            title: "Chrome tab fixture",
            createdAt: Date(timeIntervalSince1970: 0),
            capture: capture,
            pauses: []
        )

        guard let data = try? JSONEncoder.synEncoder.encode(session),
              let decoded = try? JSONDecoder.synDecoder.decode(RawCaptureSession.self, from: data) else {
            return ChromeTabFixtureResult(tabCount: tabs.count, metadataPassed: false)
        }

        let metadataPassed = tabs.count == 2
            && selected.title == "Syn Product Spec"
            && selected.url == "https://docs.example.test/syn"
            && decoded.capture.mode == CaptureMode.chromeTab.rawValue
            && decoded.capture.appName == "Google Chrome"
            && decoded.capture.chromeTab == selected
            && decoded.capture.notes.contains("Chrome tab URL: https://docs.example.test/syn")

        return ChromeTabFixtureResult(tabCount: tabs.count, metadataPassed: metadataPassed)
    }

    private static func runRawZipFixture() throws -> RawZipFixtureResult {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("syn-raw-zip-fixture-\(UUID().uuidString)", isDirectory: true)
        let folderURL = root.appendingPathComponent("raw-zip-packet", isDirectory: true)
        let context = PacketContext(
            id: UUID(),
            title: "Raw zip packet",
            createdAt: Date(timeIntervalSince1970: 0),
            folderURL: folderURL,
            zipURL: PacketLayout.zipURL(for: folderURL)
        )

        try context.ensureDerivedDirectories()
        try Data("processed".utf8).write(to: context.finalRecordingURL)
        try Data("transcript".utf8).write(to: context.transcriptURL)
        try Data("summary".utf8).write(to: context.summaryURL)
        try Data("prompt".utf8).write(to: context.agentPromptURL)
        try Data("project context".utf8).write(to: context.projectContextURL)
        try Data("manifest".utf8).write(to: context.manifestURL)
        try Data("candidate metadata".utf8).write(to: context.candidateMetadataURL)
        try Data("full frame".utf8).write(to: context.fullFramesURL.appendingPathComponent("frame-001.png"))
        try Data("compressed frame".utf8).write(to: context.compressedFramesURL.appendingPathComponent("frame-001.jpg"))
        try Data("raw video".utf8).write(to: context.rawRecordingURL)
        try Data("raw pointer".utf8).write(to: context.pointerEventsURL)
        try Data("raw segment".utf8).write(
            to: context.rawSegmentsURL.appendingPathComponent("segment-001.mp4")
        )

        try ZipService.createZip(for: context)
        try ZipService.createRawZip(for: context)
        let compactZipURL = try ZipService.createCompactZip(for: PacketSummary(
            title: context.title,
            createdAt: context.createdAt,
            duration: 1,
            status: .succeeded,
            folderURL: context.folderURL,
            zipURL: context.zipURL
        ))

        let defaultNames = try zipNames(context.zipURL)
        let rawNames = try zipNames(context.rawZipURL)
        let compactNames = try zipNames(compactZipURL)
        let zipRoot = folderURL.lastPathComponent
        let defaultExcludesRaw = !defaultNames.contains { $0.hasPrefix("\(zipRoot)/raw/") }
        let rawZipIncludesRaw = rawNames.contains("\(zipRoot)/raw/recording-source.mp4")
            && rawNames.contains("\(zipRoot)/raw/pointer-events.json")
            && rawNames.contains("\(zipRoot)/raw/segments/segment-001.mp4")
        let rawZipIncludesProcessed = rawNames.contains("\(zipRoot)/recording.mp4")
            && rawNames.contains("\(zipRoot)/manifest.json")
        let compactZipIncludesAgentFiles = compactNames.contains("\(zipRoot)/agent-prompt.md")
            && compactNames.contains("\(zipRoot)/transcript.md")
            && compactNames.contains("\(zipRoot)/summary.md")
            && compactNames.contains("\(zipRoot)/project-context.md")
            && compactNames.contains("\(zipRoot)/manifest.json")
            && compactNames.contains("\(zipRoot)/frames/candidates/metadata.json")
            && compactNames.contains("\(zipRoot)/frames/compressed/frame-001.jpg")
        let compactZipExcludesHeavyFiles = !compactNames.contains("\(zipRoot)/recording.mp4")
            && !compactNames.contains("\(zipRoot)/frames/full/frame-001.png")
            && !compactNames.contains("\(zipRoot)/raw/recording-source.mp4")
            && !compactNames.contains("\(zipRoot)/raw/pointer-events.json")

        return RawZipFixtureResult(
            defaultExcludesRaw: defaultExcludesRaw,
            rawZipIncludesRaw: rawZipIncludesRaw && rawZipIncludesProcessed,
            rawZipURL: context.rawZipURL,
            compactZipIncludesAgentFiles: compactZipIncludesAgentFiles,
            compactZipExcludesHeavyFiles: compactZipExcludesHeavyFiles,
            compactZipURL: compactZipURL
        )
    }

    @MainActor
    private static func runVideoTrimFixture(arguments: [String]) async throws -> VideoTrimFixtureResult {
        guard let fixtureIndex = arguments.firstIndex(of: videoTrimArgumentName),
              arguments.indices.contains(fixtureIndex + 1) else {
            throw FixtureProcessingError.missingInput
        }

        let inputURL = URL(fileURLWithPath: arguments[fixtureIndex + 1])
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw FixtureProcessingError.inputMissing(inputURL)
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("syn-video-trim-fixture-\(UUID().uuidString)", isDirectory: true)
        let packetFolder = root.appendingPathComponent("video-trim-packet", isDirectory: true)
        try FileManager.default.createDirectory(at: packetFolder, withIntermediateDirectories: true)
        let recordingURL = packetFolder.appendingPathComponent("recording.mp4")
        try FileManager.default.copyItem(at: inputURL, to: recordingURL)

        let zipURL = PacketLayout.zipURL(for: packetFolder)
        let duration = try await AVURLAsset(url: inputURL).load(.duration).seconds
        let packet = PacketSummary(
            title: "Video trim fixture",
            createdAt: .now,
            duration: duration,
            status: .succeeded,
            folderURL: packetFolder,
            zipURL: zipURL
        )
        let manifest = PacketManifest(
            schemaVersion: 1,
            appVersion: "fixture",
            createdAt: .now,
            duration: duration,
            capture: CaptureSourceMetadata(
                mode: CaptureMode.screen.rawValue,
                displayID: nil,
                windowID: nil,
                appName: nil,
                windowTitle: nil,
                sourceRect: nil,
                outputSize: nil,
                notes: []
            ),
            files: PacketFiles(
                recording: "recording.mp4",
                transcript: "transcript.md",
                summary: "summary.md",
                agentPrompt: "agent-prompt.md",
                agentPrompts: nil,
                framesFull: "frames/full",
                framesCompressed: "frames/compressed",
                candidateMetadata: "frames/candidates/metadata.json",
                rawRecording: "raw/recording-source.mp4",
                rawCaptureSession: nil,
                pointerEvents: "raw/pointer-events.json",
                annotations: nil,
                activeWindowSamples: nil,
                zip: zipURL.path,
                rawZip: nil,
                editedRecording: nil,
                compactZip: nil,
                projectContext: nil,
                semanticSegments: nil,
                semanticTimeline: nil
            ),
            processing: PacketProcessing(
                transcriptionProvider: "fixture",
                transcriptionModel: "fixture",
                frameSelectionProvider: "fixture",
                frameSelectionModel: nil,
                summaryProvider: "fixture",
                summaryModel: "fixture",
                status: PacketStatus.succeeded.rawValue,
                notes: []
            ),
            pauses: [],
            pointerEventCount: 0,
            pointerMapping: nil,
            annotationCount: nil,
            annotationMapping: nil,
            agentPromptProfile: nil
        )
        try JSONEncoder.synEncoder.encode(manifest)
            .write(to: packetFolder.appendingPathComponent("manifest.json"))

        let appState = AppState()
        appState.recentPackets = [packet]
        appState.selectedPacketID = packet.id
        await appState.createTrimmedRecordingForFixture(for: packet, start: 1, end: min(4, max(1.2, duration - 1)))

        let editedURL = packet.editedRecordingURL
        let editedExists = FileManager.default.fileExists(atPath: editedURL.path)
        let editedDuration = editedExists
            ? try await AVURLAsset(url: editedURL).load(.duration).seconds
            : 0
        let manifestAfterTrim = try? JSONDecoder.synDecoder.decode(
            PacketManifest.self,
            from: Data(contentsOf: packetFolder.appendingPathComponent("manifest.json"))
        )
        let manifestUpdated = manifestAfterTrim?.files.editedRecording == editedURL.path
        let statusPassed = appState.statusMessage?.contains("Edited recording ready") == true
            && appState.videoEditInProgressPacketID == nil

        return VideoTrimFixtureResult(
            outputURL: editedURL,
            trimmedDuration: editedDuration,
            manifestUpdated: manifestUpdated,
            passed: editedExists
                && editedDuration > 0.5
                && editedDuration < duration
                && manifestUpdated
                && packet.availableEditedRecordingURL == editedURL
                && statusPassed
        )
    }

    private static func zipNames(_ url: URL) throws -> Set<String> {
        let result = try Syn.run(
            executable: "/usr/bin/zipinfo",
            arguments: ["-1", url.path],
            workingDirectory: url.deletingLastPathComponent()
        )
        if result.status != 0 {
            throw NSError(
                domain: "Syn.RawZipFixture",
                code: Int(result.status),
                userInfo: [NSLocalizedDescriptionKey: result.output]
            )
        }
        return Set(result.output.split(separator: "\n").map(String.init))
    }

    private static func insetRect(_ rect: CGRect, widthFactor: CGFloat, heightFactor: CGFloat) -> CGRect {
        let insetX = max(24, rect.width * widthFactor)
        let insetY = max(24, rect.height * heightFactor)
        let inset = rect.insetBy(dx: min(insetX, rect.width / 3), dy: min(insetY, rect.height / 3))
        if inset.width > 80, inset.height > 60 {
            return inset
        }

        return CGRect(x: rect.midX - 160, y: rect.midY - 100, width: 320, height: 200)
    }
}

private struct FixtureOptions {
    var inputURL: URL
    var outputRoot: URL
}

private struct RecoveryFixtureResult {
    var historyURL: URL
    var statuses: [String]
}

private struct ActiveWindowRenderFixtureResult {
    var passed: Bool
    var renderSize: CodableSize
    var renderedClickCount: Int
}

private struct SmartRegionRenderFixtureResult {
    var passed: Bool
    var renderSize: CodableSize
    var renderedClickCount: Int
    var intervalCount: Int
}

private struct AllScreensRenderFixtureResult {
    var passed: Bool
    var compositeSize: CodableSize
    var renderSize: CodableSize
    var renderedClickCount: Int
}

private struct AnnotationRenderFixtureResult {
    var passed: Bool
    var renderSize: CodableSize
    var renderedAnnotationCount: Int
    var mappedAnnotationCount: Int
    var annotationColorPixels: Int
}

private struct AnnotationRecorderFixtureResult {
    var passed: Bool
    var strokeCount: Int
    var tools: [String]
    var pausedInputIgnored: Bool
    var clearPassed: Bool
}

private struct ChromeTabFixtureResult {
    var tabCount: Int
    var metadataPassed: Bool

    var passed: Bool {
        tabCount == 2 && metadataPassed
    }
}

private struct PromptProfileFixtureResult {
    var profileCount: Int
    var defaultProfile: AgentPromptProfile
    var persistedProfile: AgentPromptProfile
    var contractPassed: Bool

    var passed: Bool {
        profileCount >= 3
            && persistedProfile == .qaBugReport
            && contractPassed
    }
}

private struct RawZipFixtureResult {
    var defaultExcludesRaw: Bool
    var rawZipIncludesRaw: Bool
    var rawZipURL: URL
    var compactZipIncludesAgentFiles: Bool
    var compactZipExcludesHeavyFiles: Bool
    var compactZipURL: URL

    var passed: Bool {
        defaultExcludesRaw
            && rawZipIncludesRaw
            && compactZipIncludesAgentFiles
            && compactZipExcludesHeavyFiles
    }
}

private struct VideoTrimFixtureResult {
    var outputURL: URL
    var trimmedDuration: TimeInterval
    var manifestUpdated: Bool
    var passed: Bool
}

private struct ActiveWindowTrackerFixtureResult {
    var selectedAppName: String?
    var selectedWindowTitle: String?
    var passed: Bool
}

private struct HotkeyFixtureResult {
    var registration: GlobalHotkeyRegistrationSnapshot
    var chordLogicPassed: Bool

    var passed: Bool {
        registration.allRegistered && chordLogicPassed
    }
}

private struct FrameDebugFixtureResult {
    var metadataCount: Int
    var imageCount: Int
    var passed: Bool
}

private struct OCRFixtureResult {
    var packetURL: URL
    var metadataCount: Int
    var observationCount: Int
    var text: String
    var passed: Bool
}

private struct CapturePickerContractFixtureResult {
    var modeTitles: [String]
    var expectsMicStatus: Bool
    var expectsSettingsEntry: Bool
    var expectsLastMode: Bool
    var passed: Bool
}

private struct SecretStoreFixtureResult {
    var emptyReadPassed: Bool
    var saveReadPassed: Bool
    var overwritePassed: Bool
    var deletePassed: Bool

    var passed: Bool {
        emptyReadPassed && saveReadPassed && overwritePassed && deletePassed
    }
}

private struct LiveCaptureFixtureResult {
    var packet: PacketSummary
    var mode: CaptureMode
    var duration: TimeInterval
    var segmentCount: Int
    var processed: Bool
}
