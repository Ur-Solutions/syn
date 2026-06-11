import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { BillingPage } from "./BillingPage"

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <BillingPage />
  </StrictMode>,
)
