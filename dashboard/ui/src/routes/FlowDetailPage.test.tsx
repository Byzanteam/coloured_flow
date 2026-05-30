import { act, fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi, beforeEach } from "vitest"
import { MemoryRouter, Route, Routes } from "react-router-dom"
import { Toasty } from "@cloudflare/kumo"

type FlowSummary = ColouredFlowDashboardWeb.Views.FlowSummary
type FlowEnactmentEntry = ColouredFlowDashboardWeb.Views.FlowEnactmentEntry
type NetDiagram = ColouredFlowDashboardWeb.Views.NetDiagram

const { dispatchMock, snapshotMock, navigateMock, sampleDiagram } = vi.hoisted(() => {
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
    dispatchMock: vi.fn(),
    snapshotMock: vi.fn(),
    navigateMock: vi.fn(),
    sampleDiagram: diagram
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
    last_started_at: "2026-05-29T00:00:00Z",
    recent_enactments: [],
    enactments: [],
    diagram: sampleDiagram,
    ...overrides
  }
}

function makeEntry(
  id: string,
  state: FlowEnactmentEntry["state"] = "running"
): FlowEnactmentEntry {
  return { id, state, inserted_at: "2026-05-29T00:00:00Z" }
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
    dispatchMock.mockReset()
    snapshotMock.mockReset()
    navigateMock.mockReset()
  })

  it("renders the flow name as the header title", () => {
    loadSnapshot([
      makeFlow({
        enactments: [makeEntry("en-aaaa"), makeEntry("en-bbbb", "terminated")]
      })
    ])
    renderAt("/flows/flow-1")
    expect(screen.getByRole("heading", { level: 1, name: "Approval Demo" })).toBeDefined()
  })

  it("renders the version chip + place/transition counts subtitle", () => {
    loadSnapshot([makeFlow()])
    renderAt("/flows/flow-1")
    expect(screen.getByText("v1.0.0")).toBeDefined()
    expect(screen.getByText(/2 places · 1 transition/)).toBeDefined()
  })

  it("renders breadcrumbs with a Flows link and the current flow name", () => {
    loadSnapshot([makeFlow()])
    renderAt("/flows/flow-1")
    const crumbs = screen.getByTestId("page-header-breadcrumbs")
    const link = crumbs.querySelector('a[href="/flows"]') as HTMLAnchorElement | null
    expect(link).not.toBeNull()
    expect(link?.textContent).toBe("Flows")
    expect(crumbs.textContent).toMatch(/Approval Demo/)
  })

  it("mounts the NetDiagram with the flow's diagram payload", () => {
    loadSnapshot([makeFlow()])
    renderAt("/flows/flow-1")
    const stub = screen.getByTestId("net-diagram-stub")
    expect(stub.getAttribute("data-place-count")).toBe("2")
    expect(stub.getAttribute("data-transition-count")).toBe("1")
  })

  it("lists every enactment with a link to the detail page", () => {
    loadSnapshot([
      makeFlow({
        enactments: [
          makeEntry("en-aaaaaaaa-1111"),
          makeEntry("en-bbbbbbbb-2222", "exception"),
          makeEntry("en-cccccccc-3333", "terminated")
        ]
      })
    ])
    renderAt("/flows/flow-1")
    const table = screen.getByTestId("flow-detail-enactments")
    const links = table.querySelectorAll('a[href^="/enactments/"]')
    expect(links.length).toBe(3)
    expect(table.textContent).toMatch(/running/)
    expect(table.textContent).toMatch(/exception/)
    expect(table.textContent).toMatch(/terminated/)
  })

  it("dispatches :start_enactment when the Start button + Confirm is clicked", async () => {
    dispatchMock.mockResolvedValueOnce({ code: "ok", enactment_id: "en-new" })
    loadSnapshot([makeFlow()])

    renderAt("/flows/flow-1")

    await act(async () => {
      fireEvent.click(screen.getByTestId("flow-detail-start"))
    })
    expect(screen.getByText(/Start a new enactment/i)).toBeDefined()

    await act(async () => {
      fireEvent.click(screen.getByTestId("flow-detail-start-confirm"))
    })

    expect(dispatchMock).toHaveBeenCalledOnce()
    const [payload] = dispatchMock.mock.calls[0] as [{ flow_id: string }]
    expect(payload.flow_id).toBe("flow-1")
    expect(navigateMock).toHaveBeenCalledWith("/enactments/en-new")
  })

  it("disables Start for an (unknown) flow row", () => {
    loadSnapshot([makeFlow({ name: "(unknown)" })])
    renderAt("/flows/flow-1")
    const button = screen.getByTestId("flow-detail-start") as HTMLButtonElement
    expect(button.disabled).toBe(true)
  })

  it("renders a not-found banner with a Back-to-Flows link when no flow matches the id", () => {
    loadSnapshot([makeFlow({ id: "flow-other" })])
    renderAt("/flows/missing-id")
    expect(screen.getByText(/No flow matches that id/i)).toBeDefined()
    const back = screen.getByTestId("flow-detail-back-to-flows") as HTMLAnchorElement
    expect(back.getAttribute("href")).toBe("/flows")
  })

  it("renders an empty-state message when the flow has no enactments yet", () => {
    loadSnapshot([makeFlow({ enactments: [] })])
    renderAt("/flows/flow-1")
    expect(screen.getByText(/No enactments yet for this flow/i)).toBeDefined()
  })
})
