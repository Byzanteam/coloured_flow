import { forwardRef, type AnchorHTMLAttributes, type ReactNode } from "react"
import { render, screen, within } from "@testing-library/react"
import { MemoryRouter, Link as RouterLink } from "react-router-dom"
import { LinkProvider } from "@cloudflare/kumo"
import { describe, expect, it, vi } from "vitest"

import PageHeader from "./PageHeader"

vi.mock("../musubi", () => ({
  useMusubiConnectionStatus: vi.fn().mockReturnValue({
    state: "ready",
    connection: { __mock: "connection" }
  })
}))

const RouterAppLink = forwardRef<HTMLAnchorElement, AnchorHTMLAttributes<HTMLAnchorElement>>(
  ({ href, children, ...rest }, ref) => (
    <RouterLink ref={ref} to={href ?? ""} {...rest}>
      {children}
    </RouterLink>
  )
)
RouterAppLink.displayName = "RouterAppLink"

function renderWithRouter(ui: ReactNode, initial = "/") {
  return render(
    <MemoryRouter initialEntries={[initial]}>
      <LinkProvider component={RouterAppLink}>{ui}</LinkProvider>
    </MemoryRouter>
  )
}

describe("PageHeader", () => {
  it("renders the title and subtitle without breadcrumbs by default", () => {
    renderWithRouter(<PageHeader title="Inbox" subtitle="Live workitems" />)
    expect(screen.getByRole("heading", { name: "Inbox" })).not.toBeNull()
    expect(screen.getByText("Live workitems")).not.toBeNull()
    expect(screen.queryByTestId("page-header-breadcrumbs")).toBeNull()
  })

  it("renders a single-crumb breadcrumb without separator", () => {
    renderWithRouter(
      <PageHeader title="Inbox" breadcrumbs={[{ label: "Inbox" }]} />
    )
    const trail = screen.getByTestId("page-header-breadcrumbs")
    const nav = within(trail).getByRole("navigation", { name: /breadcrumb/i })
    // No separator path renders when there is only one crumb.
    expect(nav.querySelectorAll("svg").length).toBe(0)
    expect(within(trail).getAllByText("Inbox").length).toBeGreaterThan(0)
    expect(within(trail).queryByRole("link")).toBeNull()
  })

  it("renders a two-crumb breadcrumb with a React Router link for the first crumb", () => {
    renderWithRouter(
      <PageHeader
        title="Enactment"
        breadcrumbs={[
          { label: "Enactments", to: "/enactments" },
          { label: "abc12345" }
        ]}
      />,
      "/enactments/abc12345"
    )
    const trail = screen.getByTestId("page-header-breadcrumbs")
    // Kumo renders breadcrumb children twice (mobile + desktop wrappers using
    // `display:contents`); assert at least one anchor points at /enactments.
    const links = within(trail).getAllByRole("link", { name: /Enactments/i })
    expect(links.length).toBeGreaterThan(0)
    for (const link of links) {
      expect((link as HTMLAnchorElement).getAttribute("href")).toBe("/enactments")
    }

    // Current crumb is not a link and carries aria-current=page.
    expect(within(trail).queryByRole("link", { name: /abc12345/i })).toBeNull()
    const current = within(trail).getAllByText("abc12345")[0]
    expect(current.closest('[aria-current="page"]')).not.toBeNull()
  })

  it("hides the header chrome in embed mode but renders the connection pill", () => {
    render(
      <MemoryRouter initialEntries={["/?embed=1"]}>
        <LinkProvider component={RouterAppLink}>
          <PageHeader title="Inbox" breadcrumbs={[{ label: "Inbox" }]} />
        </LinkProvider>
      </MemoryRouter>
    )
    expect(screen.getByTestId("page-header-embed")).not.toBeNull()
    expect(screen.queryByTestId("page-header-breadcrumbs")).toBeNull()
    expect(screen.queryByRole("heading")).toBeNull()
  })
})
