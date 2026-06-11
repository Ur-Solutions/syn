<script>
  let { planId, price } = $props()
</script>

<section data-testid="plan-card" style="border: 1px solid #ddd; border-radius: 12px; padding: 24px;">
  <h2>Team plan</h2>
  <p>{price}</p>
  <button
    type="button"
    data-testid="upgrade-plan-button"
    style="padding: 10px 18px; border-radius: 8px; cursor: pointer;"
    onclick={() => console.log(`upgrade ${planId}`)}
  >
    <span aria-hidden="true" style="margin-right: 6px;">★</span>
    Upgrade plan
  </button>
</section>
