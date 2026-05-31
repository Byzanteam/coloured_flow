import { act, fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi, beforeEach } from "vitest"
import { MemoryRouter } from "react-router-dom"

type EnactmentRow = ColouredFlowDashboardWeb.Views.EnactmentRow

const { snapshotMock, makeRow } = vi.hoisted(() => {
  function build(
    id: string,
    flow_name: string,
    overrides: Partial<EnactmentRow> = {}
  ): EnactmentRow {
    return {
      id,
      flow_id: overrides.flow_id ?? `${id}-flow`,
      flow_name,
      state: overrides.state ?? "running",
      inserted_at: overrides.inserted_at ?? "2026-05-30T10:00:00Z",
      updated_at: overrides.updated_at ?? "2026-05-30T10:30:00Z",
      live_workitems: overrides.live_workitems ?? 0
    }
  }

  return {
    snapshotMock: vi.fn(),
    makeRow: build
  }
})

vi.mock("../musubi", () => ({
  useMusubiRootSuspense: vi.fn().mockReturnValue({ __mock: "enactments-proxy" }),
  useMusubiSnapshot: (...args: unknown[]) => snapshotMock(...args),
  useMusubiConnectionStatus: vi.fn().mockReturnValue({
    state: "ready",
    connection: { __mock: "connection" }
  })
}))

import EnactmentListPage from "./EnactmentListPage"

function loadSnapshot(
  rows: EnactmentRow[],
  counts?: {
    total_enactments: number
    running_count: number
    exception_count: number
    terminated_count: number
  }
) {
  const computed = counts ?? {
    total_enactments: rows.length,
    running_count: rows.filter((r) => r.state === "running").length,
    exception_count: rows.filter((r) => r.state === "exception").length,
    terminated_count: rows.filter((r) => r.state === "terminated").length
  }
  snapshotMock.mockReturnValue({
    enactments: rows,
    ...computed
  })
}

function renderAt(initialEntries: string[] = ["/enactments"]) {
  return render(
    <MemoryRouter initialEntries={initialEntries}>
      <EnactmentListPage />
    </MemoryRouter>
  )
}

describe("EnactmentListPage — render", () => {
  beforeEach(() => {
    snapshotMock.mockReset()
  })

  it("renders one table row per enactment with flow name + state", () => {
    loadSnapshot([
      makeRow("11111111-1111-1111-1111-111111111111", "Approval Demo", {
        state: "running",
        live_workitems: 2
      }),
      makeRow("22222222-2222-2222-2222-222222222222", "Traffic Light", {
        state: "terminated"
      })
    ])

    renderAt()

    expect(screen.getAllByText("Approval Demo").length).toBeGreaterThan(0)
    expect(screen.getAllByText("Traffic Light").length).toBeGreaterThan(0)
    expect(
      screen.getByTestId("enactment-row-11111111-1111-1111-1111-111111111111")
    ).toBeDefined()
    expect(
      screen.getByTestId("enactment-row-22222222-2222-2222-2222-222222222222")
    ).toBeDefined()
  })

  it("renders the empty state when no enactments exist", () => {
    loadSnapshot([])
    renderAt()
    expect(screen.getByText(/No enactments yet/i)).toBeDefined()
  })

  it("metrics row sums states", () => {
    loadSnapshot([
      makeRow("a", "F", { state: "running" }),
      makeRow("b", "F", { state: "exception" }),
      makeRow("c", "F", { state: "terminated" }),
      makeRow("d", "F", { state: "running" })
    ])
    renderAt()
    expect(screen.getByText("Total").nextSibling?.textContent).toBe("4")
    expect(screen.getByText("Running").nextSibling?.textContent).toBe("2")
    expect(screen.getByText("Exception").nextSibling?.textContent).toBe("1")
    expect(screen.getByText("Terminated").nextSibling?.textContent).toBe("1")
  })
})

describe("EnactmentListPage — controls", () => {
  beforeEach(() => {
    snapshotMock.mockReset()
  })

  it("filters rows by id substring search", async () => {
    loadSnapshot([
      makeRow("aaaa1111-1111-1111-1111-111111111111", "Approval"),
      makeRow("bbbb2222-2222-2222-2222-222222222222", "Traffic")
    ])
    renderAt()

    const search = screen.getByTestId("list-controls-search") as HTMLInputElement
    await act(async () => {
      fireEvent.change(search, { target: { value: "aaaa" } })
    })

    expect(
      screen.getByTestId("enactment-row-aaaa1111-1111-1111-1111-111111111111")
    ).toBeDefined()
    expect(
      screen.queryByTestId("enactment-row-bbbb2222-2222-2222-2222-222222222222")
    ).toBeNull()
  })

  it("filters rows by flow name substring search", async () => {
    loadSnapshot([
      makeRow("a-id", "Approval Demo"),
      makeRow("b-id", "Traffic Light")
    ])
    renderAt()

    const search = screen.getByTestId("list-controls-search") as HTMLInputElement
    await act(async () => {
      fireEvent.change(search, { target: { value: "traffic" } })
    })

    expect(screen.queryByTestId("enactment-row-a-id")).toBeNull()
    expect(screen.getByTestId("enactment-row-b-id")).toBeDefined()
  })

  it("filters rows by state chip toggle", async () => {
    loadSnapshot([
      makeRow("running-id", "F", { state: "running" }),
      makeRow("exception-id", "F", { state: "exception" }),
      makeRow("terminated-id", "F", { state: "terminated" })
    ])
    renderAt()

    await act(async () => {
      fireEvent.click(screen.getByTestId("enactment-state-filter-exception"))
    })

    expect(screen.queryByTestId("enactment-row-running-id")).toBeNull()
    expect(screen.getByTestId("enactment-row-exception-id")).toBeDefined()
    expect(screen.queryByTestId("enactment-row-terminated-id")).toBeNull()
  })

  it("filters rows by flow name multi-select", async () => {
    loadSnapshot([
      makeRow("a-id", "Approval Demo"),
      makeRow("b-id", "Traffic Light"),
      makeRow("c-id", "Pi Agent")
    ])
    renderAt()

    const flowSelect = screen.getByTestId("enactment-flow-filter") as HTMLSelectElement
    await act(async () => {
      Array.from(flowSelect.options).forEach((opt) => {
        opt.selected = opt.value === "Traffic Light"
      })
      fireEvent.change(flowSelect)
    })

    expect(screen.queryByTestId("enactment-row-a-id")).toBeNull()
    expect(screen.getByTestId("enactment-row-b-id")).toBeDefined()
    expect(screen.queryByTestId("enactment-row-c-id")).toBeNull()
  })

  it("hydrates filters from the URL on mount", () => {
    loadSnapshot([
      makeRow("a-id", "Approval Demo", { state: "running" }),
      makeRow("b-id", "Traffic Light", { state: "exception" })
    ])
    renderAt(["/enactments?state=exception"])

    expect(screen.queryByTestId("enactment-row-a-id")).toBeNull()
    expect(screen.getByTestId("enactment-row-b-id")).toBeDefined()
  })

  it("renders the filtered-empty card with a Clear filters affordance", async () => {
    loadSnapshot([makeRow("a-id", "Approval Demo", { state: "running" })])
    renderAt()

    const search = screen.getByTestId("list-controls-search") as HTMLInputElement
    await act(async () => {
      fireEvent.change(search, { target: { value: "no-match" } })
    })

    expect(screen.getByTestId("enactment-list-filters-empty")).toBeDefined()
    const clear = screen.getByRole("button", { name: /clear filters/i })

    await act(async () => {
      fireEvent.click(clear)
    })

    expect(screen.getByTestId("enactment-row-a-id")).toBeDefined()
  })

  it("paginates rows according to the page-size selector", () => {
    const rows = Array.from({ length: 14 }, (_, i) =>
      makeRow(`row-${i}`, "F", { state: "running" })
    )
    loadSnapshot(rows)
    renderAt(["/enactments?pageSize=10"])

    expect(screen.getByTestId("enactment-row-row-0")).toBeDefined()
    expect(screen.getByTestId("enactment-row-row-9")).toBeDefined()
    expect(screen.queryByTestId("enactment-row-row-10")).toBeNull()
  })
})
