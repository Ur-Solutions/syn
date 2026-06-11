// `@syn/web-elements/svelte` — Vite plugin for Svelte apps. Source locations come
// free from `__svelte_meta`, which vite-plugin-svelte attaches in dev builds.
//
//   import { synWebElements } from "@syn/web-elements/svelte"
//   export default defineConfig({ plugins: [svelte(), synWebElements()] })

import type { Plugin } from "vite"
import { createSynVitePlugin, type SynVitePluginOptions } from "./vite"

export type { SynVitePluginOptions }

export function synWebElements(options: SynVitePluginOptions = {}): Plugin {
  return createSynVitePlugin(options, {
    adapter: "svelte",
    framework: "svelte",
    // SvelteKit is SSR; cover its conventional client entry too.
    clientEntryPatterns: [/(?:^|\/)src\/entry-client\.[tj]s(?:\?|$)/],
  })
}
