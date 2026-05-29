import { StrictMode, type ReactNode } from "react"
import { act, render } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

const { connectMock } = vi.hoisted(() => ({ connectMock: vi.fn() }))

vi.mock("./musubi", () => {
  const fakeConnection = { disconnect: vi.fn() }
  // React 19's `use(promise)` reads the `status` / `value` fields synchronously
  // when present, so a pre-tagged thenable lets the Suspense boundary commit
  // on the very first render — keeps the test free of microtask flushing.
  const taggedPromise: Promise<typeof fakeConnection> & {
    status?: string
    value?: unknown
  } = Promise.resolve(fakeConnection)
  taggedPromise.status = "fulfilled"
  taggedPromise.value = fakeConnection
  connectMock.mockReturnValue(taggedPromise)
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

describe("<App />", () => {
  it("calls connect(socket) exactly once across StrictMode and rerenders", async () => {
    const view = render(
      <StrictMode>
        <App />
      </StrictMode>
    )

    // Flush the microtask queue so the module-scope connect promise resolves
    // and the Suspense boundary commits with the resolved Connection.
    await act(async () => {
      await Promise.resolve()
    })
    view.getByTestId("router-stub")

    // Simulate a re-render (covers a route change / parent re-render under
    // StrictMode). Module-scope connect must not run again.
    view.rerender(
      <StrictMode>
        <App />
      </StrictMode>
    )
    await act(async () => {
      await Promise.resolve()
    })
    view.getByTestId("router-stub")

    expect(connectMock).toHaveBeenCalledTimes(1)
    expect(connectMock).toHaveBeenCalledWith({ __mock: "socket" })
  })
})
