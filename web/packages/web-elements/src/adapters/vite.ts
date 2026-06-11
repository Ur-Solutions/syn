// Shared Vite plugin factory. Injection model: a virtual module that imports the
// core and calls initSynWebElements with the serialized plugin options; injected
// into index.html (`transformIndexHtml`) for SPA setups and appended to the
// client entry (`transform`) for SSR setups that never serve index.html.
// `apply: "serve"` keeps every trace of the SDK out of production builds.

import type { Plugin } from "vite"
import type { SynWebElementsConfig } from "../config"

export interface SynVitePluginOptions extends Omit<SynWebElementsConfig, "adapter" | "resolveRoute"> {
  /** Default: dev server only. Explicit `false` disables even in dev. */
  enabled?: boolean
}

export interface VitePluginDefaults {
  adapter: string
  framework: string
  /** Patterns identifying the client entry module for SSR setups. */
  clientEntryPatterns?: RegExp[]
  /** Extra statement prepended to the virtual module (e.g. a route resolver). */
  virtualModulePrelude?: string
  /** Expression for the config's resolveRoute field inside the virtual module. */
  resolveRouteExpression?: string
}

export const VIRTUAL_MODULE_ID = "virtual:syn-web-elements"
const RESOLVED_VIRTUAL_ID = `\0${VIRTUAL_MODULE_ID}`
// Vite serves \0-prefixed ids at /@id/__x00__<id>.
const VIRTUAL_BROWSER_PATH = `/@id/__x00__${VIRTUAL_MODULE_ID}`

export function createSynVitePlugin(
  options: SynVitePluginOptions,
  defaults: VitePluginDefaults,
): Plugin {
  let enabled = options.enabled ?? true

  const clientConfig: SynWebElementsConfig = {
    url: options.url,
    framework: options.framework ?? defaults.framework,
    adapter: defaults.adapter,
    props: options.props,
  }
  const virtualModule = [
    `import { initSynWebElements } from "@syn/web-elements";`,
    defaults.virtualModulePrelude ?? "",
    `const config = ${JSON.stringify(clientConfig)};`,
    defaults.resolveRouteExpression ? `config.resolveRoute = ${defaults.resolveRouteExpression};` : "",
    `initSynWebElements(config);`,
  ].filter(Boolean).join("\n")

  return {
    name: `syn-web-elements:${defaults.adapter}`,
    apply: "serve",
    configResolved(resolved) {
      if (options.enabled === undefined) {
        enabled = resolved.mode === "development" || resolved.command === "serve"
      }
    },
    resolveId(id) {
      if (id === VIRTUAL_MODULE_ID || id === VIRTUAL_BROWSER_PATH) return RESOLVED_VIRTUAL_ID
    },
    load(id) {
      if (id === RESOLVED_VIRTUAL_ID) return enabled ? virtualModule : "export {}"
    },
    transformIndexHtml() {
      if (!enabled) return
      return [
        {
          tag: "script",
          attrs: { type: "module", src: VIRTUAL_BROWSER_PATH },
          injectTo: "head" as const,
        },
      ]
    },
    transform(code, id, transformOptions) {
      if (!enabled || transformOptions?.ssr) return
      const patterns = defaults.clientEntryPatterns
      if (!patterns || !patterns.some((pattern) => pattern.test(id))) return
      return {
        code: `import "${VIRTUAL_MODULE_ID}";\n${code}`,
        map: null,
      }
    },
  }
}
