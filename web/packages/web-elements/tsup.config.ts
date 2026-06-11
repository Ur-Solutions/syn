import { defineConfig } from "tsup"

export default defineConfig({
  entry: {
    index: "src/index.ts",
    auto: "src/auto.ts",
    "adapters/vite-react": "src/adapters/vite-react.ts",
    "adapters/next": "src/adapters/next.ts",
    "adapters/tanstack-start": "src/adapters/tanstack-start.ts",
    "adapters/svelte": "src/adapters/svelte.ts",
  },
  format: ["esm", "cjs"],
  dts: true,
  sourcemap: true,
  clean: true,
  external: ["vite"],
})
