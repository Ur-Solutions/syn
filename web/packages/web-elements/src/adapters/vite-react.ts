// `@syn/web-elements/vite-react` — one plugin line in vite.config.ts:
//
//   import { synWebElements } from "@syn/web-elements/vite-react"
//   export default defineConfig({ plugins: [react(), synWebElements()] })
//
// Dev-server only by default; React resolution itself is zero-touch (fiber walk).

import type { Plugin } from "vite"
import { createSynVitePlugin, type SynVitePluginOptions } from "./vite"

export type { SynVitePluginOptions }

export function synWebElements(options: SynVitePluginOptions = {}): Plugin {
  return createSynVitePlugin(options, {
    adapter: "vite-react",
    framework: "react",
  })
}
