import { StrictMode, type ReactNode } from "react"
import { act, render } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

const { connectMock } = vi.hoisted(() => ({ connectMock: vi.fn() }))

vi.mock("./musubi", () => {
  // Pre-tagged rejected thenable: React 19's `use(promise)` reads `status`
  // synchronously when present, so the ErrorBoundary catches on the first
  // render without needing extra microtask flushing.
  const rejection: Promise<never> & { status?: string; reason?: unknown } =
    Promise.reject(new Error("boom"))
  // Swallow the unhandled-rejection so vitest does not fail the suite; React
  // re-throws via `use()` into the ErrorBoundary which is the assertion below.
  rejection.catch(() => {})
  rejection.status = "rejected"
  rejection.reason = new Error("boom")
  connectMock.mockReturnValue(rejection)
  return {
    socket: { __mock: "socket" },
    connect: connectMock,
    MusubiProvider: ({ children }: { children: ReactNode }) => <>{children}</>
  }
})

vi.mock("./routes/router", () => ({
  router: { __mock: "router" }
}))

vi.mock("react-router-dom", async () => {
  const actual = await vi.importActual<typeof import("react-router-dom")>(
    "react-router-dom"
  )
  return {
    ...actual,
    RouterProvider: () => <div data-testid="router-stub">routes</div>
  }
})

const App = (await import("./App")).default

describe("<App /> connect failure", () => {
  it("renders an error banner when connect rejects, without crashing", async () => {
    // React logs ErrorBoundary catches via console.error; silence so the test
    // output stays focused on the rendered UI assertions.
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {})

    const view = render(
      <StrictMode>
        <App />
      </StrictMode>
    )

    await act(async () => {
      await Promise.resolve()
    })

    expect(view.container.textContent).toContain("boom")
    expect(view.container.textContent).toContain("Connect failed")
    expect(view.queryByTestId("router-stub")).toBeNull()
    expect(connectMock).toHaveBeenCalledTimes(1)
    expect(connectMock).toHaveBeenCalledWith({ __mock: "socket" })

    errorSpy.mockRestore()
  })
})
