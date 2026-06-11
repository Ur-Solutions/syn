# Syn Web Element SDK — Implementation Plan

Date: 2026-06-11. Follows docs/ELEMENT_INTELLIGENCE_PRD.md (MVP 2 + 3). Native MVP 1
(macOS Accessibility picker, `Syn/Services/ElementIntelligence.swift`) is shipped.

## Decision summary

- **Bridge: local WebSocket server in Syn** (PRD-recommended prototype path), port
  `47845`, localhost only. Page SDK connects out; Syn never connects into the page.
  Native messaging/extension is future scope.
- **One npm package `@syn/web-elements`** with framework adapters as subpath exports:
  `@syn/web-elements/next`, `/tanstack-start`, `/vite-react` (plugin), `/svelte`.
  Core is framework-agnostic DOM resolution; adapters only wire dev-mode injection
  and framework-specific component resolution.
- **Dev-only by default** (`process.env.NODE_ENV === "development"` gate in every
  adapter, overridable).

## Protocol (JSON over WebSocket)

1. SDK → Syn on connect: `{type:"hello", sdkVersion, framework, adapter, url, devicePixelRatio}`;
   Syn replies `{type:"helloAck", app, version}`.
2. Syn → SDK on hover/flag: `{type:"lookup", id, screenX, screenY}`. CHANGED from the
   original sketch: coordinates are global TOP-LEFT-ORIGIN points (the `window.screenX`
   space), not Cocoa points — the page cannot convert Cocoa's bottom-left origin without
   knowing the primary screen height. Swift converts both ways at the bridge boundary.
3. SDK → Syn: `{type:"element", id, snapshot|null}` — null when the point is outside the
   page's viewport (lookups broadcast to every connected tab; first non-null wins,
   250ms timeout).
4. SDK maps screen→viewport via `window.screenX/screenY + outerHeight-innerHeight`
   chrome offset + zoom (outerWidth/innerWidth snapped to browser zoom stops); returns
   BOTH raw viewport CSS px and normalized screen rects (PRD requirement).

Swift side: `ElementPickerController` consults the bridge FIRST when the hovered
window's bundle ID is a browser (`com.google.Chrome`, `company.thebrowser.Browser`,
Safari later); falls back to the existing AX snapshot. Merge: browser snapshot wins,
AX kept in `rawProviders`.

## Component resolution (core, zero-touch)

- `elementFromPoint` → interactive-ancestor promotion (PRD heuristics list).
- **React** (Next, TanStack Start, Vite): walk `__reactFiber$*` key on the DOM node →
  nearest function/class component fiber → `displayName`/`name`; owner stack by
  walking `return` pointers (cap 8); source from `_debugSource` (dev builds have it —
  file:line:col) — this covers Next/TanStack/Vite identically since all use dev React.
- **Svelte**: `__svelte_meta` on DOM nodes in dev (`{loc:{file,line,column}}`) —
  free source locations; component name from file basename.
- Props: OFF by default; `safe-primitives` mode behind config with PRD redaction keys.

## Adapter responsibilities (thin)

- `/vite-react`: Vite plugin that injects `<script type="module">` importing the core
  + `synWebElements({enabled})` config.
- `/next`: `withSynWebElements(nextConfig, opts)` — injects via `instrumentation-client.ts`
  hook or a tiny client component in root layout (document both; prefer instrumentation).
- `/tanstack-start`: same Vite plugin re-export (TanStack Start is Vite-based) with
  router-aware `route` field from `window.location` + TanStack router state if present.
- `/svelte`: Vite plugin variant injecting the Svelte resolver.

## Repo layout

```
web/                      # new top-level workspace (pnpm), NOT in the Xcode project
  packages/web-elements/  # core + adapters, tsup build, vitest
  fixtures/vite-react/    # test app (PRD acceptance)
  fixtures/svelte/        # bonus
```

## Build order (next session)

1. Swift WebSocket bridge (`NWListener` in ElementIntelligence.swift or new file w/
   pbxproj entry) + provider priority in ElementPickerController + `provider:
   "browser.dom"|"browser.react"|"browser.svelte"` snapshots flowing into the existing
   flagged-elements pipeline (packet/prompt/burn-in already work — snapshot fields
   only need the `web`/`framework` blocks added to `FlaggedElementSnapshot`).
2. Core SDK + vite-react adapter + fixture app; verify hover/flag end-to-end with a
   real recording on the fixture (photograb hover highlight on a DOM button; check
   `flagged-elements.json` has selector + component + source).
3. Next adapter (fixture: create-next-app dev). 4. TanStack Start adapter. 5. Svelte.

## Acceptance (from PRD, trimmed)

- Flag a button in the Vite fixture → snapshot has tag/selector/testid/component
  name/source file:line; works at 100%/125% zoom on Retina; nested span promotes to
  its button; packet + prompt + burned highlight all show the flag.

## Status (2026-06-11)

Built and verified in this pass:

- Swift: `WebElementBridge.swift` (NWListener WebSocket server, 127.0.0.1:47845,
  starts in AppDelegate), `web`/`framework`/`rawProviders` blocks on
  `FlaggedElementSnapshot`, bridge-first hover/click in `ElementPickerController`
  (AX shows instantly, browser snapshot replaces it when the page answers; AX merge
  preserved in `rawProviders`), web identity inlined in the agent-prompt flagged
  element lines. xcodebuild green; live handshake + malformed-input robustness
  verified against the running app with a Node WS client.
- Web: `web/` pnpm workspace; `@syn/web-elements` core (promotion heuristics,
  selector builder, zoom/chrome-offset coordinate mapping, React fiber resolver with
  `_debugSource` + React 19 `_debugStack` parsing, Svelte `__svelte_meta` resolver,
  props off-by-default with safe-primitives + redaction), adapters `/vite-react`,
  `/next` (withSynWebElements + registerSynWebElements via instrumentation-client),
  `/tanstack-start` (client-entry injection + router-aware route), `/svelte`, plus
  `/auto` escape hatch. 47 vitest tests green; tsup build green; Vite fixture
  injection verified over HTTP (script tag + virtual module).

Remaining for full PRD acceptance (needs interactive session):

- Real-recording photograb: hover highlight on the Vite fixture button in Chrome,
  flag it, confirm `elements/flagged-elements.json` carries selector + component +
  source and the burned-in highlight. (Headless-Chrome e2e was attempted but Chrome
  headless does not navigate on this machine — environmental, not a code path.)
- 125% zoom + Retina spot check of the coordinate mapping against a real window.
Added later the same day: fixtures for ALL four adapters (`pnpm fixtures` in `web/`
runs them in parallel — vite-react :5173, svelte :5174, next :3030, tanstack-start
:3031; 3000/3001 were taken on this machine). Verified by booting each dev server:
Next bundles the SDK via instrumentation-client (markers present in main-app.js);
TanStack Start injects into its bundled default client entry
(`react-start/dist/plugin/default-entry/client.tsx` — the virtual wrapper module
bypasses the transform pipeline, so the adapter matches the real file; current Start
also wants `getRouter` exported from src/router.tsx, not `createRouter`); svelte and
vite-react inject via transformIndexHtml. Adapter entry-pattern regression tests in
`test/adapters.test.ts`.
