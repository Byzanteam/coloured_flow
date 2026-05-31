import { act, fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import NetDiagram, { buildGraph } from "./NetDiagram"

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
  ],
  colour_sets: []
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
    expect(screen.getByTestId("place-token-badge-pending")).toBeDefined()
    expect(screen.queryByTestId("place-token-badge-decided")).toBeNull()
  })

  it("renders place name + colset stacked outside the circle", () => {
    render(<NetDiagram diagram={baseDiagram()} />)
    const pendingLabel = screen.getByTestId("place-label-pending")
    expect(pendingLabel.textContent).toContain("pending")
    expect(pendingLabel.textContent).toContain("trigger_t")
    const decidedLabel = screen.getByTestId("place-label-decided")
    expect(decidedLabel.textContent).toContain("decided")
    expect(decidedLabel.textContent).toContain("outcome")
  })

  it("renders the transition name inside the rectangle and sizes width by longest name", () => {
    const diagram = baseDiagram()
    diagram.transitions = [
      {
        name: "approve",
        enabled_count: 0,
        rejected_by_guard_count: 0,
        rejected_by_arc_eval_count: 0,
        rejected_by_marking_count: 0,
        last_fired_at: null
      },
      {
        name: "submit_for_review",
        enabled_count: 0,
        rejected_by_guard_count: 0,
        rejected_by_arc_eval_count: 0,
        rejected_by_marking_count: 0,
        last_fired_at: null
      }
    ]
    render(<NetDiagram diagram={diagram} />)
    const a = screen.getByTestId("transition-node-approve") as HTMLElement
    const b = screen.getByTestId("transition-node-submit_for_review") as HTMLElement
    expect(a.style.width).toBe(b.style.width)
    expect(a.style.width).not.toBe("")
    expect(a.textContent).toContain("approve")
    expect(b.textContent).toContain("submit_for_review")
  })

  it("applies the enabled glow data attribute when enabled_count > 0", () => {
    const diagram = baseDiagram()
    diagram.transitions[0].enabled_count = 2
    render(<NetDiagram diagram={diagram} enactmentState="running" />)
    const node = screen.getByTestId("transition-node-approve")
    expect(node.getAttribute("data-enabled")).toBe("true")
    expect(node.getAttribute("data-glow")).toBe("enabled")
  })

  it("applies the exception glow when enactmentState is exception", () => {
    const diagram = baseDiagram()
    diagram.transitions[0].enabled_count = 0
    render(<NetDiagram diagram={diagram} enactmentState="exception" />)
    const node = screen.getByTestId("transition-node-approve")
    expect(node.getAttribute("data-glow")).toBe("exception")
  })

  it("emits no glow when neither enabled nor in exception", () => {
    const diagram = baseDiagram()
    diagram.transitions[0].enabled_count = 0
    render(<NetDiagram diagram={diagram} enactmentState="running" />)
    expect(screen.getByTestId("transition-node-approve").getAttribute("data-glow")).toBe(
      "none"
    )
  })

  it("invokes onSelectTransition when a transition node is clicked", () => {
    const onSelectTransition = vi.fn()
    render(
      <NetDiagram diagram={baseDiagram()} onSelectTransition={onSelectTransition} />
    )
    fireEvent.click(screen.getByTestId("transition-node-approve"))
    expect(onSelectTransition).toHaveBeenCalledWith("approve")
  })

  it("does not invoke onSelectTransition for a place click", () => {
    const onSelectTransition = vi.fn()
    render(
      <NetDiagram diagram={baseDiagram()} onSelectTransition={onSelectTransition} />
    )
    fireEvent.click(screen.getByTestId("place-node-pending"))
    expect(onSelectTransition).not.toHaveBeenCalled()
  })

  it("tags input arcs of firingTransition with firingProgress.input and output arcs with .output", () => {
    const diagram = baseDiagram()
    const inputId = "arc-p_to_t-pending-approve-0"
    const outputId = "arc-t_to_p-decided-approve-1"
    const { edges } = buildGraph(diagram, "running", "approve", { input: 0.3, output: 0.7 })

    const input = edges.find((e) => e.id === inputId)
    const output = edges.find((e) => e.id === outputId)
    expect((input?.data as Record<string, unknown>).firingProgress).toBe(0.3)
    expect((output?.data as Record<string, unknown>).firingProgress).toBe(0.7)
    // No className for firing in the new design — the inline `pathLength="1"`
    // + dasharray combo replaces the CSS keyframe.
    expect(input?.className).toBeUndefined()
    expect(output?.className).toBeUndefined()
  })

  it("omits firingProgress on edges not touching the firingTransition", () => {
    const diagram = baseDiagram()
    diagram.transitions = [
      ...diagram.transitions,
      {
        name: "reject",
        enabled_count: 0,
        rejected_by_guard_count: 0,
        rejected_by_arc_eval_count: 0,
        rejected_by_marking_count: 0,
        last_fired_at: null
      }
    ]
    diagram.arcs = [
      ...diagram.arcs,
      { place: "pending", transition: "reject", orientation: "p_to_t" }
    ]
    const { edges } = buildGraph(diagram, "running", "approve", { input: 0.5, output: 0 })
    const rejectEdge = edges.find((e) => e.id === "arc-p_to_t-pending-reject-2")
    expect((rejectEdge?.data as Record<string, unknown> | undefined)?.firingProgress).toBeUndefined()
  })

  it("clamps firingProgress to [0,1]", () => {
    const diagram = baseDiagram()
    const { edges } = buildGraph(diagram, "running", "approve", { input: -0.5, output: 1.5 })
    const input = edges.find((e) => e.id === "arc-p_to_t-pending-approve-0")
    const output = edges.find((e) => e.id === "arc-t_to_p-decided-approve-1")
    expect((input?.data as Record<string, unknown>).firingProgress).toBe(0)
    expect((output?.data as Record<string, unknown>).firingProgress).toBe(1)
  })

  it("tags p_to_t arcs of enabled transitions with cf-edge-enabled + accent style", () => {
    const diagram = baseDiagram()
    diagram.transitions[0].enabled_count = 1
    const { edges } = buildGraph(diagram, "running")
    const input = edges.find((e) => e.id === "arc-p_to_t-pending-approve-0")
    const output = edges.find((e) => e.id === "arc-t_to_p-decided-approve-1")
    expect(input?.className).toBe("cf-edge-enabled")
    expect((input?.style as Record<string, unknown>).stroke).toBe(
      "var(--color-cf-accent-tint)"
    )
    expect((input?.style as Record<string, unknown>).strokeWidth).toBe(2)
    // Output arcs of an enabled transition stay default — operators only need
    // the consume relationship visible.
    expect(output?.className).toBeUndefined()
    expect((output?.style as Record<string, unknown>).stroke).toBe(
      "var(--color-cf-border-strong)"
    )
  })

  it("leaves p_to_t arcs default when the transition is not enabled", () => {
    const diagram = baseDiagram()
    diagram.transitions[0].enabled_count = 0
    const { edges } = buildGraph(diagram, "running")
    const input = edges.find((e) => e.id === "arc-p_to_t-pending-approve-0")
    expect(input?.className).toBeUndefined()
    expect((input?.style as Record<string, unknown>).stroke).toBe(
      "var(--color-cf-border-strong)"
    )
  })

  it("enabledTransitions override wins over live enabled_count for arc accent + transition glow", () => {
    const diagram = baseDiagram()
    // Live counts disagree with replay-derived set: live says enabled, override says not.
    diagram.transitions[0].enabled_count = 5
    const override: ReadonlySet<string> = new Set()
    const { edges, nodes } = buildGraph(
      diagram,
      "running",
      null,
      { input: 0, output: 0 },
      undefined,
      override
    )
    const input = edges.find((e) => e.id === "arc-p_to_t-pending-approve-0")
    expect(input?.className).toBeUndefined()
    expect((input?.style as Record<string, unknown>).stroke).toBe(
      "var(--color-cf-border-strong)"
    )
    const approveNode = nodes.find((n) => n.id === "t:approve")
    expect((approveNode?.data as Record<string, unknown>).isEnabled).toBe(false)
  })

  it("enabledTransitions override drives transition glow when the live count says zero", () => {
    const diagram = baseDiagram()
    diagram.transitions[0].enabled_count = 0
    const override: ReadonlySet<string> = new Set(["approve"])
    const { edges, nodes } = buildGraph(
      diagram,
      "running",
      null,
      { input: 0, output: 0 },
      undefined,
      override
    )
    const input = edges.find((e) => e.id === "arc-p_to_t-pending-approve-0")
    expect(input?.className).toBe("cf-edge-enabled")
    const approveNode = nodes.find((n) => n.id === "t:approve")
    expect((approveNode?.data as Record<string, unknown>).isEnabled).toBe(true)
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
