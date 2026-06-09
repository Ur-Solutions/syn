import Foundation
import AppKit
import AVFoundation
import Carbon
import SwiftUI
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    /// Set briefly when a packet finishes so the recording HUD shows a celebratory "ready" flash.
    @Published var completionFlash = false
    @Published var isCapturePickerPresented = false
    @Published var lastCaptureMode: CaptureMode?
    @Published var selectedPacketID: PacketSummary.ID?
    @Published var recentPackets: [PacketSummary] = []
    @Published var activeRecording: ActiveRecording?
    @Published var statusMessage: String?
    @Published var lastErrorMessage: String?
    @Published var preferredPickerHotkey = "Not configured"
    @Published var preferredRepeatHotkey = "Not configured"
    @Published var pickerHotkeyStatus = "Not checked"
    @Published var repeatHotkeyStatus = "Not checked"
    @Published var micLevel: Double = 0
    @Published var isMicMeterActive = false
    @Published var recordingDurationWarningMessage: String?
    @Published var isChromeTabPickerPresented = false
    @Published var chromeTabCandidates: [ChromeTabTarget] = []
    @Published var isLoadingChromeTabs = false
    @Published var chromeTabSelectionError: String?
    @Published var defaultPromptProfile: AgentPromptProfile = .generalCoding
    @Published var isCanvasModeEnabled = false
    @Published var selectedAnnotationTool: AnnotationTool?
    @Published var canvasColorHex = "#EC6579"
    @Published var selectedAnnotationStrokeID: UUID?
    @Published var visibleAnnotationStrokes: [AnnotationStroke] = []
    @Published var videoEditInProgressPacketID: UUID?
    @Published var projectContextFolderPath: String?

    private enum HotkeyRecordingTrigger: String {
        case picker
        case `repeat`
    }

    private struct HotkeyRecordingFixture {
        var trigger: HotkeyRecordingTrigger
        var mode: CaptureMode
        var process: Bool
    }

    let outputRoot = PacketLayout.defaultRoot
    private let recorder = ScreenCaptureRecorder()
    private let pointerRecorder = PointerEventRecorder()
    private let annotationRecorder = AnnotationRecorder()
    private let activeWindowTracker = ActiveWindowTracker()
    private let micLevelMonitor = MicLevelMonitor()
    private let packetProcessor = PacketProcessor()
    private var currentPacket: PacketContext?
    private var pauseIntervals: [PauseInterval] = []
    private var currentPermissionNotes: [String] = []
    private var appPreferences = AppPreferencesStore.load()
    private var lastRegion: RegionSelection?
    private var lastSelectedWindowID: CGWindowID?
    private var lastSelectedWindowTarget: SelectedWindowTarget?
    private var lastChromeTabTarget: ChromeTabTarget?
    private var lastDisplayID: CGDirectDisplayID?
    private var currentCaptureRegion: RegionSelection?
    private var currentCaptureSelectedWindowID: CGWindowID?
    private var currentCaptureSelectedWindowTarget: SelectedWindowTarget?
    private var currentChromeTabTarget: ChromeTabTarget?
    private var currentCaptureDisplayID: CGDirectDisplayID?
    private var durationWarningTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?
    private let hotkeyActionLogURL = AppState.hotkeyActionLogURLFromArguments()
    private let isHotkeyObserverMode = ProcessInfo.processInfo.arguments.contains("--syn-hotkey-observer")
    private let selectorConfirmLogURL = AppState.selectorConfirmLogURLFromArguments()
    private let isSelectorConfirmObserverMode = ProcessInfo.processInfo.arguments.contains("--syn-selector-confirm-observer")
    private let shouldAutoConfirmSelectorFixtures = !ProcessInfo.processInfo.arguments.contains("--syn-selector-no-auto-confirm")
    private let shouldPreselectWindowSelectorFixture = !ProcessInfo.processInfo.arguments.contains("--syn-window-selector-no-preselect")
    private let selectorInputFixtureMode = AppState.selectorInputFixtureModeFromArguments()
    private let selectorRecordingLogURL = AppState.selectorRecordingLogURLFromArguments()
    private let selectorRecordingFixtureMode = AppState.selectorRecordingFixtureModeFromArguments()
    private let shouldProcessSelectorRecordingFixture = ProcessInfo.processInfo.arguments.contains("--syn-selector-recording-process")
    private let selectorRecordingDuration = AppState.selectorRecordingDurationFromArguments()
    private var selectorRecordingStopTask: Task<Void, Never>?
    private let hotkeyRecordingFixture = AppState.hotkeyRecordingFixtureFromArguments()
    private let hotkeyRecordingLogURL = AppState.hotkeyRecordingLogURLFromArguments()
    private let hotkeyRecordingDuration = AppState.hotkeyRecordingDurationFromArguments()
    private var hotkeyRecordingStopTask: Task<Void, Never>?

    var selectedPacket: PacketSummary? {
        recentPackets.first { $0.id == selectedPacketID }
    }

    var commandPacket: PacketSummary? {
        selectedPacket ?? recentPackets.first
    }

    var commandPacketZipURL: URL? {
        commandPacket?.availableZipURL
    }

    var commandPacketRawZipURL: URL? {
        commandPacket?.availableRawZipURL
    }

    var commandPacketCompactZipURL: URL? {
        commandPacket?.availableCompactZipURL
    }

    var microphoneStatusText: String {
        let microphone = MicrophonePermissionProbe.snapshot
        if microphone.isGranted {
            return "Mic ready"
        } else if microphone.isNotDetermined {
            return "Mic not requested"
        } else if microphone.combinedStatusString == "denied" {
            return "Mic needed"
        } else {
            return "Mic status unknown"
        }
    }

    init() {
        guard !FixtureProcessingRunner.isRequested else {
            return
        }

        recentPackets = PacketHistoryRecovery.recover(PacketHistoryStore.load())
        selectedPacketID = recentPackets.first?.id
        lastCaptureMode = appPreferences.lastCaptureMode
        lastRegion = appPreferences.lastRegion
        lastSelectedWindowTarget = appPreferences.lastSelectedWindowTarget
        lastSelectedWindowID = appPreferences.lastSelectedWindowTarget?.windowID ?? appPreferences.lastSelectedWindowID
        lastChromeTabTarget = appPreferences.lastChromeTabTarget
        lastDisplayID = appPreferences.lastDisplayID
        defaultPromptProfile = appPreferences.defaultPromptProfile ?? .generalCoding
        projectContextFolderPath = appPreferences.projectContextFolderPath
        packetProcessor.defaultPromptProfile = defaultPromptProfile
        packetProcessor.projectContextFolderURL = projectContextFolderPath.map { URL(fileURLWithPath: $0) }
        seedRepeatStateIfNeededForHotkeyRecordingFixture()

        GlobalHotkeyService.shared.onOpenPicker = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.recordHotkeyAction("picker")
                self.openCapturePicker()
                self.startHotkeyRecordingFixtureIfNeeded(trigger: .picker)
            }
        }
        GlobalHotkeyService.shared.onRepeatLastCapture = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.recordHotkeyAction("repeat")
                if self.isHotkeyObserverMode {
                    self.statusMessage = "Repeat hotkey observed."
                    self.showMainWindow()
                } else {
                    self.repeatLastCapture()
                }
            }
        }
        GlobalHotkeyService.shared.onToggleCanvasMode = { [weak self] in
            Task { @MainActor in
                self?.toggleCanvasMode()
            }
        }
        GlobalHotkeyService.shared.onExitCanvasMode = { [weak self] in
            Task { @MainActor in
                self?.setCanvasMode(false)
            }
        }
        GlobalHotkeyService.shared.onSelectCanvasTool = { [weak self] tool in
            Task { @MainActor in
                self?.selectCanvasTool(tool)
            }
        }
        GlobalHotkeyService.shared.onClearCanvas = { [weak self] in
            Task { @MainActor in
                self?.clearAnnotations()
            }
        }
        preferredPickerHotkey = GlobalHotkeyService.pickerDescription
        preferredRepeatHotkey = GlobalHotkeyService.repeatDescription

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            refreshHotkeyStatus()
            PermissionDiagnostics.writeStatusIfRequested()
            if let selectorInputFixtureMode {
                switch selectorInputFixtureMode {
                case .region:
                    showRegionSelectionInputFixture()
                case .selectedWindow:
                    showWindowSelectionInputFixture()
                case .screen, .allScreens, .chromeTab, .activeWindowFollow, .smartRegion:
                    break
                }
            } else if let selectorRecordingFixtureMode {
                switch selectorRecordingFixtureMode {
                case .region:
                    showRegionSelectionFixture()
                case .selectedWindow:
                    showWindowSelectionFixture()
                case .screen, .allScreens, .chromeTab, .activeWindowFollow, .smartRegion:
                    break
                }
            } else if ProcessInfo.processInfo.arguments.contains("--syn-show-settings-window") {
                showSettingsWindow()
            } else if ProcessInfo.processInfo.arguments.contains("--syn-show-recording-hud-fixture") {
                showMainWindow()
                showRecordingHUDFixture()
                if ProcessInfo.processInfo.arguments.contains("--syn-show-canvas-toolbar-fixture") {
                    showCanvasToolbarFixture()
                }
            } else if ProcessInfo.processInfo.arguments.contains("--syn-show-processing-hud-fixture") {
                showMainWindow()
                showProcessingHUDFixture()
            } else if ProcessInfo.processInfo.arguments.contains("--syn-show-completion-hud-fixture") {
                showMainWindow()
                showCompletionHUDFixture()
            } else if ProcessInfo.processInfo.arguments.contains("--syn-show-region-selector-fixture") {
                showRegionSelectionFixture()
            } else if ProcessInfo.processInfo.arguments.contains("--syn-show-window-selector-fixture") {
                showWindowSelectionFixture()
            } else if ProcessInfo.processInfo.arguments.contains("--syn-show-chrome-tab-selector-fixture") {
                showChromeTabSelectionFixture()
            } else if ProcessInfo.processInfo.arguments.contains("--syn-show-video-editor-fixture") {
                showMainWindow()
                showVideoEditorFixture()
            } else if ProcessInfo.processInfo.arguments.contains("--syn-show-capture-picker") {
                showMainWindow()
                isCapturePickerPresented = true
            } else if ProcessInfo.processInfo.arguments.contains("--syn-show-main-window") || PermissionService.shouldShowSetupChecklist {
                showMainWindow()
            }
            if PermissionDiagnostics.shouldRequestMicrophone {
                _ = await MicrophonePermissionProbe.requestAccessAndVerifyInput()
                PermissionDiagnostics.writeStatusIfRequested()
            }
        }
    }

    func refreshHotkeyStatus() {
        let snapshot = GlobalHotkeyService.shared.registrationSnapshot
        pickerHotkeyStatus = hotkeyStatusText(snapshot.pickerStatus)
        repeatHotkeyStatus = hotkeyStatusText(snapshot.repeatStatus)
    }

    func openCapturePicker() {
        guard activeRecording == nil else {
            statusMessage = "A recording is already active."
            return
        }

        showMainWindow()
        isChromeTabPickerPresented = false
        isCapturePickerPresented = true
    }

    func cancelChromeTabSelection() {
        isChromeTabPickerPresented = false
        chromeTabSelectionError = nil
        statusMessage = "Chrome tab selection cancelled."
    }

    func refreshChromeTabs() {
        chromeTabSelectionError = nil
        isLoadingChromeTabs = true
        do {
            chromeTabCandidates = try ChromeTabService.listTabs()
            if chromeTabCandidates.isEmpty {
                chromeTabSelectionError = ChromeTabServiceError.noTabs.localizedDescription
            }
        } catch {
            chromeTabCandidates = []
            chromeTabSelectionError = error.localizedDescription
        }
        isLoadingChromeTabs = false
    }

    func selectChromeTab(_ target: ChromeTabTarget) {
        Task {
            await startChromeTabCapture(target)
        }
    }

    func showMainWindow() {
        MainWindowController.shared.show(appState: self)
    }

    /// Signal packet completion in-app instead of opening the packet folder: a happy chime, a
    /// sparkle "ready" flash on the floating HUD, and a user notification when allowed.
    func celebrateCompletion(packetTitle: String) {
        NSSound(named: NSSound.Name("Glass"))?.play()

        completionFlash = true
        RecordingHUDController.shared.show(appState: self)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            self.completionFlash = false
            RecordingHUDController.shared.hide()
        }

        postCompletionNotification(packetTitle: packetTitle)
    }

    private func postCompletionNotification(packetTitle: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            func deliver() {
                let content = UNMutableNotificationContent()
                content.title = "Syn review packet ready"
                content.body = "\(packetTitle): transcript and summary are done."
                center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                deliver()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { deliver() }
                }
            default:
                break
            }
        }
    }

    func showSettingsWindow() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(
                rootView: SettingsView()
                    .environmentObject(self)
                    .frame(width: 520, height: 760)
            )
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Settings"
            window.setContentSize(NSSize(width: 560, height: 800))
            window.styleMask = NSWindow.StyleMask([.titled, .closable, .miniaturizable])
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showRecordingHUDFixture() {
        activeRecording = ActiveRecording(
            id: UUID(),
            mode: .activeWindowFollow,
            packetTitle: "HUD fixture recording",
            startedAt: Date().addingTimeInterval(-91),
            elapsedBeforeCurrentRun: 91,
            currentRunStartedAt: .now,
            pauseStartedAt: nil,
            phase: .recording
        )
        statusMessage = "Recording..."
        micLevel = 0.82
        isMicMeterActive = true
        RecordingHUDController.shared.show(appState: self)
    }

    private func showCanvasToolbarFixture() {
        if activeRecording?.phase != .recording {
            showRecordingHUDFixture()
        }
        isCanvasModeEnabled = true
        GlobalHotkeyService.shared.setCanvasModeActive(true)
        selectedAnnotationTool = .arrow
        canvasColorHex = "#EC6579"
        annotationRecorder.start()
        annotationRecorder.begin(tool: .rectangle, at: CGPoint(x: 160, y: 160), colorHex: canvasColorHex)
        annotationRecorder.update(at: CGPoint(x: 360, y: 260))
        annotationRecorder.finishDraft()
        visibleAnnotationStrokes = annotationRecorder.visibleStrokes
        selectedAnnotationStrokeID = visibleAnnotationStrokes.first?.id
        CanvasToolbarController.shared.show(appState: self)
        AnnotationOverlayController.shared.update(appState: self)
    }

    private func showProcessingHUDFixture() {
        activeRecording = ActiveRecording(
            id: UUID(),
            mode: .activeWindowFollow,
            packetTitle: "HUD fixture processing",
            startedAt: Date().addingTimeInterval(-91),
            elapsedBeforeCurrentRun: 91,
            currentRunStartedAt: nil,
            pauseStartedAt: nil,
            phase: .processing
        )
        statusMessage = "Processing packet..."
        micLevel = 0
        isMicMeterActive = false
        RecordingHUDController.shared.show(appState: self)
    }

    private func showCompletionHUDFixture() {
        // Shows the "packet ready" sparkle flash without the auto-dismiss timer so it can be captured.
        completionFlash = true
        statusMessage = "Packet ready ✨"
        RecordingHUDController.shared.show(appState: self)
    }

    private func showRegionSelectionFixture() {
        statusMessage = "Region selection fixture visible."
        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 900, height: 700)
        let width = min(max(visibleFrame.width * 0.34, 360), 560)
        let height = min(max(visibleFrame.height * 0.28, 220), 340)
        let initialRect = CGRect(
            x: max(40, visibleFrame.midX - width / 2),
            y: max(60, visibleFrame.midY - height / 2),
            width: width,
            height: height
        )
        beginRegionSelection(initialSelection: initialRect)
        autoConfirmSelectorIfNeeded(kind: .region)
    }

    private func showWindowSelectionFixture() {
        statusMessage = "Window selection fixture visible."
        beginWindowSelection(preselectFirstCandidate: shouldPreselectWindowSelectorFixture)
        autoConfirmSelectorIfNeeded(kind: .selectedWindow)
    }

    private func showChromeTabSelectionFixture() {
        showMainWindow()
        isCapturePickerPresented = false
        isChromeTabPickerPresented = true
        isLoadingChromeTabs = false
        chromeTabSelectionError = nil
        chromeTabCandidates = ChromeTabService.fixtureTabs()
        statusMessage = "Chrome tab selection fixture visible."
    }

    private func showVideoEditorFixture() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("syn-video-editor-ui-\(UUID().uuidString)", isDirectory: true)
        let folderURL = root.appendingPathComponent("video-edit-fixture", isDirectory: true)
        let recordingURL = folderURL.appendingPathComponent("recording.mp4")
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        if let sourceURL = AppState.videoEditorFixtureRecordingURLFromArguments(),
           FileManager.default.fileExists(atPath: sourceURL.path) {
            try? FileManager.default.copyItem(at: sourceURL, to: recordingURL)
        } else {
            try? Data("fixture recording".utf8).write(to: recordingURL)
        }

        let packet = PacketSummary(
            title: "Video edit fixture",
            createdAt: .now,
            duration: 7,
            status: .succeeded,
            folderURL: folderURL,
            zipURL: nil
        )
        recentPackets.insert(packet, at: 0)
        selectedPacketID = packet.id
        statusMessage = nil
    }

    private func showRegionSelectionInputFixture() {
        statusMessage = "Region selector input fixture visible."
        beginRegionSelection()
        driveSelectorInputIfNeeded(kind: .region)
    }

    private func showWindowSelectionInputFixture() {
        statusMessage = "Window selector input fixture visible."
        beginWindowSelection(preselectFirstCandidate: false)
        driveSelectorInputIfNeeded(kind: .selectedWindow)
    }

    private enum SelectorFixtureKind {
        case region
        case selectedWindow

        var captureMode: CaptureMode {
            switch self {
            case .region:
                .region
            case .selectedWindow:
                .selectedWindow
            }
        }
    }

    private func autoConfirmSelectorIfNeeded(kind: SelectorFixtureKind) {
        guard shouldAutoConfirmSelectorFixtures,
              isSelectorConfirmObserverMode || selectorRecordingFixtureMode == kind.captureMode else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            switch kind {
            case .region:
                RegionSelectionController.shared.confirmFixtureSelection()
            case .selectedWindow:
                WindowSelectionController.shared.confirmFixtureSelection()
            }
        }
    }

    private func driveSelectorInputIfNeeded(kind: SelectorFixtureKind) {
        guard selectorInputFixtureMode == kind.captureMode else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            switch kind {
            case .region:
                RegionSelectionController.shared.driveFixtureDragAndConfirm()
            case .selectedWindow:
                WindowSelectionController.shared.driveFixtureClickAndConfirm()
            }
        }
    }

    private func seedRepeatStateIfNeededForHotkeyRecordingFixture() {
        guard let hotkeyRecordingFixture,
              hotkeyRecordingFixture.trigger == .repeat else {
            return
        }

        lastCaptureMode = hotkeyRecordingFixture.mode
        switch hotkeyRecordingFixture.mode {
        case .selectedWindow:
            if let target = fixtureWindowTarget() {
                lastSelectedWindowTarget = target
                lastSelectedWindowID = target.windowID
            }
        case .region, .smartRegion:
            lastRegion = fixtureRegionSelection()
        case .screen, .allScreens:
            lastDisplayID = displayIDContainingMouse() ?? CGMainDisplayID()
        case .chromeTab:
            lastChromeTabTarget = ChromeTabService.fixtureTabs().first
        case .activeWindowFollow:
            break
        }

        let seedFolder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("syn-hotkey-repeat-seed", isDirectory: true)
        recentPackets.insert(PacketSummary(
            title: "Hotkey repeat fixture seed",
            createdAt: .now,
            duration: 1,
            status: .succeeded,
            folderURL: seedFolder
        ), at: 0)
    }

    private func startHotkeyRecordingFixtureIfNeeded(trigger: HotkeyRecordingTrigger) {
        guard let fixture = hotkeyRecordingFixture,
              fixture.trigger == trigger else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            self.isCapturePickerPresented = false
            self.startHotkeyRecordingFixtureCapture(mode: fixture.mode)
        }
    }

    private func startHotkeyRecordingFixtureCapture(mode: CaptureMode) {
        switch mode {
        case .selectedWindow:
            guard let target = fixtureWindowTarget() else {
                recordHotkeyRecording("mode=\(mode.rawValue)")
                recordHotkeyRecording("status=\(PacketStatus.failed.rawValue)")
                recordHotkeyRecording("error=No fixture target window was available.")
                terminateAfterFixtureCallback()
                return
            }
            startCapture(.selectedWindow, selectedWindowID: target.windowID)
        case .region:
            startCapture(.region, region: fixtureRegionSelection())
        case .smartRegion:
            startCapture(.smartRegion, region: fixtureRegionSelection())
        case .chromeTab:
            recordHotkeyRecording("mode=\(mode.rawValue)")
            recordHotkeyRecording("status=\(PacketStatus.failed.rawValue)")
            recordHotkeyRecording("error=Chrome tab hotkey recording fixture needs a real Chrome tab and is not auto-started.")
            terminateAfterFixtureCallback()
        case .screen, .allScreens, .activeWindowFollow:
            startCapture(mode)
        }
    }

    func repeatLastCapture() {
        guard activeRecording == nil else {
            statusMessage = "A recording is already active."
            return
        }

        guard hasCompletedRecording, let lastCaptureMode else {
            openCapturePicker()
            return
        }

        isCapturePickerPresented = false

        switch lastCaptureMode {
        case .region, .smartRegion:
            if let lastRegion {
                startCapture(lastCaptureMode, region: lastRegion)
            } else {
                beginRegionSelection(captureMode: lastCaptureMode)
            }
        case .selectedWindow:
            if let lastSelectedWindowTarget, selectedWindowIsAvailable(lastSelectedWindowTarget) {
                startCapture(.selectedWindow, selectedWindowID: lastSelectedWindowTarget.windowID)
            } else if lastSelectedWindowTarget == nil,
                      let lastSelectedWindowID,
                      selectedWindowIsAvailable(lastSelectedWindowID) {
                startCapture(.selectedWindow, selectedWindowID: lastSelectedWindowID)
            } else {
                statusMessage = "Choose a window for repeat capture."
                beginWindowSelection()
            }
        case .chromeTab:
            if let lastChromeTabTarget {
                Task {
                    await startChromeTabCapture(lastChromeTabTarget)
                }
            } else {
                beginChromeTabSelection()
            }
        case .screen, .allScreens, .activeWindowFollow:
            startCapture(lastCaptureMode)
        }
    }

    func prepareCapture(_ mode: CaptureMode) {
        isCapturePickerPresented = false

        switch mode {
        case .region, .smartRegion:
            beginRegionSelection(captureMode: mode)
        case .selectedWindow:
            beginWindowSelection()
        case .chromeTab:
            beginChromeTabSelection()
        case .screen, .allScreens, .activeWindowFollow:
            startCapture(mode)
        }
    }

    private var hasCompletedRecording: Bool {
        RepeatCapturePolicy.hasCompletedRecording(recentPackets)
    }

    func startCapture(
        _ mode: CaptureMode,
        region: RegionSelection? = nil,
        selectedWindowID: CGWindowID? = nil,
        chromeTab: ChromeTabTarget? = nil
    ) {
        Task {
            await startRecording(mode, region: region, selectedWindowID: selectedWindowID, chromeTab: chromeTab)
        }
    }

    func pauseOrResumeRecording() {
        guard let activeRecording else {
            return
        }

        if activeRecording.isPaused {
            Task { await resumeRecording() }
        } else {
            Task { await pauseRecording() }
        }
    }

    func stopRecording() {
        Task {
            await stopAndProcessRecording()
        }
    }

    func discardRecording() {
        Task {
            await discardActiveRecording()
        }
    }

    func copyPacketHandoff(for packet: PacketSummary) {
        if PacketClipboard.copyHandoff(folderURL: packet.folderURL) {
            statusMessage = "Review packet handoff copied to clipboard."
        } else {
            lastErrorMessage = "Could not copy packet handoff to the clipboard."
        }
    }

    func copyCommandPacketHandoff() {
        guard let packet = commandPacket else {
            statusMessage = "No packet selected."
            showMainWindow()
            return
        }
        copyPacketHandoff(for: packet)
    }

    func openCommandPacketFolder() {
        guard let packet = commandPacket else {
            statusMessage = "No packet selected."
            showMainWindow()
            return
        }
        NSWorkspace.shared.open(packet.folderURL)
    }

    func revealCommandPacketZip() {
        guard let packet = commandPacket else {
            statusMessage = "No packet selected."
            showMainWindow()
            return
        }
        guard let zipURL = packet.availableZipURL else {
            statusMessage = "No zip is available for this packet."
            showMainWindow()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([zipURL])
    }

    func createRawZip(for packet: PacketSummary) {
        do {
            let rawZipURL = try ZipService.createRawZip(for: packet)
            updateManifestRawZip(for: packet, rawZipURL: rawZipURL)
            statusMessage = "Raw zip is ready."
            objectWillChange.send()
        } catch {
            statusMessage = "Raw zip creation failed."
            lastErrorMessage = error.localizedDescription
        }
    }

    func revealRawZip(for packet: PacketSummary) {
        guard let rawZipURL = packet.availableRawZipURL else {
            statusMessage = "No raw zip is available for this packet."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([rawZipURL])
    }

    func createCommandPacketRawZip() {
        guard let packet = commandPacket else {
            statusMessage = "No packet selected."
            showMainWindow()
            return
        }
        createRawZip(for: packet)
    }

    func revealCommandPacketRawZip() {
        guard let packet = commandPacket else {
            statusMessage = "No packet selected."
            showMainWindow()
            return
        }
        revealRawZip(for: packet)
    }

    func createCompactZip(for packet: PacketSummary) {
        do {
            let compactZipURL = try ZipService.createCompactZip(for: packet)
            updateManifestCompactZip(for: packet, compactZipURL: compactZipURL)
            statusMessage = "Compact zip is ready."
            objectWillChange.send()
        } catch {
            statusMessage = "Compact zip creation failed."
            lastErrorMessage = error.localizedDescription
        }
    }

    func revealCompactZip(for packet: PacketSummary) {
        guard let compactZipURL = packet.availableCompactZipURL else {
            statusMessage = "No compact zip is available for this packet."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([compactZipURL])
    }

    func createCommandPacketCompactZip() {
        guard let packet = commandPacket else {
            statusMessage = "No packet selected."
            showMainWindow()
            return
        }
        createCompactZip(for: packet)
    }

    func revealCommandPacketCompactZip() {
        guard let packet = commandPacket else {
            statusMessage = "No packet selected."
            showMainWindow()
            return
        }
        revealCompactZip(for: packet)
    }

    func createTrimmedRecording(for packet: PacketSummary, start: TimeInterval, end: TimeInterval) {
        Task {
            await createTrimmedRecordingAsync(for: packet, start: start, end: end)
        }
    }

    func createTrimmedRecordingForFixture(for packet: PacketSummary, start: TimeInterval, end: TimeInterval) async {
        await createTrimmedRecordingAsync(for: packet, start: start, end: end)
    }

    func revealEditedRecording(for packet: PacketSummary) {
        guard let editedURL = packet.availableEditedRecordingURL else {
            statusMessage = "No edited recording is available for this packet."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([editedURL])
    }

    func delete(packet: PacketSummary) {
        try? FileManager.default.removeItem(at: packet.folderURL)
        if let zipURL = packet.zipURL {
            try? FileManager.default.removeItem(at: zipURL)
        }
        try? FileManager.default.removeItem(at: packet.rawZipURL)
        try? FileManager.default.removeItem(at: packet.compactZipURL)
        recentPackets.removeAll { $0.id == packet.id }
        if selectedPacketID == packet.id {
            selectedPacketID = recentPackets.first?.id
        }
        persistHistory()
    }

    func retry(packet: PacketSummary) {
        Task {
            await retryProcessing(packet)
        }
    }

    func setDefaultPromptProfile(_ profile: AgentPromptProfile) {
        defaultPromptProfile = profile
        packetProcessor.defaultPromptProfile = profile
        savePreferences()
    }

    func chooseProjectContextFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Project Context Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if let projectContextFolderPath {
            panel.directoryURL = URL(fileURLWithPath: projectContextFolderPath)
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        setProjectContextFolder(url)
    }

    func clearProjectContextFolder() {
        projectContextFolderPath = nil
        packetProcessor.projectContextFolderURL = nil
        savePreferences()
        statusMessage = "Project context cleared."
    }

    private func setProjectContextFolder(_ url: URL) {
        let standardized = url.standardizedFileURL
        projectContextFolderPath = standardized.path
        packetProcessor.projectContextFolderURL = standardized
        savePreferences()
        statusMessage = "Project context set."
    }

    func toggleCanvasMode() {
        guard activeRecording?.phase == .recording else {
            statusMessage = "Canvas is available while recording."
            return
        }
        setCanvasMode(!isCanvasModeEnabled, playFeedback: !isCanvasModeEnabled)
    }

    func setCanvasMode(_ enabled: Bool, playFeedback: Bool = false) {
        guard activeRecording?.phase == .recording || !enabled else {
            statusMessage = "Canvas is available while recording."
            return
        }

        isCanvasModeEnabled = enabled
        GlobalHotkeyService.shared.setCanvasModeActive(enabled)
        if enabled {
            selectedAnnotationTool = selectedAnnotationTool ?? .arrow
            AnnotationOverlayController.shared.update(appState: self)
            CanvasToolbarController.shared.show(appState: self)
            statusMessage = "Canvas mode on."
            if playFeedback {
                playCanvasFeedbackSound()
            }
        } else {
            selectedAnnotationTool = nil
            selectedAnnotationStrokeID = nil
            CanvasToolbarController.shared.hide()
            updateAnnotationOverlayVisibility()
            statusMessage = "Canvas mode off."
        }
    }

    func selectCanvasTool(_ tool: AnnotationTool) {
        guard AnnotationTool.canvasTools.contains(tool) else { return }
        guard activeRecording?.phase == .recording else {
            statusMessage = "Canvas tools are available while recording."
            return
        }
        if !isCanvasModeEnabled {
            setCanvasMode(true, playFeedback: true)
        }
        selectedAnnotationTool = tool
        selectedAnnotationStrokeID = nil
        AnnotationOverlayController.shared.update(appState: self)
        CanvasToolbarController.shared.update(appState: self)
    }

    func toggleAnnotationTool(_ tool: AnnotationTool) {
        selectCanvasTool(tool)
    }

    func selectAnnotationStroke(id: UUID?) {
        selectedAnnotationStrokeID = id
        if let id,
           let stroke = visibleAnnotationStrokes.first(where: { $0.id == id }) {
            canvasColorHex = stroke.colorHex
        }
        CanvasToolbarController.shared.update(appState: self)
        AnnotationOverlayController.shared.update(appState: self)
    }

    func deleteSelectedAnnotation() {
        guard let selectedAnnotationStrokeID else { return }
        annotationRecorder.deleteStroke(id: selectedAnnotationStrokeID)
        self.selectedAnnotationStrokeID = nil
        visibleAnnotationStrokes = annotationRecorder.visibleStrokes
        CanvasToolbarController.shared.update(appState: self)
        updateAnnotationOverlayVisibility()
    }

    func clearAnnotations() {
        TextAnnotationInputController.shared.cancel()
        annotationRecorder.clear()
        selectedAnnotationStrokeID = nil
        visibleAnnotationStrokes = []
        CanvasToolbarController.shared.update(appState: self)
        updateAnnotationOverlayVisibility()
    }

    func beginAnnotationText(at point: CGPoint) {
        guard activeRecording?.phase == .recording else { return }
        selectedAnnotationStrokeID = nil
        TextAnnotationInputController.shared.show(at: point, appState: self)
        CanvasToolbarController.shared.update(appState: self)
        AnnotationOverlayController.shared.update(appState: self)
    }

    func moveAnnotationStroke(id: UUID, by delta: CGSize) {
        guard activeRecording?.phase == .recording else { return }
        guard abs(delta.width) >= 0.25 || abs(delta.height) >= 0.25 else { return }
        annotationRecorder.moveStroke(id: id, by: delta)
        visibleAnnotationStrokes = annotationRecorder.visibleStrokes
        AnnotationOverlayController.shared.update(appState: self)
    }

    func resizeAnnotationStroke(id: UUID, handle: AnnotationResizeHandle, to point: CGPoint, constrained: Bool) {
        guard activeRecording?.phase == .recording else { return }
        annotationRecorder.resizeStroke(id: id, handle: handle, to: point, constrained: constrained)
        visibleAnnotationStrokes = annotationRecorder.visibleStrokes
        AnnotationOverlayController.shared.update(appState: self)
    }

    func selectCanvasColor(hex: String) {
        let normalized = normalizedCanvasColorHex(hex)
        canvasColorHex = normalized
        if let selectedAnnotationStrokeID {
            annotationRecorder.setStrokeColor(id: selectedAnnotationStrokeID, colorHex: normalized)
            visibleAnnotationStrokes = annotationRecorder.visibleStrokes
            AnnotationOverlayController.shared.update(appState: self)
        }
        CanvasToolbarController.shared.update(appState: self)
    }

    func commitAnnotationText(_ text: String, at point: CGPoint) {
        guard activeRecording?.phase == .recording else { return }
        selectedAnnotationStrokeID = nil
        annotationRecorder.addText(text, at: point, colorHex: canvasColorHex)
        visibleAnnotationStrokes = annotationRecorder.visibleStrokes
        CanvasToolbarController.shared.update(appState: self)
        AnnotationOverlayController.shared.update(appState: self)
    }

    func beginAnnotationStroke(tool: AnnotationTool, at point: CGPoint) {
        guard activeRecording?.phase == .recording else { return }
        selectedAnnotationStrokeID = nil
        annotationRecorder.begin(tool: tool, at: point, colorHex: canvasColorHex)
        visibleAnnotationStrokes = annotationRecorder.visibleStrokes
        CanvasToolbarController.shared.update(appState: self)
        AnnotationOverlayController.shared.update(appState: self)
    }

    func updateAnnotationStroke(at point: CGPoint, constrained: Bool = false) {
        guard activeRecording?.phase == .recording else { return }
        annotationRecorder.update(at: point, constrained: constrained)
        visibleAnnotationStrokes = annotationRecorder.visibleStrokes
        AnnotationOverlayController.shared.update(appState: self)
    }

    func endAnnotationStroke() {
        annotationRecorder.finishDraft()
        visibleAnnotationStrokes = annotationRecorder.visibleStrokes
        CanvasToolbarController.shared.update(appState: self)
        AnnotationOverlayController.shared.update(appState: self)
    }

    private func updateAnnotationOverlayVisibility() {
        if isCanvasModeEnabled || !visibleAnnotationStrokes.isEmpty {
            AnnotationOverlayController.shared.update(appState: self)
        } else {
            AnnotationOverlayController.shared.close()
        }
    }

    private func playCanvasFeedbackSound() {
        guard let sound = NSSound(named: "Tink") ?? NSSound(named: "Pop") else { return }
        sound.volume = 0.18
        sound.play()
    }

    private func normalizedCanvasColorHex(_ hex: String) -> String {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard value.count == 6,
              value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return canvasColorHex
        }
        return "#\(value)"
    }

    private func resetCanvasState(visibleStrokes: [AnnotationStroke] = []) {
        TextAnnotationInputController.shared.cancel()
        isCanvasModeEnabled = false
        GlobalHotkeyService.shared.setCanvasModeActive(false)
        selectedAnnotationTool = nil
        selectedAnnotationStrokeID = nil
        visibleAnnotationStrokes = visibleStrokes
        CanvasToolbarController.shared.hide()
        AnnotationOverlayController.shared.close()
    }

    private func updateManifestRawZip(for packet: PacketSummary, rawZipURL: URL) {
        let manifestURL = packet.folderURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONDecoder.synDecoder.decode(PacketManifest.self, from: data) else {
            return
        }

        manifest.files.rawZip = rawZipURL.path
        if let encoded = try? JSONEncoder.synEncoder.encode(manifest) {
            try? encoded.write(to: manifestURL)
        }
    }

    private func updateManifestEditedRecording(for packet: PacketSummary, editedURL: URL) {
        let manifestURL = packet.folderURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONDecoder.synDecoder.decode(PacketManifest.self, from: data) else {
            return
        }

        manifest.files.editedRecording = editedURL.path
        if let encoded = try? JSONEncoder.synEncoder.encode(manifest) {
            try? encoded.write(to: manifestURL)
        }
    }

    private func updateManifestCompactZip(for packet: PacketSummary, compactZipURL: URL) {
        let manifestURL = packet.folderURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONDecoder.synDecoder.decode(PacketManifest.self, from: data) else {
            return
        }

        manifest.files.compactZip = compactZipURL.path
        if let encoded = try? JSONEncoder.synEncoder.encode(manifest) {
            try? encoded.write(to: manifestURL)
        }
    }

    private func createTrimmedRecordingAsync(for packet: PacketSummary, start: TimeInterval, end: TimeInterval) async {
        guard activeRecording == nil else {
            statusMessage = "Stop the active recording before editing a packet."
            return
        }

        let sourceURL = packet.folderURL.appendingPathComponent("recording.mp4")
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            lastErrorMessage = "Could not find recording.mp4."
            return
        }

        videoEditInProgressPacketID = packet.id
        statusMessage = "Creating edited recording..."
        lastErrorMessage = nil

        do {
            let result = try await VideoTrimService.createTrimmedCopy(
                sourceURL: sourceURL,
                outputURL: packet.editedRecordingURL,
                start: start,
                end: end
            )
            updateManifestEditedRecording(for: packet, editedURL: result.outputURL)
            statusMessage = "Edited recording ready (\(DurationFormatter.string(from: result.trimmedDuration)))."
            objectWillChange.send()
        } catch {
            lastErrorMessage = error.localizedDescription
            statusMessage = "Video edit failed."
        }

        videoEditInProgressPacketID = nil
    }

    private func beginRegionSelection(initialSelection: CGRect? = nil, captureMode: CaptureMode = .region) {
        statusMessage = "Select a region..."
        RegionSelectionController.shared.begin(initialSelection: initialSelection) { [weak self] selection in
            Task { @MainActor in
                guard let self else { return }
                guard let selection else {
                    self.statusMessage = "Region selection cancelled."
                    return
                }
                if self.isSelectorConfirmObserverMode {
                    let movedSuffix = RegionSelectionController.shared.consumeFixtureMoveFlagForTesting() ? " moved=true" : ""
                    self.recordSelectorConfirm("region \(Int(selection.rect.minX)),\(Int(selection.rect.minY)),\(Int(selection.rect.width)),\(Int(selection.rect.height)) display=\(selection.displayID)\(movedSuffix)")
                    self.statusMessage = "Region selector confirmed."
                    self.terminateAfterFixtureCallback()
                    return
                }
                self.startCapture(captureMode, region: selection)
            }
        }
    }

    private func beginWindowSelection(preselectFirstCandidate: Bool = false) {
        statusMessage = "Select a window..."
        WindowSelectionController.shared.begin(preselectFirstCandidate: preselectFirstCandidate) { [weak self] windowID in
            Task { @MainActor in
                guard let self else { return }
                guard let windowID else {
                    self.statusMessage = "Window selection cancelled."
                    return
                }
                if self.isSelectorConfirmObserverMode {
                    self.recordSelectorConfirm("selectedWindow \(windowID)")
                    self.statusMessage = "Window selector confirmed."
                    self.terminateAfterFixtureCallback()
                    return
                }
                self.startCapture(.selectedWindow, selectedWindowID: windowID)
            }
        }
    }

    private func beginChromeTabSelection() {
        showMainWindow()
        isCapturePickerPresented = false
        isChromeTabPickerPresented = true
        statusMessage = "Select a Chrome tab..."
        refreshChromeTabs()
    }

    private func startChromeTabCapture(_ target: ChromeTabTarget) async {
        await MainActor.run {
            isLoadingChromeTabs = true
            chromeTabSelectionError = nil
            statusMessage = "Activating Chrome tab..."
        }

        do {
            let activated = try await ChromeTabService.activate(target)
            await MainActor.run {
                isLoadingChromeTabs = false
                isChromeTabPickerPresented = false
                startCapture(
                    .chromeTab,
                    selectedWindowID: activated.windowID,
                    chromeTab: activated
                )
            }
        } catch {
            await MainActor.run {
                isLoadingChromeTabs = false
                chromeTabSelectionError = error.localizedDescription
                lastErrorMessage = error.localizedDescription
                statusMessage = "Chrome tab capture could not start."
            }
        }
    }

    private func startRecording(
        _ mode: CaptureMode,
        region: RegionSelection? = nil,
        selectedWindowID: CGWindowID? = nil,
        chromeTab: ChromeTabTarget? = nil
    ) async {
        guard activeRecording == nil else {
            return
        }

        do {
            lastErrorMessage = nil
            statusMessage = "Starting \(mode.title.lowercased()) recording..."
            let permissionResult = try await PermissionService.verifyBeforeRecording()
            let context = try PacketContext.create(mode: mode)
            currentPacket = context
            pauseIntervals = []
            currentPermissionNotes = permissionResult.notes
            currentCaptureRegion = region
            currentCaptureSelectedWindowID = selectedWindowID
            currentCaptureSelectedWindowTarget = selectedWindowID.flatMap { selectedWindowTarget(for: $0) }
            currentChromeTabTarget = chromeTab
            currentCaptureDisplayID = preferredDisplayID(for: mode, region: region, selectedWindowID: selectedWindowID)

            let pendingPacket = PacketSummary(
                id: context.id,
                title: context.title,
                createdAt: context.createdAt,
                duration: 0,
                status: .processing,
                folderURL: context.folderURL,
                zipURL: context.zipURL
            )
            recentPackets.insert(pendingPacket, at: 0)
            selectedPacketID = pendingPacket.id
            persistHistory()

            let request = CaptureRequest(
                mode: mode,
                createdAt: context.createdAt,
                packet: context,
                preferredDisplayID: currentCaptureDisplayID,
                region: region?.rect,
                regionGlobalRect: region?.globalRect ?? region.map { globalRect(for: $0) },
                selectedWindowID: selectedWindowID,
                chromeTab: chromeTab
            )
            try await recorder.start(request: request)
            pointerRecorder.start()
            annotationRecorder.start()
            resetCanvasState()
            activeWindowTracker.start()
            startMicMeter()

            let recording = ActiveRecording(
                id: context.id,
                mode: mode,
                packetTitle: context.title,
                startedAt: .now,
                elapsedBeforeCurrentRun: 0,
                currentRunStartedAt: .now,
                pauseStartedAt: nil,
                phase: .recording
            )
            activeRecording = recording
            statusMessage = "Recording..."
            startDurationWarningMonitor()
            RecordingHUDController.shared.show(appState: self)
            // Deliberately do NOT open the main window here: a plain Shift+Shift repeat-last
            // capture should stay out of the way (only the floating HUD shows). Modes that need
            // interaction surface their own UI — the capture picker (openCapturePicker shows the
            // window) and the region/window selectors (their own overlays).
            scheduleSelectorRecordingFixtureStopIfNeeded()
            scheduleHotkeyRecordingFixtureStopIfNeeded()
        } catch {
            let failedContext = currentPacket
            lastErrorMessage = error.localizedDescription
            statusMessage = nil
            activeRecording = nil
            currentPacket = nil
            currentPermissionNotes = []
            currentCaptureRegion = nil
            currentCaptureSelectedWindowID = nil
            currentCaptureSelectedWindowTarget = nil
            currentChromeTabTarget = nil
            currentCaptureDisplayID = nil
            _ = activeWindowTracker.stop()
            stopDurationWarningMonitor()
            stopMicMeter()
            RecordingHUDController.shared.hide()
            _ = annotationRecorder.stop()
            resetCanvasState()
            if let failedContext {
                updatePacketStatus(id: failedContext.id, status: .failed, duration: 0)
            }
            if selectorRecordingFixtureMode != nil {
                recordSelectorRecording("mode=\(mode.rawValue)")
                recordSelectorRecording("status=\(PacketStatus.failed.rawValue)")
                recordSelectorRecording("error=\(error.localizedDescription)")
                if let failedContext {
                    recordSelectorRecording("folder=\(failedContext.folderURL.path)")
                }
                terminateAfterFixtureCallback()
            } else if hotkeyRecordingFixture != nil {
                recordHotkeyRecording("mode=\(mode.rawValue)")
                recordHotkeyRecording("status=\(PacketStatus.failed.rawValue)")
                recordHotkeyRecording("error=\(error.localizedDescription)")
                if let failedContext {
                    recordHotkeyRecording("folder=\(failedContext.folderURL.path)")
                }
                terminateAfterFixtureCallback()
            }
        }
    }

    private func pauseRecording() async {
        guard var recording = activeRecording, recording.phase == .recording else {
            return
        }

        do {
            setCanvasMode(false)
            try await recorder.pause()
            pointerRecorder.pause()
            annotationRecorder.pause()
            activeWindowTracker.pause()
            stopMicMeter()
            let now = Date()
            recording.elapsedBeforeCurrentRun = recording.elapsed(at: now)
            recording.currentRunStartedAt = nil
            recording.pauseStartedAt = now
            recording.phase = .paused
            activeRecording = recording
            statusMessage = "Paused"
            RecordingHUDController.shared.update(appState: self)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func resumeRecording() async {
        guard var recording = activeRecording, recording.phase == .paused else {
            return
        }

        do {
            try await recorder.resume()
            pointerRecorder.resume()
            annotationRecorder.resume()
            activeWindowTracker.resume()
            startMicMeter()
            let now = Date()
            if let pauseStartedAt = recording.pauseStartedAt {
                pauseIntervals.append(PauseInterval(startedAt: pauseStartedAt, endedAt: now))
            }
            recording.pauseStartedAt = nil
            recording.currentRunStartedAt = now
            recording.phase = .recording
            activeRecording = recording
            statusMessage = "Recording..."
            RecordingHUDController.shared.update(appState: self)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func stopAndProcessRecording() async {
        guard let context = currentPacket,
              var recording = activeRecording else {
            return
        }

        var failurePointerEvents: [PointerEvent] = []
        var failureAnnotations: [AnnotationStroke] = []
        var failureActiveWindowSamples: [ActiveWindowSample] = []
        var failureCapture: CaptureSourceMetadata?
        var failurePauses = pauseIntervals
        let fallbackFailureDuration = recording.elapsed()

        do {
            statusMessage = "Stopping recording..."
            let stopRequestedAt = Date()
            SynPerf.event("──── finalize start (mode=\(recording.mode.rawValue), elapsed=\(String(format: "%.1f", recording.elapsed(at: stopRequestedAt)))s) ────")
            if recording.phase == .paused,
               let pauseStartedAt = recording.pauseStartedAt {
                pauseIntervals.append(PauseInterval(startedAt: pauseStartedAt, endedAt: stopRequestedAt))
                failurePauses = pauseIntervals
            }

            recording.elapsedBeforeCurrentRun = recording.elapsed(at: stopRequestedAt)
            recording.currentRunStartedAt = nil
            recording.pauseStartedAt = nil
            recording.phase = .processing
            activeRecording = recording
            RecordingHUDController.shared.update(appState: self)

            let pointerEvents = pointerRecorder.stop()
            failurePointerEvents = pointerEvents
            let annotations = annotationRecorder.stop()
            failureAnnotations = annotations
            resetCanvasState()
            stopMicMeter()
            let activeWindowSamples = activeWindowTracker.stop()
            failureActiveWindowSamples = activeWindowSamples
            let recorderStopStart = Date()
            let segments = try await recorder.stop()
            SynPerf.log("recorder.stop (ScreenCaptureKit finalize)", seconds: Date().timeIntervalSince(recorderStopStart))
            var capture = recorder.sourceMetadata ?? CaptureSourceMetadata(
                mode: recording.mode.rawValue,
                displayID: nil,
                windowID: nil,
                appName: nil,
                windowTitle: nil,
                sourceRect: nil,
                outputSize: nil,
                notes: ["Capture metadata was unavailable."]
            )
            capture.notes.append(contentsOf: currentPermissionNotes)
            failureCapture = capture

            if selectorRecordingFixtureMode != nil && !shouldProcessSelectorRecordingFixture {
                try await finishSelectorRecordingFixtureRaw(
                    context: context,
                    recording: recording,
                    segments: segments,
                    capture: capture,
                    pointerEvents: pointerEvents,
                    annotations: annotations,
                    activeWindowSamples: activeWindowSamples
                )
                return
            }

            if let hotkeyRecordingFixture, !hotkeyRecordingFixture.process {
                try await finishHotkeyRecordingFixtureRaw(
                    context: context,
                    recording: recording,
                    segments: segments,
                    capture: capture,
                    pointerEvents: pointerEvents,
                    annotations: annotations,
                    activeWindowSamples: activeWindowSamples
                )
                return
            }

            statusMessage = "Processing packet..."
            // Fixture-driven processing terminates the app right after the callback, so it must
            // produce the summary + zip synchronously. Interactive recordings defer them: the
            // packet folder is revealed immediately and the layered summary + zip finish after.
            let isFixtureProcessing = (hotkeyRecordingFixture?.process == true)
                || (selectorRecordingFixtureMode != nil && shouldProcessSelectorRecordingFixture)
            let processStart = Date()
            let result = try await packetProcessor.process(
                context: context,
                segments: segments,
                capture: capture,
                pointerEvents: pointerEvents,
                annotations: annotations,
                activeWindowSamples: activeWindowSamples,
                pauses: pauseIntervals,
                deferFinalize: !isFixtureProcessing
            )
            SynPerf.log("packetProcessor.process (merge + pipeline)", seconds: Date().timeIntervalSince(processStart))

            replacePacket(result.packet)
            selectedPacketID = result.packet.id
            activeRecording = nil
            currentPacket = nil
            currentPermissionNotes = []
            stopDurationWarningMonitor()
            rememberSuccessfulCapture(mode: recording.mode)
            statusMessage = "Packet ready ✨ — handoff copied to clipboard; summary and zip are finishing in the background."
            if hotkeyRecordingFixture?.process == true {
                RecordingHUDController.shared.hide()
                recordHotkeyRecording("trigger=\(hotkeyRecordingFixture?.trigger.rawValue ?? "")")
                recordHotkeyRecording("mode=\(recording.mode.rawValue)")
                recordHotkeyRecording("status=\(result.packet.status.rawValue)")
                recordHotkeyRecording("duration=\(String(format: "%.3f", result.packet.duration))")
                recordHotkeyRecording("segments=\(segments.count)")
                recordHotkeyRecording("folder=\(context.folderURL.path)")
                recordHotkeyRecording("rawRecording=\(context.rawRecordingURL.path)")
                recordHotkeyRecording("recording=\(context.finalRecordingURL.path)")
                recordHotkeyRecording("transcript=\(context.transcriptURL.path)")
                recordHotkeyRecording("summary=\(context.summaryURL.path)")
                recordHotkeyRecording("zip=\(context.zipURL.path)")
                terminateAfterFixtureCallback()
            } else if selectorRecordingFixtureMode != nil && shouldProcessSelectorRecordingFixture {
                RecordingHUDController.shared.hide()
                recordSelectorRecording("mode=\(recording.mode.rawValue)")
                recordSelectorRecording("status=\(result.packet.status.rawValue)")
                recordSelectorRecording("duration=\(String(format: "%.3f", result.packet.duration))")
                recordSelectorRecording("segments=\(segments.count)")
                recordSelectorRecording("folder=\(context.folderURL.path)")
                recordSelectorRecording("rawRecording=\(context.rawRecordingURL.path)")
                recordSelectorRecording("recording=\(context.finalRecordingURL.path)")
                recordSelectorRecording("transcript=\(context.transcriptURL.path)")
                recordSelectorRecording("summary=\(context.summaryURL.path)")
                recordSelectorRecording("zip=\(context.zipURL.path)")
                terminateAfterFixtureCallback()
            } else {
                SynPerf.log("TOTAL stop→packet-ready", seconds: Date().timeIntervalSince(stopRequestedAt))
                // No Finder folder pop-up: signal completion in-app instead — a happy sound, a
                // sparkle flash on the HUD, and a notification if the user has allowed them.
                celebrateCompletion(packetTitle: result.packet.title)
                // Core artifacts already exist; the layered summary + shareable zip finish off the
                // critical path. Owned by the long-lived app so it isn't killed mid-flight, and
                // refreshes the UI when done so the "Reveal Zip" action appears.
                let deferredContext = context
                let deferredCapture = capture
                Task { [weak self] in
                    guard let self else { return }
                    await self.packetProcessor.runDeferredFinalize(context: deferredContext, capture: deferredCapture)
                    self.objectWillChange.send()
                }
            }
        } catch {
            let pointerEvents = failurePointerEvents.isEmpty ? pointerRecorder.stop() : failurePointerEvents
            let annotations = failureAnnotations.isEmpty ? annotationRecorder.stop() : failureAnnotations
            stopMicMeter()
            let activeWindowSamples = failureActiveWindowSamples.isEmpty ? activeWindowTracker.stop() : failureActiveWindowSamples
            let capture = failureCapture ?? recorder.sourceMetadata ?? CaptureSourceMetadata(
                mode: recording.mode.rawValue,
                displayID: nil,
                windowID: nil,
                appName: nil,
                windowTitle: nil,
                sourceRect: nil,
                outputSize: nil,
                notes: ["Capture metadata was unavailable after processing failed."]
            )
            let partialPacket = try? await packetProcessor.writePartialFailureArtifacts(
                context: context,
                capture: capture,
                pointerEvents: pointerEvents,
                annotations: annotations,
                activeWindowSamples: activeWindowSamples,
                pauses: failurePauses,
                duration: fallbackFailureDuration,
                error: error
            )
            if let partialPacket {
                replacePacket(partialPacket)
                selectedPacketID = partialPacket.id
            } else {
                try? JSONEncoder.synEncoder.encode(pointerEvents).write(to: context.pointerEventsURL)
                updatePacketStatus(id: context.id, status: .failed, duration: fallbackFailureDuration)
            }
            lastErrorMessage = error.localizedDescription
            statusMessage = partialPacket?.status == .partial
                ? "Packet partial. Raw recording kept for retry."
                : "Packet failed."
            activeRecording = nil
            currentPacket = nil
            currentPermissionNotes = []
            currentCaptureRegion = nil
            currentCaptureSelectedWindowID = nil
            currentCaptureSelectedWindowTarget = nil
            currentChromeTabTarget = nil
            currentCaptureDisplayID = nil
            resetCanvasState()
            selectorRecordingStopTask?.cancel()
            selectorRecordingStopTask = nil
            hotkeyRecordingStopTask?.cancel()
            hotkeyRecordingStopTask = nil
            stopDurationWarningMonitor()
            RecordingHUDController.shared.hide()
            if selectorRecordingFixtureMode != nil {
                recordSelectorRecording("mode=\(recording.mode.rawValue)")
                recordSelectorRecording("status=\(partialPacket?.status.rawValue ?? PacketStatus.failed.rawValue)")
                recordSelectorRecording("duration=\(String(format: "%.3f", partialPacket?.duration ?? fallbackFailureDuration))")
                recordSelectorRecording("folder=\(context.folderURL.path)")
                recordSelectorRecording("error=\(error.localizedDescription)")
                terminateAfterFixtureCallback()
            } else if hotkeyRecordingFixture != nil {
                recordHotkeyRecording("trigger=\(hotkeyRecordingFixture?.trigger.rawValue ?? "")")
                recordHotkeyRecording("mode=\(recording.mode.rawValue)")
                recordHotkeyRecording("status=\(partialPacket?.status.rawValue ?? PacketStatus.failed.rawValue)")
                recordHotkeyRecording("duration=\(String(format: "%.3f", partialPacket?.duration ?? fallbackFailureDuration))")
                recordHotkeyRecording("folder=\(context.folderURL.path)")
                recordHotkeyRecording("error=\(error.localizedDescription)")
                terminateAfterFixtureCallback()
            }
        }
    }

    private func discardActiveRecording() async {
        guard let context = currentPacket,
              activeRecording != nil else {
            return
        }

        statusMessage = "Discarding recording..."

        // Stop capture and the live recorders without processing their output.
        _ = try? await recorder.stop()
        _ = pointerRecorder.stop()
        _ = annotationRecorder.stop()
        _ = activeWindowTracker.stop()
        stopMicMeter()

        // Cancel any fixture auto-stop tasks so they cannot fire after discard.
        selectorRecordingStopTask?.cancel()
        selectorRecordingStopTask = nil
        hotkeyRecordingStopTask?.cancel()
        hotkeyRecordingStopTask = nil
        stopDurationWarningMonitor()

        // Tear down HUD and annotation overlay.
        RecordingHUDController.shared.hide()
        resetCanvasState()

        // Remove the pending packet from history and delete its folder on disk.
        recentPackets.removeAll { $0.id == context.id }
        if selectedPacketID == context.id {
            selectedPacketID = recentPackets.first?.id
        }
        try? FileManager.default.removeItem(at: context.folderURL)
        try? FileManager.default.removeItem(at: context.zipURL)
        persistHistory()

        // Reset all per-recording state (mirrors the startRecording catch block).
        // Deliberately does NOT call rememberSuccessfulCapture, so repeat-last is unchanged.
        activeRecording = nil
        currentPacket = nil
        currentPermissionNotes = []
        pauseIntervals = []
        currentCaptureRegion = nil
        currentCaptureSelectedWindowID = nil
        currentCaptureSelectedWindowTarget = nil
        currentChromeTabTarget = nil
        currentCaptureDisplayID = nil
        resetCanvasState()
        statusMessage = "Recording discarded."
    }

    private func scheduleSelectorRecordingFixtureStopIfNeeded() {
        guard selectorRecordingFixtureMode != nil else {
            return
        }

        selectorRecordingStopTask?.cancel()
        let duration = selectorRecordingDuration
        selectorRecordingStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.5, duration) * 1_000_000_000))
            await self?.stopAndProcessRecording()
        }
    }

    private func scheduleHotkeyRecordingFixtureStopIfNeeded() {
        guard hotkeyRecordingFixture != nil else {
            return
        }

        hotkeyRecordingStopTask?.cancel()
        let duration = hotkeyRecordingDuration
        hotkeyRecordingStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.5, duration) * 1_000_000_000))
            await self?.stopAndProcessRecording()
        }
    }

    private func finishSelectorRecordingFixtureRaw(
        context: PacketContext,
        recording: ActiveRecording,
        segments: [URL],
        capture: CaptureSourceMetadata,
        pointerEvents: [PointerEvent],
        annotations: [AnnotationStroke],
        activeWindowSamples: [ActiveWindowSample]
    ) async throws {
        selectorRecordingStopTask?.cancel()
        selectorRecordingStopTask = nil

        var capture = capture
        capture.notes.append("Selector recording fixture stopped before AI processing.")
        let duration = try await VideoUtilities.mergeSegments(segments, outputURL: context.rawRecordingURL)
        let rawSession = RawCaptureSession(
            schemaVersion: 1,
            packetID: context.id,
            title: context.title,
            createdAt: context.createdAt,
            capture: capture,
            pauses: pauseIntervals
        )
        try JSONEncoder.synEncoder.encode(rawSession).write(to: context.rawCaptureSessionURL)
        try JSONEncoder.synEncoder.encode(pointerEvents).write(to: context.pointerEventsURL)
        try JSONEncoder.synEncoder.encode(annotations).write(to: context.annotationEventsURL)
        if !activeWindowSamples.isEmpty {
            try JSONEncoder.synEncoder.encode(activeWindowSamples).write(to: context.activeWindowSamplesURL)
        }

        let summary = """
        # Selector Recording Fixture

        Status: Partial

        Syn confirmed the \(recording.mode.title) selector, started a real ScreenCaptureKit recording, and stopped after \(String(format: "%.1f", duration)) seconds.

        This fixture intentionally stopped after raw live capture to avoid sending screen contents or microphone audio to AI providers.
        """
        try summary.write(to: context.summaryURL, atomically: true, encoding: .utf8)

        let prompt = """
        # Syn Selector Recording Fixture

        Packet folder:
        `\(context.folderURL.path)`

        Raw recording:
        `raw/recording-source.mp4`

        Retry processing from Syn History only if the captured contents are safe to send to the configured AI providers.
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
        replacePacket(packet)
        selectedPacketID = packet.id
        activeRecording = nil
        currentPacket = nil
        currentPermissionNotes = []
        stopDurationWarningMonitor()
        rememberSuccessfulCapture(mode: recording.mode)
        statusMessage = "Selector recording fixture captured a raw packet."
        RecordingHUDController.shared.hide()
        resetCanvasState()
        recordSelectorRecording("mode=\(recording.mode.rawValue)")
        recordSelectorRecording("status=\(packet.status.rawValue)")
        recordSelectorRecording("duration=\(String(format: "%.3f", duration))")
        recordSelectorRecording("segments=\(segments.count)")
        recordSelectorRecording("folder=\(context.folderURL.path)")
        recordSelectorRecording("rawRecording=\(context.rawRecordingURL.path)")
        terminateAfterFixtureCallback()
    }

    private func finishHotkeyRecordingFixtureRaw(
        context: PacketContext,
        recording: ActiveRecording,
        segments: [URL],
        capture: CaptureSourceMetadata,
        pointerEvents: [PointerEvent],
        annotations: [AnnotationStroke],
        activeWindowSamples: [ActiveWindowSample]
    ) async throws {
        hotkeyRecordingStopTask?.cancel()
        hotkeyRecordingStopTask = nil

        var capture = capture
        capture.notes.append("Hotkey recording fixture stopped before AI processing.")
        let duration = try await VideoUtilities.mergeSegments(segments, outputURL: context.rawRecordingURL)
        let rawSession = RawCaptureSession(
            schemaVersion: 1,
            packetID: context.id,
            title: context.title,
            createdAt: context.createdAt,
            capture: capture,
            pauses: pauseIntervals
        )
        try JSONEncoder.synEncoder.encode(rawSession).write(to: context.rawCaptureSessionURL)
        try JSONEncoder.synEncoder.encode(pointerEvents).write(to: context.pointerEventsURL)
        try JSONEncoder.synEncoder.encode(annotations).write(to: context.annotationEventsURL)
        if !activeWindowSamples.isEmpty {
            try JSONEncoder.synEncoder.encode(activeWindowSamples).write(to: context.activeWindowSamplesURL)
        }

        let summary = """
        # Hotkey Recording Fixture

        Status: Partial

        Syn received the \(hotkeyRecordingFixture?.trigger.rawValue ?? "unknown") global shortcut, started a real \(recording.mode.title) ScreenCaptureKit recording, and stopped after \(String(format: "%.1f", duration)) seconds.

        This fixture intentionally stopped after raw live capture to avoid sending screen contents or microphone audio to AI providers.
        """
        try summary.write(to: context.summaryURL, atomically: true, encoding: .utf8)

        let prompt = """
        # Syn Hotkey Recording Fixture

        Packet folder:
        `\(context.folderURL.path)`

        Raw recording:
        `raw/recording-source.mp4`

        Retry processing from Syn History only if the captured contents are safe to send to the configured AI providers.
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
        replacePacket(packet)
        selectedPacketID = packet.id
        activeRecording = nil
        currentPacket = nil
        currentPermissionNotes = []
        stopDurationWarningMonitor()
        rememberSuccessfulCapture(mode: recording.mode)
        statusMessage = "Hotkey recording fixture captured a raw packet."
        RecordingHUDController.shared.hide()
        resetCanvasState()
        recordHotkeyRecording("trigger=\(hotkeyRecordingFixture?.trigger.rawValue ?? "")")
        recordHotkeyRecording("mode=\(recording.mode.rawValue)")
        recordHotkeyRecording("status=\(packet.status.rawValue)")
        recordHotkeyRecording("duration=\(String(format: "%.3f", duration))")
        recordHotkeyRecording("segments=\(segments.count)")
        recordHotkeyRecording("folder=\(context.folderURL.path)")
        recordHotkeyRecording("rawRecording=\(context.rawRecordingURL.path)")
        terminateAfterFixtureCallback()
    }

    private func retryProcessing(_ packet: PacketSummary) async {
        guard activeRecording == nil else {
            statusMessage = "Stop the active recording before retrying a packet."
            return
        }

        lastErrorMessage = nil
        statusMessage = "Retrying packet processing..."
        updatePacketStatus(id: packet.id, status: .processing, duration: packet.duration)

        do {
            let context = PacketContext.existing(packet: packet)
            let result = try await packetProcessor.retry(context: context)
            replacePacket(result.packet)
            selectedPacketID = result.packet.id
            statusMessage = "Packet ready. Agent prompt and packet folder copied; folder revealed."
            NSWorkspace.shared.activateFileViewerSelecting([context.folderURL])
        } catch {
            updatePacketStatus(id: packet.id, status: .failed, duration: packet.duration)
            lastErrorMessage = error.localizedDescription
            statusMessage = "Retry failed."
        }
    }

    private func replacePacket(_ packet: PacketSummary) {
        if let index = recentPackets.firstIndex(where: { $0.id == packet.id }) {
            recentPackets[index] = packet
        } else {
            recentPackets.insert(packet, at: 0)
        }
        persistHistory()
    }

    private func updatePacketStatus(id: UUID, status: PacketStatus, duration: TimeInterval) {
        guard let index = recentPackets.firstIndex(where: { $0.id == id }) else {
            return
        }

        recentPackets[index].status = status
        recentPackets[index].duration = duration
        persistHistory()
    }

    private func persistHistory() {
        PacketHistoryStore.save(recentPackets)
    }

    private func startDurationWarningMonitor() {
        durationWarningTask?.cancel()
        recordingDurationWarningMessage = nil
        durationWarningTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.issueDurationWarningIfNeeded()
                }

                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    break
                }
            }
        }
    }

    private func stopDurationWarningMonitor() {
        durationWarningTask?.cancel()
        durationWarningTask = nil
        recordingDurationWarningMessage = nil
    }

    private func issueDurationWarningIfNeeded(now: Date = .now) {
        guard var recording = activeRecording else {
            return
        }

        guard RecordingDurationWarning.shouldIssue(
            elapsed: recording.elapsed(at: now),
            alreadyIssued: recording.hasDurationWarning
        ) else {
            return
        }

        recording.durationWarningIssuedAt = now
        activeRecording = recording
        recordingDurationWarningMessage = RecordingDurationWarning.message
        RecordingHUDController.shared.update(appState: self)
    }

    private func rememberSuccessfulCapture(mode: CaptureMode) {
        lastCaptureMode = mode
        if let currentCaptureRegion {
            lastRegion = currentCaptureRegion
        }
        if mode == .selectedWindow, let currentCaptureSelectedWindowTarget {
            lastSelectedWindowTarget = currentCaptureSelectedWindowTarget
            lastSelectedWindowID = currentCaptureSelectedWindowTarget.windowID
        } else if mode == .selectedWindow, let currentCaptureSelectedWindowID {
            lastSelectedWindowID = currentCaptureSelectedWindowID
            lastSelectedWindowTarget = SelectedWindowTarget(
                windowID: currentCaptureSelectedWindowID,
                ownerPID: nil,
                appName: nil,
                windowTitle: nil,
                bounds: nil
            )
        }
        if mode == .chromeTab, let currentChromeTabTarget {
            lastChromeTabTarget = currentChromeTabTarget
        }
        if mode == .screen, let currentCaptureDisplayID {
            lastDisplayID = currentCaptureDisplayID
        }

        appPreferences = AppPreferences(
            lastCaptureMode: lastCaptureMode,
            lastRegion: lastRegion,
            lastSelectedWindowID: lastSelectedWindowID,
            lastSelectedWindowTarget: lastSelectedWindowTarget,
            lastChromeTabTarget: lastChromeTabTarget,
            lastDisplayID: lastDisplayID,
            defaultPromptProfile: defaultPromptProfile,
            projectContextFolderPath: projectContextFolderPath
        )
        savePreferences()
        currentCaptureRegion = nil
        currentCaptureSelectedWindowID = nil
        currentCaptureSelectedWindowTarget = nil
        currentChromeTabTarget = nil
        currentCaptureDisplayID = nil
    }

    private func savePreferences() {
        appPreferences = AppPreferences(
            lastCaptureMode: lastCaptureMode,
            lastRegion: lastRegion,
            lastSelectedWindowID: lastSelectedWindowID,
            lastSelectedWindowTarget: lastSelectedWindowTarget,
            lastChromeTabTarget: lastChromeTabTarget,
            lastDisplayID: lastDisplayID,
            defaultPromptProfile: defaultPromptProfile,
            projectContextFolderPath: projectContextFolderPath
        )
        AppPreferencesStore.save(appPreferences)
    }

    private func selectedWindowIsAvailable(_ windowID: CGWindowID) -> Bool {
        selectedWindowTarget(for: windowID) != nil
    }

    private func selectedWindowIsAvailable(_ target: SelectedWindowTarget) -> Bool {
        guard let current = selectedWindowTarget(for: target.windowID) else {
            return false
        }

        if let ownerPID = target.ownerPID,
           let currentOwnerPID = current.ownerPID,
           ownerPID != currentOwnerPID {
            return false
        }

        if let appName = target.appName,
           let currentAppName = current.appName,
           !appName.isEmpty,
           !currentAppName.isEmpty,
           appName != currentAppName {
            return false
        }

        return true
    }

    private func selectedWindowTarget(for windowID: CGWindowID) -> SelectedWindowTarget? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let ownPID = getpid()
        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != ownPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  number == windowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any] else {
                continue
            }

            let width = bounds["Width"] as? CGFloat ?? 0
            let height = bounds["Height"] as? CGFloat ?? 0
            guard width > 80, height > 60 else {
                continue
            }

            let rect = rect(fromCGWindowBounds: bounds)
            return SelectedWindowTarget(
                windowID: number,
                ownerPID: Int32(ownerPID),
                appName: info[kCGWindowOwnerName as String] as? String,
                windowTitle: info[kCGWindowName as String] as? String,
                bounds: CodableRect(rect)
            )
        }

        return nil
    }

    private func fixtureWindowTarget() -> SelectedWindowTarget? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let ownPID = getpid()
        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != ownPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let title = info[kCGWindowName as String] as? String,
                  title == "Syn Window Selection Fixture Target" else {
                continue
            }

            let rect = rect(fromCGWindowBounds: bounds)
            guard rect.width > 80, rect.height > 60 else {
                continue
            }

            return SelectedWindowTarget(
                windowID: number,
                ownerPID: Int32(ownerPID),
                appName: info[kCGWindowOwnerName as String] as? String,
                windowTitle: title,
                bounds: CodableRect(rect)
            )
        }

        return nil
    }

    private func fixtureRegionSelection() -> RegionSelection {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 900, height: 700)
        let width = min(max(frame.width * 0.24, 360), 560)
        let height = min(max(frame.height * 0.20, 220), 340)
        let rect = CGRect(
            x: max(40, frame.midX - width / 2),
            y: max(60, frame.midY - height / 2),
            width: width,
            height: height
        )
        let displayID = screen?.displayID ?? CGMainDisplayID()
        return RegionSelection(
            rect: rect,
            globalRect: CGRect(
                x: (screen?.frame.minX ?? 0) + rect.minX,
                y: (screen?.frame.minY ?? 0) + rect.minY,
                width: rect.width,
                height: rect.height
            ),
            displayID: displayID
        )
    }

    private func preferredDisplayID(
        for mode: CaptureMode,
        region: RegionSelection?,
        selectedWindowID: CGWindowID?
    ) -> CGDirectDisplayID {
        switch mode {
        case .screen:
            return lastDisplayID ?? displayIDContainingMouse() ?? CGMainDisplayID()
        case .allScreens:
            return CGMainDisplayID()
        case .region, .smartRegion:
            return region?.displayID ?? displayIDContainingMouse() ?? CGMainDisplayID()
        case .activeWindowFollow:
            return displayIDForFrontmostWindow() ?? displayIDContainingMouse() ?? CGMainDisplayID()
        case .selectedWindow, .chromeTab:
            if let selectedWindowID,
               let displayID = displayID(containingWindow: selectedWindowID) {
                return displayID
            }
            return displayIDContainingMouse() ?? CGMainDisplayID()
        }
    }

    private func displayIDContainingMouse() -> CGDirectDisplayID? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })?.displayID
    }

    private func displayIDForFrontmostWindow() -> CGDirectDisplayID? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let ownPID = getpid()
        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != ownPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any] else {
                continue
            }

            let rect = rect(fromCGWindowBounds: bounds)
            guard rect.width > 80, rect.height > 60 else {
                continue
            }

            return displayID(containingGlobalRect: rect)
        }

        return nil
    }

    private func displayID(containingWindow windowID: CGWindowID) -> CGDirectDisplayID? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], windowID) as? [[String: Any]] else {
            return nil
        }

        for info in infoList {
            guard let number = info[kCGWindowNumber as String] as? UInt32,
                  number == windowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any] else {
                continue
            }

            return displayID(containingGlobalRect: rect(fromCGWindowBounds: bounds))
        }

        return nil
    }

    private func displayID(containingGlobalRect rect: CGRect) -> CGDirectDisplayID? {
        NSScreen.screens
            .compactMap { screen -> (displayID: CGDirectDisplayID, area: CGFloat)? in
                let area = screen.frame.intersection(rect).area
                guard area > 0 else { return nil }
                return (screen.displayID, area)
            }
            .max { $0.area < $1.area }?
            .displayID
    }

    private func rect(fromCGWindowBounds bounds: [String: Any]) -> CGRect {
        CGRect(
            x: bounds["X"] as? CGFloat ?? 0,
            y: bounds["Y"] as? CGFloat ?? 0,
            width: bounds["Width"] as? CGFloat ?? 0,
            height: bounds["Height"] as? CGFloat ?? 0
        )
    }

    private func globalRect(for region: RegionSelection) -> CGRect {
        if let screen = NSScreen.screens.first(where: { $0.displayID == region.displayID }) {
            return CGRect(
                x: screen.frame.minX + region.rect.minX,
                y: screen.frame.minY + region.rect.minY,
                width: region.rect.width,
                height: region.rect.height
            )
        }

        let displayBounds = CGDisplayBounds(region.displayID)
        guard displayBounds.width > 0, displayBounds.height > 0 else {
            return region.rect
        }

        return CGRect(
            x: displayBounds.minX + region.rect.minX,
            y: displayBounds.minY + region.rect.minY,
            width: region.rect.width,
            height: region.rect.height
        )
    }

    private func startMicMeter() {
        do {
            try micLevelMonitor.start { [weak self] level in
                self?.micLevel = level
                self?.isMicMeterActive = true
            }
        } catch {
            micLevel = 0
            isMicMeterActive = false
            currentPermissionNotes.append("Mic level monitor failed: \(error.localizedDescription)")
        }
    }

    private func stopMicMeter() {
        micLevelMonitor.stop()
        micLevel = 0
        isMicMeterActive = false
    }

    private func hotkeyStatusText(_ status: OSStatus?) -> String {
        guard let status else {
            return "Not checked"
        }

        if status == noErr {
            return "Registered"
        }

        if status == GlobalHotkeyService.accessibilityRequiredStatus {
            return "Needs Accessibility"
        }

        return "Failed (\(status))"
    }

    private func recordHotkeyAction(_ action: String) {
        guard let hotkeyActionLogURL else {
            return
        }

        writeLine(action, to: hotkeyActionLogURL, failurePrefix: "hotkey action")
    }

    private func recordSelectorConfirm(_ value: String) {
        guard let selectorConfirmLogURL else {
            return
        }

        writeLine(value, to: selectorConfirmLogURL, failurePrefix: "selector confirm")
    }

    private func recordSelectorRecording(_ value: String) {
        guard let selectorRecordingLogURL else {
            return
        }

        writeLine(value, to: selectorRecordingLogURL, failurePrefix: "selector recording")
    }

    private func recordHotkeyRecording(_ value: String) {
        guard let hotkeyRecordingLogURL else {
            return
        }

        writeLine(value, to: hotkeyRecordingLogURL, failurePrefix: "hotkey recording")
    }

    private func writeLine(_ value: String, to url: URL, failurePrefix: String) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let line = "\(value)\n"
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            NSLog("Syn failed to write \(failurePrefix) log: \(error.localizedDescription)")
        }
    }

    private func terminateAfterFixtureCallback() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            NSApp.terminate(nil)
        }
    }

    private static func hotkeyActionLogURLFromArguments() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--syn-hotkey-action-log"),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        return URL(fileURLWithPath: arguments[index + 1])
    }

    private static func selectorConfirmLogURLFromArguments() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--syn-selector-confirm-log"),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        return URL(fileURLWithPath: arguments[index + 1])
    }

    private static func selectorRecordingLogURLFromArguments() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--syn-selector-recording-log"),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        return URL(fileURLWithPath: arguments[index + 1])
    }

    private static func selectorInputFixtureModeFromArguments() -> CaptureMode? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--syn-selector-input-fixture"),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        switch arguments[index + 1] {
        case CaptureMode.region.rawValue:
            return .region
        case CaptureMode.smartRegion.rawValue:
            return .smartRegion
        case CaptureMode.selectedWindow.rawValue, "window":
            return .selectedWindow
        default:
            return nil
        }
    }

    private static func videoEditorFixtureRecordingURLFromArguments() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--syn-video-editor-recording"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    private static func selectorRecordingFixtureModeFromArguments() -> CaptureMode? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--syn-selector-recording-fixture"),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        switch arguments[index + 1] {
        case CaptureMode.region.rawValue:
            return .region
        case CaptureMode.smartRegion.rawValue:
            return .smartRegion
        case CaptureMode.selectedWindow.rawValue, "window":
            return .selectedWindow
        default:
            return nil
        }
    }

    private static func selectorRecordingDurationFromArguments() -> TimeInterval {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--syn-selector-recording-duration"),
              arguments.indices.contains(index + 1),
              let duration = Double(arguments[index + 1]) else {
            return 1.25
        }

        return max(duration, 0.5)
    }

    private static func hotkeyRecordingFixtureFromArguments() -> HotkeyRecordingFixture? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--syn-hotkey-recording-fixture"),
              arguments.indices.contains(index + 1),
              let trigger = HotkeyRecordingTrigger(rawValue: arguments[index + 1]) else {
            return nil
        }

        let mode: CaptureMode
        if let modeIndex = arguments.firstIndex(of: "--syn-hotkey-recording-mode"),
           arguments.indices.contains(modeIndex + 1),
           let parsedMode = CaptureMode(rawValue: arguments[modeIndex + 1]) {
            mode = parsedMode
        } else {
            mode = .selectedWindow
        }

        return HotkeyRecordingFixture(
            trigger: trigger,
            mode: mode,
            process: arguments.contains("--syn-hotkey-recording-process")
        )
    }

    private static func hotkeyRecordingLogURLFromArguments() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--syn-hotkey-recording-log"),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        return URL(fileURLWithPath: arguments[index + 1])
    }

    private static func hotkeyRecordingDurationFromArguments() -> TimeInterval {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--syn-hotkey-recording-duration"),
              arguments.indices.contains(index + 1),
              let duration = Double(arguments[index + 1]) else {
            return 1.25
        }

        return max(duration, 0.5)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(width, 0) * max(height, 0)
    }
}
