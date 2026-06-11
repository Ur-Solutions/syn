// `@syn/web-elements/tanstack-start` — TanStack Start is Vite-based, so this is
// the shared Vite plugin with two differences: injection happens by prepending an
// import to the client entry (Start is SSR; index.html never renders), and the
// route field prefers the TanStack Router matched route id over location.pathname.
//
//   // vite.config.ts
//   import { synWebElements } from "@syn/web-elements/tanstack-start"
//   export default defineConfig({ plugins: [tanstackStart(), synWebElements()] })
//
// If your client entry is non-standard and injection misses, add
// `import "@syn/web-elements/auto"` to it instead.

import type { Plugin } from "vite"
import { createSynVitePlugin, type SynVitePluginOptions } from "./vite"

export type { SynVitePluginOptions }

// The router instance TanStack Start exposes for devtools, when present.
const RESOLVE_ROUTE = `() => {
  const router = window.__TSR_ROUTER__ ?? window.__TSR__?.router
  const matches = router?.state?.matches
  const last = matches && matches[matches.length - 1]
  return (last && (last.routeId ?? last.id)) || undefined
}`

export function synWebElements(options: SynVitePluginOptions = {}): Plugin {
  return createSynVitePlugin(options, {
    adapter: "tanstack-start",
    framework: "react",
    clientEntryPatterns: [
      /(?:^|\/)(?:app|src)\/client\.[tj]sx?(?:\?|$)/,
      // Start's bundled default entry (used when the app has no src/client.tsx).
      // The virtual wrapper module is served outside the transform pipeline, so
      // the injection targets the real entry file it imports.
      /react-start\/dist\/plugin\/default-entry\/client\.[tj]sx?(?:\?|$)/,
      /default-client-entry/,
      /tanstack-start(?:-[a-z]+)*-client-entry/,
    ],
    resolveRouteExpression: RESOLVE_ROUTE,
  })
}
