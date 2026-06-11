import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"
import { synWebElements } from "@syn/web-elements/vite-react"

export default defineConfig({
  plugins: [
    react(),
    synWebElements({
      props: { mode: "safe-primitives" },
    }),
  ],
  server: {
    port: 5173,
  },
})
