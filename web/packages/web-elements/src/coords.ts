// Screen <-> viewport mapping. Global screen coordinates are top-left-origin
// points (the space window.screenX lives in on macOS). Viewport coordinates are
// CSS pixels. The two differ by the window position, the browser chrome height,
// and the page zoom factor. This mapping is the classic source of bugs (PRD
// "Browser Coordinate Mapping"), which is why snapshots carry BOTH the raw
// viewport rect and the normalized screen rect.

import type { Rect } from "./protocol"

export interface WindowMetrics {
  screenX: number
  screenY: number
  innerWidth: number
  innerHeight: number
  outerWidth: number
  outerHeight: number
  devicePixelRatio: number
}

export function windowMetrics(win: Window): WindowMetrics {
  return {
    screenX: win.screenX,
    screenY: win.screenY,
    innerWidth: win.innerWidth,
    innerHeight: win.innerHeight,
    outerWidth: win.outerWidth,
    outerHeight: win.outerHeight,
    devicePixelRatio: win.devicePixelRatio || 1,
  }
}

// Browsers quantize zoom; snapping outerWidth/innerWidth to the nearest stop
// absorbs scrollbar and border error.
const ZOOM_STOPS = [0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5]

export function zoomFactor(metrics: WindowMetrics): number {
  if (metrics.innerWidth <= 0 || metrics.outerWidth <= 0) return 1
  const raw = metrics.outerWidth / metrics.innerWidth
  let best = 1
  let bestDistance = Number.POSITIVE_INFINITY
  for (const stop of ZOOM_STOPS) {
    const distance = Math.abs(raw - stop)
    if (distance < bestDistance) {
      best = stop
      bestDistance = distance
    }
  }
  return bestDistance <= 0.04 ? best : raw
}

/** Chrome height above the viewport (tab strip + toolbars), in screen points. */
function chromeTop(metrics: WindowMetrics, zoom: number): number {
  if (metrics.outerHeight <= 0) return 0
  return Math.max(0, metrics.outerHeight - metrics.innerHeight * zoom)
}

/** Horizontal window border, assumed symmetric (0 on modern macOS browsers). */
function chromeLeft(metrics: WindowMetrics, zoom: number): number {
  if (metrics.outerWidth <= 0) return 0
  return Math.max(0, (metrics.outerWidth - metrics.innerWidth * zoom) / 2)
}

export function screenPointToViewport(
  screenX: number,
  screenY: number,
  metrics: WindowMetrics,
): { x: number; y: number } {
  const zoom = zoomFactor(metrics)
  return {
    x: (screenX - metrics.screenX - chromeLeft(metrics, zoom)) / zoom,
    y: (screenY - metrics.screenY - chromeTop(metrics, zoom)) / zoom,
  }
}

export function viewportRectToScreen(rect: Rect, metrics: WindowMetrics): Rect {
  const zoom = zoomFactor(metrics)
  return {
    x: metrics.screenX + chromeLeft(metrics, zoom) + rect.x * zoom,
    y: metrics.screenY + chromeTop(metrics, zoom) + rect.y * zoom,
    width: rect.width * zoom,
    height: rect.height * zoom,
  }
}

export function isInsideViewport(point: { x: number; y: number }, metrics: WindowMetrics): boolean {
  return point.x >= 0 && point.y >= 0
    && point.x <= metrics.innerWidth && point.y <= metrics.innerHeight
}
