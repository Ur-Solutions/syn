// `@syn/web-elements/next` — two-piece integration, no component changes:
//
// 1. (optional) Wrap the Next config to centralize SDK options; they reach the
//    client through NEXT_PUBLIC_* env inlining:
//
//      // next.config.js
//      const { withSynWebElements } = require("@syn/web-elements/next")
//      module.exports = withSynWebElements({ reactStrictMode: true })
//
// 2. Register from the client instrumentation hook (Next 15.3+; the file is
//    loaded before the app hydrates — the PREFERRED injection point):
//
//      // instrumentation-client.ts
//      import { registerSynWebElements } from "@syn/web-elements/next"
//      registerSynWebElements()
//
//    Alternative for older Next: render a client component in the root layout
//    whose module body calls registerSynWebElements().
//
// Dev-only by default: registerSynWebElements no-ops when NODE_ENV is
// "production" unless `enabled: true` was passed explicitly.

import { initSynWebElements } from "../index"
import type { SynWebElementsConfig } from "../config"

export interface SynNextOptions extends Omit<SynWebElementsConfig, "adapter" | "framework" | "resolveRoute"> {}

const CONFIG_ENV_KEY = "NEXT_PUBLIC_SYN_WEB_ELEMENTS"

interface NextConfigLike {
  env?: Record<string, string>
  [key: string]: unknown
}

/** Wraps a Next config; serialized options flow to registerSynWebElements via env. */
export function withSynWebElements<T extends NextConfigLike>(
  nextConfig: T = {} as T,
  options: SynNextOptions = {},
): T {
  return {
    ...nextConfig,
    env: {
      ...nextConfig.env,
      [CONFIG_ENV_KEY]: JSON.stringify(options),
    },
  }
}

function envOptions(): SynNextOptions {
  try {
    const raw = process.env.NEXT_PUBLIC_SYN_WEB_ELEMENTS
    if (raw) return JSON.parse(raw) as SynNextOptions
  } catch {
    // No wrapper configured; defaults apply.
  }
  return {}
}

/** Call from instrumentation-client.ts. Inline options override withSynWebElements'. */
export function registerSynWebElements(options: SynNextOptions = {}): () => void {
  if (typeof window === "undefined") return () => {}
  const merged = { ...envOptions(), ...options }
  const isDev = typeof process !== "undefined" && process.env?.NODE_ENV !== "production"
  if (!(merged.enabled ?? isDev)) return () => {}
  return initSynWebElements({
    ...merged,
    enabled: true,
    framework: "react",
    adapter: "next",
  })
}
