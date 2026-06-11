# @syn/web-elements

Dev-mode element intelligence for the [Syn](../../..) recorder. Install once, add one
config line, and Syn's element picker (`Right Shift + E` during a recording) resolves
hovered/flagged browser elements to DOM identity — tag, selector, test id, role,
accessible name — plus framework metadata: React/Svelte component name, owner stack,
and source `file:line` in dev builds. Zero component-site changes.

The page connects out to the Syn app's local bridge (`ws://127.0.0.1:47845`,
loopback only) and answers element lookups while you record. No Syn running, no
behavior: the SDK retries quietly in the background and never breaks the host app.
Production builds are unaffected — every adapter is dev-only by default.

## Install

```sh
pnpm add -D @syn/web-elements
```

## Vite + React

```ts
// vite.config.ts
import { synWebElements } from "@syn/web-elements/vite-react"

export default defineConfig({
  plugins: [react(), synWebElements()],
})
```

The plugin only applies to the dev server (`apply: "serve"`); `vite build` output
never contains the SDK.

## Next.js

```js
// next.config.js (optional — centralizes options)
const { withSynWebElements } = require("@syn/web-elements/next")
module.exports = withSynWebElements({ /* your next config */ })
```

```ts
// instrumentation-client.ts  (Next 15.3+, at the app root)
import { registerSynWebElements } from "@syn/web-elements/next"
registerSynWebElements()
```

`registerSynWebElements` no-ops when `NODE_ENV` is `"production"` unless you pass
`enabled: true`. On older Next versions, call it from a tiny `"use client"` module
imported by the root layout instead.

## TanStack Start

```ts
// vite.config.ts
import { synWebElements } from "@syn/web-elements/tanstack-start"

export default defineConfig({
  plugins: [tanstackStart(), synWebElements()],
})
```

Start is SSR, so injection happens by prepending an import to the client entry
(`app/client.tsx` / `src/client.tsx` / the virtual default entry). The snapshot's
`route` field prefers the matched TanStack route id over `location.pathname`. If
your client entry is exotic and injection misses, add `import "@syn/web-elements/auto"`
to it manually.

## Svelte / SvelteKit

```js
// vite.config.js
import { synWebElements } from "@syn/web-elements/svelte"

export default defineConfig({
  plugins: [svelte(), synWebElements()],
})
```

Source locations come from `__svelte_meta`, which vite-plugin-svelte attaches in dev.

## Escape hatch

Any framework, any bundler:

```ts
import "@syn/web-elements/auto"          // dev-only side effect, or:
import { initSynWebElements } from "@syn/web-elements"
initSynWebElements({ framework: "react" })
```

## Props are off by default

No component props leave the page unless you opt in:

```ts
synWebElements({
  props: { mode: "safe-primitives" },    // booleans, finite numbers, short strings
})
```

Keys matching the redaction list (password/secret/token/auth/cookie/session/email/
phone/ssn/key/credential, override with `props.redactKeys`) are sent as
`"[redacted]"`. Objects, arrays, and functions are always omitted. Input values are
never captured; `href` and page URLs are stripped of query strings.

## Protocol

JSON text frames over WebSocket; the Swift side is `Syn/Services/WebElementBridge.swift`.
All screen coordinates are global top-left-origin points (the `window.screenX` space).

1. SDK → Syn on connect: `{type:"hello", sdkVersion, framework, adapter, url, devicePixelRatio}`
2. Syn → SDK: `{type:"helloAck", app:"Syn", version}`
3. Syn → SDK on hover/flag: `{type:"lookup", id, screenX, screenY}`
4. SDK → Syn: `{type:"element", id, snapshot|null}` — null when the point is outside
   this page's viewport (every connected tab is asked; the owning tab answers).

Snapshots carry bounds twice — raw viewport CSS px and normalized screen points
(zoom- and chrome-offset-corrected) — so mapping bugs are visible in the packet.

## Develop

```sh
pnpm install
pnpm build        # tsup → dist/
pnpm test         # vitest (jsdom)
```

One fixture app per adapter, each with the same flaggable billing page
(`data-testid="upgrade-plan-button"`, nested span, PlanCard owner stack). From `web/`:

```sh
pnpm fixtures                  # all four in parallel
pnpm fixture:vite-react        # http://localhost:5173
pnpm fixture:svelte            # http://localhost:5174
pnpm fixture:next              # http://localhost:3030
pnpm fixture:tanstack-start    # http://localhost:3031
```

Open one in Chrome, start a Syn recording, `Right Shift + E`, hover the button.
