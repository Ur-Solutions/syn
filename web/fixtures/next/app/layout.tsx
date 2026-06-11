import type { ReactNode } from "react"

export const metadata = {
  title: "Syn Web Elements Fixture — Next",
}

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: "system-ui", margin: 0 }}>{children}</body>
    </html>
  )
}
