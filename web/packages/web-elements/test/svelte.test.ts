import { describe, expect, it } from "vitest"
import { resolveSvelte } from "../src/svelte"

describe("resolveSvelte", () => {
  it("returns null without __svelte_meta", () => {
    expect(resolveSvelte(document.createElement("div"))).toBeNull()
  })

  it("reads loc from the element", () => {
    const button = document.createElement("button")
    ;(button as unknown as Record<string, unknown>).__svelte_meta = {
      loc: { file: "src/lib/PlanCard.svelte", line: 12, column: 4 },
    }
    const block = resolveSvelte(button)!
    expect(block.name).toBe("svelte")
    expect(block.componentName).toBe("PlanCard")
    expect(block.source).toBe("src/lib/PlanCard.svelte:12:4")
  })

  it("climbs to an ancestor with metadata", () => {
    const wrapper = document.createElement("div")
    ;(wrapper as unknown as Record<string, unknown>).__svelte_meta = {
      loc: { file: "src/App.svelte", line: 3, column: 0 },
    }
    const leaf = document.createElement("span")
    wrapper.appendChild(leaf)
    expect(resolveSvelte(leaf)!.componentName).toBe("App")
  })
})
