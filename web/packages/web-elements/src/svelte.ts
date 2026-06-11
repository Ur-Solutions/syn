// Zero-touch Svelte resolution: in dev builds (vite-plugin-svelte sets
// `dev: true`), Svelte attaches `__svelte_meta = { loc: { file, line, column } }`
// to every element it creates — free source locations. Component name is the
// .svelte file's basename.

import type { FrameworkBlock } from "./protocol"

interface SvelteMeta {
  loc?: {
    file?: string
    line?: number
    column?: number
  }
}

export function resolveSvelte(element: Element): FrameworkBlock | null {
  let node: Element | null = element
  for (let depth = 0; node && depth < 10; depth += 1, node = node.parentElement) {
    const meta = (node as unknown as { __svelte_meta?: SvelteMeta }).__svelte_meta
    const loc = meta?.loc
    if (!loc?.file) continue

    const block: FrameworkBlock = { name: "svelte" }
    const basename = loc.file.split(/[\\/]/).pop()
    if (basename?.endsWith(".svelte")) {
      block.componentName = basename.slice(0, -".svelte".length)
    }
    let source = loc.file
    if (loc.line !== undefined) {
      source += `:${loc.line}`
      if (loc.column !== undefined) source += `:${loc.column}`
    }
    block.source = source
    return block
  }
  return null
}
