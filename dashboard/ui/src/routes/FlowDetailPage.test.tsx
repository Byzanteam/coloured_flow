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
      ],
      colour_sets: [
        { name: "trigger_t", type_summary: "boolean()", description: null },
        {
          name: "outcome",
          type_summary: "{verdict_t(), note_t()}",
          description: null
        }
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

  it("renders breadcrumbs with a Flows link and the short flow id (H1 holds the name)", async () => {
    loadSnapshot([makeFlow()])
    primeDetail(makeDetail())
    await act(async () => {
      renderAt("/flows/flow-1")
    })
    const crumbs = screen.getByTestId("page-header-breadcrumbs")
    const link = crumbs.querySelector('a[href="/flows"]') as HTMLAnchorElement | null
    expect(link).not.toBeNull()
    expect(link?.textContent).toBe("Flows")
    // Tail crumb is the short id, not the flow name — H1 carries the name.
    expect(crumbs.textContent).toMatch(/flow-1/)
    expect(crumbs.textContent).not.toMatch(/Approval Demo/)
    // The byline echoes the short id parallel to EnactmentDetail's pattern.
    expect(screen.getByTestId("flow-detail-id-byline").textContent).toContain("flow-1")
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

  it("renders a not-found banner with a Back-to-Flows link when the detail reply is :not_found", async () => {
    loadSnapshot([makeFlow({ id: "flow-other" })])
    primeDetail(null)
    await act(async () => {
      renderAt("/flows/missing-id")
    })
    await waitFor(() => {
      expect(screen.getByText(/No flow matches that id/i)).toBeDefined()
    })
    const back = screen.getByTestId("flow-detail-back-to-flows") as HTMLAnchorElement
    expect(back.getAttribute("href")).toBe("/flows")
    // No diagram, no enactments shell when not_found
    expect(screen.queryByTestId("flow-detail-diagram-card")).toBeNull()
    expect(screen.queryByTestId("flow-detail-enactments")).toBeNull()
    expect(screen.queryByTestId("flow-detail-live-count")).toBeNull()
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

  it("direct load with NO FlowSummary in catalog still dispatches fetch and renders detail", async () => {
    // Catalog snapshot empty — simulates a hard reload landing on /flows/:id
    // before the live stream lands. Old behavior would flash a false
    // "Flow not found" banner; new behavior must wait for the detail reply.
    loadSnapshot([])
    primeDetail(makeDetail({ enactments: [makeEntry("en-aaaa")] }))
    await act(async () => {
      renderAt("/flows/flow-1")
    })
    await waitFor(() => {
      expect(fetchDispatchMock).toHaveBeenCalledWith({ flow_id: "flow-1" })
    })
    await waitFor(() => {
      expect(screen.getByRole("heading", { level: 1, name: "Approval Demo" })).toBeDefined()
      expect(screen.getByTestId("flow-detail-diagram-card")).toBeDefined()
      expect(screen.getByTestId("flow-detail-enactments")).toBeDefined()
    })
    // Never flashed a not-found banner.
    expect(screen.queryByText(/No flow matches that id/i)).toBeNull()
  })

  it("renders the Colour sets panel when the diagram carries colour set definitions", async () => {
    loadSnapshot([makeFlow()])
    primeDetail(makeDetail())
    await act(async () => {
      renderAt("/flows/flow-1")
    })
    await waitFor(() => {
      expect(screen.getByTestId("colour-sets-panel")).toBeDefined()
    })
    // Collapsed by default — clicking the toggle exposes the rows.
    await act(async () => {
      fireEvent.click(screen.getByTestId("colour-sets-toggle"))
    })
    expect(screen.getByTestId("colour-set-name-trigger_t").textContent).toBe(
      "trigger_t"
    )
    expect(screen.getByTestId("colour-set-type-trigger_t").textContent).toMatch(
      /boolean\(\)/
    )
    expect(screen.getByTestId("colour-set-type-outcome").textContent).toMatch(
      /\{verdict_t\(\), note_t\(\)\}/
    )
  })

  it("hides the Colour sets panel when the diagram has zero colour sets", async () => {
    loadSnapshot([makeFlow()])
    primeDetail(makeDetail({ diagram: { ...sampleDiagram, colour_sets: [] } }))
    await act(async () => {
      renderAt("/flows/flow-1")
    })
    await waitFor(() => {
      expect(screen.getByTestId("flow-detail-diagram-card")).toBeDefined()
    })
    expect(screen.queryByTestId("colour-sets-panel")).toBeNull()
  })
})

describe("FlowDetailPage — retry", () => {
  beforeEach(() => {
    snapshotMock.mockReset()
    startDispatchMock.mockReset()
    fetchDispatchMock.mockReset()
    navigateMock.mockReset()
  })

  it("recovers from a transient error via Retry", async () => {
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {})
    let shouldThrow = true
    snapshotMock.mockImplementation(() => {
      if (shouldThrow) throw new Error("boom")
      return {
        flows: [makeFlow()],
        counts: { total_flows: 1, total_live_enactments: 2 }
      }
    })
    primeDetail(makeDetail())

    await act(async () => {
      renderAt("/flows/flow-1")
    })

    expect(screen.getByTestId("flow-detail-error")).toBeDefined()
    expect(screen.getByText(/boom/)).toBeDefined()

    shouldThrow = false
    await act(async () => {
      fireEvent.click(screen.getByTestId("flow-detail-error-retry"))
    })

    expect(screen.queryByTestId("flow-detail-error")).toBeNull()
    await waitFor(() => {
      expect(screen.getByTestId("flow-detail-diagram-card")).toBeDefined()
    })
    errorSpy.mockRestore()
  })
})
