//
//  DesignSystem.swift
//  Syn
//
//  Native SwiftUI translation of the Syn design system handoff
//  (design/design-system/, Claude Design). Light is the hero; every token
//  is a dynamic light/dark pair. Restraint is the rule: warm-neutral by
//  default, rose-coral only in small moments (live dot, active tool, one
//  tinted primary per view). See docs/DESIGN_SYSTEM.md.
//

import SwiftUI
import AppKit

// MARK: - Color helpers

extension NSColor {
    /// Build a color from a "RRGGBB" / "#RRGGBB" hex string with optional alpha.
    convenience init(hex: String, alpha: CGFloat = 1) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = CGFloat((v & 0xFF0000) >> 16) / 255
        let g = CGFloat((v & 0x00FF00) >> 8) / 255
        let b = CGFloat(v & 0x0000FF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    /// A dynamic color that resolves to `light` in Aqua and `dark` in Dark Aqua.
    static func synDynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

private func dyn(_ light: NSColor, _ dark: NSColor) -> Color {
    Color(nsColor: .synDynamic(light, dark))
}
private func hx(_ hex: String, _ a: CGFloat = 1) -> NSColor { NSColor(hex: hex, alpha: a) }

// MARK: - Color tokens

/// Named color tokens. Mirrors the `--token` set in the design's index.html.
enum SynColor {
    // Neutrals — the whole interface
    static let canvas         = dyn(hx("F5F4F1"), hx("1C1C1E"))
    static let sidebar        = dyn(hx("F1F0EC"), hx("232325"))
    static let card           = dyn(hx("FFFFFF"), hx("2A2A2C"))
    static let surface2       = dyn(hx("F1F0EC"), hx("242426"))
    static let surface3       = dyn(hx("ECEBE7"), hx("38383A"))
    static let selected       = dyn(hx("ECEBE7"), hx("38383A"))
    /// Whisper-faint neutral wash for the selected list cell (final design call).
    static let cellSelected   = dyn(hx("3C3C43", 0.022), hx("FFFFFF", 0.04))
    static let hairline       = dyn(hx("E7E5E0"), hx("38383A"))
    static let hairlineStrong = dyn(hx("DCDAD3"), hx("48484A"))
    static let text1          = dyn(hx("1C1C1E"), hx("F5F5F7"))
    static let text2          = dyn(hx("6E6E73"), hx("A1A1A6"))
    static let text3          = dyn(hx("9B9BA0"), hx("6E6E73"))

    // Accent — rose-coral, a whisper
    static let accent         = dyn(hx("EC6579"), hx("F0768A"))
    static let accentHover    = dyn(hx("E24B62"), hx("EC6579"))
    static let accentPressed  = dyn(hx("D63850"), hx("E24B62"))
    static let accentTint     = dyn(hx("FDEBEE"), hx("36191E"))
    static let accentTint2    = dyn(hx("FEF6F8"), hx("2A1418"))
    static let accentRing     = dyn(hx("F099A6"), hx("7A3742"))
    static let accentDeep     = dyn(hx("D63850"), hx("F099A6"))
    static let onAccent       = dyn(hx("FFFFFF"), hx("2A0E12"))

    // Semantic state — small dots & glyphs only
    static let rec            = dyn(hx("EC6579"), hx("F0768A"))
    static let paused         = dyn(hx("F5A623"), hx("FFD60A"))
    static let processing     = dyn(hx("2E8BFF"), hx("0A84FF"))
    static let success        = dyn(hx("34C759"), hx("30D158"))
    static let warning        = dyn(hx("F5A623"), hx("FF9F0A"))
    static let destructive    = dyn(hx("E5342B"), hx("FF453A"))

    static let recTint        = dyn(hx("FDEBEE"), hx("36191E"))
    static let pausedTint     = dyn(hx("FDF1DF"), hx("3A3010"))
    static let processingTint = dyn(hx("E7F0FF"), hx("102A44"))
    static let successTint    = dyn(hx("E6F7EB"), hx("11331C"))
    static let warningTint    = dyn(hx("FDF1DF"), hx("3A2810"))

    // Key caps
    static let keycapBg       = dyn(hx("FFFFFF"), hx("3A3A3C"))
    static let keycapEdge     = dyn(hx("DCDAD3"), hx("545456"))
    static let keycapText     = dyn(hx("3A3A3C"), hx("E7E7EA"))
    static let keycapShadow   = dyn(hx("000000", 0.09), hx("000000", 0.5))

    // Overlays / floating surfaces
    static let scrim          = dyn(hx("28282A", 0.16), hx("000000", 0.45))
    static let focusRing      = dyn(hx("F099A6", 0.72), hx("F0768A", 0.6))
    /// Solid fallback for the frosted material panels (prefer `.regularMaterial`).
    static let material       = dyn(hx("FAF9F7", 0.72), hx("28282A", 0.66))
    static let materialBorder = dyn(hx("FFFFFF", 0.7), hx("FFFFFF", 0.08))

    // Annotation ink + legibility halo
    static let ink            = dyn(hx("EC6579"), hx("F0768A"))
    static let inkHalo        = dyn(hx("FFFFFF", 0.95), hx("0A0A0C", 0.92))
}

// MARK: - Spacing, radii, motion

/// 4 / 8pt spacing scale.
enum SynSpace {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s10: CGFloat = 40
}

enum SynRadius {
    static let sm: CGFloat = 6    // chips, dots, small controls
    static let md: CGFloat = 10   // buttons, cards, cells
    static let lg: CGFloat = 14   // sheets, HUD, panels
    static let xl: CGFloat = 16   // large panels
    static let pill: CGFloat = 999
}

enum SynMotion {
    static let standard = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.22)
    static let out      = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.22)
    static let spring   = Animation.spring(response: 0.3, dampingFraction: 0.72)
}

// MARK: - Typography

/// Type scale from the design tokens (px → pt, with letter-spacing in points).
enum SynFont {
    case largeTitle, title2, title3, headline, body, subhead, footnote, caption

    private var spec: (size: CGFloat, weight: Font.Weight, lsEm: CGFloat, caps: Bool) {
        switch self {
        case .largeTitle: return (26,   .bold,     -0.02,  false)
        case .title2:     return (20,   .semibold, -0.02,  false)
        case .title3:     return (17,   .semibold, -0.01,  false)
        case .headline:   return (14,   .semibold, -0.01,  false)
        case .body:       return (13,   .regular,  -0.005, false)
        case .subhead:    return (12,   .regular,   0,     false)
        case .footnote:   return (11,   .medium,    0.01,  false)
        case .caption:    return (10.5, .semibold,  0.06,  true)
        }
    }

    var font: Font { .system(size: spec.size, weight: spec.weight) }
    /// Letter-spacing converted from em to points for `.tracking(_:)`.
    var tracking: CGFloat { spec.lsEm * spec.size }
    var isUppercased: Bool { spec.caps }

    /// Monospaced numerals / readouts (timers, durations, dimensions).
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Applies a design type style (font + tracking; uppercases eyebrows).
    func synFont(_ style: SynFont) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .textCase(style.isUppercased ? .uppercase : nil)
    }
}

// MARK: - Elevation

extension View {
    /// Soft, layered elevation matching the design's shadow scale.
    @ViewBuilder
    func synShadow(_ level: Int) -> some View {
        switch level {
        case 1: self.shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
        case 2: self
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
        case 3: self
                .shadow(color: .black.opacity(0.07), radius: 8, y: 4)
                .shadow(color: .black.opacity(0.10), radius: 40, y: 18)
        default: self // floating
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
            .shadow(color: .black.opacity(0.14), radius: 48, y: 20)
        }
    }
}

// MARK: - Card

extension View {
    /// Standard data-surface card: white fill, hairline border, soft shadow.
    func synCard(padding: CGFloat = SynSpace.s4, radius: CGFloat = SynRadius.lg, float: Bool = false) -> some View {
        self
            .padding(padding)
            .background(SynColor.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(SynColor.hairline, lineWidth: 1)
            )
            .synShadow(float ? 2 : 1)
    }
}

// MARK: - Status

enum SynState {
    case recording, success, processing, warning, error, paused, idle

    var color: Color {
        switch self {
        case .recording: return SynColor.rec
        case .success:   return SynColor.success
        case .processing: return SynColor.processing
        case .warning, .paused: return SynColor.warning
        case .error:     return SynColor.destructive
        case .idle:      return SynColor.text3
        }
    }
}

/// A small state dot. Pulses for live/processing states.
struct SynStatusDot: View {
    var state: SynState = .idle
    var pulse: Bool = false
    var size: CGFloat = 8
    @State private var on = false

    var body: some View {
        Circle()
            .fill(state.color)
            .frame(width: size, height: size)
            .opacity(pulse ? (on ? 1 : 0.35) : 1)
            .animation(pulse ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: on)
            .onAppear { if pulse { on = true } }
    }
}

/// A neutral status pill: dot/glyph + gray label. Status by dot+text, never color alone.
struct SynStatusBadge: View {
    var state: SynState = .idle
    var systemImage: String? = nil
    var pulse: Bool = false
    var label: String

    var body: some View {
        HStack(spacing: SynSpace.s1 + 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(state.color)
            } else {
                SynStatusDot(state: state, pulse: pulse, size: 7)
            }
            Text(label).synFont(.footnote).foregroundStyle(SynColor.text2)
        }
        .padding(.vertical, 3)
        .padding(.leading, 8)
        .padding(.trailing, 9)
        .background(SynColor.surface2, in: Capsule())
        .overlay(Capsule().strokeBorder(SynColor.hairline, lineWidth: 1))
    }
}

// MARK: - Key caps

/// A single keyboard cap; `side` shows a tiny "L"/"R" tag (e.g. Left ⇧ vs Right ⇧).
struct SynKeyCap: View {
    var label: String
    var side: String?
    var wide: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if let side {
                Text(side)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(SynColor.text3)
            }
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(SynColor.keycapText)
        }
        .frame(minWidth: wide ? nil : 21, minHeight: 21)
        .padding(.horizontal, wide ? 8 : 5)
        .background(SynColor.keycapBg, in: RoundedRectangle(cornerRadius: SynRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SynRadius.sm, style: .continuous)
                .strokeBorder(SynColor.keycapEdge, lineWidth: 1)
        )
        .shadow(color: SynColor.keycapShadow, radius: 0, y: 1)
    }
}

// MARK: - Button styles

/// Primary action: a single, subtle rose-tinted button (never a saturated fill).
struct SynPrimaryButtonStyle: ButtonStyle {
    var size: ControlSize = .regular
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .font(.system(size: size == .small ? 12 : 13, weight: .medium))
            .tracking(-0.1)
            .foregroundStyle(SynColor.accentDeep)
            .padding(.horizontal, size == .small ? 11 : 14)
            .padding(.vertical, size == .small ? 5 : 7)
            .background(SynColor.accentTint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(SynColor.accentRing, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .contentShape(Rectangle())
    }
}

/// Secondary: neutral light pill.
struct SynSecondaryButtonStyle: ButtonStyle {
    var size: ControlSize = .regular
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .font(.system(size: size == .small ? 12 : 13, weight: .medium))
            .tracking(-0.1)
            .foregroundStyle(SynColor.text1)
            .padding(.horizontal, size == .small ? 11 : 14)
            .padding(.vertical, size == .small ? 5 : 7)
            .background(configuration.isPressed ? SynColor.selected : SynColor.card,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(SynColor.hairlineStrong, lineWidth: 1)
            )
            .synShadow(1)
            .contentShape(Rectangle())
    }
}

/// Destructive: a neutral button with a red glyph/label (rare, reserved).
struct SynDestructiveButtonStyle: ButtonStyle {
    var size: ControlSize = .regular
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .font(.system(size: size == .small ? 12 : 13, weight: .semibold))
            .tracking(-0.1)
            .foregroundStyle(SynColor.destructive)
            .padding(.horizontal, size == .small ? 11 : 14)
            .padding(.vertical, size == .small ? 5 : 7)
            .background(configuration.isPressed ? SynColor.selected : SynColor.card,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(SynColor.hairlineStrong, lineWidth: 1)
            )
            .synShadow(1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == SynPrimaryButtonStyle {
    static var synPrimary: SynPrimaryButtonStyle { .init() }
    static func synPrimary(_ size: ControlSize) -> SynPrimaryButtonStyle { .init(size: size) }
}
extension ButtonStyle where Self == SynSecondaryButtonStyle {
    static var synSecondary: SynSecondaryButtonStyle { .init() }
    static func synSecondary(_ size: ControlSize) -> SynSecondaryButtonStyle { .init(size: size) }
}
extension ButtonStyle where Self == SynDestructiveButtonStyle {
    static var synDestructive: SynDestructiveButtonStyle { .init() }
}
