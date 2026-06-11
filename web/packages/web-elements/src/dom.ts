// DOM-level resolution: interactive-ancestor promotion, selector building, and
// ARIA identity. Heuristics follow docs/ELEMENT_INTELLIGENCE_PRD.md ("Element
// Targeting Heuristics").

const INTERACTIVE_TAGS = new Set([
  "button", "a", "input", "select", "textarea", "summary", "option", "label", "details",
])

const INTERACTIVE_ROLES = new Set([
  "button", "link", "menuitem", "menuitemcheckbox", "menuitemradio", "tab", "checkbox",
  "radio", "switch", "combobox", "option", "slider", "spinbutton", "searchbox",
  "textbox", "listbox", "treeitem",
])

const TEST_ID_ATTRIBUTES = ["data-testid", "data-test", "data-test-id", "data-cy"]

export function isInteractive(element: Element): boolean {
  const tag = element.tagName.toLowerCase()
  if (INTERACTIVE_TAGS.has(tag)) {
    // Anchors only count when they actually navigate or act.
    return tag !== "a" || element.hasAttribute("href")
  }
  const role = element.getAttribute("role")
  if (role && INTERACTIVE_ROLES.has(role)) return true
  const tabIndex = element.getAttribute("tabindex")
  if (tabIndex !== null && Number(tabIndex) >= 0) return true
  if ((element as HTMLElement).isContentEditable) return true
  return false
}

export function testId(element: Element): string | undefined {
  for (const attribute of TEST_ID_ATTRIBUTES) {
    const value = element.getAttribute(attribute)
    if (value) return value
  }
  return undefined
}

function hasStableIdentity(element: Element): boolean {
  return testId(element) !== undefined
    || element.hasAttribute("aria-label")
    || element.hasAttribute("aria-labelledby")
}

/** Promote a raw elementFromPoint leaf (often a span/icon) to the element a user
 * means: the nearest interactive ancestor, else the nearest ancestor with a stable
 * identity, else the leaf itself. */
export function promoteTarget(leaf: Element): Element {
  let stable: Element | null = null
  let node: Element | null = leaf
  for (let depth = 0; node && depth < 10; depth += 1, node = node.parentElement) {
    if (isInteractive(node)) return node
    if (!stable && hasStableIdentity(node)) stable = node
  }
  return stable ?? leaf
}

function cssEscape(value: string): string {
  const css = (globalThis as { CSS?: { escape?: (v: string) => string } }).CSS
  if (css?.escape) return css.escape(value)
  return value.replace(/["\\\]]/g, "\\$&")
}

function attributeSelector(element: Element): string | undefined {
  for (const attribute of TEST_ID_ATTRIBUTES) {
    const value = element.getAttribute(attribute)
    if (value) return `[${attribute}="${cssEscape(value)}"]`
  }
  return undefined
}

function segmentFor(element: Element): { segment: string; terminal: boolean } {
  const byAttribute = attributeSelector(element)
  if (byAttribute) return { segment: byAttribute, terminal: true }
  if (element.id) return { segment: `#${cssEscape(element.id)}`, terminal: true }

  const tag = element.tagName.toLowerCase()
  const parent = element.parentElement
  if (!parent) return { segment: tag, terminal: true }
  const sameTagSiblings = Array.from(parent.children).filter(
    (child) => child.tagName === element.tagName,
  )
  if (sameTagSiblings.length === 1) return { segment: tag, terminal: false }
  const index = sameTagSiblings.indexOf(element) + 1
  return { segment: `${tag}:nth-of-type(${index})`, terminal: false }
}

/** Short, stable-leaning selector: test id or #id when present, otherwise a
 * structural path of up to 5 segments anchored at the nearest id/test-id ancestor. */
export function buildSelector(element: Element): string {
  const segments: string[] = []
  let node: Element | null = element
  for (let depth = 0; node && depth < 5; depth += 1) {
    const { segment, terminal } = segmentFor(node)
    segments.unshift(segment)
    if (terminal) break
    node = node.parentElement
    if (node && (node.tagName === "BODY" || node.tagName === "HTML")) break
  }
  return segments.join(" > ")
}

const IMPLICIT_ROLES: Record<string, string> = {
  button: "button",
  select: "combobox",
  textarea: "textbox",
  summary: "button",
  option: "option",
  img: "img",
  nav: "navigation",
  main: "main",
  form: "form",
}

export function ariaRole(element: Element): string | undefined {
  const explicit = element.getAttribute("role")
  if (explicit) return explicit
  const tag = element.tagName.toLowerCase()
  if (tag === "a") return element.hasAttribute("href") ? "link" : undefined
  if (tag === "input") {
    const type = (element.getAttribute("type") ?? "text").toLowerCase()
    if (type === "checkbox" || type === "radio" || type === "button") return type
    if (type === "submit" || type === "reset") return "button"
    if (type === "search") return "searchbox"
    if (type === "range") return "slider"
    return "textbox"
  }
  return IMPLICIT_ROLES[tag]
}

function collapse(text: string | null | undefined, limit: number): string | undefined {
  const collapsed = text?.replace(/\s+/g, " ").trim()
  if (!collapsed) return undefined
  return collapsed.length > limit ? `${collapsed.slice(0, limit)}…` : collapsed
}

/** Accessible-name approximation: aria-label, aria-labelledby, <label for>,
 * alt/title, then visible text. */
export function accessibleName(element: Element): string | undefined {
  const ariaLabel = collapse(element.getAttribute("aria-label"), 120)
  if (ariaLabel) return ariaLabel

  const labelledBy = element.getAttribute("aria-labelledby")
  if (labelledBy) {
    const text = labelledBy
      .split(/\s+/)
      .map((id) => element.ownerDocument.getElementById(id)?.textContent ?? "")
      .join(" ")
    const name = collapse(text, 120)
    if (name) return name
  }

  if (element.id) {
    const label = element.ownerDocument.querySelector(`label[for="${cssEscape(element.id)}"]`)
    const name = collapse(label?.textContent, 120)
    if (name) return name
  }

  return collapse(element.getAttribute("alt"), 120)
    ?? collapse(element.getAttribute("title"), 120)
    ?? visibleText(element)
}

export function visibleText(element: Element): string | undefined {
  const text = (element as HTMLElement).innerText ?? element.textContent
  return collapse(text, 120)
}

const SAFE_ATTRIBUTES = new Set(["id", "class", "type", "name", "role", "placeholder", "for", "disabled"])

/** Safe attribute subset: never input values; href without query/hash; all
 * aria-* and data-*, values capped. */
export function safeAttributes(element: Element): Record<string, string> | undefined {
  const attributes: Record<string, string> = {}
  for (const attribute of Array.from(element.attributes)) {
    const name = attribute.name.toLowerCase()
    if (name === "value") continue
    if (name === "href") {
      attributes.href = attribute.value.split(/[?#]/)[0] ?? ""
      continue
    }
    if (SAFE_ATTRIBUTES.has(name) || name.startsWith("aria-") || name.startsWith("data-")) {
      attributes[name] = attribute.value.length > 100
        ? `${attribute.value.slice(0, 100)}…`
        : attribute.value
    }
  }
  return Object.keys(attributes).length > 0 ? attributes : undefined
}
