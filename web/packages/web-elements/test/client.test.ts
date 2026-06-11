import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { SynBridgeClient, type SocketLike } from "../src/client"
import { resolveConfig } from "../src/config"
import type { ElementMessage, HelloMessage } from "../src/protocol"

class FakeSocket implements SocketLike {
  sent: string[] = []
  closed = false
  onopen: ((event: unknown) => void) | null = null
  onclose: ((event: unknown) => void) | null = null
  onerror: ((event: unknown) => void) | null = null
  onmessage: ((event: { data: unknown }) => void) | null = null

  send(data: string): void {
    this.sent.push(data)
  }

  close(): void {
    this.closed = true
  }

  open(): void {
    this.onopen?.({})
  }

  receive(message: unknown): void {
    this.onmessage?.({ data: JSON.stringify(message) })
  }
}

function lastMessage<T>(socket: FakeSocket): T {
  return JSON.parse(socket.sent[socket.sent.length - 1]!) as T
}

describe("SynBridgeClient", () => {
  const sockets: FakeSocket[] = []
  let client: SynBridgeClient

  beforeEach(() => {
    sockets.length = 0
    client = new SynBridgeClient({
      config: resolveConfig({ framework: "react", adapter: "vite-react" }),
      createSocket: () => {
        const socket = new FakeSocket()
        sockets.push(socket)
        return socket
      },
    })
    client.start()
  })

  afterEach(() => {
    client.dispose()
    vi.useRealTimers()
    vi.restoreAllMocks()
  })

  it("sends hello on open", () => {
    sockets[0]!.open()
    const hello = lastMessage<HelloMessage>(sockets[0]!)
    expect(hello.type).toBe("hello")
    expect(hello.framework).toBe("react")
    expect(hello.adapter).toBe("vite-react")
    expect(hello.sdkVersion).toBeTruthy()
    expect(hello.url).toContain("localhost")
  })

  it("answers lookups inside the viewport with a snapshot", () => {
    const button = document.createElement("button")
    button.setAttribute("data-testid", "upgrade-plan-button")
    button.textContent = "Upgrade"
    document.body.appendChild(button)
    button.getBoundingClientRect = () =>
      ({ x: 40, y: 50, width: 120, height: 36, top: 50, left: 40, right: 160, bottom: 86, toJSON: () => ({}) }) as DOMRect
    document.elementFromPoint = () => button

    const socket = sockets[0]!
    socket.open()
    socket.receive({ type: "lookup", id: "lk-1", screenX: 60, screenY: 70 })

    const reply = lastMessage<ElementMessage>(socket)
    expect(reply.type).toBe("element")
    expect(reply.id).toBe("lk-1")
    expect(reply.snapshot).not.toBeNull()
    expect(reply.snapshot!.provider).toBe("browser.dom")
    expect(reply.snapshot!.web.tagName).toBe("button")
    expect(reply.snapshot!.web.selector).toBe(`[data-testid="upgrade-plan-button"]`)
    expect(reply.snapshot!.identity.testId).toBe("upgrade-plan-button")
    // jsdom: zero window offset and zoom 1, so screen == viewport.
    expect(reply.snapshot!.bounds.screen.x).toBeCloseTo(40)
    expect(reply.snapshot!.bounds.viewport).toEqual({ x: 40, y: 50, width: 120, height: 36 })
  })

  it("answers lookups outside the viewport with null", () => {
    const socket = sockets[0]!
    socket.open()
    socket.receive({ type: "lookup", id: "lk-2", screenX: 99999, screenY: 70 })
    const reply = lastMessage<ElementMessage>(socket)
    expect(reply.id).toBe("lk-2")
    expect(reply.snapshot).toBeNull()
  })

  it("reconnects with backoff after close", () => {
    vi.useFakeTimers()
    sockets[0]!.open()
    sockets[0]!.onclose?.({})
    expect(sockets).toHaveLength(1)
    vi.advanceTimersByTime(1_000)
    expect(sockets).toHaveLength(2)
    sockets[1]!.onclose?.({})
    vi.advanceTimersByTime(1_999)
    expect(sockets).toHaveLength(2)
    vi.advanceTimersByTime(1)
    expect(sockets).toHaveLength(3)
  })

  it("stops reconnecting after dispose", () => {
    vi.useFakeTimers()
    sockets[0]!.onclose?.({})
    client.dispose()
    vi.advanceTimersByTime(60_000)
    expect(sockets).toHaveLength(1)
  })
})
