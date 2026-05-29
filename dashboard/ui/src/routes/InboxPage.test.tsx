import { act, fireEvent, render, screen, waitFor } from "@testing-library/react"
import { describe, expect, it, vi, beforeEach } from "vitest"
import type { ReactNode } from "react"
import { Toasty } from "@cloudflare/kumo"

// ---------------------------------------------------------------------------
// musubi mocks
// ---------------------------------------------------------------------------
//
// The Inbox page consumes the musubi react surface (`useMusubiSnapshot`,
// `useMusubiRootSuspense`, `useMusubiCommand`). We stub those so the test
// renders synchronously without a real socket.

const { dispatchMock, sampleRow, sampleCounts } = vi.hoisted(() => {
  const row = {
    id: "wi-1",
    enactment_id: "enactment-aaaa-bbbb-cccc",
    flow_topic_id: "topic-x",
    transition: "approve",
    state: "enabled" as const,
    binding_summary: "verdict = nil, note = nil",
    output_vars: ["note", "verdict"],
    enabled_at: "2026-05-29T00:00:00Z",
    updated_at: "2026-05-29T00:00:00Z"
  }

  return {
    dispatchMock: vi.fn(),
    sampleRow: row,
    sampleCounts: { enabled: 1, started: 0, by_enactment: { [row.enactment_id]: 1 } }
  }
})

vi.mock("../musubi", () => ({
  useMusubiRootSuspense: vi.fn().mockReturnValue({ __mock: "inbox-proxy" }),
  useMusubiSnapshot: vi.fn().mockReturnValue({
    workitems: [sampleRow],
    counts: sampleCounts
  }),
  useMusubiCommand: () => ({
    dispatch: dispatchMock,
    isPending: false,
    error: null,
    data: null,
    reset: vi.fn()
  })
}))

// Mirror the real `MusubiCommandError` shape from
// `dashboard/deps/musubi/packages/client/src/error.ts` closely enough that
// `MusubiCommandError.is(cause)` succeeds AND `cause.reply` / `cause.code`
// are reachable from the catch branch. We can't instantiate the real class
// here because its constructor wants a Musubi `Connection`-scoped envelope
// shape we don't have in the test harness; a small subclass-style stub is
// sufficient since the call site only depends on `instanceof Error` +
// `name === "MusubiCommandError"`.
// Mirror the real `MusubiCommandError` shape from
// `dashboard/deps/musubi/packages/client/src/error.ts` closely enough that
// `MusubiCommandError.is(cause)` succeeds AND `cause.reply` / `cause.code`
// are reachable from the catch branch. We can't instantiate the real class
// from production code paths in tests cleanly (its constructor expects a
// Musubi `Connection`-scoped envelope shape that the test harness doesn't
// build), so we provide a minimal subclass-style stub that honours the same
// constructor signature + static `is`. `code` is derived from the reply, as
// the real class does.
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
  return render(<Toasty>{children}</Toasty>)
}

async function openDrawer() {
  await act(async () => {
    fireEvent.click(
      screen.getByRole("button", { name: /open outputs drawer for workitem wi-1/i })
    )
  })
}

describe("InboxPage outputs drawer", () => {
  beforeEach(() => {
    dispatchMock.mockReset()
  })

  it("renders the action button per row", () => {
    renderWithProviders(<InboxPage />)
    expect(
      screen.getByRole("button", { name: /open outputs drawer for workitem wi-1/i })
    ).toBeDefined()
  })

  it("opens the drawer with row data when Action is clicked", async () => {
    renderWithProviders(<InboxPage />)
    await openDrawer()

    expect(screen.getByText(/Complete workitem · approve/i)).toBeDefined()
    expect(screen.getByText("note")).toBeDefined()
    expect(screen.getByText("verdict")).toBeDefined()
  })

  it("dispatches :complete_workitem with parsed JSON on submit", async () => {
    dispatchMock.mockResolvedValueOnce({ code: "ok" })

    renderWithProviders(<InboxPage />)
    await openDrawer()

    const textarea = screen.getByTestId("outputs-textarea") as HTMLTextAreaElement
    await act(async () => {
      fireEvent.change(textarea, {
        target: { value: '{"verdict": "approve", "note": "ok"}' }
      })
    })

    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    expect(dispatchMock).toHaveBeenCalledOnce()
    expect(dispatchMock).toHaveBeenCalledWith({
      workitem_id: "wi-1",
      outputs: { verdict: "approve", note: "ok" }
    })
  })

  it("collapses :already_completed into a close+toast race outcome", async () => {
    dispatchMock.mockRejectedValueOnce(
      new MusubiCommandError({
        kind: "failed",
        command: "complete_workitem",
        storeId: ["ColouredFlowDashboardWeb.Stores.InboxStore", "default"],
        reply: { code: "already_completed", workitem_id: "wi-1" }
      })
    )

    renderWithProviders(<InboxPage />)
    await openDrawer()
    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    // Drawer closed (textarea unmounted).
    await waitFor(() => {
      expect(screen.queryByTestId("outputs-textarea")).toBeNull()
    })

    // Toast surfaces in the portal.
    await waitFor(() => {
      expect(screen.getByText(/already handled/i)).toBeDefined()
      expect(
        screen.getByText(/another operator handled this workitem/i)
      ).toBeDefined()
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

    renderWithProviders(<InboxPage />)
    await openDrawer()
    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    await waitFor(() => {
      expect(screen.queryByTestId("outputs-textarea")).toBeNull()
    })
    await waitFor(() => {
      expect(screen.getByText(/already handled/i)).toBeDefined()
    })
  })

  it("keeps drawer open + shows inline Banner for :unknown_variable", async () => {
    dispatchMock.mockRejectedValueOnce(
      new MusubiCommandError({
        kind: "failed",
        command: "complete_workitem",
        storeId: ["ColouredFlowDashboardWeb.Stores.InboxStore", "default"],
        // The ad-hoc `variable` field MUST flow through `cause.reply` so the
        // Banner can name the offending key.
        reply: { code: "unknown_variable", variable: "verdict", workitem_id: "wi-1" }
      })
    )

    renderWithProviders(<InboxPage />)
    await openDrawer()
    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    // Drawer stays mounted so the operator can edit.
    expect(screen.getByTestId("outputs-textarea")).toBeDefined()
    expect(screen.getByText(/unknown variable/i)).toBeDefined()
    expect(
      screen.getByText(/does not recognise the output variable "verdict"/i)
    ).toBeDefined()
  })

  it("keeps drawer open + shows inline Banner for :invalid_outputs", async () => {
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

    renderWithProviders(<InboxPage />)
    await openDrawer()
    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    expect(screen.getByTestId("outputs-textarea")).toBeDefined()
    expect(screen.getByText(/invalid outputs/i)).toBeDefined()
  })

  it("surfaces :runner_error as a toast and keeps drawer open for context", async () => {
    dispatchMock.mockRejectedValueOnce(
      new MusubiCommandError({
        kind: "failed",
        command: "complete_workitem",
        storeId: ["ColouredFlowDashboardWeb.Stores.InboxStore", "default"],
        reply: { code: "runner_error", message: "Action raised RuntimeError" }
      })
    )

    renderWithProviders(<InboxPage />)
    await openDrawer()
    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    expect(screen.getByTestId("outputs-textarea")).toBeDefined()
    await waitFor(() => {
      expect(screen.getByText(/runner rejected the completion/i)).toBeDefined()
      expect(screen.getByText(/Action raised RuntimeError/i)).toBeDefined()
    })
  })

  it("falls back to a generic toast for non-MusubiCommandError exceptions", async () => {
    // Network failure, runtime crash, etc. — no structured envelope.
    dispatchMock.mockRejectedValueOnce(new Error("socket closed"))

    renderWithProviders(<InboxPage />)
    await openDrawer()
    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    expect(screen.getByTestId("outputs-textarea")).toBeDefined()
    await waitFor(() => {
      expect(screen.getByText(/submission failed/i)).toBeDefined()
      expect(screen.getByText(/socket closed/i)).toBeDefined()
    })
  })

  it("disables Submit immediately when JSON becomes invalid, no blur required", async () => {
    renderWithProviders(<InboxPage />)
    await openDrawer()

    const textarea = screen.getByTestId("outputs-textarea") as HTMLTextAreaElement
    const submit = screen.getByTestId("outputs-submit") as HTMLButtonElement

    // Sanity: template is valid JSON, button enabled.
    expect(submit.disabled).toBe(false)

    await act(async () => {
      fireEvent.change(textarea, { target: { value: "{not json" } })
    })

    // Derived via useMemo — disabled on the same render as the change.
    expect(submit.disabled).toBe(true)
  })
})
