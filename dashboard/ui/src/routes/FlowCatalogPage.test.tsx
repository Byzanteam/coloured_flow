import { act, fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi, beforeEach } from "vitest"
import type { ReactNode } from "react"
import { MemoryRouter } from "react-router-dom"
import { Toasty } from "@cloudflare/kumo"

type FlowSummary = ColouredFlowDashboardWeb.Views.FlowSummary

const { dispatchMock, snapshotMock, navigateMock, makeFlow } = vi.hoisted(() => {
  function build(
    id: string,
    name: string,
    overrides: Partial<FlowSummary> = {}
  ): FlowSummary {
    return {
      id,
      name,
      version: overrides.version ?? "1.0.0",
      place_count: overrides.place_count ?? 2,
      transition_count: overrides.transition_count ?? 1,
      live_enactments: overrides.live_enactments ?? 0,
      total_enactments: overrides.total_enactments ?? 0,
      last_started_at: overrides.last_started_at ?? null,
      recent_enactments: overrides.recent_enactments ?? []
    }
  }

  return {
    dispatchMock: vi.fn(),
    snapshotMock: vi.fn(),
    navigateMock: vi.fn(),
    makeFlow: build
  }
})

vi.mock("../musubi", () => ({
  useMusubiRootSuspense: vi.fn().mockReturnValue({ __mock: "catalog-proxy" }),
  useMusubiSnapshot: (...args: unknown[]) => snapshotMock(...args),
  useMusubiCommand: () => ({
    dispatch: dispatchMock,
    isPending: false,
    error: null,
    data: null,
    reset: vi.fn()
  }),
  useMusubiConnectionStatus: vi.fn().mockReturnValue({
    state: "ready",
    connection: { __mock: "connection" }
  })
}))

vi.mock("react-router-dom", async () => {
  const actual =
    await vi.importActual<typeof import("react-router-dom")>("react-router-dom")
  return {
    ...actual,
    useNavigate: () => navigateMock
  }
})

vi.mock("@musubi/react", () => {
  class MusubiCommandError extends Error {
    readonly kind: "failed" | "timeout"
    readonly command: string
    readonly storeId: readonly string[]
    readonly reply: unknown
    readonly code: string | undefined
    constructor(options: {
      kind: "failed" | "timeout"
      command: string
      storeId: readonly string[]
      reply?: unknown
      cause?: unknown
    }) {
      super(`Command "${options.command}" failed`)
      this.name = "MusubiCommandError"
      this.kind = options.kind
      this.command = options.command
      this.storeId = options.storeId
      this.reply = options.reply
      this.code = extractCode(options.reply)
    }
    static is(value: unknown): value is MusubiCommandError {
      return (
        value instanceof Error && (value as { name?: string }).name === "MusubiCommandError"
      )
    }
  }
  function extractCode(reply: unknown): string | undefined {
    if (typeof reply !== "object" || reply === null) return undefined
    const record = reply as Record<string, unknown>
    for (const key of ["code", "error", "reason"]) {
      const value = record[key]
      if (typeof value === "string") return value
    }
    return undefined
  }
  return { MusubiCommandError }
})

import { MusubiCommandError } from "@musubi/react"
import FlowCatalogPage from "./FlowCatalogPage"

function renderWithProviders(children: ReactNode) {
  return render(
    <MemoryRouter>
      <Toasty>{children}</Toasty>
    </MemoryRouter>
  )
}

function loadSnapshot(
  flows: FlowSummary[],
  counts?: ColouredFlowDashboardWeb.Views.FlowCatalogCounts
) {
  snapshotMock.mockReturnValue({
    flows,
    counts: counts ?? {
      total_flows: flows.length,
      total_live_enactments: flows.reduce((sum, f) => sum + f.live_enactments, 0)
    }
  })
}

describe("FlowCatalogPage — render", () => {
  beforeEach(() => {
    dispatchMock.mockReset()
    snapshotMock.mockReset()
    navigateMock.mockReset()
  })

  it("renders one card per flow with name + counts", () => {
    loadSnapshot([
      makeFlow("flow-1", "Approval Demo", { live_enactments: 2, place_count: 2, transition_count: 1 }),
      makeFlow("flow-2", "Traffic Light", { live_enactments: 0, place_count: 8, transition_count: 6 })
    ])

    renderWithProviders(<FlowCatalogPage />)

    expect(screen.getByText("Approval Demo")).toBeDefined()
    expect(screen.getByText("Traffic Light")).toBeDefined()
    expect(screen.getByTestId("flow-card-flow-1")).toBeDefined()
    expect(screen.getByTestId("flow-card-flow-2")).toBeDefined()
  })

  it("renders the empty state when no flows are registered", () => {
    loadSnapshot([])
    renderWithProviders(<FlowCatalogPage />)
    expect(screen.getByText(/No flows registered/i)).toBeDefined()
  })

  it("disables Start for an (unknown) flow row", () => {
    loadSnapshot([makeFlow("flow-x", "(unknown)")])

    renderWithProviders(<FlowCatalogPage />)
    const button = screen.getByTestId("flow-card-flow-x-start") as HTMLButtonElement
    expect(button.disabled).toBe(true)
  })
})

describe("FlowCatalogPage — start enactment", () => {
  beforeEach(() => {
    dispatchMock.mockReset()
    snapshotMock.mockReset()
    navigateMock.mockReset()
  })

  it("dispatches :start_enactment with the flow_id and navigates on success", async () => {
    dispatchMock.mockResolvedValueOnce({ code: "ok", enactment_id: "enactment-9" })
    loadSnapshot([makeFlow("flow-1", "Approval Demo")])

    renderWithProviders(<FlowCatalogPage />)

    await act(async () => {
      fireEvent.click(screen.getByTestId("flow-card-flow-1-start"))
    })

    expect(screen.getByText(/Start a new enactment/i)).toBeDefined()

    await act(async () => {
      fireEvent.click(screen.getByTestId("flow-start-confirm"))
    })

    expect(dispatchMock).toHaveBeenCalledOnce()
    const [payload] = dispatchMock.mock.calls[0] as [{ flow_id: string }]
    expect(payload.flow_id).toBe("flow-1")
    expect(navigateMock).toHaveBeenCalledWith("/enactments/enactment-9")
  })

  it("surfaces an error toast when the server rejects with :unknown_flow", async () => {
    dispatchMock.mockRejectedValueOnce(
      new MusubiCommandError({
        kind: "failed",
        command: "start_enactment",
        storeId: ["ColouredFlowDashboardWeb.Stores.FlowCatalogStore", "default"],
        reply: { code: "unknown_flow", enactment_id: null }
      })
    )
    loadSnapshot([makeFlow("flow-1", "Approval Demo")])

    renderWithProviders(<FlowCatalogPage />)

    await act(async () => {
      fireEvent.click(screen.getByTestId("flow-card-flow-1-start"))
    })

    await act(async () => {
      fireEvent.click(screen.getByTestId("flow-start-confirm"))
    })

    expect(screen.getByText(/Flow not found/i)).toBeDefined()
    expect(navigateMock).not.toHaveBeenCalled()
  })
})

describe("FlowCatalogPage controls — search/filter/pagination", () => {
  beforeEach(() => {
    dispatchMock.mockReset()
    snapshotMock.mockReset()
    navigateMock.mockReset()
  })

  function renderAt(initialEntries: string[] = ["/flows"]) {
    return render(
      <MemoryRouter initialEntries={initialEntries}>
        <Toasty>
          <FlowCatalogPage />
        </Toasty>
      </MemoryRouter>
    )
  }

  it("filters cards by name substring", async () => {
    loadSnapshot([
      makeFlow("flow-1", "Approval Demo"),
      makeFlow("flow-2", "Traffic Light"),
      makeFlow("flow-3", "Pi Agent")
    ])
    renderAt()

    expect(screen.getByTestId("flow-card-flow-1")).toBeDefined()
    expect(screen.getByTestId("flow-card-flow-2")).toBeDefined()
    expect(screen.getByTestId("flow-card-flow-3")).toBeDefined()

    const search = screen.getByTestId("list-controls-search") as HTMLInputElement
    await act(async () => {
      fireEvent.change(search, { target: { value: "traffic" } })
    })

    expect(screen.queryByTestId("flow-card-flow-1")).toBeNull()
    expect(screen.getByTestId("flow-card-flow-2")).toBeDefined()
    expect(screen.queryByTestId("flow-card-flow-3")).toBeNull()
  })

  it("hides idle flows when the Live only switch is toggled on", async () => {
    loadSnapshot([
      makeFlow("flow-1", "Approval Demo", { live_enactments: 0 }),
      makeFlow("flow-2", "Traffic Light", { live_enactments: 3 })
    ])
    renderAt()

    expect(screen.getByTestId("flow-card-flow-1")).toBeDefined()
    expect(screen.getByTestId("flow-card-flow-2")).toBeDefined()

    const toggle = screen.getByTestId("flow-catalog-live-only") as HTMLButtonElement
    await act(async () => {
      fireEvent.click(toggle)
    })

    expect(screen.queryByTestId("flow-card-flow-1")).toBeNull()
    expect(screen.getByTestId("flow-card-flow-2")).toBeDefined()
  })

  it("paginates cards according to the page-size selector", async () => {
    const flows = Array.from({ length: 14 }, (_, i) => makeFlow(`flow-${i}`, `Flow ${i}`))
    loadSnapshot(flows)
    renderAt(["/flows?pageSize=10"])

    expect(screen.getByTestId("flow-card-flow-0")).toBeDefined()
    expect(screen.getByTestId("flow-card-flow-9")).toBeDefined()
    expect(screen.queryByTestId("flow-card-flow-10")).toBeNull()
    expect(screen.getByTestId("list-pagination-info").textContent).toMatch(
      /Showing 1–10 of 14/
    )
  })

  it("hydrates Live only state from the URL", () => {
    loadSnapshot([
      makeFlow("flow-1", "Approval Demo", { live_enactments: 0 }),
      makeFlow("flow-2", "Traffic Light", { live_enactments: 1 })
    ])
    renderAt(["/flows?live_only=1"])

    expect(screen.queryByTestId("flow-card-flow-1")).toBeNull()
    expect(screen.getByTestId("flow-card-flow-2")).toBeDefined()
  })

  it("shows Empty + Clear filters when no flow matches", async () => {
    loadSnapshot([makeFlow("flow-1", "Approval Demo")])
    renderAt()

    const search = screen.getByTestId("list-controls-search") as HTMLInputElement
    await act(async () => {
      fireEvent.change(search, { target: { value: "no-match" } })
    })

    expect(screen.getByTestId("flow-catalog-filters-empty")).toBeDefined()
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: /clear filters/i }))
    })
    expect(screen.getByTestId("flow-card-flow-1")).toBeDefined()
  })
})
