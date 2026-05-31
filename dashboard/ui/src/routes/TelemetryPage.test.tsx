import { act, fireEvent, render, screen } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"
import { MemoryRouter } from "react-router-dom"
import { Toasty } from "@cloudflare/kumo"

type Entry = ColouredFlowDashboardWeb.Views.GlobalTelemetryEntry

const { snapshotMock, makeEntry } = vi.hoisted(() => {
  function build(id: string, overrides: Partial<Entry> = {}): Entry {
    return {
      id,
      event: overrides.event ?? "produce_workitems_stop",
      enactment_id: overrides.enactment_id ?? "11111111-aaaa-aaaa-aaaa-000000000000",
      flow_id: overrides.flow_id ?? "1234",
      occurred_at: overrides.occurred_at ?? "2026-05-30T10:00:00Z",
      seq: overrides.seq ?? 1,
      measurements_json: overrides.measurements_json ?? '{"seq":1}',
      metadata_json: overrides.metadata_json ?? '{"kind":"produce_workitems_stop"}',
      summary: overrides.summary ?? "produced 1 workitem(s)"
    }
  }

  return {
    snapshotMock: vi.fn(),
    makeEntry: build
  }
})

vi.mock("../musubi", () => ({
  useMusubiRootSuspense: vi.fn().mockReturnValue({ __mock: "feed-proxy" }),
  useMusubiSnapshot: (...args: unknown[]) => snapshotMock(...args),
  useMusubiCommand: () => ({
    dispatch: vi.fn(),
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

vi.mock("@musubi/react", () => {
  class MusubiCommandError extends Error {
    readonly kind: "failed" | "timeout"
    readonly command: string
    readonly storeId: readonly string[]
    constructor(options: {
      kind: "failed" | "timeout"
      command: string
      storeId: readonly string[]
    }) {
      super(`Command "${options.command}" failed`)
      this.name = "MusubiCommandError"
      this.kind = options.kind
      this.command = options.command
      this.storeId = options.storeId
    }
    static is(value: unknown): value is MusubiCommandError {
      return value instanceof Error && (value as { name?: string }).name === "MusubiCommandError"
    }
  }
  return { MusubiCommandError }
})

import TelemetryPage from "./TelemetryPage"

function loadSnapshot(entries: Entry[], totals?: { total_events?: number; entries_in_window?: number }) {
  snapshotMock.mockReturnValue({
    entries,
    total_events: totals?.total_events ?? entries.length,
    entries_in_window: totals?.entries_in_window ?? entries.length,
    oldest_seq: entries.length > 0 ? entries[entries.length - 1]!.seq : null,
    newest_seq: entries.length > 0 ? entries[0]!.seq : null
  })
}

function renderAt(initialEntries: string[] = ["/telemetry"]) {
  return render(
    <MemoryRouter initialEntries={initialEntries}>
      <Toasty>
        <TelemetryPage />
      </Toasty>
    </MemoryRouter>
  )
}

describe("TelemetryPage — render", () => {
  beforeEach(() => {
    snapshotMock.mockReset()
  })

  it("renders one row per entry with event name + short enactment id", () => {
    loadSnapshot([
      makeEntry("tf-1", {
        seq: 3,
        event: "complete_workitems_stop",
        enactment_id: "abcdef12-aaaa-aaaa-aaaa-000000000000"
      }),
      makeEntry("tf-2", {
        seq: 2,
        event: "produce_workitems_stop",
        enactment_id: "11111111-aaaa-aaaa-aaaa-000000000000"
      })
    ])

    renderAt()

    expect(screen.getByTestId("telemetry-row-tf-1")).toBeDefined()
    expect(screen.getByTestId("telemetry-row-tf-2")).toBeDefined()
    expect(screen.getAllByText("complete_workitems_stop").length).toBeGreaterThan(0)
    expect(screen.getByText(/abcdef12/)).toBeDefined()
  })

  it("renders empty state when feed is empty", () => {
    loadSnapshot([])
    renderAt()
    expect(screen.getByText(/No telemetry yet/i)).toBeDefined()
  })
})

describe("TelemetryPage — filters", () => {
  beforeEach(() => {
    snapshotMock.mockReset()
  })

  it("filters rows by search query (event name)", async () => {
    loadSnapshot([
      makeEntry("tf-1", { event: "produce_workitems_stop" }),
      makeEntry("tf-2", { event: "complete_workitems_stop" })
    ])
    renderAt()

    const search = screen.getByTestId("list-controls-search") as HTMLInputElement
    await act(async () => {
      fireEvent.change(search, { target: { value: "complete" } })
    })

    expect(screen.queryByTestId("telemetry-row-tf-1")).toBeNull()
    expect(screen.getByTestId("telemetry-row-tf-2")).toBeDefined()
  })

  it("narrows rows via event-name multi-select", async () => {
    loadSnapshot([
      makeEntry("tf-1", { event: "produce_workitems_stop" }),
      makeEntry("tf-2", { event: "complete_workitems_stop" }),
      makeEntry("tf-3", { event: "enactment_start" })
    ])
    renderAt()

    const eventFilter = screen.getByTestId("telemetry-event-filter") as HTMLSelectElement
    // Native multi-select: set selected on the chosen option.
    await act(async () => {
      const opt = Array.from(eventFilter.options).find(
        (o) => o.value === "enactment_start"
      )!
      opt.selected = true
      fireEvent.change(eventFilter)
    })

    expect(screen.queryByTestId("telemetry-row-tf-1")).toBeNull()
    expect(screen.queryByTestId("telemetry-row-tf-2")).toBeNull()
    expect(screen.getByTestId("telemetry-row-tf-3")).toBeDefined()
  })

  it("shows Empty + Clear filters when no row matches", async () => {
    loadSnapshot([makeEntry("tf-1", { event: "produce_workitems_stop" })])
    renderAt()

    const search = screen.getByTestId("list-controls-search") as HTMLInputElement
    await act(async () => {
      fireEvent.change(search, { target: { value: "no-match" } })
    })

    expect(screen.getByTestId("telemetry-filters-empty")).toBeDefined()
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: /clear filters/i }))
    })
    expect(screen.getByTestId("telemetry-row-tf-1")).toBeDefined()
  })
})

describe("TelemetryPage — retry", () => {
  beforeEach(() => {
    snapshotMock.mockReset()
  })

  it("recovers from a transient error via Retry", async () => {
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {})
    let shouldThrow = true
    snapshotMock.mockImplementation(() => {
      if (shouldThrow) throw new Error("boom")
      return {
        entries: [],
        total_events: 0,
        entries_in_window: 0,
        oldest_seq: null,
        newest_seq: null
      }
    })

    renderAt()
    expect(screen.getByTestId("telemetry-error")).toBeDefined()
    expect(screen.getByText(/boom/)).toBeDefined()

    shouldThrow = false
    await act(async () => {
      fireEvent.click(screen.getByTestId("telemetry-error-retry"))
    })

    expect(screen.queryByTestId("telemetry-error")).toBeNull()
    expect(screen.getByText(/No telemetry yet/i)).toBeDefined()
    errorSpy.mockRestore()
  })
})

describe("TelemetryPage — pagination", () => {
  beforeEach(() => {
    snapshotMock.mockReset()
  })

  it("paginates entries according to the page-size selector", () => {
    const entries = Array.from({ length: 14 }, (_, i) =>
      makeEntry(`tf-${i}`, { seq: 14 - i })
    )
    loadSnapshot(entries)
    renderAt(["/telemetry?pageSize=10"])

    expect(screen.getByTestId("telemetry-row-tf-0")).toBeDefined()
    expect(screen.getByTestId("telemetry-row-tf-9")).toBeDefined()
    expect(screen.queryByTestId("telemetry-row-tf-10")).toBeNull()
    expect(screen.getByTestId("list-pagination-info").textContent).toMatch(
      /Showing 1–10 of 14/
    )
  })
})
