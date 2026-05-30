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
// `useMusubiRoot`, `useMusubiCommand`). We stub those so the test renders
// synchronously without a real socket.

type OutputVar = ColouredFlowDashboardWeb.Views.OutputVar
type WorkitemRow = ColouredFlowDashboardWeb.Views.WorkitemRow

const { dispatchMock, snapshotMock, makeRow, schemaMix, schemaBinary, schemaJson } = vi.hoisted(
  () => {
    type SchemaInput = { name: string; colour_set: string; kind: OutputVar["kind"]; enum_values?: string[] | null; hint?: string | null }
    const v = (s: SchemaInput): OutputVar => ({
      name: s.name,
      colour_set: s.colour_set,
      kind: s.kind,
      enum_values: s.enum_values ?? null,
      hint: s.hint ?? null
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

    const json: OutputVar[] = [
      v({
        name: "payload",
        colour_set: "complex_t",
        kind: "json",
        hint: "Complex shape; provide JSON."
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
      schemaJson: json
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
  useMusubiRoot: vi.fn().mockReturnValue({
    status: "ready",
    store: { __mock: "inbox-proxy" },
    error: null
  }),
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

  it("falls back to a JSON Textarea for unknown shapes", async () => {
    loadSnapshot(makeRow("wi-3", "weird", schemaJson))
    renderWithProviders(<InboxPage />)
    await openDrawer("wi-3")

    expect(screen.getByTestId("outputs-field-payload-json")).toBeDefined()
    expect(screen.getByText(/Complex shape; provide JSON/i)).toBeDefined()
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

  it("dispatches parsed JSON for fallback :json vars", async () => {
    dispatchMock.mockResolvedValueOnce({ code: "ok" })

    loadSnapshot(makeRow("wi-3", "weird", schemaJson))
    renderWithProviders(<InboxPage />)
    await openDrawer("wi-3")

    const textarea = screen.getByTestId("outputs-field-payload-json") as HTMLTextAreaElement
    await act(async () => {
      fireEvent.change(textarea, { target: { value: '{"k":1}' } })
    })

    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    expect(dispatchMock).toHaveBeenCalledWith({
      workitem_id: "wi-3",
      outputs: { payload: { k: 1 } }
    })
  })

  it("keeps submit disabled while JSON fallback text is invalid", async () => {
    loadSnapshot(makeRow("wi-3", "weird", schemaJson))
    renderWithProviders(<InboxPage />)
    await openDrawer("wi-3")

    const textarea = screen.getByTestId("outputs-field-payload-json") as HTMLTextAreaElement
    const submit = screen.getByTestId("outputs-submit") as HTMLButtonElement
    expect(submit.disabled).toBe(false)

    await act(async () => {
      fireEvent.change(textarea, { target: { value: "{not json" } })
    })

    expect(submit.disabled).toBe(true)
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

    expect(screen.getByTestId("inbox-enactment-chip-exception")).toBeDefined()
    expect(screen.getByText(/Exception/i)).toBeDefined()

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

    expect(screen.getByTestId("inbox-enactment-chip-terminated")).toBeDefined()
    expect(screen.getByText(/Terminated/i)).toBeDefined()

    const link = screen.getByTestId("inbox-open-detail-wi-term") as HTMLAnchorElement
    expect(link.tagName).toBe("A")
    expect(link.getAttribute("href")).toBe("/enactments/enactment-aaaa-bbbb-cccc")

    expect(
      screen.queryByRole("button", { name: /open outputs drawer for workitem wi-term/i })
    ).toBeNull()
  })
})
