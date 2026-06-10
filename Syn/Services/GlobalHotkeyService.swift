import ApplicationServices
import AppKit
import Carbon
import Foundation
import IOKit.hidsystem

struct GlobalHotkeyRegistrationSnapshot {
    var eventHandlerStatus: OSStatus?
    var pickerStatus: OSStatus?
    var repeatStatus: OSStatus?

    var allRegistered: Bool {
        eventHandlerStatus == noErr
            && pickerStatus == noErr
            && repeatStatus == noErr
    }
}

final class GlobalHotkeyService {
    static let shared = GlobalHotkeyService()

    static let pickerDescription = "Left Shift + Right Shift + R"
    static let repeatDescription = "Left Shift + Right Shift"
    static let canvasDescription = "Right Shift + C"
    static let canvasClearDescription = "Right Shift + D, D"
    static let accessibilityRequiredStatus: OSStatus = -25211
    static let eventTapCreationFailedStatus: OSStatus = -25212
    static let eventTapSourceFailedStatus: OSStatus = -25213

    var onOpenPicker: (() -> Void)?
    var onRepeatLastCapture: (() -> Void)?
    var onToggleCanvasMode: (() -> Void)?
    var onExitCanvasMode: (() -> Void)?
    var onSelectCanvasTool: ((AnnotationTool) -> Void)?
    var onClearCanvas: (() -> Void)?
    var onDeleteSelectedAnnotation: (() -> Void)?
    var onUndoAnnotation: (() -> Void)?
    var onCycleAnnotationSelection: (() -> Void)?
    var onNudgeSelectedAnnotation: ((CGFloat, CGFloat) -> Void)?
    var onToggleElementPicker: (() -> Void)?

    private let leftShiftKeyCode = CGKeyCode(56)
    private let rightShiftKeyCode = CGKeyCode(60)
    private let rKeyCode = CGKeyCode(15)
    private let cKeyCode = CGKeyCode(8)
    private let dKeyCode = CGKeyCode(2)
    private let escapeKeyCode = CGKeyCode(53)
    private let oneKeyCode = CGKeyCode(18)
    private let twoKeyCode = CGKeyCode(19)
    private let threeKeyCode = CGKeyCode(20)
    private let fourKeyCode = CGKeyCode(21)
    private let fiveKeyCode = CGKeyCode(23)
    private let sixKeyCode = CGKeyCode(22)
    private let xKeyCode = CGKeyCode(7)
    private let zKeyCode = CGKeyCode(6)
    private let eKeyCode = CGKeyCode(14)
    private let tabKeyCode = CGKeyCode(48)
    private let leftArrowKeyCode = CGKeyCode(123)
    private let rightArrowKeyCode = CGKeyCode(124)
    private let downArrowKeyCode = CGKeyCode(125)
    private let upArrowKeyCode = CGKeyCode(126)
    private let leftShiftEventFlagMask = UInt64(NX_DEVICELSHIFTKEYMASK)
    private let rightShiftEventFlagMask = UInt64(NX_DEVICERSHIFTKEYMASK)
    private let chordRPollInterval: TimeInterval = 0.001
    private let pendingRepeatRPollInterval: TimeInterval = 0.001
    private let repeatDispatchDelay: TimeInterval = 0.85
    private let repeatInputDrainDelay: TimeInterval = 0.35
    private let repeatDeadlineSettleNanoseconds: UInt64 = 150_000_000
    private let canvasClearDoubleTapWindow: TimeInterval = 0.75
    private let resolutionQueue = DispatchQueue(label: "com.trmd.syn.global-hotkey-resolution")
    private let resolutionQueueKey = DispatchSpecificKey<Void>()
    private let lifecycleLock = NSLock()
    private let snapshotLock = NSLock()
    private let canvasModeLock = NSLock()
    private let debugEventLogURL = GlobalHotkeyService.debugEventLogURLFromArguments()
    private let debugEventLogLock = NSLock()

    private var eventTaps: [CFMachPort] = []
    private var runLoopSources: [CFRunLoopSource] = []
    private var eventTapRunLoop: CFRunLoop?
    private var eventTapThread: Thread?
    private var eventMonitorTokens: [Any] = []
    private var isLeftShiftDown = false
    private var isRightShiftDown = false
    private var isRDown = false
    private var isCDown = false
    private var isDDown = false
    private var isXDown = false
    private var isZDown = false
    private var isTabDown = false
    private var isEDown = false
    private var shiftChordArmed = false
    private var shiftChordBeganAtNanoseconds: UInt64?
    private var chordTriggered = false
    private var nonShiftKeyPressedDuringChord = false
    private var rKeyParticipatedInChord = false
    private var chordRPollTimer: DispatchSourceTimer?
    private var chordRPollGeneration = 0
    private var pendingRepeatWorkItem: DispatchWorkItem?
    private var pendingRepeatPollTimer: DispatchSourceTimer?
    private var pendingRepeatGeneration = 0
    private var pendingRepeatDidDrainInput = false
    private var physicalRKeyStateOverride: Bool?
    private var lastCanvasDKeyDownAtNanoseconds: UInt64?
    private var lastKeyEventUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
    private var storedCanvasModeActive = false

    private var storedRegistrationSnapshot = GlobalHotkeyRegistrationSnapshot(
        eventHandlerStatus: nil,
        pickerStatus: nil,
        repeatStatus: nil
    )

    var registrationSnapshot: GlobalHotkeyRegistrationSnapshot {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return storedRegistrationSnapshot
    }

    private init() {
        resolutionQueue.setSpecific(key: resolutionQueueKey, value: ())
    }

    func start() {
        stop()

        guard AXIsProcessTrusted() else {
            setRegistrationSnapshot(GlobalHotkeyRegistrationSnapshot(
                eventHandlerStatus: Self.accessibilityRequiredStatus,
                pickerStatus: Self.accessibilityRequiredStatus,
                repeatStatus: Self.accessibilityRequiredStatus
            ))
            NSLog("Syn left/right Shift global shortcuts need Accessibility permission.")
            return
        }

        let startupSemaphore = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            self?.runEventTapThread(startupSemaphore: startupSemaphore)
            startupSemaphore.signal()
        }
        thread.name = "Syn Global Hotkey Event Tap"

        lifecycleLock.lock()
        eventTapThread = thread
        lifecycleLock.unlock()

        thread.start()
        _ = startupSemaphore.wait(timeout: .now() + 1.0)
        installSupplementalKeyMonitors()
    }

    func stop() {
        removeSupplementalKeyMonitors()

        syncOnResolutionQueue {
            cancelPendingRepeat()
            resetKeyState()
        }

        lifecycleLock.lock()
        let runLoop = eventTapRunLoop
        eventTapThread = nil
        lifecycleLock.unlock()

        if let runLoop {
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
        }
    }

    func handleKeyStateForTesting(leftShift: Bool, rightShift: Bool, r: Bool) {
        _ = syncOnResolutionQueue {
            handleKeyState(leftShift: leftShift, rightShift: rightShift, r: r)
        }
    }

    func handleKeyEventForTesting(leftShift: Bool, rightShift: Bool, r: Bool, keyCode: CGKeyCode, type: CGEventType) {
        _ = syncOnResolutionQueue {
            handleKeyState(leftShift: leftShift, rightShift: rightShift, r: r, keyCode: keyCode, type: type)
        }
    }

    func handleRawKeyEventForTesting(keyCode: CGKeyCode, type: CGEventType, eventFlagsRaw: UInt64) {
        _ = syncOnResolutionQueue {
            handleKeyEvent(keyCode: keyCode, type: type, eventFlags: CGEventFlags(rawValue: eventFlagsRaw))
        }
    }

    func hasPendingRepeatForTesting() -> Bool {
        syncOnResolutionQueue {
            pendingRepeatWorkItem != nil
        }
    }

    func firePendingRepeatForTesting() {
        syncOnResolutionQueue {
            guard pendingRepeatWorkItem != nil else {
                return
            }
            firePendingRepeatIfCurrent(generation: pendingRepeatGeneration, checkPhysicalRKey: false)
        }
    }

    func setCanvasModeActive(_ active: Bool) {
        canvasModeLock.lock()
        storedCanvasModeActive = active
        canvasModeLock.unlock()
    }

    func firePendingRepeatWithInputDrainForTesting() {
        syncOnResolutionQueue {
            guard pendingRepeatWorkItem != nil else {
                return
            }
            firePendingRepeatIfCurrent(generation: pendingRepeatGeneration, checkPhysicalRKey: true)
        }
    }

    func resetChordStateForTesting() {
        syncOnResolutionQueue {
            cancelPendingRepeat()
            physicalRKeyStateOverride = nil
            resetKeyState()
        }
    }

    func setPhysicalRKeyStateForTesting(_ isDown: Bool?) {
        syncOnResolutionQueue {
            physicalRKeyStateOverride = isDown
        }
    }

    private func runEventTapThread(startupSemaphore: DispatchSemaphore) {
        autoreleasepool {
            guard configureEventTapOnCurrentThread() else {
                return
            }
            startupSemaphore.signal()
            CFRunLoopRun()
            tearDownEventTapOnCurrentThread()
        }
    }

    private func configureEventTapOnCurrentThread() -> Bool {
        let currentRunLoop = CFRunLoopGetCurrent()

        let keyAndModifierEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let keyOnlyEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
            if service.handleEventTapCallback(type: type, event: event) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        guard let hidTap = createEventTap(
            location: .cghidEventTap,
            eventMask: CGEventMask(keyAndModifierEventMask),
            callback: callback
        ) else {
            setRegistrationSnapshot(GlobalHotkeyRegistrationSnapshot(
                eventHandlerStatus: Self.eventTapCreationFailedStatus,
                pickerStatus: Self.eventTapCreationFailedStatus,
                repeatStatus: Self.eventTapCreationFailedStatus
            ))
            NSLog("Syn failed to create left/right Shift global shortcut HID event tap.")
            return false
        }

        var taps = [hidTap.tap]
        var sources = [hidTap.source]

        if let sessionTap = createEventTap(
            location: .cgSessionEventTap,
            eventMask: CGEventMask(keyOnlyEventMask),
            callback: callback
        ) {
            taps.append(sessionTap.tap)
            sources.append(sessionTap.source)
        } else {
            NSLog("Syn could not create the supplemental session key tap; relying on HID shortcut events only.")
        }

        if let annotatedSessionTap = createEventTap(
            location: .cgAnnotatedSessionEventTap,
            eventMask: CGEventMask(keyOnlyEventMask),
            callback: callback
        ) {
            taps.append(annotatedSessionTap.tap)
            sources.append(annotatedSessionTap.source)
        } else {
            NSLog("Syn could not create the supplemental annotated-session key tap; relying on HID/session shortcut events only.")
        }

        lifecycleLock.lock()
        eventTaps = taps
        runLoopSources = sources
        eventTapRunLoop = currentRunLoop
        lifecycleLock.unlock()

        sources.forEach { CFRunLoopAddSource(currentRunLoop, $0, .commonModes) }
        taps.forEach { CGEvent.tapEnable(tap: $0, enable: true) }

        setRegistrationSnapshot(GlobalHotkeyRegistrationSnapshot(
            eventHandlerStatus: noErr,
            pickerStatus: noErr,
            repeatStatus: noErr
        ))
        return true
    }

    private func createEventTap(
        location: CGEventTapLocation,
        eventMask: CGEventMask,
        callback: @escaping CGEventTapCallBack
    ) -> (tap: CFMachPort, source: CFRunLoopSource)? {
        guard let tap = CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return nil
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return nil
        }

        return (tap, source)
    }

    private func tearDownEventTapOnCurrentThread() {
        lifecycleLock.lock()
        let taps = eventTaps
        let sources = runLoopSources
        let runLoop = eventTapRunLoop
        eventTaps = []
        runLoopSources = []
        eventTapRunLoop = nil
        lifecycleLock.unlock()

        taps.forEach { CGEvent.tapEnable(tap: $0, enable: false) }

        if let runLoop {
            sources.forEach { CFRunLoopRemoveSource(runLoop, $0, .commonModes) }
        }

        taps.forEach { CFMachPortInvalidate($0) }
    }

    private func handleEventTapCallback(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lifecycleLock.lock()
            let taps = eventTaps
            lifecycleLock.unlock()
            taps.forEach { CGEvent.tapEnable(tap: $0, enable: true) }
            return false
        }

        guard type == .keyDown || type == .keyUp || type == .flagsChanged else {
            return false
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let eventFlags = event.flags
        return syncOnResolutionQueue {
            handleKeyEvent(keyCode: keyCode, type: type, eventFlags: eventFlags)
        }
    }

    private func installSupplementalKeyMonitors() {
        let install = { [weak self] in
            guard let self, self.eventMonitorTokens.isEmpty else {
                return
            }

            let global = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                self?.handleSupplementalKeyEvent(event)
            }
            let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                self?.handleSupplementalKeyEvent(event)
                return event
            }

            eventMonitorTokens = [global, local].compactMap { $0 }
        }

        if Thread.isMainThread {
            install()
        } else {
            DispatchQueue.main.async(execute: install)
        }
    }

    private func removeSupplementalKeyMonitors() {
        let remove = { [weak self] in
            guard let self else {
                return
            }
            eventMonitorTokens.forEach { NSEvent.removeMonitor($0) }
            eventMonitorTokens = []
        }

        if Thread.isMainThread {
            remove()
        } else {
            DispatchQueue.main.async(execute: remove)
        }
    }

    private func handleSupplementalKeyEvent(_ event: NSEvent) {
        guard event.keyCode == rKeyCode else {
            return
        }

        let type: CGEventType
        switch event.type {
        case .keyDown:
            type = .keyDown
        case .keyUp:
            type = .keyUp
        default:
            return
        }

        let keyCode = CGKeyCode(event.keyCode)
        resolutionQueue.async { [weak self] in
            self?.recordDebugEvent("monitor key=\(keyCode) type=\(type.rawValue)")
            _ = self?.handleKeyEvent(keyCode: keyCode, type: type, eventFlags: nil)
        }
    }

    @discardableResult
    private func handleKeyEvent(keyCode: CGKeyCode, type: CGEventType, eventFlags: CGEventFlags? = nil) -> Bool {
        lastKeyEventUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds

        var leftShift = isLeftShiftDown
        var rightShift = isRightShiftDown
        var r = isRDown

        if let eventFlags, let shiftState = shiftState(from: eventFlags) {
            leftShift = shiftState.left
            rightShift = shiftState.right
        } else if keyCode == leftShiftKeyCode {
            if type == .keyDown {
                leftShift = true
            } else if type == .keyUp {
                leftShift = false
            } else if type == .flagsChanged {
                leftShift.toggle()
            }
        } else if keyCode == rightShiftKeyCode {
            if type == .keyDown {
                rightShift = true
            } else if type == .keyUp {
                rightShift = false
            } else if type == .flagsChanged {
                rightShift.toggle()
            }
        }

        if keyCode == rKeyCode {
            if type == .keyDown {
                r = true
            } else if type == .keyUp {
                r = false
            }
        }

        recordDebugEvent(
            "event key=\(keyCode) type=\(type.rawValue) flags=\(eventFlags?.rawValue ?? 0) left=\(leftShift) right=\(rightShift) r=\(r)"
        )
        return handleKeyState(leftShift: leftShift, rightShift: rightShift, r: r, keyCode: keyCode, type: type)
    }

    private func shiftState(from eventFlags: CGEventFlags) -> (left: Bool, right: Bool)? {
        let raw = eventFlags.rawValue
        let left = (raw & leftShiftEventFlagMask) != 0
        let right = (raw & rightShiftEventFlagMask) != 0
        if left || right || !eventFlags.contains(.maskShift) {
            return (left, right)
        }

        return nil
    }

    @discardableResult
    private func handleKeyState(
        leftShift: Bool,
        rightShift: Bool,
        r: Bool,
        keyCode: CGKeyCode? = nil,
        type: CGEventType? = nil
    ) -> Bool {
        let wasRDown = isRDown
        let wasBothShiftsDown = isLeftShiftDown && isRightShiftDown
        var resolvedR = r
        let now = DispatchTime.now().uptimeNanoseconds
        let bothShiftsDown = leftShift && rightShift
        let anyShiftDown = leftShift || rightShift
        let isShiftKey = keyCode == leftShiftKeyCode || keyCode == rightShiftKeyCode
        let isRKeyEvent = keyCode == rKeyCode && (type == .keyDown || type == .keyUp)
        let isNonShiftKeyDown = type == .keyDown
            && !isShiftKey

        if keyCode == dKeyCode, type == .keyUp {
            isDDown = false
        }
        if keyCode == cKeyCode, type == .keyUp {
            isCDown = false
        }
        if keyCode == xKeyCode, type == .keyUp { isXDown = false }
        if keyCode == zKeyCode, type == .keyUp { isZDown = false }
        if keyCode == tabKeyCode, type == .keyUp { isTabDown = false }
        if keyCode == eKeyCode, type == .keyUp { isEDown = false }

        let shouldSamplePhysicalR = pendingRepeatWorkItem != nil
            || shiftChordArmed
            || bothShiftsDown
            || wasBothShiftsDown
        if shouldSamplePhysicalR, rKeyIsPhysicallyDown() {
            if !resolvedR {
                recordDebugEvent("sample physical r")
            }
            resolvedR = true
        }

        if shouldSamplePhysicalR, resolvedR || wasRDown || isRKeyEvent {
            rKeyParticipatedInChord = true
        }

        isLeftShiftDown = leftShift
        isRightShiftDown = rightShift
        isRDown = resolvedR

        if handleCanvasShortcutIfNeeded(
            keyCode: keyCode,
            type: type,
            leftShift: leftShift,
            rightShift: rightShift,
            now: now
        ) {
            return true
        }

        if pendingRepeatWorkItem != nil, type == .flagsChanged, isShiftKey, anyShiftDown {
            cancelPendingRepeat()
        }

        if pendingRepeatWorkItem != nil, rKeyParticipatedInChord || resolvedR || isRKeyEvent {
            triggerPickerShortcut()
            return false
        }

        if pendingRepeatWorkItem != nil, isNonShiftKeyDown {
            cancelPendingRepeat()
            nonShiftKeyPressedDuringChord = true
            if keyCode == rKeyCode {
                triggerPickerShortcut()
            }
            return false
        }

        if bothShiftsDown, !shiftChordArmed, !chordTriggered {
            cancelPendingRepeat()
            scheduleChordRPoll()
            shiftChordArmed = true
            shiftChordBeganAtNanoseconds = now
            chordTriggered = false
            nonShiftKeyPressedDuringChord = false
            rKeyParticipatedInChord = resolvedR || wasRDown || isRKeyEvent
        }

        if shiftChordArmed, isRKeyEvent {
            nonShiftKeyPressedDuringChord = true
            rKeyParticipatedInChord = true
            triggerPickerShortcut()
            return false
        }

        if shiftChordArmed, isNonShiftKeyDown {
            nonShiftKeyPressedDuringChord = true
        }

        if shiftChordArmed, bothShiftsDown, resolvedR {
            rKeyParticipatedInChord = true
            triggerPickerShortcut()
            return false
        }

        if wasRDown {
            nonShiftKeyPressedDuringChord = true
            rKeyParticipatedInChord = true
        }

        if !shiftChordArmed, chordTriggered, !anyShiftDown {
            resetChordResolutionState()
        } else if shiftChordArmed, !anyShiftDown {
            if chordTriggered || nonShiftKeyPressedDuringChord {
                resetChordResolutionState()
            } else {
                schedulePendingRepeat()
                shiftChordArmed = false
                shiftChordBeganAtNanoseconds = nil
                chordTriggered = false
                nonShiftKeyPressedDuringChord = false
                rKeyParticipatedInChord = false
            }
        }
        return false
    }

    private func handleCanvasShortcutIfNeeded(
        keyCode: CGKeyCode?,
        type: CGEventType?,
        leftShift: Bool,
        rightShift: Bool,
        now: UInt64
    ) -> Bool {
        guard type == .keyDown, let keyCode else {
            return false
        }

        if keyCode == escapeKeyCode, isCanvasModeActive {
            cancelPendingRepeat()
            resetChordResolutionState()
            NSLog("Syn global shortcut pressed: Escape canvas exit")
            recordDebugEvent("action canvas-exit")
            onExitCanvasMode?()
            return true
        }

        guard rightShift, !leftShift else {
            return false
        }

        guard keyCode == cKeyCode || keyCode == eKeyCode || isCanvasModeActive else {
            return false
        }

        if keyCode == eKeyCode {
            guard !isEDown else { return true }
            isEDown = true
            cancelPendingRepeat()
            resetChordResolutionState()
            NSLog("Syn global shortcut pressed: Right Shift + E element picker")
            recordDebugEvent("action element-picker-toggle")
            onToggleElementPicker?()
            return true
        }

        switch keyCode {
        case cKeyCode:
            guard !isCDown else {
                return true
            }
            isCDown = true
            cancelPendingRepeat()
            resetChordResolutionState()
            NSLog("Syn global shortcut pressed: \(Self.canvasDescription)")
            recordDebugEvent("action canvas-toggle")
            onToggleCanvasMode?()
            return true
        case oneKeyCode:
            triggerCanvasToolShortcut(.arrow)
            return true
        case twoKeyCode:
            triggerCanvasToolShortcut(.rectangle)
            return true
        case threeKeyCode:
            triggerCanvasToolShortcut(.ellipse)
            return true
        case fourKeyCode:
            triggerCanvasToolShortcut(.text)
            return true
        case fiveKeyCode:
            triggerCanvasToolShortcut(.line)
            return true
        case sixKeyCode:
            triggerCanvasToolShortcut(.pen)
            return true
        case xKeyCode:
            guard !isXDown else { return true }
            isXDown = true
            recordDebugEvent("action canvas-delete-selected")
            onDeleteSelectedAnnotation?()
            return true
        case zKeyCode:
            guard !isZDown else { return true }
            isZDown = true
            recordDebugEvent("action canvas-undo")
            onUndoAnnotation?()
            return true
        case tabKeyCode:
            guard !isTabDown else { return true }
            isTabDown = true
            recordDebugEvent("action canvas-cycle-selection")
            onCycleAnnotationSelection?()
            return true
        case leftArrowKeyCode:
            onNudgeSelectedAnnotation?(-8, 0)
            return true
        case rightArrowKeyCode:
            onNudgeSelectedAnnotation?(8, 0)
            return true
        case upArrowKeyCode:
            onNudgeSelectedAnnotation?(0, 8)
            return true
        case downArrowKeyCode:
            onNudgeSelectedAnnotation?(0, -8)
            return true
        case dKeyCode:
            guard !isDDown else {
                return true
            }
            isDDown = true
            if let last = lastCanvasDKeyDownAtNanoseconds,
               now >= last,
               TimeInterval(now - last) / 1_000_000_000 <= canvasClearDoubleTapWindow {
                lastCanvasDKeyDownAtNanoseconds = nil
                cancelPendingRepeat()
                resetChordResolutionState()
                NSLog("Syn global shortcut pressed: \(Self.canvasClearDescription)")
                recordDebugEvent("action canvas-clear")
                onClearCanvas?()
            } else {
                lastCanvasDKeyDownAtNanoseconds = now
                recordDebugEvent("pending canvas-clear")
            }
            return true
        default:
            return false
        }
    }

    private var isCanvasModeActive: Bool {
        canvasModeLock.lock()
        defer { canvasModeLock.unlock() }
        return storedCanvasModeActive
    }

    private func triggerCanvasToolShortcut(_ tool: AnnotationTool) {
        cancelPendingRepeat()
        resetChordResolutionState()
        NSLog("Syn global shortcut pressed: Right Shift + \(tool.shortcutLabel ?? tool.title)")
        recordDebugEvent("action canvas-tool-\(tool.rawValue)")
        onSelectCanvasTool?(tool)
    }

    private func triggerPickerShortcut() {
        guard !chordTriggered else {
            return
        }

        cancelPendingRepeat()
        cancelChordRPoll()
        chordTriggered = true
        nonShiftKeyPressedDuringChord = true
        shiftChordArmed = false
        shiftChordBeganAtNanoseconds = nil
        rKeyParticipatedInChord = true
        NSLog("Syn global shortcut pressed: \(Self.pickerDescription)")
        recordDebugEvent("action picker")
        onOpenPicker?()
    }

    private func schedulePendingRepeat() {
        cancelPendingRepeat()
        cancelChordRPoll()

        pendingRepeatGeneration += 1
        pendingRepeatDidDrainInput = false
        let generation = pendingRepeatGeneration
        recordDebugEvent("pending repeat generation=\(generation)")
        schedulePendingRepeatRPoll(generation: generation)
        schedulePendingRepeatFire(generation: generation, delay: repeatDispatchDelay)
    }

    private func schedulePendingRepeatFire(generation: Int, delay: TimeInterval) {
        let item = DispatchWorkItem { [weak self] in
            self?.firePendingRepeatIfCurrent(generation: generation, checkPhysicalRKey: true)
        }
        pendingRepeatWorkItem = item
        resolutionQueue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func scheduleChordRPoll() {
        cancelChordRPoll()
        chordRPollGeneration += 1
        scheduleChordRPoll(generation: chordRPollGeneration)
    }

    private func scheduleChordRPoll(generation: Int) {
        let timer = DispatchSource.makeTimerSource(queue: resolutionQueue)
        timer.schedule(
            deadline: .now() + chordRPollInterval,
            repeating: chordRPollInterval,
            leeway: .nanoseconds(0)
        )
        timer.setEventHandler { [weak self] in
            self?.pollArmedChordForR(generation: generation)
        }
        chordRPollTimer = timer
        timer.resume()
    }

    private func pollArmedChordForR(generation: Int) {
        guard chordRPollGeneration == generation else {
            return
        }
        guard shiftChordArmed, !chordTriggered else {
            cancelChordRPoll()
            return
        }

        if rKeyIsPhysicallyDown() {
            recordDebugEvent("poll chord r generation=\(generation)")
            triggerPickerShortcut()
            return
        }
    }

    private func cancelChordRPoll() {
        chordRPollTimer?.cancel()
        chordRPollTimer = nil
        chordRPollGeneration += 1
    }

    private func cancelPendingRepeat() {
        pendingRepeatWorkItem?.cancel()
        pendingRepeatWorkItem = nil
        pendingRepeatDidDrainInput = false
        cancelPendingRepeatPoll()
        pendingRepeatGeneration += 1
    }

    private func schedulePendingRepeatRPoll(generation: Int) {
        cancelPendingRepeatPoll()
        let timer = DispatchSource.makeTimerSource(queue: resolutionQueue)
        timer.schedule(
            deadline: .now() + pendingRepeatRPollInterval,
            repeating: pendingRepeatRPollInterval,
            leeway: .nanoseconds(0)
        )
        timer.setEventHandler { [weak self] in
            self?.pollPendingRepeatForR(generation: generation)
        }
        pendingRepeatPollTimer = timer
        timer.resume()
    }

    private func pollPendingRepeatForR(generation: Int) {
        guard pendingRepeatGeneration == generation else {
            return
        }
        guard pendingRepeatWorkItem != nil else {
            cancelPendingRepeatPoll()
            return
        }

        if rKeyIsPhysicallyDown() {
            recordDebugEvent("poll r generation=\(generation)")
            triggerPickerShortcut()
            return
        }
    }

    private func firePendingRepeatIfCurrent(generation: Int, checkPhysicalRKey: Bool) {
        guard pendingRepeatGeneration == generation, pendingRepeatWorkItem != nil else {
            return
        }

        if rKeyParticipatedInChord {
            triggerPickerShortcut()
            return
        }

        if checkPhysicalRKey, rKeyIsPhysicallyDown() {
            triggerPickerShortcut()
            return
        }

        if checkPhysicalRKey {
            if !pendingRepeatDidDrainInput {
                pendingRepeatDidDrainInput = true
                recordDebugEvent("pending repeat input drain generation=\(generation)")
                schedulePendingRepeatFire(generation: generation, delay: repeatInputDrainDelay)
                return
            }

            let now = DispatchTime.now().uptimeNanoseconds
            let keyEventAge = now >= lastKeyEventUptimeNanoseconds
                ? now - lastKeyEventUptimeNanoseconds
                : repeatDeadlineSettleNanoseconds

            if keyEventAge < repeatDeadlineSettleNanoseconds {
                let remainingNanoseconds = repeatDeadlineSettleNanoseconds - keyEventAge
                let remainingDelay = TimeInterval(remainingNanoseconds) / 1_000_000_000
                recordDebugEvent("pending repeat settle generation=\(generation)")
                schedulePendingRepeatFire(generation: generation, delay: remainingDelay)
                return
            }
        }

        pendingRepeatWorkItem = nil
        cancelPendingRepeatPoll()
        chordTriggered = true
        NSLog("Syn global shortcut pressed: \(Self.repeatDescription)")
        recordDebugEvent("action repeat generation=\(generation)")
        onRepeatLastCapture?()
        resetChordResolutionState()
    }

    private func cancelPendingRepeatPoll() {
        pendingRepeatPollTimer?.cancel()
        pendingRepeatPollTimer = nil
    }

    private func resetChordResolutionState() {
        cancelChordRPoll()
        shiftChordArmed = false
        shiftChordBeganAtNanoseconds = nil
        chordTriggered = false
        nonShiftKeyPressedDuringChord = false
        rKeyParticipatedInChord = false
    }

    private func resetKeyState() {
        isLeftShiftDown = false
        isRightShiftDown = false
        isRDown = false
        isCDown = false
        isDDown = false
        lastCanvasDKeyDownAtNanoseconds = nil
        resetChordResolutionState()
    }

    private func rKeyIsPhysicallyDown() -> Bool {
        if let physicalRKeyStateOverride {
            return physicalRKeyStateOverride
        }

        return CGEventSource.keyState(.combinedSessionState, key: rKeyCode)
            || CGEventSource.keyState(.hidSystemState, key: rKeyCode)
    }

    private func recordDebugEvent(_ line: String) {
        guard let debugEventLogURL else {
            return
        }

        debugEventLogLock.lock()
        defer { debugEventLogLock.unlock() }

        do {
            try FileManager.default.createDirectory(
                at: debugEventLogURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = "\(line)\n".data(using: .utf8) ?? Data()
            if FileManager.default.fileExists(atPath: debugEventLogURL.path) {
                let handle = try FileHandle(forWritingTo: debugEventLogURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: debugEventLogURL, options: .atomic)
            }
        } catch {
            NSLog("Syn failed to write hotkey event log: \(error.localizedDescription)")
        }
    }

    private static func debugEventLogURLFromArguments() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--syn-hotkey-event-log"),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        return URL(fileURLWithPath: arguments[index + 1])
    }

    private func setRegistrationSnapshot(_ snapshot: GlobalHotkeyRegistrationSnapshot) {
        snapshotLock.lock()
        storedRegistrationSnapshot = snapshot
        snapshotLock.unlock()
    }

    private func syncOnResolutionQueue<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: resolutionQueueKey) != nil {
            return work()
        } else {
            return resolutionQueue.sync(execute: work)
        }
    }
}
