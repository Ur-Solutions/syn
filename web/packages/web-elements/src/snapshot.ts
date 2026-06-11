// Builds the element snapshot for a lookup: screen point -> viewport point ->
// elementFromPoint -> same-origin iframe descent -> interactive promotion ->
// DOM identity + framework resolution -> bounds in both raw viewport CSS px and
// normalized global screen points.

import {
  type ElementSnapshotPayload,
  type FrameworkBlock,
  type Provider,
  type Rect,
} from "./protocol"
import type { ResolvedConfig } from "./config"
import {
  accessibleName,
  ariaRole,
  buildSelector,
  promoteTarget,
  safeAttributes,
  testId,
  visibleText,
} from "./dom"
import {
  isInsideViewport,
  screenPointToViewport,
  viewportRectToScreen,
  windowMetrics,
  zoomFactor,
} from "./coords"
import { resolveReact } from "./react"
import { resolveSvelte } from "./svelte"

interface HitResult {
  element: Element
  /** Offset of the element's document relative to the top-level viewport, CSS px. */
  frameOffsetX: number
  frameOffsetY: number
  framePath: string[]
}

const MAX_FRAME_DEPTH = 4

/** elementFromPoint with same-origin iframe descent. Cross-origin frames stop the
 * walk and report the iframe element itself (PRD: limited metadata is acceptable). */
function hitTest(doc: Document, x: number, y: number): HitResult | null {
  let currentDoc = doc
  let offsetX = 0
  let offsetY = 0
  const framePath: string[] = []
  for (let depth = 0; depth <= MAX_FRAME_DEPTH; depth += 1) {
    const element = currentDoc.elementFromPoint(x - offsetX, y - offsetY)
    if (!element) return null
    if (element.tagName === "IFRAME" || element.tagName === "FRAME") {
      let innerDoc: Document | null = null
      try {
        innerDoc = (element as HTMLIFrameElement).contentDocument
      } catch {
        innerDoc = null
      }
      if (innerDoc && depth < MAX_FRAME_DEPTH) {
        const rect = element.getBoundingClientRect()
        framePath.push(buildSelector(element))
        offsetX += rect.x
        offsetY += rect.y
        currentDoc = innerDoc
        continue
      }
    }
    return { element, frameOffsetX: offsetX, frameOffsetY: offsetY, framePath }
  }
  return null
}

function resolveFramework(element: Element, config: ResolvedConfig): FrameworkBlock | null {
  const resolvers = config.framework === "svelte"
    ? [resolveSvelte, (el: Element) => resolveReact(el, config)]
    : [(el: Element) => resolveReact(el, config), resolveSvelte]
  for (const resolver of resolvers) {
    try {
      const block = resolver(element)
      if (block) return block
    } catch {
      // Framework internals shifted under us; fall through to plain DOM.
    }
  }
  return null
}

function currentRoute(config: ResolvedConfig, win: Window): string | undefined {
  if (config.resolveRoute) {
    try {
      const route = config.resolveRoute()
      if (route) return route
    } catch {
      // fall through
    }
  }
  return win.location.pathname || undefined
}

export function buildSnapshotAtScreenPoint(
  screenX: number,
  screenY: number,
  config: ResolvedConfig,
  win: Window = window,
): ElementSnapshotPayload | null {
  const metrics = windowMetrics(win)
  const point = screenPointToViewport(screenX, screenY, metrics)
  if (!isInsideViewport(point, metrics)) return null

  const hit = hitTest(win.document, point.x, point.y)
  if (!hit) return null
  const leaf = hit.element
  const target = promoteTarget(leaf)

  const leafRect = leaf.getBoundingClientRect()
  const rect = target.getBoundingClientRect()
  // Bail when the page has no layout for this node — Syn falls back to AX.
  if (rect.width <= 0 && rect.height <= 0 && leafRect.width <= 0) return null

  const viewportRect: Rect = {
    x: rect.x + hit.frameOffsetX,
    y: rect.y + hit.frameOffsetY,
    width: rect.width,
    height: rect.height,
  }

  const framework = resolveFramework(target, config) ?? undefined
  const provider: Provider = framework?.name === "react"
    ? "browser.react"
    : framework?.name === "svelte"
      ? "browser.svelte"
      : "browser.dom"

  const url = `${win.location.origin}${win.location.pathname}`
  return {
    provider,
    identity: {
      role: ariaRole(target),
      label: accessibleName(target),
      text: visibleText(target),
      testId: testId(target),
    },
    web: {
      tagName: target.tagName.toLowerCase(),
      selector: buildSelector(target),
      leafSelector: leaf === target ? undefined : buildSelector(leaf),
      testId: testId(target),
      text: visibleText(target),
      url,
      route: currentRoute(config, win),
      title: win.document.title || undefined,
      attributes: safeAttributes(target),
      framePath: hit.framePath.length > 0 ? hit.framePath : undefined,
    },
    framework,
    bounds: {
      screen: viewportRectToScreen(viewportRect, metrics),
      viewport: viewportRect,
      devicePixelRatio: metrics.devicePixelRatio,
      zoom: zoomFactor(metrics),
    },
  }
}
