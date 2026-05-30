import {
  memo,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties
} from "react"
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
import { Badge, Surface } from "@cloudflare/kumo"

type NetDiagramPayload = ColouredFlowDashboardWeb.Views.NetDiagram
type DiagramPlace = ColouredFlowDashboardWeb.Views.NetDiagramPlace
type DiagramTransition = ColouredFlowDashboardWeb.Views.NetDiagramTransition
type DiagramArc = ColouredFlowDashboardWeb.Views.NetDiagramArc

type EnactmentState = "running" | "exception" | "terminated"

interface NetDiagramProps {
  diagram: NetDiagramPayload | null | undefined
  enactmentState?: EnactmentState
  /**
   * Fires when the operator clicks a transition node. Used by the detail page
   * to switch to the Debug tab and pre-filter the binding inspector to the
   * clicked transition.
   */
  onSelectTransition?: (name: string) => void
  /**
   * Edges whose stroke should fill from source to target with the accent
   * color, signalling that their transition just fired. Ids match
   * `arc-${orientation}-${place}-${transition}-${index}`.
   */
  firingEdgeIds?: ReadonlySet<string>
  /**
   * Duration of the firing fill animation. Scales with timeline playback
   * speed (4× → 150ms, 1× → 600ms, 0.25× → 2400ms). Default 600.
   */
  firingDurationMs?: number
}

const DEFAULT_FIRING_DURATION_MS = 600

const EMPTY_FIRING_SET: ReadonlySet<string> = new Set()

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

export default function NetDiagram({
  diagram,
  enactmentState = "running",
  onSelectTransition,
  firingEdgeIds = EMPTY_FIRING_SET,
  firingDurationMs = DEFAULT_FIRING_DURATION_MS
}: NetDiagramProps) {
  const { nodes, edges, isEmpty } = useMemo(
    () => buildGraph(diagram, enactmentState, firingEdgeIds, firingDurationMs),
    [diagram, enactmentState, firingEdgeIds, firingDurationMs]
  )

  const handleNodeClick = useCallback(
    (_event: React.MouseEvent, node: Node) => {
      if (!onSelectTransition) return
      if (node.type !== TRANSITION_NODE) return
      const data = node.data as TransitionNodeData
      onSelectTransition(data.name)
    },
    [onSelectTransition]
  )

  if (isEmpty) {
    return (
      <div
        className="flex h-full min-h-[320px] flex-col items-center justify-center gap-1 px-6 text-center"
        data-testid="net-diagram-empty"
      >
        <span className="text-sm text-cf-ink-muted">Waiting for net definition</span>
        <span className="text-xs text-cf-ink-faint">
          The diagram appears once the first telemetry event lands.
        </span>
      </div>
    )
  }

  return (
    <div className="h-full w-full" data-testid="net-diagram">
      <ReactFlow
        nodes={nodes}
        edges={edges}
        nodeTypes={NODE_TYPES}
        nodesDraggable={true}
        nodesConnectable={false}
        elementsSelectable={Boolean(onSelectTransition)}
        zoomOnDoubleClick={false}
        defaultEdgeOptions={{ style: DEFAULT_EDGE_STYLE, markerEnd: DEFAULT_MARKER }}
        proOptions={{ hideAttribution: true }}
        fitView
        fitViewOptions={{ padding: 0.12, minZoom: 0.4, maxZoom: 1.5 }}
        onNodeClick={onSelectTransition ? handleNodeClick : undefined}
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

export function buildGraph(
  diagram: NetDiagramPayload | null | undefined,
  enactmentState: EnactmentState,
  firingEdgeIds: ReadonlySet<string> = EMPTY_FIRING_SET,
  firingDurationMs: number = DEFAULT_FIRING_DURATION_MS
): { nodes: Array<PlaceNode | TransitionNode>; edges: Edge[]; isEmpty: boolean } {
  const places = diagram?.places ?? []
  const transitions = diagram?.transitions ?? []
  const arcs = diagram?.arcs ?? []

  if (places.length === 0 && transitions.length === 0) {
    return { nodes: [], edges: [], isEmpty: true }
  }

  const g = new dagre.graphlib.Graph()
  g.setDefaultEdgeLabel(() => ({}))
  const tight = places.length + transitions.length <= 6
  g.setGraph({
    rankdir: "TB",
    nodesep: tight ? 50 : 80,
    ranksep: tight ? 80 : 140,
    edgesep: tight ? 20 : 30,
    marginx: 30,
    marginy: 30,
    ranker: "tight-tree"
  })

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
      sourcePosition: Position.Bottom,
      targetPosition: Position.Top,
      draggable: true,
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
      sourcePosition: Position.Bottom,
      targetPosition: Position.Top,
      draggable: true,
      selectable: true
    }
  })

  const edges: Edge[] = arcs.map((arc, index) => {
    const [from, to] = arcEndpoints(arc)
    const id = `arc-${arc.orientation}-${arc.place}-${arc.transition}-${index}`
    const isFiring = firingEdgeIds.has(id)
    // CSS custom property piped to `.cf-edge-firing` keyframes so animation
    // cadence matches the timeline playback speed.
    const style: CSSProperties = isFiring
      ? { ...DEFAULT_EDGE_STYLE, ["--cf-edge-duration" as string]: `${firingDurationMs}ms` }
      : DEFAULT_EDGE_STYLE
    const edge: Edge = {
      id,
      source: from,
      target: to,
      type: "smoothstep",
      animated: false,
      style,
      markerEnd: DEFAULT_MARKER
    }
    if (isFiring) edge.className = "cf-edge-firing"
    return edge
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
    <Surface
      as="div"
      title={tooltip}
      className="relative flex h-[96px] w-[96px] items-center justify-center rounded-full border bg-cf-surface text-center shadow-sm"
      style={{
        borderColor: hasTokens ? "var(--color-cf-accent)" : "var(--color-cf-border)",
        borderWidth: hasTokens ? 2 : 1.5
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
        {hasTokens ? (
          <span data-testid={`place-tokens-${data.name}`} className="contents">
            <Badge
              variant="primary"
              className="bg-cf-accent-tint px-2 py-0 text-base font-semibold leading-none tabular-nums text-cf-accent-ink"
            >
              {data.tokens_count}
            </Badge>
          </span>
        ) : null}
        <span className="max-w-[80px] truncate text-xs font-medium text-cf-ink">
          {truncate(data.name, 12)}
        </span>
        {data.colour_set ? (
          <span className="max-w-[80px] truncate text-[10px] uppercase tracking-wide text-cf-ink-faint">
            {truncate(data.colour_set, 12)}
          </span>
        ) : null}
      </div>
      <Handle
        type="source"
        position={Position.Right}
        style={PLACE_HANDLE_STYLE}
        isConnectable={false}
      />
    </Surface>
  )
}

const PlaceNodeView = memo(PlaceNodeViewImpl)

function TransitionNodeViewImpl({ data }: NodeProps<TransitionNode>) {
  const pulsing = usePulseOnChange(data.last_fired_at)

  const glowKind: "exception" | "enabled" | "none" = useMemo(() => {
    if (data.enactmentState === "exception") return "exception"
    if (data.enabled_count > 0) return "enabled"
    return "none"
  }, [data.enactmentState, data.enabled_count])

  const glow =
    glowKind === "exception"
      ? "var(--color-cf-dot-exception)"
      : glowKind === "enabled"
        ? "var(--color-cf-dot-enabled)"
        : null

  const pulseColor =
    data.enactmentState === "exception"
      ? "var(--color-cf-dot-exception)"
      : "var(--color-cf-accent)"
  const baseShadow = glow ? `0 0 0 4px color-mix(in oklab, ${glow} 25%, transparent)` : "none"
  const pulseShadow = pulsing
    ? `0 0 0 6px color-mix(in oklab, ${pulseColor} 32%, transparent)`
    : null

  return (
    <Surface
      as="div"
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
      data-glow={glowKind}
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
    </Surface>
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
