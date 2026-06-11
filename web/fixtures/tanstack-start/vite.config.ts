import { defineConfig } from "vite"
import { tanstackStart } from "@tanstack/react-start/plugin/vite"
import viteReact from "@vitejs/plugin-react"
import { synWebElements } from "@syn/web-elements/tanstack-start"

export default defineConfig({
  plugins: [
    tanstackStart(),
    viteReact(),
    synWebElements({
      props: { mode: "safe-primitives" },
    }),
  ],
})
