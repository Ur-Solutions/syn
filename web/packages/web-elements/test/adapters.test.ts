import { describe, expect, it } from "vitest"
import { synWebElements as tanstackStart } from "../src/adapters/tanstack-start"
import { synWebElements as svelte } from "../src/adapters/svelte"

type TransformHook = (code: string, id: string, options?: { ssr?: boolean }) => { code: string } | undefined

function transformOf(plugin: unknown): TransformHook {
  const hook = (plugin as { transform: unknown }).transform
  return (typeof hook === "function" ? hook : (hook as { handler: unknown }).handler) as TransformHook
}

describe("tanstack-start client entry injection", () => {
  const transform = transformOf(tanstackStart({ enabled: true }))

  const matching = [
    "/repo/src/client.tsx",
    "/repo/app/client.tsx",
    // Bundled default entry used when the app has no explicit client entry
    // (observed with @tanstack/react-start 1.168).
    "/repo/node_modules/@tanstack/react-start/dist/plugin/default-entry/client.tsx",
    "\0virtual:tanstack-start-dev-client-entry",
    "virtual:tanstack-start-client-entry",
  ]

  it.each(matching)("injects into %s", (id) => {
    const result = transform("export {}", id, { ssr: false })
    expect(result?.code).toContain(`import "virtual:syn-web-elements"`)
  })

  it("ignores other modules and SSR passes", () => {
    expect(transform("export {}", "/repo/src/routes/index.tsx", { ssr: false })).toBeUndefined()
    expect(transform("export {}", "/repo/src/client.tsx", { ssr: true })).toBeUndefined()
  })
})

describe("svelte client entry injection", () => {
  it("covers the SvelteKit client entry", () => {
    const transform = transformOf(svelte({ enabled: true }))
    const result = transform("export {}", "/repo/src/entry-client.ts", { ssr: false })
    expect(result?.code).toContain(`import "virtual:syn-web-elements"`)
  })
})
