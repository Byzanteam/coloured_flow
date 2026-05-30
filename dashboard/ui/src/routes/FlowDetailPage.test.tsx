import { act, fireEvent, render, screen, waitFor } from "@testing-library/react"
import { describe, expect, it, vi, beforeEach } from "vitest"
import { MemoryRouter, Route, Routes } from "react-router-dom"
import { Toasty } from "@cloudflare/kumo"

type FlowSummary = ColouredFlowDashboardWeb.Views.FlowSummary
type FlowDetail = ColouredFlowDashboardWeb.Views.FlowDetail
type FlowEnactmentEntry = ColouredFlowDashboardWeb.Views.FlowEnactmentEntry
type NetDiagram = ColouredFlowDashboardWeb.Views.NetDiagram

const { startDispatchMock, fetchDispatchMock, snapshotMock, navigateMock, sampleDiagram } =
  vi.hoisted(() => {
    const diagram: NetDiagram = {
      places: [
        { name: "pending", colour_set: "trigger_t", tokens_count: 0, tokens_summary: "" },
        { name: "decided", colour_set: "outcome", tokens_count: 0, tokens_summary: "" }
      ],
      transitions: [
        {
          name: "approve",
          enabled_count: 0,
          rejected_by_guard_count: 0,
          rejected_by_arc_eval_count: 0,
          rejected_by_marking_count: 0,
          last_fired_at: null
        }
      ],
      arcs: [
        { place: "pending", transition: "approve", orientation: "p_to_t" },
        { place: "decided", transition: "approve", orientation: "t_to_p" }
      ]
    }

    return {
      startDispatchMock: vi.fn(),
      fetchDispatchMock: vi.fn(),
      snapshotMock: vi.fn(),
      navigateMock: vi.fn(),
      sampleDiagram: diagram
    }
  })

vi.mock("../musubi", () => ({
  useMusubiRootSuspense: vi.fn().mockReturnValue({ __mock: "catalog-proxy" }),
  useMusubiSnapshot: (...args: unknown[]) => snapshotMock(...args),
  useMusubiCommand: (_proxy: unknown, command: string) => {
    const dispatch =
      command === "fetch_flow_detail" ? fetchDispatchMock : startDispatchMock
    return {
      dispatch,
      isPending: false,
      error: null,
      data: null,
      reset: vi.fn()
    }
  },
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

vi.mock("../components/NetDiagram", () => ({
  default: ({ diagram }: { diagram: NetDiagram | null | undefined }) => (
    <div
      data-testid="net-diagram-stub"
      data-place-count={String(diagram?.places.length ?? 0)}
      data-transition-count={String(diagram?.transitions.length ?? 0)}
    />
  )
}))

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
      return value instanceof Error && (value as { name?: string }).name === "MusubiCommandError"
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

import FlowDetailPage from "./FlowDetailPage"

function makeFlow(overrides: Partial<FlowSummary> = {}): FlowSummary {
  return {
    id: "flow-1",
    name: "Approval Demo",
    version: "1.0.0",
    place_count: 2,
    transition_count: 1,
    live_enactments: 2,
    total_enactments: 0,
    last_started_at: "2026-05-29T00:00:00Z",
    recent_enactments: [],
    ...overrides
  }
}

function makeEntry(
  id: string,
  state: FlowEnactmentEntry["state"] = "running"
): FlowEnactmentEntry {
  return { id, state, inserted_at: "2026-05-29T00:00:00Z" }
}

function makeDetail(overrides: Partial<FlowDetail> = {}): FlowDetail {
  return {
    id: "flow-1",
    name: "Approval Demo",
    version: "1.0.0",
    place_count: 2,
    transition_count: 1,
    live_enactments: 2,
    total_enactments: overrides.enactments?.length ?? 0,
    last_started_at: "2026-05-29T00:00:00Z",
    enactments: [],
    diagram: sampleDiagram,
    ...overrides
  }
}

function loadSnapshot(flows: FlowSummary[]) {
  snapshotMock.mockReturnValue({
    flows,
    counts: {
      total_flows: flows.length,
      total_live_enactments: flows.reduce((sum, f) => sum + f.live_enactments, 0)
    }
  })
}

function primeDetail(detail: FlowDetail | null) {
  if (detail === null) {
    fetchDispatchMock.mockResolvedValue({ code: "not_found", flow: null })
  } else {
    fetchDispatchMock.mockResolvedValue({ code: "ok", flow: detail })
  }
}

function renderAt(path: string) {
  return render(
    <Toasty>
      <MemoryRouter initialEntries={[path]}>
        <Routes>
          <Route path="/flows/:flow_id" element={<FlowDetailPage />} />
        </Routes>
      </MemoryRouter>
    </Toasty>
  )
}

describe("FlowDetailPage", () => {
  beforeEach(() => {
    startDispatchMock.mockReset()
    fetchDispatchMock.mockReset()
    snapshotMock.mockReset()
    navigateMock.mockReset()
  })

  it("renders the flow name as the header title", async () => {
    loadSnapshot([
      makeFlow({
        total_enactments: 2
      })
    ])
    primeDetail(
      makeDetail({
        enactments: [makeEntry("en-aaaa"), makeEntry("en-bbbb", "terminated")]
      })
    )
    await act(async () => {
      renderAt("/flows/flow-1")
    })
    expect(screen.getByRole("heading", { level: 1, name: "Approval Demo" })).toBeDefined()
  })

  it("renders the version chip + place/transition counts subtitle", async () => {
    loadSnapshot([makeFlow()])
    primeDetail(makeDetail())
    await act(async () => {
      renderAt("/flows/flow-1")
    })
    expect(screen.getByText("v1.0.0")).toBeDefined()
    expect(screen.getByText(/2 places · 1 transition/)).toBeDefined()
  })

  it("renders breadcrumbs with a Flows link and the current flow name", async () => {
    loadSnapshot([makeFlow()])
    primeDetail(makeDetail())
    await act(async () => {
      renderAt("/flows/flow-1")
    })
    const crumbs = screen.getByTestId("page-header-breadcrumbs")
    const link = crumbs.querySelector('a[href="/flows"]') as HTMLAnchorElement | null
    expect(link).not.toBeNull()
    expect(link?.textContent).toBe("Flows")
    expect(crumbs.textContent).toMatch(/Approval Demo/)
  })

  it("dispatches :fetch_flow_detail on mount and mounts NetDiagram with the reply payload", async () => {
    loadSnapshot([makeFlow()])
    primeDetail(makeDetail())
    await act(async () => {
      renderAt("/flows/flow-1")
    })
    await waitFor(() => {
      expect(fetchDispatchMock).toHaveBeenCalledWith({ flow_id: "flow-1" })
    })
    await waitFor(() => {
      const stub = screen.getByTestId("net-diagram-stub")
      expect(stub.getAttribute("data-place-count")).toBe("2")
      expect(stub.getAttribute("data-transition-count")).toBe("1")
    })
  })

  it("lists every enactment from the detail reply with a link to the enactment page", async () => {
    loadSnapshot([makeFlow({ total_enactments: 3 })])
    primeDetail(
      makeDetail({
        enactments: [
          makeEntry("en-aaaaaaaa-1111"),
          makeEntry("en-bbbbbbbb-2222", "exception"),
          makeEntry("en-cccccccc-3333", "terminated")
        ]
      })
    )
    await act(async () => {
      renderAt("/flows/flow-1")
    })
    await waitFor(() => {
      const table = screen.getByTestId("flow-detail-enactments")
      expect(table.querySelectorAll('a[href^="/enactments/"]').length).toBe(3)
      expect(table.textContent).toMatch(/running/)
      expect(table.textContent).toMatch(/exception/)
      expect(table.textContent).toMatch(/terminated/)
    })
  })

  it("dispatches :start_enactment when the Start button + Confirm is clicked", async () => {
    startDispatchMock.mockResolvedValueOnce({ code: "ok", enactment_id: "en-new" })
    loadSnapshot([makeFlow()])
    primeDetail(makeDetail())

    await act(async () => {
      renderAt("/flows/flow-1")
    })

    await act(async () => {
      fireEvent.click(screen.getByTestId("flow-detail-start"))
    })
    expect(screen.getByText(/Start a new enactment/i)).toBeDefined()

    await act(async () => {
      fireEvent.click(screen.getByTestId("flow-detail-start-confirm"))
    })

    expect(startDispatchMock).toHaveBeenCalledOnce()
    const [payload] = startDispatchMock.mock.calls[0] as [{ flow_id: string }]
    expect(payload.flow_id).toBe("flow-1")
    expect(navigateMock).toHaveBeenCalledWith("/enactments/en-new")
  })

  it("disables Start for an (unknown) flow row", async () => {
    loadSnapshot([makeFlow({ name: "(unknown)" })])
    primeDetail(makeDetail({ name: "(unknown)" }))
    await act(async () => {
      renderAt("/flows/flow-1")
    })
    const button = screen.getByTestId("flow-detail-start") as HTMLButtonElement
    expect(button.disabled).toBe(true)
  })

  it("renders a not-found banner with a Back-to-Flows link when no flow matches the id", async () => {
    loadSnapshot([makeFlow({ id: "flow-other" })])
    primeDetail(makeDetail())
    await act(async () => {
      renderAt("/flows/missing-id")
    })
    expect(screen.getByText(/No flow matches that id/i)).toBeDefined()
    const back = screen.getByTestId("flow-detail-back-to-flows") as HTMLAnchorElement
    expect(back.getAttribute("href")).toBe("/flows")
  })

  it("renders an empty-state message when the detail reply carries no enactments", async () => {
    loadSnapshot([makeFlow()])
    primeDetail(makeDetail({ enactments: [] }))
    await act(async () => {
      renderAt("/flows/flow-1")
    })
    await waitFor(() => {
      expect(screen.getByText(/No enactments yet for this flow/i)).toBeDefined()
    })
  })
})
