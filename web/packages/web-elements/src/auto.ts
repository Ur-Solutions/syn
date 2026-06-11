// Side-effect entry: `import "@syn/web-elements/auto"` from any client entry file
// when an adapter cannot inject automatically. Dev-only via the standard
// bundler-inlined NODE_ENV check.

import { initSynWebElements } from "./index"

if (typeof process === "undefined" || process.env?.NODE_ENV !== "production") {
  initSynWebElements({ adapter: "auto" })
}
