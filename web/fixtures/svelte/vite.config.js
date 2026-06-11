import { defineConfig } from "vite"
import { svelte } from "@sveltejs/vite-plugin-svelte"
import { synWebElements } from "@syn/web-elements/svelte"

export default defineConfig({
  plugins: [svelte(), synWebElements()],
  server: {
    port: 5174,
  },
})
