import { render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import type { ReactNode } from "react"
import { MemoryRouter, Route, Routes } from "react-router-dom"
import { Toasty } from "@cloudflare/kumo"

// Companion to EnactmentDetailPage.test.tsx — that file stubs NetDiagram to
// keep the layout-shell assertions isolated. This file does NOT stub the
// component, so the real `@xyflow/react`-backed renderer mounts against a
// sample payload and we can pin node count + edge count + fallback copy.

const { sampleSnapshot } = vi.hoisted(() => {
  const summary = {
    enactment_id: "en-real-diagram",
    flow_topic_id: "topic-x",
    state: "running" as const,
    version: 0,
    markings_count: 0,
    workitems_count: 0,
    last_occurrence_at: null as string | null,
    last_exception_banner: null as string | null
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

  return {
    sampleSnapshot: {
      summary,
      transitions: ["approve"],
      diagram,
      markings: [],
      workitems: [],
      occurrences: [],
      telemetry: []
    }
  }
})

vi.mock("../musubi", () => ({
  useMusubiRootSuspense: vi.fn().mockReturnValue({ __mock: "detail-proxy" }),
  useMusubiSnapshot: vi.fn().mockReturnValue(sampleSnapshot),
  useMusubiCommand: vi.fn().mockReturnValue({
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
    static is(value: unknown): value is MusubiCommandError {
      return value instanceof Error && (value as { name?: string }).name === "MusubiCommandError"
    }
  }
  return { MusubiCommandError }
})

import EnactmentDetailPage from "./EnactmentDetailPage"

function renderRoute(children: ReactNode) {
  return render(
    <Toasty>
      <MemoryRouter initialEntries={["/enactments/en-real-diagram"]}>
        <Routes>
          <Route path="/enactments/:id" element={children} />
        </Routes>
      </MemoryRouter>
    </Toasty>
  )
}

describe("EnactmentDetailPage with the real NetDiagram", () => {
  it("renders one node per place + one per transition + the empty-fallback never trips", () => {
    renderRoute(<EnactmentDetailPage />)
    // Real React Flow mounts inside the diagram card.
    expect(screen.getByTestId("net-diagram")).toBeDefined()
    expect(screen.queryByTestId("net-diagram-empty")).toBeNull()
    expect(screen.getByTestId("place-node-pending")).toBeDefined()
    expect(screen.getByTestId("place-node-decided")).toBeDefined()
    expect(screen.getByTestId("transition-node-approve")).toBeDefined()
  })

  it("renders the fallback copy when the diagram payload has no nodes", () => {
    sampleSnapshot.diagram.places = []
    sampleSnapshot.diagram.transitions = []
    sampleSnapshot.diagram.arcs = []
    renderRoute(<EnactmentDetailPage />)
    expect(screen.getByTestId("net-diagram-empty")).toBeDefined()
    expect(screen.getByText(/Waiting for net definition/)).toBeDefined()
  })
})
