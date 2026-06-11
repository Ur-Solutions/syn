// Wire protocol with the Syn app's WebElementBridge (Syn/Services/WebElementBridge.swift).
// JSON text frames over ws://127.0.0.1:47845. All screen coordinates are GLOBAL
// TOP-LEFT-ORIGIN points — the space `window.screenX`/`window.screenY` lives in;
// the Swift side converts to/from Cocoa's bottom-left origin.

export const SDK_VERSION = "0.1.0"
export const DEFAULT_BRIDGE_URL = "ws://127.0.0.1:47845"

export interface Rect {
  x: number
  y: number
  width: number
  height: number
}

/** SDK -> Syn, once per connection. */
export interface HelloMessage {
  type: "hello"
  sdkVersion: string
  framework: string
  adapter?: string
  url: string
  devicePixelRatio: number
}

/** Syn -> SDK, reply to hello. */
export interface HelloAckMessage {
  type: "helloAck"
  app: string
  version: string
}

/** Syn -> SDK on hover/flag. */
export interface LookupMessage {
  type: "lookup"
  id: string
  screenX: number
  screenY: number
}

/** SDK -> Syn, reply to lookup. `snapshot` is null when the point is not in this page. */
export interface ElementMessage {
  type: "element"
  id: string
  snapshot: ElementSnapshotPayload | null
}

export type IncomingMessage = HelloAckMessage | LookupMessage
export type OutgoingMessage = HelloMessage | ElementMessage

export type Provider = "browser.dom" | "browser.react" | "browser.svelte"

export interface ElementIdentity {
  role?: string
  label?: string
  text?: string
  testId?: string
}

export interface WebBlock {
  tagName: string
  selector: string
  /** Selector of the raw elementFromPoint leaf before interactive-ancestor promotion. */
  leafSelector?: string
  testId?: string
  text?: string
  /** Query string and hash are stripped before sending. */
  url?: string
  route?: string
  title?: string
  attributes?: Record<string, string>
  /** Selector chain of same-origin iframes the element lives behind, outermost first. */
  framePath?: string[]
}

export interface FrameworkBlock {
  name: string
  componentName?: string
  ownerStack?: string[]
  /** `file:line[:column]` from the dev build, when available. */
  source?: string
  propsMode?: "off" | "safe-primitives"
  propsRedacted?: boolean
  props?: Record<string, unknown>
}

export interface BoundsBlock {
  /** Normalized: global top-left-origin screen points. */
  screen: Rect
  /** Raw: viewport CSS pixels, kept so Syn can verify the mapping visually. */
  viewport: Rect
  devicePixelRatio: number
  zoom: number
}

export interface ElementSnapshotPayload {
  provider: Provider
  identity: ElementIdentity
  web: WebBlock
  framework?: FrameworkBlock
  bounds: BoundsBlock
}
