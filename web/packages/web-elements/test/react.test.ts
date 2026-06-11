import { describe, expect, it } from "vitest"
import { resolveReact, sourceFromDebugStack } from "../src/react"
import { resolveConfig } from "../src/config"

const offConfig = resolveConfig({})
const propsConfig = resolveConfig({ props: { mode: "safe-primitives" } })

function UpgradePlanButton() {}
function PlanCard() {}
function BillingPage() {}

interface FakeFiber {
  tag?: number
  type?: unknown
  return?: FakeFiber | null
  memoizedProps?: unknown
  _debugSource?: { fileName: string; lineNumber: number; columnNumber?: number }
  _debugStack?: { stack: string }
}

function attach(element: Element, fiber: FakeFiber): void {
  ;(element as unknown as Record<string, unknown>)["__reactFiber$test123"] = fiber
}

function fiberChain(host: Partial<FakeFiber>): FakeFiber {
  const billing: FakeFiber = { tag: 0, type: BillingPage, return: null }
  const card: FakeFiber = { tag: 0, type: PlanCard, return: billing }
  const component: FakeFiber = {
    tag: 0,
    type: UpgradePlanButton,
    return: card,
    memoizedProps: {
      variant: "primary",
      disabled: false,
      planId: "team",
      authToken: "s3cret",
      onClick: () => {},
      children: "Upgrade",
    },
  }
  return { tag: 5, type: "button", return: component, ...host }
}

describe("resolveReact", () => {
  it("returns null without a fiber", () => {
    const element = document.createElement("button")
    expect(resolveReact(element, offConfig)).toBeNull()
  })

  it("finds component name, owner stack, and _debugSource location", () => {
    const element = document.createElement("button")
    attach(element, fiberChain({
      _debugSource: { fileName: "/src/billing/UpgradePlanButton.tsx", lineNumber: 38, columnNumber: 7 },
    }))
    const block = resolveReact(element, offConfig)!
    expect(block.name).toBe("react")
    expect(block.componentName).toBe("UpgradePlanButton")
    expect(block.ownerStack).toEqual(["BillingPage", "PlanCard", "UpgradePlanButton"])
    expect(block.source).toBe("/src/billing/UpgradePlanButton.tsx:38:7")
    expect(block.props).toBeUndefined()
  })

  it("falls back to React 19 _debugStack parsing", () => {
    const element = document.createElement("button")
    attach(element, fiberChain({
      _debugStack: {
        stack: [
          "Error",
          "    at jsxDEV (http://localhost:5173/node_modules/.vite/deps/react_jsx-dev-runtime.js:10:5)",
          "    at UpgradePlanButton (http://localhost:5173/src/billing/UpgradePlanButton.tsx?t=99:38:7)",
          "    at renderWithHooks (http://localhost:5173/node_modules/.vite/deps/react-dom.js:999:1)",
        ].join("\n"),
      },
    }))
    const block = resolveReact(element, offConfig)!
    expect(block.source).toBe("/src/billing/UpgradePlanButton.tsx:38:7")
  })

  it("sanitizes props in safe-primitives mode", () => {
    const element = document.createElement("button")
    attach(element, fiberChain({}))
    const block = resolveReact(element, propsConfig)!
    expect(block.propsMode).toBe("safe-primitives")
    expect(block.propsRedacted).toBe(true)
    expect(block.props).toEqual({
      variant: "primary",
      disabled: false,
      planId: "team",
      authToken: "[redacted]",
    })
  })

  it("filters framework internals and names server components from their source", () => {
    // RSC-rendered DOM: the only function fibers above it are Next router internals
    // (observed with Next 15 app router); the host's _debugStack still names the file.
    function SegmentViewNode() {}
    function InnerLayoutRouter() {}
    function LoadingBoundary() {}
    const internals: FakeFiber = {
      tag: 0,
      type: SegmentViewNode,
      memoizedProps: { pagePath: "page.tsx", type: "page" },
      return: { tag: 0, type: InnerLayoutRouter, return: { tag: 0, type: LoadingBoundary, return: null } },
    }
    const element = document.createElement("section")
    attach(element, {
      tag: 5,
      type: "section",
      return: internals,
      _debugStack: {
        stack: "    at PlanCard (http://localhost:3030/app/components/PlanCard.tsx:11:87)",
      },
    })
    const block = resolveReact(element, propsConfig)!
    expect(block.componentName).toBe("PlanCard")
    expect(block.ownerStack).toBeUndefined()
    expect(block.source).toBe("/app/components/PlanCard.tsx:11:87")
    expect(block.props).toBeUndefined()
  })

  it("resolves forwardRef and memo wrappers", () => {
    const element = document.createElement("input")
    const render = function FancyInput() {}
    attach(element, {
      tag: 5,
      type: "input",
      return: { tag: 11, type: { render }, return: null },
    })
    expect(resolveReact(element, offConfig)!.componentName).toBe("FancyInput")
  })
})

describe("sourceFromDebugStack", () => {
  it("skips internal frames", () => {
    const source = sourceFromDebugStack([
      "    at jsx (http://localhost:3000/node_modules/react/jsx-dev-runtime.js:5:1)",
      "    at App (http://localhost:3000/src/App.tsx:12:9)",
    ].join("\n"))
    expect(source).toBe("/src/App.tsx:12:9")
  })

  it("handles webpack-internal frames, dropping the bundle-layer prefix", () => {
    const source = sourceFromDebugStack(
      "    at Page (webpack-internal:///(app-pages-browser)/./app/page.tsx:22:88)",
    )
    expect(source).toBe("app/page.tsx:22:88")
  })

  it("returns undefined for empty stacks", () => {
    expect(sourceFromDebugStack("Error")).toBeUndefined()
  })
})
