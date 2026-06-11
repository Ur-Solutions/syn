// PRD acceptance fixture: flagging the upgrade button must yield
// tag/selector/testid/component name/source file:line, and the nested span must
// promote to its button.

import { PlanCard } from "./PlanCard"

export function BillingPage() {
  return (
    <main style={{ fontFamily: "system-ui", maxWidth: 640, margin: "48px auto" }}>
      <h1>Billing</h1>
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
