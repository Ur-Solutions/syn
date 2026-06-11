import { DEFAULT_BRIDGE_URL } from "./protocol"

export interface PropsConfig {
  /** "off" (default): no props leave the page. "safe-primitives": booleans, finite
   * numbers, and short strings only, with redaction applied first. */
  mode?: "off" | "safe-primitives"
  /** Case-insensitive substrings; matching prop keys are sent as "[redacted]". */
  redactKeys?: string[]
}

export interface SynWebElementsConfig {
  /** Hard gate. Adapters pass dev-mode detection through here. */
  enabled?: boolean
  /** Bridge endpoint; the Syn app listens on ws://127.0.0.1:47845. */
  url?: string
  /** Framework hint; orders resolver attempts. Detection is still per-element. */
  framework?: "react" | "svelte" | "dom" | (string & {})
  /** Adapter name reported in the hello message (e.g. "vite-react"). */
  adapter?: string
  props?: PropsConfig
  /** Override route detection (e.g. a router's matched route id). Falls back to
   * location.pathname; errors are swallowed. */
  resolveRoute?: () => string | undefined
}

export const DEFAULT_REDACT_KEYS = [
  "password",
  "secret",
  "token",
  "auth",
  "authorization",
  "cookie",
  "session",
  "email",
  "phone",
  "ssn",
  "key",
  "credential",
]

export interface ResolvedConfig {
  url: string
  framework: string
  adapter?: string
  propsMode: "off" | "safe-primitives"
  redactKeys: string[]
  resolveRoute?: () => string | undefined
}

export function resolveConfig(config: SynWebElementsConfig): ResolvedConfig {
  return {
    url: config.url ?? DEFAULT_BRIDGE_URL,
    framework: config.framework ?? "dom",
    adapter: config.adapter,
    propsMode: config.props?.mode ?? "off",
    redactKeys: config.props?.redactKeys ?? DEFAULT_REDACT_KEYS,
    resolveRoute: config.resolveRoute,
  }
}
