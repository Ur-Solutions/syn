"use client"

export function UpgradePlanButton({ planId }: { planId: string }) {
  return (
    <button
      type="button"
      data-testid="upgrade-plan-button"
      onClick={() => console.log(`upgrade ${planId}`)}
      style={{ padding: "10px 18px", borderRadius: 8, cursor: "pointer" }}
    >
      {/* Nested span: hovering it must promote to this button. */}
      <span aria-hidden="true" style={{ marginRight: 6 }}>
        ★
      </span>
      Upgrade plan
    </button>
  )
}
