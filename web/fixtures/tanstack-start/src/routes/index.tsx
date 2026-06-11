import { createFileRoute } from "@tanstack/react-router"
import { PlanCard } from "../components/PlanCard"

export const Route = createFileRoute("/")({
  component: BillingPage,
})

function BillingPage() {
  return (
    <main style={{ maxWidth: 640, margin: "48px auto" }}>
      <h1>Billing (TanStack Start)</h1>
      <p>Syn web-elements fixture. Hover and flag the controls below.</p>
      <PlanCard planId="team" price="$12/mo" />
    </main>
  )
}
