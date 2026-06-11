import { PlanCard } from "./components/PlanCard"

export default function BillingPage() {
  return (
    <main style={{ maxWidth: 640, margin: "48px auto" }}>
      <h1>Billing (Next)</h1>
      <p>Syn web-elements fixture. Hover and flag the controls below.</p>
      <PlanCard planId="team" price="$12/mo" />
      <form style={{ marginTop: 32, display: "grid", gap: 8 }}>
        <label htmlFor="billing-email">Billing email</label>
        <input id="billing-email" type="email" placeholder="you@example.com" />
        <a href="/invoices?token=should-not-leak">View invoices</a>
      </form>
    </main>
  )
}
