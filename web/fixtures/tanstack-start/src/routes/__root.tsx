import { createRootRoute, HeadContent, Outlet, Scripts } from "@tanstack/react-router"

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { title: "Syn Web Elements Fixture — TanStack Start" },
    ],
  }),
  component: RootComponent,
})

function RootComponent() {
  return (
    <html lang="en">
      <head>
        <HeadContent />
      </head>
      <body style={{ fontFamily: "system-ui", margin: 0 }}>
        <Outlet />
        <Scripts />
      </body>
    </html>
  )
}
