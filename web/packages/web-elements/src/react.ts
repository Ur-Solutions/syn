// Zero-touch React resolution: walk the fiber attached to the DOM node to the
// nearest function/class component. Dev-only data sources, in order:
//   - `_debugSource` (React <=18 with the dev JSX transform): exact file:line:col.
//   - `_debugStack` (React 19 dev): an Error capturing the JSX callsite; parsed.
// React internals are not a public API; everything here is defensive and returns
// null rather than throwing.

import type { FrameworkBlock } from "./protocol"
import { sanitizeProps } from "./privacy"
import type { ResolvedConfig } from "./config"

interface DebugSource {
  fileName?: string
  lineNumber?: number
  columnNumber?: number
}

interface FiberLike {
  tag?: number
  type?: unknown
  return?: FiberLike | null
  memoizedProps?: unknown
  _debugSource?: DebugSource | null
  _debugStack?: { stack?: string } | string | null
}

// Component fiber tags across React 17-19.
const FUNCTION_COMPONENT = 0
const CLASS_COMPONENT = 1
const FORWARD_REF = 11
const MEMO_COMPONENT = 14
const SIMPLE_MEMO_COMPONENT = 15
const COMPONENT_TAGS = new Set([
  FUNCTION_COMPONENT, CLASS_COMPONENT, FORWARD_REF, MEMO_COMPONENT, SIMPLE_MEMO_COMPONENT,
])

const OWNER_STACK_LIMIT = 8

export function findFiber(element: Element): FiberLike | null {
  const record = element as unknown as Record<string, unknown>
  for (const key of Object.keys(record)) {
    if (key.startsWith("__reactFiber$") || key.startsWith("__reactInternalInstance$")) {
      return (record[key] as FiberLike) ?? null
    }
  }
  return null
}

function componentName(type: unknown): string | undefined {
  if (typeof type === "function") {
    const fn = type as { displayName?: string; name?: string }
    return fn.displayName || fn.name || undefined
  }
  if (type && typeof type === "object") {
    const wrapped = type as {
      displayName?: string
      render?: { displayName?: string; name?: string }
      type?: unknown
    }
    if (wrapped.displayName) return wrapped.displayName
    if (wrapped.render) return wrapped.render.displayName || wrapped.render.name || undefined
    if (wrapped.type) return componentName(wrapped.type)
  }
  return undefined
}

function normalizeSourcePath(file: string): string {
  let path = file
  // Vite served URLs and bundler pseudo-protocols down to plain paths.
  path = path.replace(/^webpack-internal:\/\/\//, "").replace(/^webpack:\/\//, "")
  if (/^https?:\/\//.test(path)) {
    try {
      path = new URL(path).pathname
    } catch {
      // keep as-is
    }
  }
  path = path.replace(/^\/@fs\//, "/")
  path = path.replace(/^\/\.\//, "")
  const queryIndex = path.indexOf("?")
  if (queryIndex >= 0) path = path.slice(0, queryIndex)
  return path
}

function formatDebugSource(source: DebugSource): string | undefined {
  if (!source.fileName) return undefined
  let formatted = normalizeSourcePath(source.fileName)
  if (source.lineNumber !== undefined) {
    formatted += `:${source.lineNumber}`
    if (source.columnNumber !== undefined) formatted += `:${source.columnNumber}`
  }
  return formatted
}

/** Parse a React 19 `_debugStack` (Error or string): first frame that is not
 * react-internal and not in node_modules is the JSX callsite. */
export function sourceFromDebugStack(stack: string): string | undefined {
  for (const line of stack.split("\n")) {
    const match = /(?:at\s+.*?\(|at\s+|@)?((?:https?:\/\/|webpack|file:|\/)[^\s)]+?):(\d+):(\d+)\)?\s*$/.exec(line.trim())
    if (!match) continue
    const [, file, lineNumber, column] = match
    if (!file) continue
    if (/node_modules|react-dom|react-server|jsx-dev-runtime|chunk-/.test(file)) continue
    return `${normalizeSourcePath(file)}:${lineNumber}:${column}`
  }
  return undefined
}

function fiberSource(fiber: FiberLike): string | undefined {
  if (fiber._debugSource) {
    const formatted = formatDebugSource(fiber._debugSource)
    if (formatted) return formatted
  }
  const debugStack = fiber._debugStack
  const stack = typeof debugStack === "string" ? debugStack : debugStack?.stack
  if (stack) return sourceFromDebugStack(stack)
  return undefined
}

export function resolveReact(element: Element, config: ResolvedConfig): FrameworkBlock | null {
  let fiber: FiberLike | null
  try {
    fiber = findFiber(element)
  } catch {
    return null
  }
  if (!fiber) return null

  // The host fiber's debug source is the JSX callsite of the DOM element itself —
  // the most precise location. Component fibers further up are the fallback.
  let source = fiberSource(fiber)

  let componentFiber: FiberLike | null = null
  const ownerStack: string[] = []
  for (let node = fiber.return ?? null; node && ownerStack.length < OWNER_STACK_LIMIT; node = node.return ?? null) {
    if (node.tag === undefined || !COMPONENT_TAGS.has(node.tag)) continue
    const name = componentName(node.type)
    if (!name) continue
    if (!componentFiber) componentFiber = node
    ownerStack.push(name)
    if (!source) source = fiberSource(node)
  }

  const block: FrameworkBlock = { name: "react" }
  if (componentFiber) {
    block.componentName = ownerStack[0]
    // Outermost-first, matching the PRD example ["BillingPage","PlanCard","UpgradePlanButton"].
    block.ownerStack = [...ownerStack].reverse()
  }
  if (source) block.source = source

  if (config.propsMode !== "off" && componentFiber?.memoizedProps !== undefined) {
    const { props, redacted } = sanitizeProps(componentFiber.memoizedProps, config.propsMode, config.redactKeys)
    block.propsMode = config.propsMode
    block.propsRedacted = redacted
    if (props) block.props = props
  }

  return block.componentName || block.source ? block : null
}
