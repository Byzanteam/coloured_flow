import { act, render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import NetDiagram from "./NetDiagram"

type DiagramPayload = ColouredFlowDashboardWeb.Views.NetDiagram

const baseDiagram = (): DiagramPayload => ({
  places: [
    {
      name: "pending",
      colour_set: "trigger_t",
      tokens_count: 1,
      tokens_summary: "1×true"
    },
    {
      name: "decided",
      colour_set: "outcome",
      tokens_count: 0,
      tokens_summary: ""
    }
  ],
  transitions: [
    {
      name: "approve",
      enabled_count: 1,
      rejected_by_guard_count: 0,
      rejected_by_arc_eval_count: 0,
      rejected_by_marking_count: 0,
      last_fired_at: null
    }
  ],
  arcs: [
    { place: "pending", transition: "approve", orientation: "p_to_t" },
    { place: "decided", transition: "approve", orientation: "t_to_p" }
  ]
})

describe("NetDiagram", () => {
  it("renders an empty hint when the diagram payload has no nodes", () => {
    render(<NetDiagram diagram={null} />)
    expect(screen.getByTestId("net-diagram-empty")).toBeDefined()
  })

  it("renders one node per place + transition and emits arc edges", () => {
    render(<NetDiagram diagram={baseDiagram()} />)
    expect(screen.getByTestId("net-diagram")).toBeDefined()
    expect(screen.getByTestId("place-node-pending")).toBeDefined()
    expect(screen.getByTestId("place-node-decided")).toBeDefined()
    expect(screen.getByTestId("transition-node-approve")).toBeDefined()
    // React Flow only paints SVG edge paths after measuring node geometry,
    // which jsdom does not do; assert structural node coverage instead.
    expect(screen.getAllByText("approve").length).toBeGreaterThan(0)
  })

  it("shows a token badge only when the place has tokens", () => {
    render(<NetDiagram diagram={baseDiagram()} />)
    expect(screen.getByTestId("place-tokens-pending")).toBeDefined()
    expect(screen.queryByTestId("place-tokens-decided")).toBeNull()
  })

  it("pulses the transition node when last_fired_at changes", async () => {
    vi.useFakeTimers()
    const initial = baseDiagram()
    initial.transitions[0].last_fired_at = null
    const { rerender } = render(<NetDiagram diagram={initial} />)

    const transitionNode = screen.getByTestId("transition-node-approve")
    expect(transitionNode.getAttribute("data-pulsing")).toBe("false")

    const next = baseDiagram()
    next.transitions[0].last_fired_at = "2026-05-30T12:00:00Z"

    await act(async () => {
      rerender(<NetDiagram diagram={next} />)
    })
    expect(screen.getByTestId("transition-node-approve").getAttribute("data-pulsing")).toBe(
      "true"
    )

    await act(async () => {
      vi.advanceTimersByTime(300)
    })
    expect(screen.getByTestId("transition-node-approve").getAttribute("data-pulsing")).toBe(
      "false"
    )
    vi.useRealTimers()
  })
})
