# Authoritative mockups

High-fidelity ChatGPT-generated mockups that are the **source of truth** for the
screens listed below. Where these disagree with the JSX prototype in
`design/design-system/`, **these win.** The design-system tokens/primitives in
`Syn/Support/DesignSystem.swift` still provide the underlying vocabulary
(colors, type, spacing); the mockups govern layout, composition, and per-screen
treatment.

| File | Screen | Implements |
|------|--------|-----------|
| `overview-window.png` | **Overview window** (main) | sidebar (Capture + Previous Recordings w/ status badges, selected row) · detail: title + Ready badge, top-right Copy Packet / Open Folder / Reveal Zip / ⋯, video preview, Overview · Summary · Files · Included files · Paths |
| `recording-hud.png` | **Recording HUD** (studio) | frosted pill: red live dot · mode + mono timer · green mic meter · rose Canvas (palette) toggle · pause · discard (trash) · red Stop |
| `recording-hud-in-context.png` | **Recording HUD** (floating over Overview) | same HUD, shown in situ over a blurred window |
| `canvas-mode.png` | **Canvas Mode** | code editor with ink annotations · HUD on top (Canvas active) · "Syn — Canvas Mode" toolbar (cursor · pen · line · rect · ellipse · eraser · close) · shortcut chips |
| `region-overlay.png` | **Region-selection overlay** | dim scrim · rose selection stroke + corner handles · `960 × 540` chip · "Packet ready" completion toast · Confirm (Return) / Cancel (Esc) bar |
| `capture-picker.png` | **Capture picker** sheet | "Start Recording" · Displays / Windows / Targeted · Select Window = "Last" w/ rose ring · mic-ready footer · help |

## What's authoritative: FEEL, not color

The mockups govern **feel** — layout, composition, hierarchy, spacing, which
sections/content appear, and overall polish. **Color comes from the design
system** (`Syn/Support/DesignSystem.swift`, the `#EC6579` rose token set), not
sampled from the mockups (generation drift makes the mockup hues slightly off).

Apply design-system color to these layouts:

- **Live dot** = rose `rec` token `#EC6579` (keep the brand; the mockup's brighter
  coral was just drift).
- **Stop** = `destructive` red. The mockups DO inform its *form*: a solid filled
  red button (a composition choice we take from the mockup).
- **Canvas toggle** = faint rose tint when active; rose stays a whisper
  (active-tool tint, last-mode ring, selection accent).
- **Selection** = faint neutral wash (`cellSelected`), not rose.
- Mic meter, badges, etc. use the design-system semantic tokens.

## Not yet covered by a mockup

Settings, the menu-bar dropdown, the Canvas toolbar in isolation, and the app
icon — for these, fall back to `design/design-system/` (the JSX prototype).
