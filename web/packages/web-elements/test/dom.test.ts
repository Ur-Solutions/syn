import { describe, expect, it } from "vitest"
import {
  accessibleName,
  ariaRole,
  buildSelector,
  promoteTarget,
  safeAttributes,
} from "../src/dom"

function html(markup: string): HTMLElement {
  document.body.innerHTML = markup
  return document.body
}

describe("promoteTarget", () => {
  it("promotes a nested span to its button", () => {
    const body = html(`<button data-testid="upgrade-plan-button"><span class="icon">★</span></button>`)
    const span = body.querySelector("span")!
    expect(promoteTarget(span).tagName).toBe("BUTTON")
  })

  it("promotes through multiple decorative levels", () => {
    const body = html(`<a href="/billing"><span><svg><path /></svg></span></a>`)
    const path = body.querySelector("path")!
    expect(promoteTarget(path).tagName).toBe("A")
  })

  it("treats role=button as interactive", () => {
    const body = html(`<div role="button"><span>Go</span></div>`)
    const span = body.querySelector("span")!
    expect(promoteTarget(span).getAttribute("role")).toBe("button")
  })

  it("ignores anchors without href", () => {
    const body = html(`<a><span id="leaf">x</span></a>`)
    const span = body.querySelector("#leaf")!
    expect(promoteTarget(span)).toBe(span)
  })

  it("falls back to a test-id ancestor when nothing is interactive", () => {
    const body = html(`<div data-testid="card"><div><span id="leaf">text</span></div></div>`)
    const span = body.querySelector("#leaf")!
    expect(promoteTarget(span).getAttribute("data-testid")).toBe("card")
  })

  it("keeps the leaf when nothing better exists", () => {
    const body = html(`<div><span id="leaf">text</span></div>`)
    const span = body.querySelector("#leaf")!
    expect(promoteTarget(span)).toBe(span)
  })
})

describe("buildSelector", () => {
  it("prefers data-testid", () => {
    const body = html(`<button data-testid="upgrade-plan-button">Up</button>`)
    expect(buildSelector(body.querySelector("button")!)).toBe(`[data-testid="upgrade-plan-button"]`)
  })

  it("uses the matching test attribute name", () => {
    const body = html(`<button data-test="save">Save</button>`)
    expect(buildSelector(body.querySelector("button")!)).toBe(`[data-test="save"]`)
  })

  it("uses ids", () => {
    const body = html(`<button id="save">Save</button>`)
    expect(buildSelector(body.querySelector("button")!)).toBe("#save")
  })

  it("disambiguates same-tag siblings with nth-of-type", () => {
    const body = html(`<ul><li>a</li><li id="">b</li><li>c</li></ul>`)
    const second = body.querySelectorAll("li")[1]!
    expect(buildSelector(second)).toBe("ul > li:nth-of-type(2)")
  })

  it("anchors paths at a test-id ancestor", () => {
    const body = html(`<div data-testid="card"><div><button>Go</button></div></div>`)
    expect(buildSelector(body.querySelector("button")!)).toBe(`[data-testid="card"] > div > button`)
  })
})

describe("ariaRole", () => {
  it("maps implicit roles", () => {
    const body = html(`<button>x</button><a href="/y">y</a><a id="bare">z</a><input type="checkbox" /><input />`)
    expect(ariaRole(body.querySelector("button")!)).toBe("button")
    expect(ariaRole(body.querySelector("a[href]")!)).toBe("link")
    expect(ariaRole(body.querySelector("#bare")!)).toBeUndefined()
    expect(ariaRole(body.querySelector("input[type=checkbox]")!)).toBe("checkbox")
    expect(ariaRole(body.querySelector("input:not([type])")!)).toBe("textbox")
  })

  it("prefers explicit role", () => {
    const body = html(`<div role="tab">x</div>`)
    expect(ariaRole(body.querySelector("div")!)).toBe("tab")
  })
})

describe("accessibleName", () => {
  it("prefers aria-label", () => {
    const body = html(`<button aria-label="Close dialog">×</button>`)
    expect(accessibleName(body.querySelector("button")!)).toBe("Close dialog")
  })

  it("resolves label[for]", () => {
    const body = html(`<label for="mail">Work address</label><input id="mail" />`)
    expect(accessibleName(body.querySelector("input")!)).toBe("Work address")
  })

  it("falls back to visible text, collapsed", () => {
    const body = html(`<button>  Upgrade\n   plan </button>`)
    expect(accessibleName(body.querySelector("button")!)).toBe("Upgrade plan")
  })
})

describe("safeAttributes", () => {
  it("omits input values and strips href queries", () => {
    const body = html(
      `<input value="hunter2" type="text" name="pw" /><a href="/x?token=abc#frag">x</a>`,
    )
    const input = safeAttributes(body.querySelector("input")!)!
    expect(input.value).toBeUndefined()
    expect(input.type).toBe("text")
    expect(input.name).toBe("pw")
    const anchor = safeAttributes(body.querySelector("a")!)!
    expect(anchor.href).toBe("/x")
  })

  it("keeps data-* and aria-*", () => {
    const body = html(`<button data-testid="b" aria-pressed="false" onclick="x()">b</button>`)
    const attributes = safeAttributes(body.querySelector("button")!)!
    expect(attributes["data-testid"]).toBe("b")
    expect(attributes["aria-pressed"]).toBe("false")
    expect(attributes.onclick).toBeUndefined()
  })
})
