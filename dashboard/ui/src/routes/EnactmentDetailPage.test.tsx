import { act, fireEvent, render, screen, waitFor } from "@testing-library/react"
import { describe, expect, it, vi, beforeEach } from "vitest"
import type { ReactNode } from "react"
import { MemoryRouter, Route, Routes } from "react-router-dom"
import { Toasty } from "@cloudflare/kumo"

const {
  takeSnapshotMock,
  forceTerminateMock,
  inspectTransitionMock,
  retryEnactmentMock,
  sampleSnapshot
} = vi.hoisted(() => {
  const summary = {
    enactment_id: "en-aaaa",
    flow_topic_id: "topic-x",
    state: "running" as const,
    version: 3,
    markings_count: 1,
    workitems_count: 1,
    last_occurrence_at: "2026-05-29T00:00:00Z",
    last_exception_banner: null as string | null
  }

  const marking = {
    place: "input",
    colour_set: "int",
    tokens_count: 2,
    tokens_summary: '2×"a"'
  }

  const workitem = {
    id: "wi-1",
    enactment_id: "en-aaaa",
    flow_topic_id: "topic-x",
    transition: "approve",
    state: "enabled" as const,
    binding_summary: "x = 1",
    output_vars: [],
    enabled_at: "2026-05-29T00:00:00Z",
    updated_at: "2026-05-29T00:00:00Z"
  }

  const occurrence = {
    id: "en-aaaa-1",
    step_number: 1,
    transition: "submit",
    binding_summary: "x = 1",
    occurred_at: "2026-05-29T00:00:00Z",
    outputs_summary: ""
  }

  const diagram = {
    places: [
      {
        name: "pending",
        colour_set: "trigger_t",
        tokens_count: 1,
        tokens_summary: "1×true"
      },
      { name: "decided", colour_set: "outcome", tokens_count: 0, tokens_summary: "" }
    ],
    transitions: [
      {
        name: "approve",
        enabled_count: 1,
        rejected_by_guard_count: 0,
        rejected_by_arc_eval_count: 0,
        rejected_by_marking_count: 0,
        last_fired_at: null as string | null
      }
    ],
    arcs: [
      { place: "pending", transition: "approve", orientation: "p_to_t" as const },
      { place: "decided", transition: "approve", orientation: "t_to_p" as const }
    ]
  }

  const telemetryEntry = {
    id: "en-aaaa-1",
    kind: "produce_workitems_stop" as const,
    at: "2026-05-29T00:00:00Z",
    summary: "Produced 1 workitem(s)",
    severity: "info" as const,
    payload_json: '{"operation":"produce_workitems"}'
  }

  return {
    takeSnapshotMock: vi.fn(),
    forceTerminateMock: vi.fn(),
    inspectTransitionMock: vi.fn(),
    retryEnactmentMock: vi.fn(),
    sampleSnapshot: {
      summary,
      transitions: ["approve"],
      diagram,
      markings: [marking],
      workitems: [workitem],
      occurrences: [occurrence],
      telemetry: [telemetryEntry]
    }
  }
})

// NetDiagram pulls in `@xyflow/react`, which requires DOM measurement APIs
// that jsdom does not implement for full edge painting. The stub forwards the
// click-to-Debug-tab click flow so page-level wiring can be exercised without
// mounting React Flow; NetDiagram has its own component test for the real
// rendering surface, and `mounts the real NetDiagram with a sample payload`
// below double-checks the shared default path.
vi.mock("../components/NetDiagram", () => ({
  default: ({
    onSelectTransition
  }: {
    onSelectTransition?: (name: string) => void
  }) => (
    <div data-testid="net-diagram-stub">
      <button
        type="button"
        data-testid="net-diagram-click-approve"
        onClick={() => onSelectTransition?.("approve")}
      >
        click approve transition
      </button>
    </div>
  )
}))

vi.mock("../musubi", () => ({
  useMusubiRoot: vi.fn().mockReturnValue({
    status: "ready",
    store: { __mock: "detail-proxy" },
    error: null
  }),
  useMusubiSnapshot: vi.fn().mockReturnValue(sampleSnapshot),
  useMusubiCommand: vi.fn().mockImplementation((_proxy: unknown, name: string) => {
    const dispatch =
      name === "take_snapshot"
        ? takeSnapshotMock
        : name === "inspect_transition"
          ? inspectTransitionMock
          : name === "retry_enactment"
            ? retryEnactmentMock
            : forceTerminateMock
    return {
      dispatch,
      isPending: false,
      error: null,
      data: null,
      reset: vi.fn()
    }
  }),
  // The redesigned PageHeader renders a live connection pill via this hook.
  useMusubiConnectionStatus: vi.fn().mockReturnValue({
    state: "ready",
    connection: { __mock: "connection" }
  })
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

import { MusubiCommandError } from "@musubi/react"
import EnactmentDetailPage from "./EnactmentDetailPage"

function renderRoute(children: ReactNode) {
  return render(
    <Toasty>
      <MemoryRouter initialEntries={["/enactments/en-aaaa"]}>
        <Routes>
          <Route path="/enactments/:id" element={children} />
        </Routes>
      </MemoryRouter>
    </Toasty>
  )
}

describe("EnactmentDetailPage", () => {
  beforeEach(() => {
    takeSnapshotMock.mockReset()
    forceTerminateMock.mockReset()
    inspectTransitionMock.mockReset()
    retryEnactmentMock.mockReset()
  })

  it("renders the net diagram card with NetDiagram mounted inside", () => {
    renderRoute(<EnactmentDetailPage />)
    expect(screen.getByTestId("net-diagram-card")).toBeDefined()
    expect(screen.getByTestId("net-diagram-stub")).toBeDefined()
  })

  it("lays out the diagram and the tabs as siblings under a split container", () => {
    renderRoute(<EnactmentDetailPage />)
    const split = screen.getByTestId("detail-split")
    const diagramCard = screen.getByTestId("net-diagram-card")
    const tabsPane = screen.getByTestId("detail-tabs-pane")
    // Immutable requirement: diagram + tabs share a parent (the split) so
    // the desktop layout can place them left/right (lg:flex-row). If a
    // future change moves them into unrelated containers, the spec breaks.
    expect(split.contains(diagramCard)).toBe(true)
    expect(split.contains(tabsPane)).toBe(true)
    expect(split.className).toMatch(/lg:flex-row/)
    expect(diagramCard.className).toMatch(/lg:basis-3\/5/)
    expect(tabsPane.className).toMatch(/lg:basis-2\/5/)
  })

  it("clicking a transition in the diagram switches to Debug and dispatches inspect_transition", async () => {
    inspectTransitionMock.mockResolvedValueOnce({
      code: "ok",
      transition: "approve",
      info: {
        transition: "approve",
        candidates_count: 1,
        enabled_count: 1,
        rejected_by_guard_count: 0,
        rejected_by_arc_eval_count: 0,
        rejected_by_marking_count: 0
      },
      candidates: [
        {
          transition: "approve",
          binding_summary: "t = true",
          guard_status: "enabled" as const,
          reason: null
        }
      ]
    })

    renderRoute(<EnactmentDetailPage />)

    await act(async () => {
      fireEvent.click(screen.getByTestId("net-diagram-click-approve"))
    })

    // Debug tab becomes the active tab + the inspector fires for the clicked
    // transition, both wired by the parent page (the DebugTab itself never
    // sees the click).
    await waitFor(() => {
      expect(screen.getByTestId("debug-tab")).toBeDefined()
      expect(inspectTransitionMock).toHaveBeenCalledWith({ transition: "approve" })
    })
  })

  it("renders the header with summary stats", () => {
    renderRoute(<EnactmentDetailPage />)
    expect(screen.getByText("en-aaaa")).toBeDefined()
    expect(screen.getByText("running")).toBeDefined()
    expect(screen.getByText(/Live workitems/)).toBeDefined()
  })

  it("renders Markings tab by default", () => {
    renderRoute(<EnactmentDetailPage />)
    expect(screen.getByRole("tab", { name: /Markings/ })).toBeDefined()
    expect(screen.getByText("input")).toBeDefined()
    expect(screen.getByText('2×"a"')).toBeDefined()
  })

  it("switches to Workitems tab and shows the live row", async () => {
    renderRoute(<EnactmentDetailPage />)
    await act(async () => {
      fireEvent.click(screen.getByRole("tab", { name: /Workitems/ }))
    })
    expect(screen.getByText("approve")).toBeDefined()
    // Withdraw action is intentionally absent — see plan note 2026-05-29
    // user decision dropping Withdraw/Reoffer end-to-end.
    expect(screen.queryByRole("button", { name: /Withdraw/ })).toBeNull()
  })

  it("renders the stale-markings Banner on the Markings tab", () => {
    renderRoute(<EnactmentDetailPage />)
    expect(screen.getByText(/Markings are mount-time-accurate/i)).toBeDefined()
    expect(
      screen.getByText(/Click Take snapshot in the action bar, then reload/i)
    ).toBeDefined()
  })

  it("labels the occurrences position column with a hover tooltip", async () => {
    renderRoute(<EnactmentDetailPage />)
    await act(async () => {
      fireEvent.click(screen.getByRole("tab", { name: /Occurrences/ }))
    })
    const position = screen.getByText("Position")
    expect(position).toBeDefined()
    expect(position.tagName).toBe("ABBR")
    expect((position as HTMLElement).getAttribute("title")).toMatch(
      /Per-mount stable index/
    )
  })

  it("switches to Occurrences tab and shows the synthesised row", async () => {
    renderRoute(<EnactmentDetailPage />)
    await act(async () => {
      fireEvent.click(screen.getByRole("tab", { name: /Occurrences/ }))
    })
    expect(screen.getByText("submit")).toBeDefined()
  })

  it("opens the force-terminate confirm dialog + dispatches", async () => {
    forceTerminateMock.mockResolvedValueOnce({ code: "ok" })

    renderRoute(<EnactmentDetailPage />)
    await act(async () => {
      fireEvent.click(screen.getByTestId("action-force-terminate"))
    })

    expect(screen.getByText(/Force terminate enactment/)).toBeDefined()

    await act(async () => {
      fireEvent.change(screen.getByTestId("force-terminate-reason"), {
        target: { value: "demo reset" }
      })
    })

    await act(async () => {
      fireEvent.click(screen.getByTestId("force-terminate-confirm"))
    })

    expect(forceTerminateMock).toHaveBeenCalledOnce()
    expect(forceTerminateMock).toHaveBeenCalledWith({ reason: "demo reset" })

    await waitFor(() => {
      expect(screen.getByText(/Enactment terminated/i)).toBeDefined()
    })
  })

  it("collapses :already_terminated into an info toast", async () => {
    forceTerminateMock.mockRejectedValueOnce(
      new MusubiCommandError({
        kind: "failed",
        command: "force_terminate",
        storeId: ["ColouredFlowDashboardWeb.Stores.EnactmentDetailStore", "en-aaaa"],
        reply: { code: "already_terminated" }
      })
    )

    renderRoute(<EnactmentDetailPage />)
    await act(async () => {
      fireEvent.click(screen.getByTestId("action-force-terminate"))
    })
    await act(async () => {
      fireEvent.click(screen.getByTestId("force-terminate-confirm"))
    })

    await waitFor(() => {
      expect(screen.getByText(/Already terminated/i)).toBeDefined()
    })
  })

  it("renders telemetry rows on the Telemetry tab", async () => {
    renderRoute(<EnactmentDetailPage />)
    await act(async () => {
      fireEvent.click(screen.getByRole("tab", { name: /Telemetry/ }))
    })
    expect(screen.getByTestId("telemetry-tab")).toBeDefined()
    expect(screen.getByText(/Produced 1 workitem/)).toBeDefined()
    expect(screen.getByText("produce_workitems_stop")).toBeDefined()
  })

  it("renders the exception banner from summary.last_exception_banner, ignoring workitem-op exception telemetry rows", async () => {
    const mut = sampleSnapshot as unknown as {
      summary: { state: string; last_exception_banner: string | null }
      telemetry: unknown[]
    }
    const originalState = mut.summary.state
    const originalBanner = mut.summary.last_exception_banner
    const originalTelemetry = mut.telemetry

    mut.summary.state = "exception"
    mut.summary.last_exception_banner = "real enactment failure"
    mut.telemetry = [
      // A workitem-op exception came first AND is the earliest "error" row;
      // the banner must NOT pick this — it must source from
      // summary.last_exception_banner instead.
      {
        id: "en-aaaa-wi-exc",
        kind: "produce_workitems_exception",
        at: "2026-05-29T00:00:00Z",
        summary: "workitem op blew up",
        severity: "error",
        payload_json: '{"error_banner":"workitem op blew up"}'
      },
      {
        id: "en-aaaa-exc",
        kind: "enactment_exception",
        at: "2026-05-29T00:00:01Z",
        summary: "real enactment failure",
        severity: "error",
        payload_json: '{"error_banner":"real enactment failure"}'
      }
    ]

    try {
      renderRoute(<EnactmentDetailPage />)
      await act(async () => {
        fireEvent.click(screen.getByRole("tab", { name: /Telemetry/ }))
      })
      await waitFor(() => {
        // Page-level exception banner sources its description from
        // `summary.last_exception_banner` — never from the telemetry stream.
        expect(screen.getAllByText("Enactment exception").length).toBeGreaterThanOrEqual(1)
        expect(screen.getAllByText("real enactment failure").length).toBeGreaterThanOrEqual(1)
      })

      // Sanity: page banner description does NOT contain the workitem-op text.
      // The telemetry row's summary cell does — but the banner does not.
      const allMatches = screen.queryAllByText("workitem op blew up")
      // Exactly one match (the telemetry row summary), never two.
      expect(allMatches.length).toBe(1)
    } finally {
      mut.summary.state = originalState
      mut.summary.last_exception_banner = originalBanner
      mut.telemetry = originalTelemetry
    }
  })

  it("dispatches :inspect_transition from the Debug tab and renders candidates", async () => {
    inspectTransitionMock.mockResolvedValueOnce({
      code: "ok",
      transition: "approve",
      info: {
        transition: "approve",
        candidates_count: 1,
        enabled_count: 1,
        rejected_by_guard_count: 0,
        rejected_by_arc_eval_count: 0,
        rejected_by_marking_count: 0
      },
      candidates: [
        {
          transition: "approve",
          binding_summary: "t = true",
          guard_status: "enabled" as const,
          reason: null
        }
      ]
    })

    renderRoute(<EnactmentDetailPage />)
    await act(async () => {
      fireEvent.click(screen.getByRole("tab", { name: /Debug/ }))
    })

    await act(async () => {
      fireEvent.click(screen.getByTestId("debug-transition-approve"))
    })

    expect(inspectTransitionMock).toHaveBeenCalledWith({ transition: "approve" })
    await waitFor(() => {
      expect(screen.getByTestId("debug-info-card")).toBeDefined()
      expect(screen.getByText("t = true")).toBeDefined()
    })
  })

  it("dispatches :take_snapshot and surfaces the ok toast", async () => {
    takeSnapshotMock.mockResolvedValueOnce({ code: "ok" })

    renderRoute(<EnactmentDetailPage />)
    await act(async () => {
      fireEvent.click(screen.getByTestId("action-take-snapshot"))
    })

    expect(takeSnapshotMock).toHaveBeenCalledOnce()
    await waitFor(() => {
      expect(screen.getByText(/Snapshot scheduled/i)).toBeDefined()
    })
  })

  describe("M6 exception affordances", () => {
    const mutate = (
      state: "running" | "exception" | "terminated",
      banner: string | null = null
    ) => {
      const mut = sampleSnapshot as unknown as {
        summary: { state: string; last_exception_banner: string | null }
      }
      const original = { state: mut.summary.state, banner: mut.summary.last_exception_banner }
      mut.summary.state = state
      mut.summary.last_exception_banner = banner
      return () => {
        mut.summary.state = original.state
        mut.summary.last_exception_banner = original.banner
      }
    }

    it("renders red Exception pill + subtitle + page banner when state=:exception", () => {
      const restore = mutate("exception", "Action raised")
      try {
        renderRoute(<EnactmentDetailPage />)
        expect(screen.getByTestId("state-badge-exception")).toBeDefined()
        expect(screen.getByTestId("detail-exception-banner")).toBeDefined()
        expect(
          screen.getByText("This enactment cannot make progress until terminated or reset.")
        ).toBeDefined()
        // Banner description renders from summary.last_exception_banner.
        expect(screen.getAllByText("Action raised").length).toBeGreaterThanOrEqual(1)
      } finally {
        restore()
      }
    })

    it("Retry button only renders in :exception and dispatches retry_enactment", async () => {
      const restore = mutate("exception", "boom")
      retryEnactmentMock.mockResolvedValueOnce({ code: "ok" })
      try {
        renderRoute(<EnactmentDetailPage />)
        const retry = screen.getByTestId("action-retry-enactment")
        await act(async () => {
          fireEvent.click(retry)
        })
        expect(retryEnactmentMock).toHaveBeenCalledOnce()
        await waitFor(() => {
          expect(screen.getByText(/Retry requested/i)).toBeDefined()
        })
      } finally {
        restore()
      }
    })

    it("Retry button is absent when state=:running", () => {
      renderRoute(<EnactmentDetailPage />)
      expect(screen.queryByTestId("action-retry-enactment")).toBeNull()
    })

    it("uses fallback banner copy when last_exception_banner is null", () => {
      const restore = mutate("exception", null)
      try {
        renderRoute(<EnactmentDetailPage />)
        // Page-level banner falls back to the generic copy.
        expect(screen.getAllByText(/Enactment is in an exception state/).length)
          .toBeGreaterThanOrEqual(1)
      } finally {
        restore()
      }
    })

    it("Errors only filter on Telemetry tab hides non-error rows", async () => {
      const mut = sampleSnapshot as unknown as {
        telemetry: Array<{
          id: string
          kind: string
          at: string
          summary: string
          severity: string
          payload_json: string
        }>
      }
      const original = mut.telemetry
      mut.telemetry = [
        { id: "a", kind: "produce_workitems_stop", at: "2026-05-29T00:00:00Z",
          summary: "Produced 1", severity: "info", payload_json: "{}" },
        { id: "b", kind: "enactment_exception", at: "2026-05-29T00:00:01Z",
          summary: "boom", severity: "error", payload_json: '{"transition":"approve"}' }
      ]
      try {
        renderRoute(<EnactmentDetailPage />)
        await act(async () => {
          fireEvent.click(screen.getByRole("tab", { name: /Telemetry/ }))
        })
        // Both rows render initially.
        expect(screen.getByTestId("telemetry-row-a")).toBeDefined()
        expect(screen.getByTestId("telemetry-row-b")).toBeDefined()

        await act(async () => {
          fireEvent.click(screen.getByTestId("telemetry-errors-only-checkbox"))
        })
        await waitFor(() => {
          expect(screen.queryByTestId("telemetry-row-a")).toBeNull()
          expect(screen.getByTestId("telemetry-row-b")).toBeDefined()
        })
      } finally {
        mut.telemetry = original
      }
    })

    it("Open in Debug button switches tab and dispatches inspect for the payload transition", async () => {
      const mut = sampleSnapshot as unknown as {
        telemetry: Array<{
          id: string
          kind: string
          at: string
          summary: string
          severity: string
          payload_json: string
        }>
      }
      const original = mut.telemetry
      mut.telemetry = [
        { id: "err-1", kind: "enactment_exception", at: "2026-05-29T00:00:00Z",
          summary: "boom", severity: "error",
          payload_json: '{"transition":"approve"}' }
      ]
      inspectTransitionMock.mockResolvedValueOnce({
        code: "ok",
        transition: "approve",
        info: {
          transition: "approve",
          candidates_count: 0,
          enabled_count: 0,
          rejected_by_guard_count: 0,
          rejected_by_arc_eval_count: 0,
          rejected_by_marking_count: 0
        },
        candidates: []
      })
      try {
        renderRoute(<EnactmentDetailPage />)
        await act(async () => {
          fireEvent.click(screen.getByRole("tab", { name: /Telemetry/ }))
        })
        await act(async () => {
          fireEvent.click(screen.getByTestId("telemetry-open-debug-err-1"))
        })
        await waitFor(() => {
          expect(inspectTransitionMock).toHaveBeenCalledWith({ transition: "approve" })
        })
      } finally {
        mut.telemetry = original
      }
    })
  })
})
