import { act, fireEvent, render, screen, waitFor } from "@testing-library/react"
import { describe, expect, it, vi, beforeEach } from "vitest"
import type { ReactNode } from "react"
import { MemoryRouter, Route, Routes } from "react-router-dom"
import { Toasty } from "@cloudflare/kumo"

const { takeSnapshotMock, forceTerminateMock, inspectTransitionMock, sampleSnapshot } = vi.hoisted(() => {
  const summary = {
    enactment_id: "en-aaaa",
    flow_topic_id: "topic-x",
    state: "running" as const,
    version: 3,
    markings_count: 1,
    workitems_count: 1,
    last_occurrence_at: "2026-05-29T00:00:00Z"
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
    sampleSnapshot: {
      summary,
      transitions: ["approve"],
      markings: [marking],
      workitems: [workitem],
      occurrences: [occurrence],
      telemetry: [telemetryEntry]
    }
  }
})

vi.mock("../musubi", () => ({
  useMusubiRootSuspense: vi.fn().mockReturnValue({ __mock: "detail-proxy" }),
  useMusubiSnapshot: vi.fn().mockReturnValue(sampleSnapshot),
  useMusubiCommand: vi.fn().mockImplementation((_proxy: unknown, name: string) => {
    const dispatch =
      name === "take_snapshot"
        ? takeSnapshotMock
        : name === "inspect_transition"
          ? inspectTransitionMock
          : forceTerminateMock
    return {
      dispatch,
      isPending: false,
      error: null,
      data: null,
      reset: vi.fn()
    }
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

  it("renders the exception banner when summary.state is :exception", async () => {
    const mut = sampleSnapshot as unknown as {
      summary: { state: string }
      telemetry: unknown[]
    }
    const original = mut.summary.state
    mut.summary.state = "exception"
    const originalTelemetry = mut.telemetry
    mut.telemetry = [
      {
        id: "en-aaaa-exc",
        kind: "enactment_exception",
        at: "2026-05-29T00:00:00Z",
        summary: "boom",
        severity: "error",
        payload_json: '{"error_banner":"boom"}'
      }
    ]
    try {
      renderRoute(<EnactmentDetailPage />)
      await act(async () => {
        fireEvent.click(screen.getByRole("tab", { name: /Telemetry/ }))
      })
      await waitFor(() => {
        expect(screen.getByText("Enactment exception")).toBeDefined()
      })
    } finally {
      mut.summary.state = original
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

})
