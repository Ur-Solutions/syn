// @syn/web-elements core. Framework adapters (subpath exports) only wire
// dev-mode injection; everything real lives here. See docs/WEB_ELEMENT_SDK_PLAN.md
// in the Syn repo and Syn/Services/WebElementBridge.swift for the receiving end.

import { resolveConfig, type SynWebElementsConfig } from "./config"
import { SynBridgeClient } from "./client"
import { SDK_VERSION } from "./protocol"

export type { SynWebElementsConfig, PropsConfig } from "./config"
export { DEFAULT_REDACT_KEYS } from "./config"
export { SDK_VERSION, DEFAULT_BRIDGE_URL } from "./protocol"
export type {
  ElementSnapshotPayload,
  ElementIdentity,
  WebBlock,
  FrameworkBlock,
  BoundsBlock,
  Rect,
} from "./protocol"
export { buildSnapshotAtScreenPoint } from "./snapshot"

interface GlobalHandle {
  version: string
  dispose: () => void
}

declare global {
  interface Window {
    __SYN_WEB_ELEMENTS__?: GlobalHandle
  }
}

/** Connects this page to the Syn recorder's element bridge. Idempotent — adapters
 * may inject more than once. Returns a dispose function. */
export function initSynWebElements(config: SynWebElementsConfig = {}): () => void {
  if (typeof window === "undefined" || typeof WebSocket === "undefined") {
    return () => {}
  }
  const existing = window.__SYN_WEB_ELEMENTS__
  if (existing) return existing.dispose
  if (config.enabled === false) return () => {}

  const client = new SynBridgeClient({ config: resolveConfig(config) })
  const dispose = () => {
    client.dispose()
    delete window.__SYN_WEB_ELEMENTS__
  }
  window.__SYN_WEB_ELEMENTS__ = { version: SDK_VERSION, dispose }
  client.start()
  return dispose
}
