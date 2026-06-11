# Syn web workspace

pnpm workspace for Syn's browser-side element intelligence. Not part of the Xcode
project.

- `packages/web-elements` — `@syn/web-elements`: the page SDK + framework adapters
  (Vite React, Next, TanStack Start, Svelte). See its README.
- `fixtures/*` — one minimal test app per adapter, same billing page in each.
  `pnpm fixtures` runs all four: vite-react :5173, svelte :5174, next :3030,
  tanstack-start :3031.

The native counterpart is `Syn/Services/WebElementBridge.swift` (WebSocket server on
127.0.0.1:47845) wired into `ElementPickerController`. Plan and decisions:
`docs/WEB_ELEMENT_SDK_PLAN.md`; product context: `docs/ELEMENT_INTELLIGENCE_PRD.md`.
