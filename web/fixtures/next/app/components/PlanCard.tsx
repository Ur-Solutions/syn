import { UpgradePlanButton } from "./UpgradePlanButton"

export function PlanCard({ planId, price }: { planId: string; price: string }) {
  return (
    <section
      data-testid="plan-card"
      style={{ border: "1px solid #ddd", borderRadius: 12, padding: 24 }}
    >
      <h2>Team plan</h2>
      <p>{price}</p>
      <UpgradePlanButton planId={planId} />
    </section>
  )
}
