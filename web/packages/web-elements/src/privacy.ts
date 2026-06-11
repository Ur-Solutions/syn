// Props never leave the page unless explicitly enabled, and then only as
// redacted safe primitives (PRD "Props And Runtime Data").

const SKIP_KEYS = new Set(["children", "dangerouslySetInnerHTML", "ref", "key"])
const MAX_PROPS = 20
const MAX_STRING = 64

export interface SanitizedProps {
  props?: Record<string, unknown>
  redacted: boolean
}

export function sanitizeProps(
  raw: unknown,
  mode: "off" | "safe-primitives",
  redactKeys: string[],
): SanitizedProps {
  if (mode === "off" || raw === null || typeof raw !== "object") {
    return { redacted: false }
  }
  const lowered = redactKeys.map((key) => key.toLowerCase())
  const props: Record<string, unknown> = {}
  let redacted = false
  let count = 0
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (SKIP_KEYS.has(key)) continue
    if (count >= MAX_PROPS) break
    const keyLower = key.toLowerCase()
    if (lowered.some((needle) => keyLower.includes(needle))) {
      props[key] = "[redacted]"
      redacted = true
      count += 1
      continue
    }
    const safe = safePrimitive(value)
    if (safe !== undefined) {
      props[key] = safe
      count += 1
    }
  }
  return { props: count > 0 ? props : undefined, redacted }
}

function safePrimitive(value: unknown): unknown {
  if (value === null) return null
  switch (typeof value) {
    case "boolean":
      return value
    case "number":
      return Number.isFinite(value) ? value : undefined
    case "string":
      return value.length <= MAX_STRING ? value : `${value.slice(0, MAX_STRING)}…`
    default:
      // Objects, arrays, functions, symbols, bigints: omitted entirely.
      return undefined
  }
}
