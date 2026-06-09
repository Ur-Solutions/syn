# Syn Design System

The Syn visual identity and component system, designed in **Claude Design**
(claude.ai/design) after an iterative brief, and handed off here for native
implementation.

## Source

- **Claude Design handoff:** `https://api.anthropic.com/v1/design/h/OcxgVJEUmt18fg3Un96Eqw?open_file=index.html`
  (the URL serves the whole project as a gzip bundle, regardless of `open_file`).
- **Local bundle (reference, do not edit):** [`design/design-system/`](../design/design-system)
  - `README.md` — handoff notes from Claude Design.
  - `chats/` — the full design conversation (where the intent lives).
  - `project/` — the HTML/JSX prototype: `index.html` (tokens + shell),
    `tokens.jsx`, `primitives.jsx`, `foundations.jsx`, `gallery.jsx`,
    `screens1.jsx`, `screens2.jsx`, `icons.jsx`, `app.jsx`.
- **Earlier exploration:** [`design/syn-color-lab.html`](../design/syn-color-lab) — the
  interactive accent picker used to land on the rose-coral accent.

The prototype is the source of truth for *visual output*; we recreate it natively
in SwiftUI rather than copying its structure.

## Authoritative mockups (precedence: these win)

High-fidelity ChatGPT mockups in [`design/mockups/`](../design/mockups) are the
**source of truth** for the screens they cover. Where they disagree with the JSX
prototype, the mockups win; the tokens/primitives still supply the vocabulary.

- `overview-window.png` — Overview window
- `recording-hud.png` / `recording-hud-in-context.png` — Recording HUD
- `canvas-mode.png` — Canvas Mode (HUD + toolbar + annotations)
- `region-overlay.png` — Region-selection overlay + completion toast
- `capture-picker.png` — Capture picker sheet

The mockups are authoritative for **feel** (layout, composition, hierarchy,
polish); **color comes from the design-system tokens**, not the mockups. So the
live dot stays the rose `rec` token, and where the mockup shows a *solid red Stop
button* that's a form choice rendered with the `destructive` token. See
[`design/mockups/README.md`](../design/mockups/README.md). Not yet mocked:
Settings, menu-bar dropdown, Canvas toolbar in isolation, app icon → use the JSX
prototype for those.

## Direction (one line)

A calm, warm-neutral, **light-first** macOS app in the spirit of Wispr Flow /
Willow — near-monochrome by default, with **rose-coral used only as a whisper**
(the live dot, the active tool, one subtly-tinted primary per view). Restraint is
the rule; red is reserved for destructive/error.

## Tokens

Authoritative values live in `design/design-system/project/index.html` (`:root` +
`.theme-light` / `.theme-dark`) and are translated to SwiftUI in
[`Syn/Support/DesignSystem.swift`](../Syn/Support/DesignSystem.swift).

| Group | Light highlights |
|------|------|
| Neutrals | canvas `#F5F4F1` · sidebar `#F1F0EC` · card `#FFFFFF` · selected `#ECEBE7` · hairline `#E7E5E0` · text `#1C1C1E` / `#6E6E73` / `#9B9BA0` |
| Accent (rose) | accent `#EC6579` · hover `#E24B62` · pressed/deep `#D63850` · tint `#FDEBEE` · ring `#F099A6` |
| Semantic (dots only) | rec = accent · success `#34C759` · processing `#2E8BFF` · warning/paused `#F5A623` · destructive `#E5342B` |
| Type | SF Pro scale 26/20/17/14/13/12/11/10.5; SF Mono for timers/durations/dimensions |
| Space | 4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 |
| Radii | sm 6 · md 10 · lg 14 · xl 16 · pill |
| Selection | whisper-faint neutral wash (`rgba(60,60,67,0.022)` light) — **not** rose |

Every token is a dynamic light/dark pair. Light is the showcase; dark adapts.

## Components (`primitives.jsx` → SwiftUI)

Button (primary subtle-rose / secondary neutral / tertiary / destructive-red-glyph),
IconButton, ToolButton, KeyCap + KeyChord (distinguishes Left ⇧ vs Right ⇧),
StatusDot, StatusBadge, Card, packet ListCell (hero), MicMeter, Switch,
ProgressSteps, SecureKeyField, Select, TrafficLights, AnnotationSelection,
CaptureModeCard, MenuRow, ProviderCard, PermissionCard, EmptyState, CompletionMoment.

## Screens (`screens1.jsx` / `screens2.jsx`)

Menu-bar dropdown (idle + recording) · Capture picker sheet (7 modes, 3 sections) ·
Recording HUD (recording / canvas-on / processing / completion) · Canvas Mode +
floating toolbar · Region-selection overlay · Overview window (sidebar + packet
detail + trim scrubber + packet contents) · Settings (tabbed cards) · App icon +
menu-bar glyph states · Dark-mode check.

## Implementation status

- [x] Reference bundle saved (`design/design-system/`)
- [x] **Foundation** — tokens, type scale, spacing, radii, shadows, and core
      primitives (status dots/badges, key caps, card, button styles) →
      `Syn/Support/DesignSystem.swift` (builds clean)
- [ ] Surface re-skins (incremental): Overview window · Recording HUD ·
      Capture picker · Canvas toolbar · Settings · selection overlays · menu bar
- [ ] App icon + asset catalog + menu-bar template glyph

> Implementation note: the Xcode project uses explicit file references (no
> filesystem-synchronized groups), so each new Swift file needs `project.pbxproj`
> entries (PBXBuildFile + PBXFileReference + group child + Sources phase).
