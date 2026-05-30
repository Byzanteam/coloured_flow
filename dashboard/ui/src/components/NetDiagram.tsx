import { memo, useEffect, useMemo, useRef, useState } from "react"
import {
  Background,
  Controls,
  Handle,
  MarkerType,
  Position,
  ReactFlow,
  type Edge,
  type Node,
  type NodeProps
} from "@xyflow/react"
import dagre from "@dagrejs/dagre"

type NetDiagramPayload = ColouredFlowDashboardWeb.Views.NetDiagram
type DiagramPlace = ColouredFlowDashboardWeb.Views.NetDiagramPlace
type DiagramTransition = ColouredFlowDashboardWeb.Views.NetDiagramTransition
type DiagramArc = ColouredFlowDashboardWeb.Views.NetDiagramArc

type EnactmentState = "running" | "exception" | "terminated"

interface NetDiagramProps {
  diagram: NetDiagramPayload | null | undefined
  enactmentState?: EnactmentState
}

const PLACE_NODE = "cf-place"
const TRANSITION_NODE = "cf-transition"

const PLACE_W = 96
const PLACE_H = 96
const TRANSITION_W = 128
const TRANSITION_H = 56

type PlaceNodeData = DiagramPlace & Record<string, unknown>
type TransitionNodeData = DiagramTransition & {
  enactmentState: EnactmentState
} & Record<string, unknown>

type PlaceNode = Node<PlaceNodeData, typeof PLACE_NODE>
type TransitionNode = Node<TransitionNodeData, typeof TRANSITION_NODE>

const DEFAULT_EDGE_STYLE = {
  stroke: "var(--color-cf-border-strong)",
  strokeWidth: 1.5
} as const

const DEFAULT_MARKER = {
  type: MarkerType.ArrowClosed,
  width: 14,
  height: 14,
  color: "var(--color-cf-border-strong)"
}

export default function NetDiagram({ diagram, enactmentState = "running" }: NetDiagramProps) {
  const { nodes, edges, isEmpty } = useMemo(
    () => buildGraph(diagram, enactmentState),
    [diagram, enactmentState]
  )

  if (isEmpty) {
    return (
      <div
        className="flex h-full min-h-[320px] items-center justify-center px-6 text-center text-sm text-cf-ink-muted"
        data-testid="net-diagram-empty"
      >
        Net definition unavailable yet — the bridge will populate it shortly.
      </div>
    )
  }

  return (
    <div className="h-full w-full" data-testid="net-diagram">
      <ReactFlow
        nodes={nodes}
        edges={edges}
        nodeTypes={NODE_TYPES}
        nodesDraggable={false}
        nodesConnectable={false}
        elementsSelectable={false}
        zoomOnDoubleClick={false}
        defaultEdgeOptions={{ style: DEFAULT_EDGE_STYLE, markerEnd: DEFAULT_MARKER }}
        proOptions={{ hideAttribution: true }}
        fitView
        fitViewOptions={{ padding: 0.2 }}
      >
        <Background gap={18} size={1} color="var(--color-cf-border)" />
        <Controls showInteractive={false} />
      </ReactFlow>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

function buildGraph(
  diagram: NetDiagramPayload | null | undefined,
  enactmentState: EnactmentState
): { nodes: Array<PlaceNode | TransitionNode>; edges: Edge[]; isEmpty: boolean } {
  const places = diagram?.places ?? []
  const transitions = diagram?.transitions ?? []
  const arcs = diagram?.arcs ?? []

  if (places.length === 0 && transitions.length === 0) {
    return { nodes: [], edges: [], isEmpty: true }
  }

  const g = new dagre.graphlib.Graph()
  g.setDefaultEdgeLabel(() => ({}))
  g.setGraph({ rankdir: "LR", nodesep: 80, ranksep: 120, marginx: 20, marginy: 20 })

  for (const place of places) {
    g.setNode(placeId(place.name), { width: PLACE_W, height: PLACE_H })
  }
  for (const transition of transitions) {
    g.setNode(transitionId(transition.name), {
      width: TRANSITION_W,
      height: TRANSITION_H
    })
  }
  for (const arc of arcs) {
    const [from, to] = arcEndpoints(arc)
    g.setEdge(from, to)
  }

  dagre.layout(g)

  const placeNodes: PlaceNode[] = places.map((place) => {
    const pos = g.node(placeId(place.name))
    return {
      id: placeId(place.name),
      type: PLACE_NODE,
      position: { x: pos.x - PLACE_W / 2, y: pos.y - PLACE_H / 2 },
      data: { ...place } as PlaceNodeData,
      sourcePosition: Position.Right,
      targetPosition: Position.Left,
      draggable: false,
      selectable: false
    }
  })

  const transitionNodes: TransitionNode[] = transitions.map((transition) => {
    const pos = g.node(transitionId(transition.name))
    return {
      id: transitionId(transition.name),
      type: TRANSITION_NODE,
      position: { x: pos.x - TRANSITION_W / 2, y: pos.y - TRANSITION_H / 2 },
      data: { ...transition, enactmentState } as TransitionNodeData,
      sourcePosition: Position.Right,
      targetPosition: Position.Left,
      draggable: false,
      selectable: false
    }
  })

  const edges: Edge[] = arcs.map((arc, index) => {
    const [from, to] = arcEndpoints(arc)
    return {
      id: `arc-${arc.orientation}-${arc.place}-${arc.transition}-${index}`,
      source: from,
      target: to,
      type: "bezier",
      animated: false,
      style: DEFAULT_EDGE_STYLE,
      markerEnd: DEFAULT_MARKER
    }
  })

  return { nodes: [...placeNodes, ...transitionNodes], edges, isEmpty: false }
}

function arcEndpoints(arc: DiagramArc): [string, string] {
  return arc.orientation === "p_to_t"
    ? [placeId(arc.place), transitionId(arc.transition)]
    : [transitionId(arc.transition), placeId(arc.place)]
}

const placeId = (name: string) => `p:${name}`
const transitionId = (name: string) => `t:${name}`

// ---------------------------------------------------------------------------
// Custom node renderers
// ---------------------------------------------------------------------------

const PLACE_HANDLE_STYLE = {
  background: "transparent",
  border: "none",
  width: 1,
  height: 1
}

function PlaceNodeViewImpl({ data }: NodeProps<PlaceNode>) {
  const hasTokens = data.tokens_count > 0
  const tooltip = data.tokens_summary || `${data.tokens_count} token(s)`
  return (
    <div
      title={tooltip}
      className="relative flex h-[96px] w-[96px] items-center justify-center rounded-full border bg-cf-surface text-center shadow-sm"
      style={{
        borderColor: "var(--color-cf-border)",
        borderWidth: 1.5
      }}
      data-testid={`place-node-${data.name}`}
    >
      <Handle
        type="target"
        position={Position.Left}
        style={PLACE_HANDLE_STYLE}
        isConnectable={false}
      />
      <div className="flex flex-col items-center gap-0.5 px-2">
        <span className="max-w-[80px] truncate text-xs font-medium text-cf-ink">
          {truncate(data.name, 12)}
        </span>
        {data.colour_set ? (
          <span className="max-w-[80px] truncate text-[10px] uppercase tracking-wide text-cf-ink-faint">
            {truncate(data.colour_set, 12)}
          </span>
        ) : null}
      </div>
      {hasTokens ? (
        <span
          className="absolute -right-1 -top-1 inline-flex min-w-[20px] items-center justify-center rounded-full px-1.5 py-0.5 text-[10px] font-semibold text-white shadow-sm"
          style={{ background: "var(--color-cf-accent)" }}
          data-testid={`place-tokens-${data.name}`}
        >
          {data.tokens_count}
        </span>
      ) : null}
      <Handle
        type="source"
        position={Position.Right}
        style={PLACE_HANDLE_STYLE}
        isConnectable={false}
      />
    </div>
  )
}

const PlaceNodeView = memo(PlaceNodeViewImpl)

function TransitionNodeViewImpl({ data }: NodeProps<TransitionNode>) {
  const pulsing = usePulseOnChange(data.last_fired_at)

  const glow = useMemo(() => {
    if (data.enactmentState === "exception") return "var(--color-cf-dot-exception)"
    if (data.enabled_count > 0) return "var(--color-cf-dot-enabled)"
    return null
  }, [data.enactmentState, data.enabled_count])

  const baseShadow = glow ? `0 0 0 4px color-mix(in oklab, ${glow} 25%, transparent)` : "none"
  const pulseShadow = pulsing
    ? `0 0 0 6px color-mix(in oklab, var(--color-cf-accent) 30%, transparent)`
    : null

  return (
    <div
      className="flex h-[56px] w-[128px] items-center justify-center rounded-md border bg-cf-surface text-center shadow-sm"
      style={{
        borderColor: "var(--color-cf-border)",
        borderWidth: 1.5,
        boxShadow: pulseShadow ?? baseShadow,
        transform: pulsing ? "scale(1.05)" : "scale(1)",
        filter: pulsing ? "brightness(1.15)" : "none",
        transition: "box-shadow 200ms cubic-bezier(0.16, 1, 0.3, 1), transform 200ms cubic-bezier(0.16, 1, 0.3, 1), filter 200ms cubic-bezier(0.16, 1, 0.3, 1)"
      }}
      data-testid={`transition-node-${data.name}`}
      data-pulsing={pulsing ? "true" : "false"}
      data-enabled={data.enabled_count > 0 ? "true" : "false"}
    >
      <Handle
        type="target"
        position={Position.Left}
        style={PLACE_HANDLE_STYLE}
        isConnectable={false}
      />
      <span className="max-w-[112px] truncate px-2 text-xs font-medium text-cf-ink">
        {truncate(data.name, 16)}
      </span>
      <Handle
        type="source"
        position={Position.Right}
        style={PLACE_HANDLE_STYLE}
        isConnectable={false}
      />
    </div>
  )
}

const TransitionNodeView = memo(TransitionNodeViewImpl)

const NODE_TYPES = {
  [PLACE_NODE]: PlaceNodeView,
  [TRANSITION_NODE]: TransitionNodeView
} as const

// ---------------------------------------------------------------------------
// Hooks + helpers
// ---------------------------------------------------------------------------

function usePulseOnChange(value: string | null): boolean {
  const [pulsing, setPulsing] = useState(false)
  const lastRef = useRef<string | null>(value)

  useEffect(() => {
    if (value === lastRef.current) return
    lastRef.current = value
    if (!value) return
    setPulsing(true)
    const timer = window.setTimeout(() => setPulsing(false), 220)
    return () => window.clearTimeout(timer)
  }, [value])

  return pulsing
}

function truncate(value: string, max: number): string {
  if (value.length <= max) return value
  return `${value.slice(0, max - 1)}…`
}
