import { describe, expect, it } from "vitest"
import {
  isInsideViewport,
  screenPointToViewport,
  viewportRectToScreen,
  zoomFactor,
  type WindowMetrics,
} from "../src/coords"

function metrics(overrides: Partial<WindowMetrics> = {}): WindowMetrics {
  return {
    screenX: 0,
    screenY: 0,
    innerWidth: 1000,
    innerHeight: 700,
    outerWidth: 1000,
    outerHeight: 700,
    devicePixelRatio: 2,
    ...overrides,
  }
}

describe("zoomFactor", () => {
  it("is 1 at no zoom", () => {
    expect(zoomFactor(metrics())).toBe(1)
  })

  it("snaps near-stop ratios (scrollbar error) to the stop", () => {
    expect(zoomFactor(metrics({ outerWidth: 1253 }))).toBe(1.25)
  })

  it("returns the raw ratio when no stop is close", () => {
    expect(zoomFactor(metrics({ outerWidth: 1370 }))).toBeCloseTo(1.37)
  })

  it("guards against jsdom-style zero outer sizes", () => {
    expect(zoomFactor(metrics({ outerWidth: 0 }))).toBe(1)
  })
})

describe("screen <-> viewport mapping", () => {
  // Window at (100, 50), 125% zoom, 55pt of chrome above the viewport.
  const zoomed = metrics({
    screenX: 100,
    screenY: 50,
    outerWidth: 1250,
    outerHeight: 930,
  })

  it("maps a screen point into viewport CSS px", () => {
    const point = screenPointToViewport(200, 155, zoomed)
    expect(point.x).toBeCloseTo(80)
    expect(point.y).toBeCloseTo(40)
  })

  it("maps a viewport rect back to screen points", () => {
    const rect = viewportRectToScreen({ x: 80, y: 40, width: 100, height: 20 }, zoomed)
    expect(rect.x).toBeCloseTo(200)
    expect(rect.y).toBeCloseTo(155)
    expect(rect.width).toBeCloseTo(125)
    expect(rect.height).toBeCloseTo(25)
  })

  it("round-trips at 100% zoom on a secondary-display offset", () => {
    const plain = metrics({ screenX: -1440, screenY: 200, outerHeight: 780 })
    const point = screenPointToViewport(-1400, 300, plain)
    expect(point.x).toBeCloseTo(40)
    expect(point.y).toBeCloseTo(20) // 80pt chrome
    const back = viewportRectToScreen({ x: point.x, y: point.y, width: 10, height: 10 }, plain)
    expect(back.x).toBeCloseTo(-1400)
    expect(back.y).toBeCloseTo(300)
  })

  it("DPR does not affect point mapping (it is metadata only)", () => {
    const a = screenPointToViewport(500, 400, metrics({ devicePixelRatio: 1 }))
    const b = screenPointToViewport(500, 400, metrics({ devicePixelRatio: 2 }))
    expect(a).toEqual(b)
  })
})

describe("isInsideViewport", () => {
  it("accepts inside, rejects outside", () => {
    const m = metrics()
    expect(isInsideViewport({ x: 10, y: 10 }, m)).toBe(true)
    expect(isInsideViewport({ x: -5, y: 10 }, m)).toBe(false)
    expect(isInsideViewport({ x: 10, y: 800 }, m)).toBe(false)
  })
})
