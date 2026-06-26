# Syn Element Intelligence PRD

Date: 2026-06-06

Status: Draft

Owner: Syn

## Summary

Syn should support an optional element intelligence layer that lets a recorder hover, flag, and highlight real UI elements instead of only drawing over pixels. The feature should work first with macOS Accessibility for native apps and browser DOM inspection for web apps, then evolve toward richer framework-aware providers that can identify React/Vue/Svelte/etc. components, source locations, and sanitized debug metadata.

The guiding principle is zero-touch integration for existing codebases. Teams should not need to wrap components, add refs, or annotate every button. The integration should feel closer to Sentry: install a package, add one dev/build/plugin configuration, and get richer metadata automatically in development/debug builds. Explicit annotations may exist as an advanced escape hatch later, but they are not the default product path.

## Problem

Syn's current capture model can record the screen, microphone narration, pointer movement, clicks, canvas drawings, and processed video output. This is useful, but the metadata is mostly pixel-level:

- Cursor was at coordinate `(x, y)`.
- User clicked at coordinate `(x, y)`.
- User drew a rectangle or pen stroke over a screen region.
- Processing can burn visual overlays into the video.

For feedback to developers and agents, pixel-level information is often not enough. The user may want to say "this button is wrong" or "this card has the bug" and have Syn preserve knowledge of the actual element, not just the coordinates at the time.

The missing capability is semantic UI understanding:

- What UI element was under the cursor?
- What app, window, DOM node, or component did it belong to?
- What role, label, text, selector, accessibility name, test id, route, or source location identifies it?
- Can Syn store that element in the packet so an agent can reason about it later?
- Can Syn burn a clear highlight/callout into the final video around flagged elements?

## Product Goals

1. Let the user hover over UI and see a live highlight around the element Syn understands.
2. Let the user click to flag a specific element during recording.
3. Store flagged element metadata in the recording packet.
4. Burn flagged element highlights into the processed video.
5. Provide a generic macOS baseline using Accessibility APIs.
6. Provide a generic web baseline using browser DOM inspection.
7. Provide a zero-touch framework integration path for richer React/Vue/Svelte/etc. metadata in dev/debug mode.
8. Keep the feature optional and non-invasive. Syn should continue to work without app-side integration.
9. Avoid large diffs in customer codebases.
10. Redact or avoid sensitive runtime data by default.

## Non-Goals

1. Do not require explicit per-component code such as `useSynElement`, `synRef`, `SynElement`, or manual wrappers for MVP.
2. Do not require teams to edit every button, card, input, or component.
3. Do not make source-aware integration part of the critical recording path.
4. Do not require browser/framework integration for basic element highlighting.
5. Do not capture arbitrary props or runtime objects without explicit privacy controls.
6. Do not attempt to fully control third-party apps beyond what macOS Accessibility safely exposes.
7. Do not block packet generation if element metadata is unavailable.
8. Do not send element metadata to external AI providers unless it is included in the packet and follows the same user-controlled processing rules as the rest of Syn.

## User Stories

### Native macOS App Feedback

As a user recording feedback on a macOS app, I can enable element picker mode, hover a button or text field, see Syn draw a highlight around it, click to flag it, and later send a packet where the agent can see that the flagged element was a button titled "Export" inside a specific app/window.

### Web App Feedback Without Integration

As a user recording feedback on a web app, I can enable element picker mode and flag a DOM element. Syn stores useful baseline metadata such as tag name, visible text, ARIA role/name, `id`, classes, `data-testid`, selector, bounds, URL, and frame information.

### Web App Feedback With Framework Integration

As a team using React in dev mode, we can add one Syn provider/plugin configuration. When a user flags an element, Syn stores richer metadata such as component name, owner stack, route, source file/line, and sanitized props where allowed.

### Agent Handoff

As a user sending a packet to a coding agent, I want the packet to include a clear list of flagged elements, screenshots/video highlights, timestamps, and enough semantic metadata for the agent to locate the relevant code or UI surface quickly.

### Debugging Existing Large Codebases

As a developer on a large existing app, I should not need a large diff or explicit annotations. A one-line dev plugin/config change is acceptable; editing hundreds of components is not.

## User Experience

### Entry Point

Add an element picker mode alongside canvas mode.

Proposed shortcut:

- `Right Shift + E`: toggle element picker mode.

The exact shortcut can be changed before implementation, but it should not conflict with existing capture and canvas shortcuts:

- Capture picker: `Left Shift + Right Shift + R`
- Repeat last capture: `Left Shift + Right Shift`
- Canvas mode: `Right Shift + C`
- Canvas tools: `Right Shift + 1/2/3/4/5/6`
- Canvas clear: `Right Shift + D, D`

### Active Mode Behavior

When element picker mode is active:

1. Syn tracks the cursor position.
2. Syn asks available element providers what element is under the cursor.
3. Syn chooses the best available element snapshot.
4. Syn draws a hover highlight around the element bounds.
5. The user clicks to flag the element.
6. Flagged elements remain visibly marked during the recording.
7. The user can select/delete flagged elements.
8. The final video can burn in the highlight/callout for flagged elements.

### Visual Language

The visual treatment should be distinct from canvas drawings and pointer click bubbles.

Initial treatment:

- Hover element: thin outline, subtle fill, no permanent marker.
- Flagged element: stronger outline, small numbered badge, optional label.
- Deleted/unselected state: remove highlight from recording metadata.
- Burned-in video: clean callout box or pulse around the element at the relevant timestamp.

The overlay must stay out of captured source material and should be rendered into final video during processing, similar to clicks and annotations.

### Element Picker Toolbar

Element picker mode may eventually have a compact toolbar below the recording HUD, but the MVP can be shortcut-driven:

- Toggle element picker.
- Flag on click.
- Delete selected flagged element.
- Exit element picker.

If a toolbar is added, it should follow the canvas toolbar style and remain draggable.

## Core Concepts

### Element Snapshot

An element snapshot is the normalized record Syn stores when it understands or flags a UI element.

Example shape:

```json
{
  "id": "element-0007",
  "timestamp": 42.310,
  "provider": "browser.dom",
  "confidence": 0.92,
  "bounds": {
    "screen": { "x": 520, "y": 244, "width": 132, "height": 40 },
    "source": { "x": 520, "y": 244, "width": 132, "height": 40 },
    "video": { "x": 544, "y": 268, "width": 132, "height": 40 }
  },
  "identity": {
    "role": "button",
    "label": "Upgrade",
    "text": "Upgrade",
    "stableId": "upgrade-plan-button"
  },
  "context": {
    "appBundleId": "com.google.Chrome",
    "windowTitle": "Billing - Syn Test App",
    "url": "http://localhost:3000/billing",
    "route": "/billing"
  },
  "web": {
    "tagName": "button",
    "selector": "[data-testid='upgrade-plan-button']",
    "attributes": {
      "type": "button",
      "data-testid": "upgrade-plan-button"
    }
  },
  "framework": {
    "name": "react",
    "componentName": "UpgradePlanButton",
    "ownerStack": ["BillingPage", "PlanCard", "UpgradePlanButton"],
    "source": "src/billing/UpgradePlanButton.tsx:38",
    "props": {
      "variant": "primary",
      "disabled": false,
      "planId": "team"
    }
  },
  "privacy": {
    "propsRedacted": true,
    "sensitiveFieldsOmitted": ["email", "token"]
  }
}
```

Fields should be optional and provider-dependent. Syn must handle partial snapshots.

### Element Provider

An element provider is a source of semantic element metadata.

Conceptual interface:

```swift
protocol ElementProvider {
    var id: String { get }
    var displayName: String { get }
    var priority: Int { get }

    func element(at screenPoint: CGPoint) async -> ElementSnapshot?
}
```

Candidate providers:

- `macos.accessibility`
- `browser.dom`
- `browser.react`
- `browser.vue`
- `browser.svelte`
- `browser.angular`
- `swift.accessibility`
- `swift.synDebug`

Providers can be local-only. Browser/framework providers may require a companion extension or local bridge.

### Provider Selection

Multiple providers may return metadata for the same point. Syn should merge or prioritize snapshots.

Priority example:

1. Framework/build plugin provider with source location.
2. Framework devtools provider.
3. Browser DOM provider.
4. macOS Accessibility provider.
5. Pixel fallback.

If two providers return compatible bounds, Syn can merge metadata. If they disagree, Syn should prefer the higher-confidence provider while preserving lower-level fallback metadata in `rawProviders`.

## macOS Accessibility Provider

### Capability

macOS Accessibility can provide a baseline "element under cursor" experience for many native apps.

Syn can use the system-wide accessibility element and APIs such as:

- `AXUIElementCreateSystemWide`
- `AXUIElementCopyElementAtPosition`
- `AXUIElementCopyAttributeValue`
- `AXUIElementCopyActionNames`

Potential attributes:

- `AXRole`
- `AXSubrole`
- `AXTitle`
- `AXValue`
- `AXDescription`
- `AXHelp`
- `AXIdentifier` where available
- `AXPosition`
- `AXSize`
- supported actions such as `AXPress`

Syn can also associate the element with:

- owning process id
- app bundle id
- app name
- frontmost window
- window title

### Strengths

- Works across native macOS apps without app changes.
- Syn already needs Accessibility permission for other features.
- Good enough for many AppKit and SwiftUI controls.
- Can provide screen-space bounds for hover highlights and burned-in video overlays.

### Limitations

- Quality depends on the target app's accessibility tree.
- Custom-rendered apps may expose one large canvas instead of individual controls.
- Electron/webview apps may expose inconsistent or overly broad elements.
- Source file/component metadata is usually unavailable.
- Some attributes may be missing or localized.
- Accessibility bounds can be stale or approximate.

### MVP Behavior

For native macOS apps:

1. Ask Accessibility for the element at cursor point.
2. Read role, title, value, description, identifier, position, size, actions.
3. Compute screen bounds.
4. Draw hover highlight.
5. On click, store the element snapshot.
6. During processing, map screen bounds into source/video coordinates and burn highlight into final video.

## Browser DOM Provider

### Capability

A browser extension can inspect the page under the cursor and return DOM element metadata.

Baseline data:

- URL
- top-level origin
- frame/iframe path
- tag name
- visible text
- ARIA role
- accessible name
- `id`
- classes
- `data-testid`
- `data-test`
- other safe `data-*` attributes
- CSS selector
- XPath-like path
- bounding client rect
- computed visibility
- nearest label
- nearest form
- nearest landmark/section

### Architecture

Recommended architecture:

1. Syn native app runs an element provider bridge.
2. Browser extension content script listens for element lookup requests.
3. Extension maps screen point to browser viewport coordinates.
4. Content script calls `document.elementFromPoint`.
5. Content script walks up the DOM to find the most useful target element.
6. Extension returns normalized metadata to Syn.

The bridge can use one of:

- Native messaging host.
- Localhost/WebSocket bridge in dev builds.
- App group/IPC helper if needed later.

Native messaging is likely the cleanest long-term browser extension bridge, but a local WebSocket bridge may be faster for initial development.

### Element Targeting Heuristics

The raw `elementFromPoint` result may be a nested span/icon inside a button. The DOM provider should promote the target to a meaningful element.

Promotion rules:

- Prefer interactive ancestors: `button`, `a`, `input`, `select`, `textarea`, `[role=button]`, `[role=link]`, `[tabindex]`.
- Prefer elements with ARIA label/name.
- Prefer elements with `data-testid`, `data-test`, or stable test attributes.
- Prefer form controls and labels together.
- Avoid tiny decorative elements if parent has a better semantic role.
- Preserve the raw leaf element in metadata for debugging.

### MVP Browser Behavior

For web apps without app-side integration:

1. Browser extension detects the current tab/page.
2. Syn asks the extension for the element under the cursor.
3. Extension returns DOM metadata and viewport bounds.
4. Syn converts bounds into screen/source/video coordinates.
5. User can flag the element.
6. Packet includes the DOM snapshot.

## Framework Integration Model

### Guiding Principle

Framework integrations must be zero-touch at component sites.

Accepted:

- Install package.
- Add one plugin/config entry.
- Enable dev/debug mode.
- Use a browser extension.
- Provide global config for privacy/sanitization.

Not accepted as the default:

- Wrapping every component.
- Adding refs everywhere.
- Adding `data-syn-id` manually across a large codebase.
- Requiring teams to edit every button/card/input.

### Sentry-Like Integration Shape

The desired developer experience should look like:

```ts
// vite.config.ts
import { synReactDev } from "@syn/react-dev/vite"

export default defineConfig({
  plugins: [
    react(),
    synReactDev({
      enabled: process.env.NODE_ENV === "development",
      props: {
        mode: "safe-primitives",
        redactKeys: ["token", "secret", "password", "email", "auth"]
      }
    })
  ]
})
```

Or:

```js
// next.config.js
const { withSynReactDev } = require("@syn/react-dev/next")

module.exports = withSynReactDev({
  reactStrictMode: true
}, {
  enabled: process.env.NODE_ENV === "development"
})
```

The app code itself should not need to change.

### React Provider Levels

#### Level 1: DOM Baseline

No app package required. Browser extension inspects DOM.

This gives:

- tag
- role
- label
- text
- selector
- test ids
- bounds
- route/URL

#### Level 2: React DevTools/Fiber Provider

In dev mode, the extension can attempt to use React DevTools-style hooks or React Fiber references attached to DOM nodes.

Potential data:

- nearest owning React component
- component stack
- display names
- selected props
- hook/state hints where safe

Risks:

- React internals are not a stable public API.
- Minified/prod builds may have poor names.
- Different React versions can behave differently.

Use this as a useful dev-mode enhancement, not the only source of truth.

#### Level 3: Build Plugin Provider

A Vite/Babel/Next/SWC plugin can inject dev-only metadata or emit sidecar maps.

Potential data:

- JSX source file and line
- component name
- route/module
- owner stack hints
- stable generated element ids
- source map references

This is likely the best long-term path for high-quality source locations without component-site code changes.

Preferred behavior:

- Development-only by default.
- Tree-shaken or disabled in production.
- Emits metadata sidecar where possible.
- Avoids mutating visible DOM unless necessary.
- Does not add user data to source maps or build artifacts.

### Framework-Agnostic Provider API

Each framework adapter should normalize into the same shape.

Conceptual browser-side interface:

```ts
export interface SynBrowserElementProvider {
  id: string
  framework: string
  priority: number
  elementFromPoint(input: {
    clientX: number
    clientY: number
    document: Document
    rawElement: Element | null
  }): Promise<SynElementSnapshot | null>
}
```

Adapters can exist for:

- React
- Vue
- Svelte
- Angular
- Solid
- Ember
- plain DOM

The browser extension should own provider orchestration and return one normalized snapshot to Syn.

## Props And Runtime Data

Props are useful but risky. They can contain secrets, tokens, internal customer data, emails, API responses, and large objects.

Default rule:

- Do not capture arbitrary props by default.

Safer modes:

1. `off`: no props.
2. `safe-primitives`: booleans, numbers, short strings, enums, nulls.
3. `allowlist`: only configured prop names.
4. `debug-local`: richer local-only capture, never sent unless explicitly included.

Redaction should happen before data leaves the page process.

Default redaction keys:

- `password`
- `secret`
- `token`
- `auth`
- `authorization`
- `cookie`
- `session`
- `email`
- `phone`
- `ssn`
- `key`
- `credential`

Large objects should be summarized or omitted.

Packet metadata should record that redaction occurred.

## Swift/macOS App Integration

### Accessibility-First Baseline

For arbitrary macOS apps, Syn should start with Accessibility metadata.

### Better Metadata For Apps We Control

For Syn-owned or instrumented Swift apps, richer metadata can come from:

- `accessibilityIdentifier`
- SwiftUI accessibility labels/values
- a debug-only local provider
- a small Swift package/SDK
- XPC/local socket bridge

This should follow the same zero-touch philosophy where possible:

- Encourage teams to already use accessibility identifiers for testing.
- Avoid forcing per-view Syn wrappers.
- Provide build/debug integration where feasible.

### Native Provider Snapshot

Example:

```json
{
  "provider": "macos.accessibility",
  "identity": {
    "role": "AXButton",
    "label": "Start with...",
    "identifier": "capture.startButton"
  },
  "context": {
    "appBundleId": "com.trmdy.syn",
    "windowTitle": "Overview"
  },
  "actions": ["AXPress"],
  "bounds": {
    "screen": { "x": 72, "y": 114, "width": 152, "height": 32 }
  }
}
```

## Recording And Packet Integration

### Capture-Time Storage

Add a metadata file for flagged elements:

```text
elements/
  flagged-elements.json
  provider-events.jsonl
```

Or store inside `manifest.json` if the count is small. A separate folder is cleaner as this grows.

`flagged-elements.json` should contain:

- normalized element snapshots
- timestamps
- selection/flag action metadata
- coordinate transforms
- provider versions
- privacy/redaction flags

`provider-events.jsonl` can be optional debug output for hover events and provider failures.

### Manifest Integration

`manifest.json` should summarize:

- element intelligence enabled/disabled
- providers available
- providers used
- flagged element count
- redaction mode
- browser extension version, if used
- framework provider version, if used

### Agent Prompt Integration

`agent-prompt.md` should reference flagged elements when present:

```md
## Flagged Elements

1. 00:42.310 - Upgrade button
   - Provider: browser.react
   - Component: UpgradePlanButton
   - Source: src/billing/UpgradePlanButton.tsx:38
   - DOM: button[data-testid="upgrade-plan-button"]
   - Notes: User clicked this element while describing the plan upgrade bug.
```

### Summary Integration

`summary.md` should include flagged elements in timestamped observations. The summary model can use this metadata to identify likely code locations and affected components.

### Video Rendering

Processing should map flagged element bounds into final video coordinates and burn highlights into `recording.mp4`.

The renderer should support:

- short pulse at flag timestamp
- persistent highlight for a small configurable duration
- optional numbered badge
- optional label/callout

The renderer must handle all capture modes:

- screen
- all screens
- active-window-follow
- selected window
- Chrome tab
- region
- Smart Region

For dynamic capture modes, element bounds must be transformed through the same source-to-output mapping as cursor/click/canvas annotations.

## Technical Architecture

### Native App Components

Proposed Swift components:

- `ElementIntelligenceController`
- `ElementProviderRegistry`
- `MacAccessibilityElementProvider`
- `BrowserElementProvider`
- `ElementOverlayController`
- `ElementSelectionStore`
- `ElementRenderLayer`
- `ElementPacketWriter`

### Provider Registry

The registry owns provider discovery, health, priority, and lookup.

Responsibilities:

- know which providers are available
- poll or request current hover element
- merge provider responses
- debounce expensive provider calls
- expose the current hover element to overlay UI
- store provider diagnostics

### Overlay Controller

The overlay controller draws:

- hover outline
- selected/flagged outlines
- numbered badges
- optional labels

It should share concepts with `AnnotationOverlayController` where sensible, but it should remain separate enough that canvas drawing and element picking do not fight over mouse handling.

### Coordinate Spaces

Element snapshots should record:

- screen coordinates
- display id where known
- source capture coordinates
- final video coordinates
- transform metadata

This matches the existing pointer/click requirement: store both source and final video canvas coordinates plus transform metadata.

### Browser Bridge

The browser bridge should support:

- provider availability handshake
- current active tab/window lookup
- element lookup at screen point
- extension version reporting
- provider version reporting
- framework provider metadata
- diagnostics when the extension is missing or stale

Possible bridge options:

1. Native messaging host.
2. Local WebSocket server.
3. Local HTTP endpoint.
4. XPC helper.

Recommended sequence:

- Prototype with local WebSocket or HTTP for speed.
- Move to native messaging for durable browser extension distribution.

### Browser Coordinate Mapping

The browser provider must map:

- global screen coordinates
- browser window coordinates
- web content viewport coordinates
- iframe coordinates
- device pixel ratio
- browser zoom
- display scale

This is a major source of bugs. The provider should return both raw and normalized rects so Syn can verify mapping visually.

## Privacy And Security

### Default Privacy Position

Element intelligence should be local-first and conservative.

Default behavior:

- Store role/label/text/bounds/selectors.
- Store component names/source only in dev/debug integrations.
- Do not store arbitrary props by default.
- Redact sensitive keys.
- Include provider metadata in packets only after local processing.
- Do not directly send element metadata to remote providers except as part of the same user-controlled packet/summary flow.

### Sensitive Data Risks

Potential sensitive data:

- visible text on page
- input values
- customer names
- emails
- tokens in props
- URLs with secrets
- DOM attributes with internal identifiers
- source paths

Controls:

- redact URL query params by default
- omit input values unless explicitly allowed
- truncate long text
- hash or omit sensitive attributes
- prop allowlists
- local-only debug mode
- packet preview

### Production Builds

Framework plugins should default to development-only. If a team enables production metadata, it should require explicit configuration.

## MVP Scope

### MVP 1: macOS Accessibility Element Picker

Deliver:

- `Right Shift + E` toggles element picker mode.
- Hover highlights current Accessibility element.
- Click flags the element.
- Flagged elements are stored in packet metadata.
- Flagged elements are rendered into final video.
- Packet prompt includes flagged elements.
- Works without browser extension.

Acceptance:

- Native macOS buttons/text fields can be highlighted and flagged.
- Accessibility permission failure is handled clearly.
- No crash if the element has missing attributes.
- Works across multiple displays.
- Works with region and screen capture at minimum.

### MVP 2: Browser DOM Provider

Deliver:

- Chrome extension or dev bridge.
- DOM element lookup under cursor.
- Metadata includes tag, role, label, text, selector, test ids, URL, bounds.
- Syn can highlight and flag browser DOM elements.
- Packet includes DOM metadata.

Acceptance:

- Works on a local dev web app.
- Handles nested icons/spans inside buttons.
- Handles browser zoom and retina scaling.
- Handles at least same-origin iframes; cross-origin iframes may return limited metadata.

### MVP 3: React Dev Provider

Deliver:

- Zero-touch React dev provider.
- One config/plugin install path.
- Component name and owner stack where available.
- Source file/line where available.
- Sanitized props behind config.
- No per-component code changes required.

Acceptance:

- Works in a Vite React app.
- Works in a Next app if feasible in first pass, otherwise documented as next target.
- Provides useful component/source metadata for flagged elements.
- Does not leak props by default.

## Future Scope

1. Vue provider.
2. Svelte provider.
3. Angular provider.
4. Swift debug SDK.
5. Element-based replay or automated reproduction hints.
6. Click-to-open-source integration.
7. IDE integration for flagged elements.
8. Element-aware frame selection.
9. Element-aware AI summary sections.
10. Element-aware issue templates.
11. Team-shared provider configs.
12. Per-project privacy policies.

## Open Questions

1. What shortcut should final element picker mode use?
2. Should element picker and canvas mode be mutually exclusive, or can both be active?
3. Should flagged elements appear in the same annotation timeline as canvas drawings?
4. Should flagged elements be editable after recording?
5. Should hover events be stored, or only explicit flagged clicks?
6. How much element metadata should be included in default zips?
7. Should source paths be included in default packets?
8. Should input values always be omitted?
9. Should browser extension support only Chrome first, or Chrome plus Arc/Brave/Edge from day one?
10. Should framework providers be open plugin APIs from the first version?

## Risks

### Accessibility Quality

Some apps expose poor Accessibility trees. Syn must degrade gracefully and offer pixel/canvas fallback.

### Browser Coordinate Mapping

Screen-to-DOM coordinate mapping can be fragile with multiple displays, zoom, browser chrome, device scale, iframes, and full-screen modes. This requires strong test fixtures and photograbs.

### React Internals Fragility

React Fiber/devtools metadata can change across React versions. A build plugin or source map approach is more durable for source locations.

### Privacy

Props and DOM text can leak sensitive data. Defaults must be conservative.

### Scope Creep

Source-aware framework integration can become a large product on its own. MVP should start with Accessibility and DOM providers, then add one framework provider.

## Testing Plan

### Native Accessibility Tests

- Hover and flag a SwiftUI button.
- Hover and flag an AppKit text field.
- Hover and flag a menu item if accessible.
- Handle missing title/value.
- Handle zero-size or invalid bounds.
- Multiple display coordinate mapping.
- Region capture transform.
- Active-window-follow transform.

### Browser DOM Tests

- Plain HTML button.
- Button with nested icon/span.
- Link.
- Text input with label.
- ARIA button.
- Element with `data-testid`.
- Browser zoom at 80/100/125 percent.
- Retina and non-retina displays.
- Same-origin iframe.
- Cross-origin iframe fallback.

### React Provider Tests

- Vite React dev app.
- Next dev app.
- Component name detection.
- Owner stack detection.
- Source location mapping.
- Prop redaction.
- Production build disabled by default.

### Packet Tests

- `manifest.json` records provider usage.
- `elements/flagged-elements.json` is valid JSON.
- `agent-prompt.md` lists flagged elements.
- `summary.md` can consume flagged metadata.
- Default zip includes safe element metadata.
- Raw/debug provider logs are excluded unless debug mode is enabled.

### Video Render Tests

- Flagged element outline appears in final video.
- Highlight timing matches flag timestamp.
- Highlight maps correctly for screen capture.
- Highlight maps correctly for region capture.
- Highlight maps correctly for active-window-follow.
- Highlight does not appear when deleted before stop.

### Photograb Requirements

Any UI testing for this feature must include screenshots/photograbs of:

- element picker mode active
- hover highlight
- flagged highlight
- packet/history UI showing flagged element metadata if exposed
- final rendered video frame with burned-in element highlight

## Implementation Milestones

### Milestone 1: Data Model And Packet Shape

- Define `ElementSnapshot`.
- Define `ElementBounds`.
- Define `ElementProviderMetadata`.
- Add packet writer for `elements/flagged-elements.json`.
- Add manifest summary fields.
- Add fixture coverage.

### Milestone 2: macOS Accessibility Provider

- Implement element lookup at cursor point.
- Normalize attributes.
- Handle missing/invalid values.
- Add hover highlight overlay.
- Add click-to-flag.
- Add delete selected flagged element.

### Milestone 3: Video Burn-In

- Map element bounds through capture transforms.
- Add render layer for highlighted elements.
- Add fixtures for region/screen modes.
- Add visual/pixel verification.

### Milestone 4: Browser DOM Prototype

- Build Chrome extension/dev bridge.
- Implement DOM lookup and target promotion.
- Map coordinates.
- Return normalized snapshots.
- Add local test page fixture.

### Milestone 5: React Dev Provider

- Prototype React metadata extraction.
- Add build plugin path.
- Add safe prop capture modes.
- Add Vite fixture app.
- Add source location verification.

## Success Metrics

1. User can flag a native macOS UI element in under two seconds.
2. User can flag a web DOM element in under two seconds.
3. At least 90 percent of basic native controls in test apps return usable bounds and labels.
4. At least 90 percent of basic web controls in test pages return usable DOM metadata.
5. React dev provider returns component name for common component patterns.
6. Element highlights render correctly in final video across primary capture modes.
7. Default provider configuration does not capture arbitrary props.
8. Existing recording workflows still work when no providers are available.

## Recommended First Build

Build the feature in this order:

1. macOS Accessibility element picker.
2. Element snapshot packet metadata.
3. Burned-in element highlights.
4. Browser DOM extension/bridge.
5. React dev provider.

This order gives Syn a useful local feature quickly, validates the packet/rendering model, and leaves the more complex framework integrations behind a provider interface instead of entangling them with the core recorder.
