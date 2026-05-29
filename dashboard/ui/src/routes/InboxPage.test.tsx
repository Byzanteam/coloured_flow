import { act, fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi, beforeEach } from "vitest"
import type { ReactNode } from "react"

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

vi.mock("@musubi/react", () => ({
  MusubiCommandError: {
    is: () => false
  }
}))

import InboxPage from "./InboxPage"

function renderWithSuspense(children: ReactNode) {
  return render(<>{children}</>)
}

describe("InboxPage outputs drawer", () => {
  beforeEach(() => {
    dispatchMock.mockReset()
  })

  it("renders the action button per row", () => {
    renderWithSuspense(<InboxPage />)
    expect(
      screen.getByRole("button", { name: /open outputs drawer for workitem wi-1/i })
    ).toBeDefined()
  })

  it("opens the drawer with row data when Action is clicked", async () => {
    renderWithSuspense(<InboxPage />)

    await act(async () => {
      fireEvent.click(
        screen.getByRole("button", { name: /open outputs drawer for workitem wi-1/i })
      )
    })

    expect(screen.getByText(/Complete workitem · approve/i)).toBeDefined()
    expect(screen.getByText("note")).toBeDefined()
    expect(screen.getByText("verdict")).toBeDefined()
  })

  it("dispatches :complete_workitem with parsed JSON on submit", async () => {
    dispatchMock.mockResolvedValueOnce({ code: "ok" })

    renderWithSuspense(<InboxPage />)
    await act(async () => {
      fireEvent.click(
        screen.getByRole("button", { name: /open outputs drawer for workitem wi-1/i })
      )
    })

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

  it("renders the server banner on a non-:ok reply", async () => {
    dispatchMock.mockResolvedValueOnce({ code: "already_completed", workitem_id: "wi-1" })

    renderWithSuspense(<InboxPage />)
    await act(async () => {
      fireEvent.click(
        screen.getByRole("button", { name: /open outputs drawer for workitem wi-1/i })
      )
    })

    await act(async () => {
      fireEvent.click(screen.getByTestId("outputs-submit"))
    })

    expect(screen.getAllByText(/Already handled/i).length).toBeGreaterThan(0)
  })
})
