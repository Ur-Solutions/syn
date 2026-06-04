import CoreGraphics
import Foundation
import IOKit.hidsystem

let leftShiftKey = CGKeyCode(56)
let rightShiftKey = CGKeyCode(60)
let rKey = CGKeyCode(15)

let shiftMask = UInt64(NX_SHIFTMASK)
let leftShiftMask = UInt64(NX_DEVICELSHIFTKEYMASK)
let rightShiftMask = UInt64(NX_DEVICERSHIFTKEYMASK)
let leftShiftFlags = shiftMask | leftShiftMask
let rightShiftFlags = shiftMask | rightShiftMask
let bothShiftFlags = shiftMask | leftShiftMask | rightShiftMask

let mode = CommandLine.arguments.dropFirst().first ?? "suffix-r"
let source = CGEventSource(stateID: .hidSystemState)
source?.localEventsSuppressionInterval = 0

func post(
    _ key: CGKeyCode,
    down: Bool,
    flags: UInt64,
    tap: CGEventTapLocation = .cghidEventTap,
    delayMicros: useconds_t = 60_000
) {
    guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else {
        fputs("Could not create CGEvent for key \(key).\n", stderr)
        exit(2)
    }
    event.flags = CGEventFlags(rawValue: flags)
    event.post(tap: tap)
    usleep(delayMicros)
}

switch mode {
case "suffix-r":
    post(leftShiftKey, down: true, flags: leftShiftFlags)
    post(rightShiftKey, down: true, flags: bothShiftFlags)
    post(rightShiftKey, down: false, flags: leftShiftFlags)
    post(leftShiftKey, down: false, flags: 0, delayMicros: 250_000)
    post(rKey, down: true, flags: 0)
    post(rKey, down: false, flags: 0)
case "medium-suffix-r":
    post(leftShiftKey, down: true, flags: leftShiftFlags)
    post(rightShiftKey, down: true, flags: bothShiftFlags)
    post(rightShiftKey, down: false, flags: leftShiftFlags)
    post(leftShiftKey, down: false, flags: 0, delayMicros: 950_000)
    post(rKey, down: true, flags: 0)
    post(rKey, down: false, flags: 0)
case "slow-suffix-r":
    post(leftShiftKey, down: true, flags: leftShiftFlags)
    post(rightShiftKey, down: true, flags: bothShiftFlags)
    post(rightShiftKey, down: false, flags: leftShiftFlags)
    post(leftShiftKey, down: false, flags: 0, delayMicros: 2_250_000)
    post(rKey, down: true, flags: 0)
    post(rKey, down: false, flags: 0)
case "held-r":
    post(leftShiftKey, down: true, flags: leftShiftFlags)
    post(rightShiftKey, down: true, flags: bothShiftFlags, delayMicros: 250_000)
    post(rKey, down: true, flags: bothShiftFlags)
    post(rKey, down: false, flags: bothShiftFlags)
    post(rightShiftKey, down: false, flags: leftShiftFlags)
    post(leftShiftKey, down: false, flags: 0)
case "fast-held-r":
    post(leftShiftKey, down: true, flags: leftShiftFlags)
    post(rightShiftKey, down: true, flags: bothShiftFlags, delayMicros: 80_000)
    post(rKey, down: true, flags: bothShiftFlags, delayMicros: 1_000)
    post(rKey, down: false, flags: bothShiftFlags)
    post(rightShiftKey, down: false, flags: leftShiftFlags)
    post(leftShiftKey, down: false, flags: 0)
case "long-held-r":
    post(leftShiftKey, down: true, flags: leftShiftFlags)
    post(rightShiftKey, down: true, flags: bothShiftFlags, delayMicros: 700_000)
    post(rKey, down: true, flags: bothShiftFlags, delayMicros: 15_000)
    post(rKey, down: false, flags: bothShiftFlags)
    post(rightShiftKey, down: false, flags: leftShiftFlags)
    post(leftShiftKey, down: false, flags: 0)
case "repeat":
    post(leftShiftKey, down: true, flags: leftShiftFlags)
    post(rightShiftKey, down: true, flags: bothShiftFlags, delayMicros: 700_000)
    post(rightShiftKey, down: false, flags: leftShiftFlags)
    post(leftShiftKey, down: false, flags: 0)
default:
    fputs("usage: swift script/post_syn_hotkey_sequence.swift [suffix-r|medium-suffix-r|slow-suffix-r|held-r|fast-held-r|long-held-r|repeat]\n", stderr)
    exit(2)
}
