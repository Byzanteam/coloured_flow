import { act, fireEvent, render, screen, waitFor } from "@testing-library/react"
import { describe, expect, it, vi, beforeEach } from "vitest"
import type { ReactNode } from "react"
import { MemoryRouter } from "react-router-dom"
import { Toasty } from "@cloudflare/kumo"

// ---------------------------------------------------------------------------
// musubi mocks
// ---------------------------------------------------------------------------
//
// The Inbox page consumes the musubi react surface (`useMusubiSnapshot`,
// `useMusubiRootSuspense`, `useMusubiCommand`). We stub those so the test renders
// synchronously without a real socket.

type OutputVar = ColouredFlowDashboardWeb.Views.OutputVar
type WorkitemRow = ColouredFlowDashboardWeb.Views.WorkitemRow

const { dispatchMock, snapshotMock, makeRow, schemaMix, schemaBinary, schemaElixir } = vi.hoisted(
  () => {
    type SchemaInput = { name: string; colour_set: string; kind: OutputVar["kind"]; enum_values?: string[] | null; hint?: string | null; example?: string | null }
    const v = (s: SchemaInput): OutputVar => ({
      name: s.name,
      colour_set: s.colour_set,
      kind: s.kind,
      enum_values: s.enum_values ?? null,
      hint: s.hint ?? null,
      example: s.example ?? null
    })

    const binary: OutputVar[] = [
      v({ name: "note", colour_set: "note_t", kind: "string" }),
      v({ name: "verdict", colour_set: "verdict_t", kind: "string" })
    ]

    const mixed: OutputVar[] = [
      v({
        name: "severity",
        colour_set: "severity_t",
        kind: "enum",
        enum_values: ["low", "medium", "high"]
      }),
      v({ name: "acknowledged", colour_set: "alert_t", kind: "boolean" }),
      v({ name: "count", colour_set: "int", kind: "integer" }),
      v({ name: "note", colour_set: "note_t", kind: "string" })
    ]

    const elixir: OutputVar[] = [
      v({
        name: "payload",
        colour_set: "tool_call",
        kind: "elixir",
        hint: "Colour set `tool_call` is complex; provide an Elixir term literal.",
        example: '{:read, "text"}'
      })
    ]

    function buildRow(id: string, transition: string, schema: OutputVar[]): WorkitemRow {
      return {
        id,
        enactment_id: "enactment-aaaa-bbbb-cccc",
        flow_topic_id: "topic-x",
        transition,
        state: "enabled",
        enactment_state: "running",
        binding_summary: "",
        output_vars: schema,
        enabled_at: "2026-05-29T00:00:00Z",
        updated_at: "2026-05-29T00:00:00Z"
      }
    }

    const snapshotMock = vi.fn()

    return {
      dispatchMock: vi.fn(),
      snapshotMock,
      makeRow: buildRow,
      schemaBinary: binary,
      schemaMix: mixed,
      schemaElixir: elixir
    }
  }
)

function loadSnapshot(row: WorkitemRow) {
  snapshotMock.mockReturnValue({
    workitems: [row],
    counts: { enabled: 1, started: 0, by_enactment: { [row.enactment_id]: 1 } }
  })
}

vi.mock("../musubi", () => ({
  useMusubiRootSuspense: vi.fn().mockReturnValue({ __mock: "inbox-proxy" }),
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
import InboxPage from "./InboxPage"

function renderWithProviders(children: ReactNode) {
  // PageHeader now reads `useSearchParams` (embed-mode hook), so every
  // InboxPage render needs a Router context. MemoryRouter is the cheapest.
  return render(
    <MemoryRouter>
      <Toasty>{children}</Toasty>
    </MemoryRouter>
  )
}

function renderWithRouter(children: ReactNode) {
  return render(
    <MemoryRouter>
      <Toasty>{children}</Toasty>
    </MemoryRouter>
  )
}

async function openDrawer(workitemId: string) {
  await act(async () => {
    fireEvent.click(
      screen.getByRole("button", { name: new RegExp(`open outputs drawer for workitem ${workitemId}`, "i") })
    )
  })
}

describe("InboxPage outputs drawer — render", () => {
  beforeEach(() => {
    dispatchMock.mockReset()
  })

  it("opens the drawer with the schema-driven form", async () => {
    loadSnapshot(makeRow("wi-1", "approve", schemaBinary))
    renderWithProviders(<InboxPage />)
    await openDrawer("wi-1")

    expect(screen.getByText(/Complete workitem · approve/i)).toBeDefined()
    expect(screen.getByTestId("outputs-form")).toBeDefined()
    expect(screen.getByTestId("outputs-field-verdict")).toBeDefined()
    expect(screen.getByTestId("outputs-field-note")).toBeDefined()
  })

  it("renders binding_summary inside Kumo CodeBlock", async () => {
    const row = {
      ...makeRow("wi-bind", "approve", schemaBinary),
      binding_summary: "x = 1, y = :foo"
    }
    loadSnapshot(row)
    renderWithProviders(<InboxPage />)
    await openDrawer("wi-bind")

    const wrap = screen.getByTestId("drawer-binding-code")
    expect(wrap).toBeDefined()
    expect(wrap.textContent).toContain("x = 1, y = :foo")
    // CodeBlock renders a <code> child inside its bordered container; the
    // wrapper itself is not a <pre>, but Kumo's CodeBlock injects one.
    expect(wrap.querySelector("pre")).not.toBeNull()
  })
})

describe("InboxPage outputs drawer — control types", () => {
  beforeEach(() => {
    dispatchMock.mockReset()
  })

  it("renders Input controls for :string vars", async () => {
    loadSnapshot(makeRow("wi-1", "approve", schemaBinary))
    renderWithProviders(<InboxPage />)
    await openDrawer("wi-1")

    const note = screen.getByTestId("outputs-field-note") as HTMLInputElement
    expect(note.type).toBe("text")
    expect(note.value).toBe("")
  })

  it("renders a number input for :integer vars and rejects NaN", async () => {
    loadSnapshot(makeRow("wi-2", "triage", schemaMix))
    renderWithProviders(<InboxPage />)
    await openDrawer("wi-2")

    const count = screen.getByTestId("outputs-field-count") as HTMLInputElement
    expect(count.type).toBe("number")

    // Empty string → null → submit stays disabled.
    const submit = screen.getByTestId("outputs-submit") as HTMLButtonElement
    expect(submit.disabled).toBe(true)
  })

  it("renders Checkbox for :boolean vars and defaults to false", async () => {
    loadSnapshot(makeRow("wi-2", "triage", schemaMix))
    renderWithProviders(<InboxPage />)
    await openDrawer("wi-2")

    const checkbox = screen.getByTestId("outputs-field-acknowledged") as HTMLInputElement
    // Base UI Checkbox renders as an input under the hood; assert it exists +
    // is initially not checked.
    expect(checkbox).toBeDefined()
    expect(checkbox.checked === true).toBe(false)
  })

  it("renders Select for :enum vars and disables submit until a choice", async () => {
    loadSnapshot(makeRow("wi-2", "triage", schemaMix))
    renderWithProviders(<InboxPage />)
    await openDrawer("wi-2")

    expect(screen.getByTestId("outputs-field-severity")).toBeDefined()

    const submit = screen.getByTestId("outputs-submit") as HTMLButtonElement
    expect(submit.disabled).toBe(true)
  })

  it("falls back to an Elixir InputArea for unknown shapes", async () => {
    loadSnapshot(makeRow("wi-3", "weird", schemaElixir))
    renderWithProviders(<InboxPage />)
    await openDrawer("wi-3")

    const textarea = screen.getByTestId("outputs-field-payload-elixir") as HTMLTextAreaElement
    expect(textarea.tagName).toBe("TEXTAREA")
    expect(textarea.placeholder).toBe('{:read, "text"}')
    expect(screen.getByText(/provide an Elixir term literal/i)).toBeDefined()
  })
})

describe("InboxPage outputs drawer — submission", () => {
  beforeEach(() => {
    dispatchMock.mockReset()
  })

  it("dispatches typed payload from mixed schema submission", async () => {
    dispatchMock.mockResolvedValueOnce({ code: "ok" })

    loadSnapshot(makeRow("wi-2", "triage", schemaMix))
    renderWithProviders(<InboxPage />)
    await openDrawer("wi-2")

    // Severity = "medium"
    const severity = screen.getByTestId("outputs-field-severity") as HTMLInputElement
    await act(async () => {
      // Kumo Select syncs `value` via a hidden input; firing change is enough
      // for the controlled-mode onValueChange to fire in jsdom.
      fireEvent.change(severity, { target: { value: "medium" } })
    })

    // Acknowledged checkbox → click toggles to true.
    const ack = screen.getByTestId("outputs-field-acknowledged") as HTMLInputElement
    await act(async () => {
      fireEvent.click(ack)
    })

    // Count = 3
    const count = screen.getByTestId("outputs-field-count") as HTMLInputElement
    await act(async () => {
      fireEvent.change(count, { target: { value: "3" } })
    })

    // Note = "loud"
    const note = screen.getByTestId("outputs-field-note") as HTMLInputElement
    await act(async () => {
      fireEvent.change(note, { target: { value: "loud" } })
    })

    const submit = screen.getByTestId("outputs-submit") as HTMLButtonElement
    await waitFor(() => expect(submit.disabled).toBe(false))

    await act(async () => {
      fireEvent.click(submit)
    })

    expect(dispatchMock).toHaveBeenCalledOnce()
    const [args] = dispatchMock.mock.calls[0] as [{ workitem_id: string; outputs: Record<string, unknown> }]
    expect(args.workitem_id).toBe("wi-2")
    expect(args.outputs.severity).toBe("medium")
    expect(args.outputs.acknowledged).toBe(true)
    expect(args.outputs.count).toBe(3)
    expect(args.outputs.note).toBe("loud")
  })

  it("dispatches raw Elixir source for fallback :elixir vars", async () => {
    dispatchMock.mockResolvedValueOnce({ code: "ok" })

    loadSnapshot(makeRow("wi-3", "weird", schemaElixir))
    renderWithProviders(<InboxPage />)
    await openDrawer("wi-3")

    const textarea = screen.getByTestId("outputs-field-payload-elixir") as HTMLTextAreaElement
    await act(async () => {
      fireEvent.change(textarea, { target: { value: '{:read, "lib/"}' } })
    })

    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    expect(dispatchMock).toHaveBeenCalledWith({
      workitem_id: "wi-3",
      outputs: { payload: '{:read, "lib/"}' }
    })
  })

  it("keeps submit disabled while :elixir fallback text is empty", async () => {
    loadSnapshot(makeRow("wi-3", "weird", schemaElixir))
    renderWithProviders(<InboxPage />)
    await openDrawer("wi-3")

    // Initial value is empty string → required.
    const submit = screen.getByTestId("outputs-submit") as HTMLButtonElement
    expect(submit.disabled).toBe(true)

    const textarea = screen.getByTestId("outputs-field-payload-elixir") as HTMLTextAreaElement
    await act(async () => {
      fireEvent.change(textarea, { target: { value: ":approve" } })
    })

    expect(submit.disabled).toBe(false)
  })
})

describe("InboxPage outputs drawer — reply handling (M2b regressions)", () => {
  beforeEach(() => {
    dispatchMock.mockReset()
  })

  function withFilledBinary() {
    loadSnapshot(makeRow("wi-1", "approve", schemaBinary))
    renderWithProviders(<InboxPage />)
  }

  it("collapses :already_completed into close+toast", async () => {
    dispatchMock.mockRejectedValueOnce(
      new MusubiCommandError({
        kind: "failed",
        command: "complete_workitem",
        storeId: ["ColouredFlowDashboardWeb.Stores.InboxStore", "default"],
        reply: { code: "already_completed", workitem_id: "wi-1" }
      })
    )

    withFilledBinary()
    await openDrawer("wi-1")
    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    await waitFor(() => {
      expect(screen.queryByTestId("outputs-form")).toBeNull()
    })
    await waitFor(() => {
      expect(screen.getByText(/already handled/i)).toBeDefined()
    })
  })

  it("collapses :unknown_workitem into the same race outcome", async () => {
    dispatchMock.mockRejectedValueOnce(
      new MusubiCommandError({
        kind: "failed",
        command: "complete_workitem",
        storeId: ["ColouredFlowDashboardWeb.Stores.InboxStore", "default"],
        reply: { code: "unknown_workitem", workitem_id: "wi-1" }
      })
    )

    withFilledBinary()
    await openDrawer("wi-1")
    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    await waitFor(() => {
      expect(screen.queryByTestId("outputs-form")).toBeNull()
    })
    await waitFor(() => {
      expect(screen.getByText(/already handled/i)).toBeDefined()
    })
  })

  it("keeps drawer open + inline Banner for :unknown_variable", async () => {
    dispatchMock.mockRejectedValueOnce(
      new MusubiCommandError({
        kind: "failed",
        command: "complete_workitem",
        storeId: ["ColouredFlowDashboardWeb.Stores.InboxStore", "default"],
        reply: { code: "unknown_variable", variable: "verdict", workitem_id: "wi-1" }
      })
    )

    withFilledBinary()
    await openDrawer("wi-1")
    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    expect(screen.getByTestId("outputs-form")).toBeDefined()
    expect(screen.getByText(/unknown variable/i)).toBeDefined()
    expect(
      screen.getByText(/does not recognise the output variable "verdict"/i)
    ).toBeDefined()
  })

  it("keeps drawer open + inline Banner for :invalid_outputs", async () => {
    dispatchMock.mockRejectedValueOnce(
      new MusubiCommandError({
        kind: "failed",
        command: "complete_workitem",
        storeId: ["ColouredFlowDashboardWeb.Stores.InboxStore", "default"],
        reply: {
          code: "invalid_outputs",
          message: "outputs must be a JSON object",
          workitem_id: "wi-1"
        }
      })
    )

    withFilledBinary()
    await openDrawer("wi-1")
    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    expect(screen.getByTestId("outputs-form")).toBeDefined()
    expect(screen.getByText(/invalid outputs/i)).toBeDefined()
  })

  it("surfaces :invalid_elixir reply inline as actionable Banner", async () => {
    dispatchMock.mockRejectedValueOnce(
      new MusubiCommandError({
        kind: "failed",
        command: "complete_workitem",
        storeId: ["ColouredFlowDashboardWeb.Stores.InboxStore", "default"],
        reply: {
          code: "invalid_elixir",
          variable: "payload",
          message:
            "Output `payload` is not a valid Elixir term literal: calls and variables are not allowed (`puts`)"
        }
      })
    )

    loadSnapshot(makeRow("wi-3", "weird", schemaElixir))
    renderWithProviders(<InboxPage />)
    await openDrawer("wi-3")

    const textarea = screen.getByTestId("outputs-field-payload-elixir") as HTMLTextAreaElement
    await act(async () => {
      fireEvent.change(textarea, { target: { value: 'IO.puts("x")' } })
    })

    await waitFor(() =>
      expect((screen.getByTestId("outputs-submit") as HTMLButtonElement).disabled).toBe(false)
    )
    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    expect(screen.getByTestId("outputs-form")).toBeDefined()
    expect(screen.getByText(/invalid elixir term/i)).toBeDefined()
    expect(screen.getByText(/calls and variables are not allowed/i)).toBeDefined()
  })

  it("surfaces new :type_mismatch reply inline (M5 actionable path)", async () => {
    dispatchMock.mockRejectedValueOnce(
      new MusubiCommandError({
        kind: "failed",
        command: "complete_workitem",
        storeId: ["ColouredFlowDashboardWeb.Stores.InboxStore", "default"],
        reply: {
          code: "type_mismatch",
          variable: "count",
          expected_kind: "integer",
          message: "Output `count` must be a integer."
        }
      })
    )

    loadSnapshot(makeRow("wi-2", "triage", schemaMix))
    renderWithProviders(<InboxPage />)
    await openDrawer("wi-2")

    // Fill every required field so submit clicks past local validation.
    await act(async () => {
      fireEvent.change(screen.getByTestId("outputs-field-severity"), {
        target: { value: "low" }
      })
    })
    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-field-acknowledged"))
    })
    await act(async () => {
      fireEvent.change(screen.getByTestId("outputs-field-count"), {
        target: { value: "1" }
      })
    })

    await waitFor(() =>
      expect((screen.getByTestId("outputs-submit") as HTMLButtonElement).disabled).toBe(false)
    )
    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    expect(screen.getByTestId("outputs-form")).toBeDefined()
    expect(screen.getByText(/Wrong type/i)).toBeDefined()
    expect(screen.getByText(/Output `count` must be a integer/i)).toBeDefined()
  })

  it("surfaces :runner_error via toast and keeps drawer open", async () => {
    dispatchMock.mockRejectedValueOnce(
      new MusubiCommandError({
        kind: "failed",
        command: "complete_workitem",
        storeId: ["ColouredFlowDashboardWeb.Stores.InboxStore", "default"],
        reply: { code: "runner_error", message: "Action raised RuntimeError" }
      })
    )

    withFilledBinary()
    await openDrawer("wi-1")
    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    expect(screen.getByTestId("outputs-form")).toBeDefined()
    await waitFor(() => {
      expect(screen.getByText(/runner rejected the completion/i)).toBeDefined()
    })
  })

  it("falls back to a generic toast for non-MusubiCommandError exceptions", async () => {
    dispatchMock.mockRejectedValueOnce(new Error("socket closed"))

    withFilledBinary()
    await openDrawer("wi-1")
    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    expect(screen.getByTestId("outputs-form")).toBeDefined()
    await waitFor(() => {
      expect(screen.getByText(/submission failed/i)).toBeDefined()
      expect(screen.getByText(/socket closed/i)).toBeDefined()
    })
  })
})

describe("InboxPage row — enactment_state affordances (P19 M6)", () => {
  beforeEach(() => {
    dispatchMock.mockReset()
  })

  function makeRowWithEnactmentState(
    id: string,
    enactment_state: WorkitemRow["enactment_state"]
  ): WorkitemRow {
    const base = makeRow(id, "approve", schemaBinary)
    return { ...base, enactment_state }
  }

  it("renders Exception chip + Open detail link (not the outputs Action) when enactment_state = 'exception'", () => {
    loadSnapshot(makeRowWithEnactmentState("wi-exc", "exception"))
    renderWithRouter(<InboxPage />)

    const chip = screen.getByTestId("inbox-enactment-chip-exception")
    expect(chip).toBeDefined()
    expect(chip.textContent).toMatch(/Exception/i)

    const link = screen.getByTestId("inbox-open-detail-wi-exc") as HTMLAnchorElement
    expect(link.tagName).toBe("A")
    expect(link.getAttribute("href")).toBe("/enactments/enactment-aaaa-bbbb-cccc")

    // The drawer-opening Action button must NOT be present for non-running rows.
    expect(
      screen.queryByRole("button", { name: /open outputs drawer for workitem wi-exc/i })
    ).toBeNull()
  })

  it("renders Terminated chip + Open detail link (not the outputs Action) when enactment_state = 'terminated'", () => {
    loadSnapshot(makeRowWithEnactmentState("wi-term", "terminated"))
    renderWithRouter(<InboxPage />)

    const chip = screen.getByTestId("inbox-enactment-chip-terminated")
    expect(chip).toBeDefined()
    expect(chip.textContent).toMatch(/Terminated/i)

    const link = screen.getByTestId("inbox-open-detail-wi-term") as HTMLAnchorElement
    expect(link.tagName).toBe("A")
    expect(link.getAttribute("href")).toBe("/enactments/enactment-aaaa-bbbb-cccc")

    expect(
      screen.queryByRole("button", { name: /open outputs drawer for workitem wi-term/i })
    ).toBeNull()
  })
})

describe("InboxPage controls — search/filter/pagination", () => {
  beforeEach(() => {
    dispatchMock.mockReset()
    snapshotMock.mockReset()
  })

  function loadMany(rows: WorkitemRow[]) {
    snapshotMock.mockReturnValue({
      workitems: rows,
      counts: {
        enabled: rows.filter((r) => r.state === "enabled").length,
        started: rows.filter((r) => r.state === "started").length,
        by_enactment: rows.reduce<Record<string, number>>((acc, r) => {
          acc[r.enactment_id] = (acc[r.enactment_id] ?? 0) + 1
          return acc
        }, {})
      }
    })
  }

  function buildN(n: number, transitions: readonly string[] = ["approve"]): WorkitemRow[] {
    return Array.from({ length: n }, (_, i) =>
      makeRow(`wi-${i}`, transitions[i % transitions.length]!, schemaBinary)
    )
  }

  function renderAt(initialEntries: string[] = ["/"]) {
    return render(
      <MemoryRouter initialEntries={initialEntries}>
        <Toasty>
          <InboxPage />
        </Toasty>
      </MemoryRouter>
    )
  }

  it("filters rows by free-text search against transition", async () => {
    const rows = [
      makeRow("wi-a", "approve", schemaBinary),
      makeRow("wi-b", "notify", schemaBinary),
      makeRow("wi-c", "submit", schemaBinary)
    ]
    loadMany(rows)
    renderAt()

    expect(screen.getByTestId("inbox-row-wi-a")).toBeDefined()
    expect(screen.getByTestId("inbox-row-wi-b")).toBeDefined()
    expect(screen.getByTestId("inbox-row-wi-c")).toBeDefined()

    const search = screen.getByTestId("list-controls-search") as HTMLInputElement
    await act(async () => {
      fireEvent.change(search, { target: { value: "notify" } })
    })

    expect(screen.queryByTestId("inbox-row-wi-a")).toBeNull()
    expect(screen.getByTestId("inbox-row-wi-b")).toBeDefined()
    expect(screen.queryByTestId("inbox-row-wi-c")).toBeNull()
  })

  it("narrows by state filter chip", async () => {
    const rows: WorkitemRow[] = [
      { ...makeRow("wi-en", "approve", schemaBinary), state: "enabled" },
      { ...makeRow("wi-st", "approve", schemaBinary), state: "started" }
    ]
    loadMany(rows)
    renderAt()

    expect(screen.getByTestId("inbox-row-wi-en")).toBeDefined()
    expect(screen.getByTestId("inbox-row-wi-st")).toBeDefined()

    await act(async () => {
      fireEvent.click(screen.getByTestId("inbox-state-filter-started"))
    })

    expect(screen.queryByTestId("inbox-row-wi-en")).toBeNull()
    expect(screen.getByTestId("inbox-row-wi-st")).toBeDefined()
  })

  it("paginates with the page-size selector and exposes total count", async () => {
    loadMany(buildN(30))
    renderAt()

    // Default page size 25 → 25 rows visible + pagination info reflects total.
    expect(screen.queryByTestId("inbox-row-wi-24")).toBeDefined()
    expect(screen.queryByTestId("inbox-row-wi-25")).toBeNull()
    expect(screen.getByTestId("list-pagination-info").textContent).toMatch(
      /Showing 1–25 of 30/
    )

    const pageSize = screen.getByTestId("list-controls-page-size") as HTMLSelectElement
    await act(async () => {
      fireEvent.change(pageSize, { target: { value: "10" } })
    })

    expect(screen.queryByTestId("inbox-row-wi-9")).toBeDefined()
    expect(screen.queryByTestId("inbox-row-wi-10")).toBeNull()
    expect(screen.getByTestId("list-pagination-info").textContent).toMatch(
      /Showing 1–10 of 30/
    )
  })

  it("hydrates from URL search params (q + pageSize + page)", () => {
    // Mix transitions so search narrows by transition substring, the only
    // text the rows expose to the matcher.
    loadMany(buildN(30, ["approve", "notify", "submit"]))
    renderAt(["/?q=notify&pageSize=10&page=2"])

    expect((screen.getByTestId("list-controls-search") as HTMLInputElement).value).toBe(
      "notify"
    )
    expect((screen.getByTestId("list-controls-page-size") as HTMLSelectElement).value).toBe(
      "10"
    )
    // pageSize=10, only ~10 notify rows; page 2 shows nothing → pagination
    // clamps back to page 1 and renders the rows.
    expect(screen.getAllByTestId(/inbox-row-wi-/).length).toBeGreaterThan(0)
  })

  it("shows the Empty + Clear filters affordance when filters strand every row", async () => {
    loadMany([makeRow("wi-1", "approve", schemaBinary)])
    renderAt()

    const search = screen.getByTestId("list-controls-search") as HTMLInputElement
    await act(async () => {
      fireEvent.change(search, { target: { value: "zzzzz-no-match" } })
    })

    expect(screen.getByTestId("inbox-filters-empty")).toBeDefined()
    const clear = screen.getByRole("button", { name: /clear filters/i })
    await act(async () => {
      fireEvent.click(clear)
    })

    expect(screen.getByTestId("inbox-row-wi-1")).toBeDefined()
  })
})
