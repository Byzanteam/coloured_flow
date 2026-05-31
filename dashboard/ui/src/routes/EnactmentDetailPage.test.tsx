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
  replayToVersionMock,
  exitReplayMock,
  completeWorkitemMock,
  sampleSnapshot
} = vi.hoisted(() => {
  const summary = {
    enactment_id: "en-aaaa",
    flow_topic_id: "topic-x",
    flow_name: "Approval Demo",
    state: "running" as const,
    version: 3,
    markings_count: 1,
    workitems_count: 1,
    last_occurrence_at: "2026-05-29T00:00:00Z",
    last_exception_banner: null as string | null,
    replay_state: null as null | { version: number; derived_at: string },
    version_range: { min: 0, max: 3 } as { min: number; max: number }
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
    enactment_state: "running" as const,
    binding_summary: "x = 1",
    binding_pairs: [],
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
    replayToVersionMock: vi.fn(),
    exitReplayMock: vi.fn(),
    completeWorkitemMock: vi.fn(),
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
    onSelectTransition,
    firingTransition,
    firingProgress,
    enabledTransitions
  }: {
    onSelectTransition?: (name: string) => void
    firingTransition?: string | null
    firingProgress?: { input: number; output: number }
    enabledTransitions?: ReadonlySet<string>
  }) => (
    <div
      data-testid="net-diagram-stub"
      data-firing-transition={firingTransition ?? ""}
      data-firing-input={String(firingProgress?.input ?? 0)}
      data-firing-output={String(firingProgress?.output ?? 0)}
      data-enabled-transitions={
        enabledTransitions === undefined
          ? "live"
          : JSON.stringify([...enabledTransitions].sort())
      }
    >
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
  useMusubiRootSuspense: vi.fn().mockReturnValue({ __mock: "detail-proxy" }),
  useMusubiSnapshot: vi.fn().mockReturnValue(sampleSnapshot),
  useMusubiCommand: vi.fn().mockImplementation((_proxy: unknown, name: string) => {
    const dispatch =
      name === "take_snapshot"
        ? takeSnapshotMock
        : name === "inspect_transition"
          ? inspectTransitionMock
          : name === "retry_enactment"
            ? retryEnactmentMock
            : name === "replay_to_version"
              ? replayToVersionMock
              : name === "exit_replay"
                ? exitReplayMock
                : name === "complete_workitem"
                  ? completeWorkitemMock
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
import { useMusubiSnapshot } from "../musubi"
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
    replayToVersionMock.mockReset()
    exitReplayMock.mockReset()
    completeWorkitemMock.mockReset()
  })

  it("renders the net diagram card with NetDiagram mounted inside", () => {
    renderRoute(<EnactmentDetailPage />)
    expect(screen.getByTestId("net-diagram-card")).toBeDefined()
    expect(screen.getByTestId("net-diagram-stub")).toBeDefined()
  })

  it("renders the H1 as `<flow name> · <short id>` when the summary carries flow_name", () => {
    renderRoute(<EnactmentDetailPage />)
    expect(
      screen.getByRole("heading", { level: 1, name: /Approval Demo · en-aaa/i })
    ).toBeDefined()
    // Byline still carries the full UUID so operators can copy it verbatim.
    expect(screen.getByText("en-aaaa")).toBeDefined()
  })

  it("falls back to a generic 'Enactment' H1 when flow_name is null", () => {
    const snap = vi.mocked(useMusubiSnapshot)
    snap.mockReturnValue({
      ...sampleSnapshot,
      summary: { ...sampleSnapshot.summary, flow_name: null }
    })
    try {
      renderRoute(<EnactmentDetailPage />)
      expect(screen.getByRole("heading", { level: 1, name: "Enactment" })).toBeDefined()
    } finally {
      snap.mockReturnValue(sampleSnapshot)
    }
  })

  it("renders the Colour sets panel from the snapshot diagram", async () => {
    renderRoute(<EnactmentDetailPage />)
    expect(screen.getByTestId("colour-sets-panel")).toBeDefined()
    await act(async () => {
      fireEvent.click(screen.getByTestId("colour-sets-toggle"))
    })
    expect(screen.getByTestId("colour-set-name-trigger_t").textContent).toBe(
      "trigger_t"
    )
    expect(screen.getByTestId("colour-set-type-outcome").textContent).toMatch(
      /\{verdict_t\(\), note_t\(\)\}/
    )
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

  it("workitems tab renders an Open button per row using the shared a11y label", async () => {
    renderRoute(<EnactmentDetailPage />)
    await act(async () => {
      fireEvent.click(screen.getByRole("tab", { name: /Workitems/ }))
    })
    expect(
      screen.getByRole("button", { name: "Open outputs drawer for workitem wi-1" })
    ).toBeDefined()
  })

  it("clicking Open mounts the OutputsDrawer with the workitem", async () => {
    renderRoute(<EnactmentDetailPage />)
    await act(async () => {
      fireEvent.click(screen.getByRole("tab", { name: /Workitems/ }))
    })

    await act(async () => {
      fireEvent.click(
        screen.getByRole("button", { name: "Open outputs drawer for workitem wi-1" })
      )
    })

    // Drawer title + workitem chrome
    expect(screen.getByText(/Complete workitem · approve/)).toBeDefined()
    // Free variables list is empty in the sample snapshot — no-free-variables banner.
    expect(screen.getByText(/No free variables/)).toBeDefined()
  })

  it("submitting the drawer dispatches complete_workitem against EnactmentDetailStore", async () => {
    completeWorkitemMock.mockResolvedValueOnce({ code: "ok" })

    renderRoute(<EnactmentDetailPage />)
    await act(async () => {
      fireEvent.click(screen.getByRole("tab", { name: /Workitems/ }))
    })
    await act(async () => {
      fireEvent.click(
        screen.getByRole("button", { name: "Open outputs drawer for workitem wi-1" })
      )
    })

    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    await waitFor(() => {
      expect(completeWorkitemMock).toHaveBeenCalledWith({
        workitem_id: "wi-1",
        outputs: {}
      })
    })
  })

  it("omits the legacy stale-markings Banner from the Markings tab", () => {
    renderRoute(<EnactmentDetailPage />)
    expect(screen.queryByTestId("markings-stale-banner")).toBeNull()
    expect(screen.queryByText(/Markings are mount-time-accurate/i)).toBeNull()
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

  describe("M7a timeline scrubber + replay", () => {
    const mutateReplay = (
      replayState: null | { version: number; derived_at: string },
      range?: { min: number; max: number }
    ) => {
      const mut = sampleSnapshot as unknown as {
        summary: {
          replay_state: null | { version: number; derived_at: string }
          version_range: { min: number; max: number }
        }
      }
      const original = {
        replay_state: mut.summary.replay_state,
        version_range: mut.summary.version_range
      }
      mut.summary.replay_state = replayState
      if (range) mut.summary.version_range = range
      return () => {
        mut.summary.replay_state = original.replay_state
        mut.summary.version_range = original.version_range
      }
    }

    it("renders the slider with the correct min/max from summary.version_range", () => {
      const restore = mutateReplay(null, { min: 2, max: 9 })
      try {
        renderRoute(<EnactmentDetailPage />)
        const slider = screen.getByTestId("timeline-slider") as HTMLInputElement
        expect(slider.min).toBe("2")
        expect(slider.max).toBe("9")
      } finally {
        restore()
      }
    })

    it("dragging dispatches a debounced :replay_to_version after 150ms", async () => {
      vi.useFakeTimers()
      replayToVersionMock.mockResolvedValue({
        code: "ok",
        markings: [],
        replay_state: { version: 2, derived_at: "2026-05-29T01:00:00Z" },
        available_max_version: 5,
        snapshot_floor: 0
      })
      try {
        renderRoute(<EnactmentDetailPage />)
        const slider = screen.getByTestId("timeline-slider")
        fireEvent.change(slider, { target: { value: "1" } })
        fireEvent.change(slider, { target: { value: "2" } })
        // Before debounce window: no dispatch yet.
        expect(replayToVersionMock).not.toHaveBeenCalled()
        await act(async () => {
          await vi.advanceTimersByTimeAsync(160)
        })
        // Only the last value should hit the server.
        expect(replayToVersionMock).toHaveBeenCalledTimes(1)
        expect(replayToVersionMock).toHaveBeenCalledWith({ version: 2 })
      } finally {
        vi.useRealTimers()
      }
    })

    it("step-forward button dispatches immediately without debounce", async () => {
      replayToVersionMock.mockResolvedValueOnce({
        code: "ok",
        markings: [],
        replay_state: { version: 1, derived_at: "2026-05-29T01:00:00Z" },
        available_max_version: 3,
        snapshot_floor: 0
      })
      const restore = mutateReplay(null, { min: 0, max: 3 })
      try {
        renderRoute(<EnactmentDetailPage />)
        // value starts at liveVersion=3; step back once to v2, dispatch fires now.
        await act(async () => {
          fireEvent.click(screen.getByTestId("timeline-step-back"))
        })
        expect(replayToVersionMock).toHaveBeenCalledWith({ version: 2 })
      } finally {
        restore()
      }
    })

    it("renders the Markings replay banner when summary.replay_state is set, without a separate page-header REPLAY pill", () => {
      const restore = mutateReplay(
        { version: 1, derived_at: "2026-05-29T01:00:00Z" },
        { min: 0, max: 3 }
      )
      try {
        renderRoute(<EnactmentDetailPage />)
        // The page-header REPLAY pill was dropped — TimelineScrubber's own
        // status line + the jump-to-live button now signal replay mode.
        expect(screen.queryByTestId("state-badge-replay")).toBeNull()
        expect(screen.getByTestId("markings-replay-banner")).toBeDefined()
      } finally {
        restore()
      }
    })

    it("live mode passes undefined enabledTransitions so NetDiagram uses its internal enabled_count derivation", () => {
      renderRoute(<EnactmentDetailPage />)
      expect(
        screen.getByTestId("net-diagram-stub").dataset.enabledTransitions
      ).toBe("live")
    })

    it("replay_to_version reply's enabled_transitions wires straight into NetDiagram's enabledTransitions", async () => {
      replayToVersionMock.mockResolvedValueOnce({
        code: "ok",
        markings: [],
        enabled_transitions: ["approve"],
        replay_state: { version: 1, derived_at: "2026-05-29T01:00:00Z" },
        available_max_version: 3,
        snapshot_floor: 0
      })
      const restore = mutateReplay(
        { version: 1, derived_at: "2026-05-29T01:00:00Z" },
        { min: 0, max: 3 }
      )
      try {
        renderRoute(<EnactmentDetailPage />)
        await act(async () => {
          fireEvent.click(screen.getByTestId("timeline-step-back"))
        })
        await waitFor(() => {
          const value = screen.getByTestId("net-diagram-stub").dataset.enabledTransitions
          expect(value).toBe(JSON.stringify(["approve"]))
        })
      } finally {
        restore()
      }
    })

    it("an empty enabled_transitions clears the replay enabled-transitions override", async () => {
      replayToVersionMock.mockResolvedValueOnce({
        code: "ok",
        markings: [],
        enabled_transitions: [],
        replay_state: { version: 0, derived_at: "2026-05-29T01:00:00Z" },
        available_max_version: 3,
        snapshot_floor: 0
      })
      const restore = mutateReplay(
        { version: 1, derived_at: "2026-05-29T01:00:00Z" },
        { min: 0, max: 3 }
      )
      try {
        renderRoute(<EnactmentDetailPage />)
        await act(async () => {
          fireEvent.click(screen.getByTestId("timeline-step-back"))
        })
        await waitFor(() => {
          // Override must be a concrete (empty) set, NOT "live" — replay mode
          // must never fall back to the live `enabled_count`.
          expect(
            screen.getByTestId("net-diagram-stub").dataset.enabledTransitions
          ).toBe("[]")
        })
      } finally {
        restore()
      }
    })

    it("starts firingTransition + drives firingProgress over the speed-duration window when live version advances", async () => {
      const mut = sampleSnapshot as unknown as {
        summary: { version: number }
        occurrences: Array<{
          id: string
          step_number: number
          transition: string
          binding_summary: string
          occurred_at: string
          outputs_summary: string
        }>
      }
      const origVersion = mut.summary.version
      const origOccurrences = mut.occurrences
      // Park the live version at 3 with no occurrence at v=3 so the initial
      // mount seeds `lastVersionRef` without firing the animation.
      mut.summary.version = 3
      mut.occurrences = []

      const rafCallbacks: FrameRequestCallback[] = []
      const nowRef = { current: 1_000 }
      const performanceSpy = vi.spyOn(performance, "now").mockImplementation(() => nowRef.current)
      const rafSpy = vi
        .spyOn(window, "requestAnimationFrame")
        .mockImplementation((cb: FrameRequestCallback): number => {
          rafCallbacks.push(cb)
          return rafCallbacks.length
        })
      const cafSpy = vi.spyOn(window, "cancelAnimationFrame").mockImplementation(() => {})
      const flushRaf = async () => {
        const due = rafCallbacks.splice(0)
        await act(async () => {
          due.forEach((cb) => cb(nowRef.current))
        })
      }

      try {
        const { rerender } = renderRoute(<EnactmentDetailPage />)
        const stub = () => screen.getByTestId("net-diagram-stub")
        expect(stub().dataset.firingTransition).toBe("")

        // Bump version → simulate occurrence at v=4 firing `approve`.
        mut.summary.version = 4
        mut.occurrences = [
          {
            id: "occ-4",
            step_number: 4,
            transition: "approve",
            binding_summary: "",
            occurred_at: "2026-05-29T01:00:00Z",
            outputs_summary: ""
          }
        ]
        await act(async () => {
          rerender(
            <Toasty>
              <MemoryRouter initialEntries={["/enactments/en-aaaa"]}>
                <Routes>
                  <Route path="/enactments/:id" element={<EnactmentDetailPage />} />
                </Routes>
              </MemoryRouter>
            </Toasty>
          )
        })

        expect(stub().dataset.firingTransition).toBe("approve")
        // 1× speed default → 2000 ms window split 40/20/40 (inputEndMs=800,
        // outputStartMs=1200, fullMs=2000). RAF hasn't ticked → progress=0.
        expect(stub().dataset.firingInput).toBe("0")
        expect(stub().dataset.firingOutput).toBe("0")

        // Phase A midpoint (elapsed = 400 ms → input = 400/800 = 0.5).
        nowRef.current = 1_400
        await flushRaf()
        expect(Number(stub().dataset.firingInput)).toBeCloseTo(0.5, 2)
        expect(stub().dataset.firingOutput).toBe("0")

        // Dwell interval (elapsed = 1000 ms → input = 1, output = 0).
        nowRef.current = 2_000
        await flushRaf()
        expect(stub().dataset.firingInput).toBe("1")
        expect(stub().dataset.firingOutput).toBe("0")

        // Phase B midpoint (elapsed = 1600 ms → input = 1, output = (1600-1200)/800 = 0.5).
        nowRef.current = 2_600
        await flushRaf()
        expect(stub().dataset.firingInput).toBe("1")
        expect(Number(stub().dataset.firingOutput)).toBeCloseTo(0.5, 2)

        // Past full duration → firingPhase cleared.
        nowRef.current = 3_100
        await flushRaf()
        expect(stub().dataset.firingTransition).toBe("")
        expect(stub().dataset.firingInput).toBe("0")
        expect(stub().dataset.firingOutput).toBe("0")
      } finally {
        mut.summary.version = origVersion
        mut.occurrences = origOccurrences
        performanceSpy.mockRestore()
        rafSpy.mockRestore()
        cafSpy.mockRestore()
      }
    })

    it("replay step-forward holds the PRE-fire enabled set across the entire firing window, then snaps to post-fire at fullMs", async () => {
      const restore = mutateReplay(
        { version: 0, derived_at: "2026-05-29T01:00:00Z" },
        { min: 0, max: 3 }
      )
      const mut = sampleSnapshot as unknown as {
        occurrences: Array<{
          id: string
          step_number: number
          transition: string
          binding_summary: string
          occurred_at: string
          outputs_summary: string
        }>
      }
      const origOccurrences = mut.occurrences
      // Replay needs the occurrence at v=1 so the page detects a single-step
      // advance worth animating.
      mut.occurrences = [
        {
          id: "occ-1",
          step_number: 1,
          transition: "approve",
          binding_summary: "",
          occurred_at: "2026-05-29T01:00:00Z",
          outputs_summary: ""
        }
      ]
      replayToVersionMock.mockResolvedValueOnce({
        code: "ok",
        markings: [],
        enabled_transitions: ["after_fire"],
        replay_state: { version: 1, derived_at: "2026-05-29T01:00:00Z" },
        available_max_version: 3,
        snapshot_floor: 0
      })

      // Manual RAF pump: fake timers can't drive RAF inside `await act(async)`
      // here because the dispatch promise resolves on the microtask queue and
      // `vi.advanceTimersByTime` interleaves badly with the dispatch flush.
      // Replacing rAF gives us full control over each tick.
      const rafCallbacks: FrameRequestCallback[] = []
      const nowRef = { current: 5_000 }
      const performanceSpy = vi.spyOn(performance, "now").mockImplementation(() => nowRef.current)
      const rafSpy = vi
        .spyOn(window, "requestAnimationFrame")
        .mockImplementation((cb: FrameRequestCallback): number => {
          rafCallbacks.push(cb)
          return rafCallbacks.length
        })
      const cafSpy = vi.spyOn(window, "cancelAnimationFrame").mockImplementation(() => {})
      const flushRaf = async () => {
        const due = rafCallbacks.splice(0)
        await act(async () => {
          due.forEach((cb) => cb(nowRef.current))
        })
      }

      try {
        renderRoute(<EnactmentDetailPage />)
        await act(async () => {
          fireEvent.click(screen.getByTestId("timeline-step-forward"))
        })
        const stub = () => screen.getByTestId("net-diagram-stub")

        // After reply but BEFORE the first RAF tick: firingPhase is set, and
        // the enabledTransitions override is still the pre-fire empty set —
        // the post-fire `["after_fire"]` payload is stashed in a ref waiting
        // for the Phase B end (fullMs), NOT applied yet.
        expect(stub().dataset.firingTransition).toBe("approve")
        expect(stub().dataset.enabledTransitions).toBe("[]")

        // First RAF tick at elapsed = 0. Pre-fire.
        await flushRaf()
        expect(stub().dataset.enabledTransitions).toBe("[]")

        // Cross inputEndMs (=800) into the intermediate (dwell) window. The
        // engine-correct intermediate enabled set can't be computed
        // client-side (arc multiplicity / guards / binding expressions are
        // not on the wire), so we keep the pre-fire enabled set instead of
        // lying with a tokens-only approximation.
        nowRef.current = 5_900
        await flushRaf()
        expect(stub().dataset.enabledTransitions).toBe("[]")

        // Still in Phase B (elapsed = 1600 → between outputStartMs=1200 and
        // fullMs=2000). Override still pre-fire.
        nowRef.current = 6_600
        await flushRaf()
        expect(stub().dataset.enabledTransitions).toBe("[]")

        // Past fullMs → applyFinalPendings flips replayEnabledTransitions to
        // the post-fire set carried by the reply.
        nowRef.current = 7_100
        await flushRaf()
        expect(stub().dataset.firingTransition).toBe("")
        expect(stub().dataset.enabledTransitions).toBe(JSON.stringify(["after_fire"]))
      } finally {
        mut.occurrences = origOccurrences
        restore()
        performanceSpy.mockRestore()
        rafSpy.mockRestore()
        cafSpy.mockRestore()
      }
    })

    it("skips the live firing animation when activeVersion jumps by more than 1 (multi-occurrence batch)", async () => {
      const mut = sampleSnapshot as unknown as {
        summary: { version: number }
        occurrences: Array<{
          id: string
          step_number: number
          transition: string
          binding_summary: string
          occurred_at: string
          outputs_summary: string
        }>
      }
      const origVersion = mut.summary.version
      const origOccurrences = mut.occurrences
      // Park at v=3 with no occurrence so mount seeds lastVersionRef without
      // animating.
      mut.summary.version = 3
      mut.occurrences = []

      try {
        const { rerender } = renderRoute(<EnactmentDetailPage />)
        const stub = () => screen.getByTestId("net-diagram-stub")
        expect(stub().dataset.firingTransition).toBe("")

        // Jump from v=3 to v=5 (TWO occurrences). The runner batched both;
        // animating only the LAST would misrepresent the timeline, so the
        // page must snap to post-fire without running the firing animation.
        mut.summary.version = 5
        mut.occurrences = [
          {
            id: "occ-4",
            step_number: 4,
            transition: "approve",
            binding_summary: "",
            occurred_at: "2026-05-29T01:00:00Z",
            outputs_summary: ""
          },
          {
            id: "occ-5",
            step_number: 5,
            transition: "approve",
            binding_summary: "",
            occurred_at: "2026-05-29T01:00:01Z",
            outputs_summary: ""
          }
        ]
        await act(async () => {
          rerender(
            <Toasty>
              <MemoryRouter initialEntries={["/enactments/en-aaaa"]}>
                <Routes>
                  <Route path="/enactments/:id" element={<EnactmentDetailPage />} />
                </Routes>
              </MemoryRouter>
            </Toasty>
          )
        })

        expect(stub().dataset.firingTransition).toBe("")
        expect(stub().dataset.firingInput).toBe("0")
        expect(stub().dataset.firingOutput).toBe("0")
      } finally {
        mut.summary.version = origVersion
        mut.occurrences = origOccurrences
      }
    })

    it("live firing animation holds the PRE-fire enabled set across all phases via the override", async () => {
      const mut = sampleSnapshot as unknown as {
        summary: { version: number }
        occurrences: Array<{
          id: string
          step_number: number
          transition: string
          binding_summary: string
          occurred_at: string
          outputs_summary: string
        }>
      }
      const origVersion = mut.summary.version
      const origOccurrences = mut.occurrences
      // Sample diagram has `approve` with enabled_count=1, so the pre-fire
      // enabled set derived in live mode is ["approve"]. NetDiagram normally
      // derives that itself from displayedDiagram.transitions[].enabled_count,
      // so the stub reports "live". With the firing override active during
      // the animation it should switch to a concrete set instead.
      mut.summary.version = 3
      mut.occurrences = []

      const rafCallbacks: FrameRequestCallback[] = []
      const nowRef = { current: 1_000 }
      const performanceSpy = vi.spyOn(performance, "now").mockImplementation(() => nowRef.current)
      const rafSpy = vi
        .spyOn(window, "requestAnimationFrame")
        .mockImplementation((cb: FrameRequestCallback): number => {
          rafCallbacks.push(cb)
          return rafCallbacks.length
        })
      const cafSpy = vi.spyOn(window, "cancelAnimationFrame").mockImplementation(() => {})
      const flushRaf = async () => {
        const due = rafCallbacks.splice(0)
        await act(async () => {
          due.forEach((cb) => cb(nowRef.current))
        })
      }

      try {
        const { rerender } = renderRoute(<EnactmentDetailPage />)
        const stub = () => screen.getByTestId("net-diagram-stub")
        // No firing yet → NetDiagram derives enabled set itself.
        expect(stub().dataset.enabledTransitions).toBe("live")

        mut.summary.version = 4
        mut.occurrences = [
          {
            id: "occ-4",
            step_number: 4,
            transition: "approve",
            binding_summary: "",
            occurred_at: "2026-05-29T01:00:00Z",
            outputs_summary: ""
          }
        ]
        await act(async () => {
          rerender(
            <Toasty>
              <MemoryRouter initialEntries={["/enactments/en-aaaa"]}>
                <Routes>
                  <Route path="/enactments/:id" element={<EnactmentDetailPage />} />
                </Routes>
              </MemoryRouter>
            </Toasty>
          )
        })

        expect(stub().dataset.firingTransition).toBe("approve")
        // Override active across pre + intermediate + Phase B (until fullMs).
        const preFireSet = JSON.stringify(["approve"])
        expect(stub().dataset.enabledTransitions).toBe(preFireSet)

        // Phase A midpoint.
        nowRef.current = 1_400
        await flushRaf()
        expect(stub().dataset.enabledTransitions).toBe(preFireSet)

        // Intermediate (dwell).
        nowRef.current = 2_000
        await flushRaf()
        expect(stub().dataset.enabledTransitions).toBe(preFireSet)

        // Phase B midpoint.
        nowRef.current = 2_600
        await flushRaf()
        expect(stub().dataset.enabledTransitions).toBe(preFireSet)

        // Past fullMs → firing clears, override goes away, NetDiagram derives
        // from the (post-fire) displayed diagram again.
        nowRef.current = 3_100
        await flushRaf()
        expect(stub().dataset.firingTransition).toBe("")
        expect(stub().dataset.enabledTransitions).toBe("live")
      } finally {
        mut.summary.version = origVersion
        mut.occurrences = origOccurrences
        performanceSpy.mockRestore()
        rafSpy.mockRestore()
        cafSpy.mockRestore()
      }
    })

    it("Jump-to-live button dispatches :exit_replay while in replay", async () => {
      const restore = mutateReplay(
        { version: 1, derived_at: "2026-05-29T01:00:00Z" },
        { min: 0, max: 3 }
      )
      exitReplayMock.mockResolvedValueOnce({ code: "ok" })
      try {
        renderRoute(<EnactmentDetailPage />)
        await act(async () => {
          fireEvent.click(screen.getByTestId("timeline-jump-live"))
        })
        expect(exitReplayMock).toHaveBeenCalledOnce()
      } finally {
        restore()
      }
    })
  })
})

describe("EnactmentDetailPage — retry", () => {
  beforeEach(() => {
    takeSnapshotMock.mockReset()
    forceTerminateMock.mockReset()
    inspectTransitionMock.mockReset()
    retryEnactmentMock.mockReset()
    replayToVersionMock.mockReset()
    exitReplayMock.mockReset()
    completeWorkitemMock.mockReset()
    vi.mocked(useMusubiSnapshot).mockReturnValue(sampleSnapshot)
  })

  it("recovers from a transient error via Retry", async () => {
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {})
    let shouldThrow = true
    vi.mocked(useMusubiSnapshot).mockImplementation(() => {
      if (shouldThrow) throw new Error("boom")
      return sampleSnapshot
    })

    renderRoute(<EnactmentDetailPage />)
    expect(screen.getByTestId("detail-error")).toBeDefined()
    expect(screen.getByText(/boom/)).toBeDefined()

    shouldThrow = false
    await act(async () => {
      fireEvent.click(screen.getByTestId("detail-error-retry"))
    })

    expect(screen.queryByTestId("detail-error")).toBeNull()
    expect(screen.getByTestId("net-diagram-card")).toBeDefined()
    errorSpy.mockRestore()
  })
})
