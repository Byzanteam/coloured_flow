import { act, fireEvent, render, screen, within } from "@testing-library/react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { MemoryRouter, Route, Routes } from "react-router-dom"

import RootLayout from "./RootLayout"

type ConnectionStatus =
  | { state: "connecting"; connection: null }
  | { state: "ready"; connection: { __mock: string } }
  | { state: "error"; connection: null; error: Error }

const { connectionStatusMock } = vi.hoisted(() => ({
  connectionStatusMock: vi.fn<() => ConnectionStatus>(() => ({
    state: "ready",
    connection: { __mock: "connection" }
  }))
}))

vi.mock("../musubi", () => ({
  useMusubiRoot: vi.fn().mockReturnValue({ status: "loading", store: null }),
  useMusubiSnapshot: vi.fn().mockReturnValue(undefined),
  useMusubiConnectionStatus: () => connectionStatusMock()
}))

function renderLayout(initialPath = "/") {
  return render(
    <MemoryRouter initialEntries={[initialPath]}>
      <Routes>
        <Route element={<RootLayout />}>
          <Route path="*" element={<div data-testid="outlet">main</div>} />
        </Route>
      </Routes>
    </MemoryRouter>
  )
}

describe("RootLayout", () => {
  beforeEach(() => {
    // jsdom lacks matchMedia. Kumo's Sidebar reads it to detect mobile
    // breakpoints. Stub to a desktop-shaped no-op MediaQueryList.
    if (typeof window.matchMedia !== "function") {
      window.matchMedia = ((query: string) =>
        ({
          matches: false,
          media: query,
          onchange: null,
          addListener: () => {},
          removeListener: () => {},
          addEventListener: () => {},
          removeEventListener: () => {},
          dispatchEvent: () => false
        }) as unknown as MediaQueryList) as unknown as typeof window.matchMedia
    }
    window.localStorage.clear()
    document.documentElement.removeAttribute("data-theme")
    document.documentElement.removeAttribute("data-mode")
    connectionStatusMock.mockReturnValue({
      state: "ready",
      connection: { __mock: "connection" }
    })
  })

  afterEach(() => {
    window.localStorage.clear()
  })

  it("renders Inbox / Flows / Telemetry nav links and omits Settings", () => {
    renderLayout()

    expect(screen.getByRole("link", { name: /inbox/i })).toBeTruthy()
    expect(screen.getByRole("link", { name: /flows/i })).toBeTruthy()
    expect(screen.getByRole("link", { name: /telemetry/i })).toBeTruthy()
    expect(screen.queryByText(/settings/i)).toBeNull()
    expect(screen.queryByText(/Soon/i)).toBeNull()
  })

  it("Telemetry nav targets /telemetry", () => {
    renderLayout()
    const link = screen.getByRole("link", { name: /telemetry/i })
    expect(link.getAttribute("href")).toBe("/telemetry")
  })

  it("renders the aurora brand wordmark", () => {
    renderLayout()
    const brand = screen.getByTestId("brand-wordmark")
    const aurora = within(brand).getByTestId("aurora-text")
    expect(aurora.textContent).toContain("Coloured Flow")
  })

  it("keeps the theme toggle visible in both expanded and collapsed states", () => {
    renderLayout()
    expect(screen.getByTestId("theme-toggle")).toBeTruthy()
    const toggle = screen.getByTestId("sidebar-toggle")
    act(() => {
      fireEvent.click(toggle)
    })
    expect(screen.getByTestId("theme-toggle")).toBeTruthy()
  })

  it("collapses the brand wordmark to a single 'C' aurora letter", () => {
    window.localStorage.setItem("cf-sidebar-collapsed", "true")
    renderLayout()
    const brand = screen.getByTestId("brand-wordmark")
    const aurora = within(brand).getByTestId("aurora-text")
    expect(aurora.textContent).toContain("C")
    expect(aurora.textContent).not.toContain("Coloured")
  })

  it("marks the active route", () => {
    renderLayout("/telemetry")
    const telemetry = screen.getByRole("link", { name: /telemetry/i })
    expect(telemetry.getAttribute("data-active")).toBe("true")
    const inbox = screen.getByRole("link", { name: /inbox/i })
    expect(inbox.getAttribute("data-active")).toBeNull()
  })

  it("shows footer with version and connection status when expanded", () => {
    renderLayout()
    const footer = screen.getByTestId("sidebar-footer-expanded")
    expect(footer.textContent).toContain("v0.1.0")
    expect(within(footer).getByTestId("connection-status").textContent).toContain(
      "Connected"
    )
  })

  it("hosts the status pill, theme toggle, and collapse trigger together in the footer", () => {
    renderLayout()
    const footer = screen.getByTestId("sidebar-footer-expanded")
    expect(within(footer).getByTestId("connection-status")).toBeTruthy()
    expect(within(footer).getByTestId("theme-toggle")).toBeTruthy()
    expect(within(footer).getByTestId("sidebar-toggle")).toBeTruthy()
  })

  it("keeps the status dot, theme toggle, and collapse trigger together in the collapsed footer", () => {
    window.localStorage.setItem("cf-sidebar-collapsed", "true")
    renderLayout()
    const footer = screen.getByTestId("sidebar-footer-collapsed")
    expect(within(footer).getByTestId("connection-status")).toBeTruthy()
    expect(within(footer).getByTestId("theme-toggle")).toBeTruthy()
    expect(within(footer).getByTestId("sidebar-toggle")).toBeTruthy()
  })

  it("does not render the collapse trigger inside the brand header", () => {
    renderLayout()
    const brand = screen.getByTestId("brand-wordmark")
    expect(within(brand).queryByTestId("sidebar-toggle")).toBeNull()
  })

  it("renders the app version as plain text without the shimmer animation", () => {
    renderLayout()
    const version = screen.getByTestId("app-version")
    expect(version.tagName.toLowerCase()).toBe("span")
    expect(version.getAttribute("data-testid")).toBe("app-version")
    expect(within(version).queryByTestId("animated-shiny-text")).toBeNull()
  })

  it("uses shiny shimmer on the status line while connecting", () => {
    connectionStatusMock.mockReturnValue({
      state: "connecting",
      connection: null
    })
    renderLayout()
    const status = screen.getByTestId("connection-status")
    expect(within(status).getAllByTestId("animated-shiny-text").length).toBeGreaterThan(
      0
    )
    expect(status.textContent).toContain("Connecting")
  })

  it("renders Disconnected exception colors on error", () => {
    connectionStatusMock.mockReturnValue({
      state: "error",
      connection: null,
      error: new Error("boom")
    })
    renderLayout()
    const status = screen.getByTestId("connection-status")
    expect(status.textContent).toContain("Disconnected")
    expect(status.querySelector(".bg-cf-dot-exception")).not.toBeNull()
  })

  it("collapses on toggle and persists collapsed state in localStorage", () => {
    renderLayout()
    const sidebar = document.querySelector('[data-sidebar="sidebar"]') as HTMLElement
    expect(sidebar).toBeTruthy()
    expect(sidebar.getAttribute("data-state")).toBe("expanded")

    const toggle = screen.getByTestId("sidebar-toggle")
    act(() => {
      fireEvent.click(toggle)
    })

    expect(sidebar.getAttribute("data-state")).toBe("collapsed")
    expect(window.localStorage.getItem("cf-sidebar-collapsed")).toBe("true")
    expect(screen.queryByTestId("sidebar-footer-expanded")).toBeNull()
    expect(screen.getByTestId("sidebar-footer-collapsed")).toBeTruthy()
  })

  it("restores collapsed state from localStorage on mount", () => {
    window.localStorage.setItem("cf-sidebar-collapsed", "true")
    renderLayout()
    const sidebar = document.querySelector('[data-sidebar="sidebar"]') as HTMLElement
    expect(sidebar.getAttribute("data-state")).toBe("collapsed")
  })

  it("renders main outlet content alongside the sidebar", () => {
    renderLayout()
    expect(screen.getByTestId("outlet").textContent).toBe("main")
  })
})
