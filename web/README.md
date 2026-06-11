# Syn web workspace

pnpm workspace for Syn's browser-side element intelligence. Not part of the Xcode
project.

- `packages/web-elements` — `@syn/web-elements`: the page SDK + framework adapters
  (Vite React, Next, TanStack Start, Svelte). See its README.
- `fixtures/vite-react` — PRD acceptance fixture (`pnpm fixture:vite-react`, :5173).
- `fixtures/svelte` — Svelte fixture (`pnpm fixture:svelte`, :5174).

The native counterpart is `Syn/Services/WebElementBridge.swift` (WebSocket server on
127.0.0.1:47845) wired into `ElementPickerController`. Plan and decisions:
`docs/WEB_ELEMENT_SDK_PLAN.md`; product context: `docs/ELEMENT_INTELLIGENCE_PRD.md`.
