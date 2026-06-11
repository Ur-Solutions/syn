// WebSocket client for the Syn bridge. The page connects OUT to Syn
// (ws://127.0.0.1:47845) and keeps retrying quietly forever — Syn may launch
// after the dev server, or not at all. All failure modes are silent: this SDK
// must never break the host app.

import {
  DEFAULT_BRIDGE_URL,
  SDK_VERSION,
  type ElementMessage,
  type HelloMessage,
  type IncomingMessage,
} from "./protocol"
import type { ResolvedConfig } from "./config"
import { buildSnapshotAtScreenPoint } from "./snapshot"

const INITIAL_RETRY_MS = 1_000
const MAX_RETRY_MS = 10_000

export interface SocketLike {
  send(data: string): void
  close(): void
  onopen: ((event: unknown) => void) | null
  onclose: ((event: unknown) => void) | null
  onerror: ((event: unknown) => void) | null
  onmessage: ((event: { data: unknown }) => void) | null
}

export interface BridgeClientOptions {
  config: ResolvedConfig
  win?: Window
  /** Test seam; defaults to `new WebSocket(url)`. */
  createSocket?: (url: string) => SocketLike
}

export class SynBridgeClient {
  private readonly config: ResolvedConfig
  private readonly win: Window
  private readonly createSocket: (url: string) => SocketLike
  private socket: SocketLike | null = null
  private retryDelay = INITIAL_RETRY_MS
  private retryTimer: ReturnType<typeof setTimeout> | null = null
  private disposed = false

  constructor(options: BridgeClientOptions) {
    this.config = options.config
    this.win = options.win ?? window
    this.createSocket = options.createSocket ?? ((url) => new WebSocket(url) as unknown as SocketLike)
  }

  start(): void {
    this.connect()
  }

  dispose(): void {
    this.disposed = true
    if (this.retryTimer !== null) clearTimeout(this.retryTimer)
    this.retryTimer = null
    try {
      this.socket?.close()
    } catch {
      // already closed
    }
    this.socket = null
  }

  private connect(): void {
    if (this.disposed) return
    let socket: SocketLike
    try {
      socket = this.createSocket(this.config.url ?? DEFAULT_BRIDGE_URL)
    } catch {
      this.scheduleReconnect()
      return
    }
    this.socket = socket
    socket.onopen = () => {
      this.retryDelay = INITIAL_RETRY_MS
      this.send(this.helloMessage())
    }
    socket.onmessage = (event) => {
      if (typeof event.data === "string") this.handleMessage(event.data)
    }
    socket.onerror = () => {
      // onclose follows; reconnect is handled there.
    }
    socket.onclose = () => {
      this.socket = null
      this.scheduleReconnect()
    }
  }

  private scheduleReconnect(): void {
    if (this.disposed || this.retryTimer !== null) return
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null
      this.connect()
    }, this.retryDelay)
    this.retryDelay = Math.min(MAX_RETRY_MS, this.retryDelay * 2)
  }

  private helloMessage(): HelloMessage {
    return {
      type: "hello",
      sdkVersion: SDK_VERSION,
      framework: this.config.framework,
      adapter: this.config.adapter,
      url: `${this.win.location.origin}${this.win.location.pathname}`,
      devicePixelRatio: this.win.devicePixelRatio || 1,
    }
  }

  private handleMessage(raw: string): void {
    let message: IncomingMessage
    try {
      message = JSON.parse(raw) as IncomingMessage
    } catch {
      return
    }
    if (message.type !== "lookup") return

    let snapshot: ElementMessage["snapshot"] = null
    try {
      snapshot = buildSnapshotAtScreenPoint(message.screenX, message.screenY, this.config, this.win)
    } catch {
      snapshot = null
    }
    this.send({ type: "element", id: message.id, snapshot })
  }

  private send(message: HelloMessage | ElementMessage): void {
    try {
      this.socket?.send(JSON.stringify(message))
    } catch {
      // Connection raced shut; the reconnect loop recovers.
    }
  }
}
