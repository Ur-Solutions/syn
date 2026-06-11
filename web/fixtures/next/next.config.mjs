import { withSynWebElements } from "@syn/web-elements/next"

export default withSynWebElements(
  { reactStrictMode: true },
  { props: { mode: "safe-primitives" } },
)
