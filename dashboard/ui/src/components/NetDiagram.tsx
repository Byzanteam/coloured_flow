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
  BaseEdge,
  Background,
  ControlButton,
  Controls,
  Handle,
  MarkerType,
  Position,
  ReactFlow,
  useReactFlow,
  type Edge,
  type EdgeProps,
  type Node,
  type NodeProps
} from "@xyflow/react"
import ELK, { type ElkNode, type ElkExtendedEdge, type ElkPoint } from "elkjs/lib/elk.bundled.js"
import { ArrowsCounterClockwiseIcon } from "@phosphor-icons/react"
import { Badge, Surface } from "@cloudflare/kumo"

type NetDiagramPayload = ColouredFlowDashboardWeb.Views.NetDiagram
type DiagramPlace = ColouredFlowDashboardWeb.Views.NetDiagramPlace
type DiagramTransition = ColouredFlowDashboardWeb.Views.NetDiagramTransition
type DiagramArc = ColouredFlowDashboardWeb.Views.NetDiagramArc

type EnactmentState = "running" | "exception" | "terminated"

interface NetDiagramProps {
  diagram: NetDiagramPayload | null | undefined
  enactmentState?: EnactmentState
  onSelectTransition?: (name: string) => void
  firingEdgeIds?: ReadonlySet<string>
  firingDurationMs?: number
}

const DEFAULT_FIRING_DURATION_MS = 600

const EMPTY_FIRING_SET: ReadonlySet<string> = new Set()

const PLACE_NODE = "cf-place"
const TRANSITION_NODE = "cf-transition"
const ORTHO_EDGE = "ortho"

// Compact node footprint — A.2 of the polish pass. Place is a 16px circle
// (1rem) inside a 48px outer wrapper that also holds the external label
// underneath. Transitions are 32px tall, width clamps to label length.
const PLACE_CIRCLE = 16
const PLACE_LABEL_GAP = 32
const PLACE_W = 48
const PLACE_H = PLACE_CIRCLE + PLACE_LABEL_GAP
const TRANSITION_H = 32
const TRANSITION_MIN_W = 56
const TRANSITION_MAX_W = 200
const TRANSITION_CHAR_PX = 7
const TRANSITION_PAD_PX = 24

function computeTransitionWidth(transitions: ReadonlyArray<DiagramTransition>): number {
  let maxLen = 0
  for (const t of transitions) {
    if (t.name.length > maxLen) maxLen = t.name.length
  }
  const raw = maxLen * TRANSITION_CHAR_PX + TRANSITION_PAD_PX
  return Math.max(TRANSITION_MIN_W, Math.min(TRANSITION_MAX_W, raw))
}

type PlaceNodeData = DiagramPlace & Record<string, unknown>
type TransitionNodeData = DiagramTransition & {
  enactmentState: EnactmentState
  width: number
} & Record<string, unknown>

type PlaceNode = Node<PlaceNodeData, typeof PLACE_NODE>
type TransitionNode = Node<TransitionNodeData, typeof TRANSITION_NODE>

type OrthoEdgeData = {
  points: ReadonlyArray<ElkPoint>
} & Record<string, unknown>

const DEFAULT_EDGE_STYLE = {
  stroke: "var(--color-cf-border-strong)",
  strokeWidth: 1.5
} as const

const ENABLED_EDGE_STYLE = {
  stroke: "var(--color-cf-accent-tint)",
  strokeWidth: 2
} as const

const DEFAULT_MARKER = {
  type: MarkerType.ArrowClosed,
  width: 14,
  height: 14,
  color: "var(--color-cf-border-strong)"
}

const ENABLED_MARKER = {
  type: MarkerType.ArrowClosed,
  width: 14,
  height: 14,
  color: "var(--color-cf-accent-tint)"
}

// Single ELK instance reused across renders — constructing one allocates the
// fake-worker bundle (~200 kB), so we share it. ELK.layout is async; concurrent
// callers each get their own promise back, so reuse is safe.
const elk = new ELK()

export default function NetDiagram({
  diagram,
  enactmentState = "running",
  onSelectTransition,
  firingEdgeIds = EMPTY_FIRING_SET,
  firingDurationMs = DEFAULT_FIRING_DURATION_MS
}: NetDiagramProps) {
  const layout = useElkLayout(diagram)

  const { nodes, edges, isEmpty } = useMemo(
    () => buildGraph(diagram, enactmentState, firingEdgeIds, firingDurationMs, layout),
    [diagram, layout, enactmentState, firingEdgeIds, firingDurationMs]
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
        edgeTypes={EDGE_TYPES}
        nodesDraggable={true}
        nodesConnectable={false}
        elementsSelectable={Boolean(onSelectTransition)}
        zoomOnDoubleClick={false}
        defaultEdgeOptions={{ style: DEFAULT_EDGE_STYLE, markerEnd: DEFAULT_MARKER }}
        proOptions={{ hideAttribution: true }}
        fitView
        minZoom={0.1}
        maxZoom={1.5}
        fitViewOptions={{ padding: 0.12, minZoom: 0.1, maxZoom: 1.5 }}
        onNodeClick={onSelectTransition ? handleNodeClick : undefined}
      >
        <Background gap={18} size={1} color="var(--color-cf-border)" />
        <DiagramControls />
      </ReactFlow>
    </div>
  )
}

function DiagramControls() {
  const { setViewport } = useReactFlow()
  const onReset = useCallback(() => {
    setViewport({ x: 0, y: 0, zoom: 1 }, { duration: 200 })
  }, [setViewport])

  return (
    <Controls showInteractive={false}>
      <ControlButton
        onClick={onReset}
        title="Reset zoom"
        aria-label="Reset zoom"
        data-testid="net-diagram-reset-zoom"
      >
        <ArrowsCounterClockwiseIcon size={14} />
      </ControlButton>
    </Controls>
  )
}

// ---------------------------------------------------------------------------
// Layout (ELK orthogonal routing)
// ---------------------------------------------------------------------------

type Layout = {
  // node id → top-left x,y
  positions: Map<string, { x: number; y: number }>
  // arc index → polyline points (start + bends + end), absolute graph coords
  edgePoints: Map<number, ReadonlyArray<ElkPoint>>
}

const EMPTY_LAYOUT: Layout = {
  positions: new Map(),
  edgePoints: new Map()
}

function useElkLayout(diagram: NetDiagramPayload | null | undefined): Layout {
  const [layout, setLayout] = useState<Layout>(EMPTY_LAYOUT)

  const places = diagram?.places ?? []
  const transitions = diagram?.transitions ?? []
  const arcs = diagram?.arcs ?? []

  // Stable signature so re-renders with structurally identical inputs reuse
  // the existing layout instead of re-running ELK (~80ms on traffic_light).
  const signature = useMemo(
    () => layoutSignature(places, transitions, arcs),
    [places, transitions, arcs]
  )

  useEffect(() => {
    if (places.length === 0 && transitions.length === 0) {
      setLayout(EMPTY_LAYOUT)
      return
    }

    let cancelled = false
    const transitionW = computeTransitionWidth(transitions)
    const graph: ElkNode = {
      id: "root",
      layoutOptions: {
        "elk.algorithm": "layered",
        "elk.direction": "DOWN",
        "elk.layered.edgeRouting": "ORTHOGONAL",
        // Tuned for CPN bipartite structure: places + transitions alternate
        // layers, so generous inter-layer spacing keeps both types readable.
        "elk.layered.spacing.nodeNodeBetweenLayers": "55",
        "elk.spacing.nodeNode": "32",
        "elk.spacing.edgeNode": "16",
        "elk.spacing.edgeEdge": "12",
        "elk.padding": "[top=20,left=20,right=20,bottom=20]"
      },
      children: [
        ...places.map((p) => ({
          id: placeId(p.name),
          width: PLACE_W,
          height: PLACE_H
        })),
        ...transitions.map((t) => ({
          id: transitionId(t.name),
          width: transitionW,
          height: TRANSITION_H
        }))
      ],
      edges: arcs.map((arc, index) => {
        const [from, to] = arcEndpoints(arc)
        return {
          id: arcEdgeId(arc, index),
          sources: [from],
          targets: [to]
        } satisfies ElkExtendedEdge
      })
    }

    elk
      .layout(graph)
      .then((laidOut) => {
        if (cancelled) return
        const positions = new Map<string, { x: number; y: number }>()
        for (const child of laidOut.children ?? []) {
          positions.set(child.id, { x: child.x ?? 0, y: child.y ?? 0 })
        }
        const edgePoints = new Map<number, ReadonlyArray<ElkPoint>>()
        const elkEdges = (laidOut.edges ?? []) as ElkExtendedEdge[]
        arcs.forEach((arc, index) => {
          const id = arcEdgeId(arc, index)
          const elkEdge = elkEdges.find((e) => e.id === id)
          const section = elkEdge?.sections?.[0]
          if (!section) return
          const points: ElkPoint[] = [
            section.startPoint,
            ...(section.bendPoints ?? []),
            section.endPoint
          ]
          edgePoints.set(index, points)
        })
        setLayout({ positions, edgePoints })
      })
      .catch(() => {
        if (!cancelled) setLayout(EMPTY_LAYOUT)
      })

    return () => {
      cancelled = true
    }
    // signature collapses logically-equal diagrams; the underlying arrays
    // are intentionally not deps so a parent re-rendering with the same
    // structure doesn't re-layout.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [signature])

  return layout
}

function layoutSignature(
  places: ReadonlyArray<DiagramPlace>,
  transitions: ReadonlyArray<DiagramTransition>,
  arcs: ReadonlyArray<DiagramArc>
): string {
  const p = places.map((x) => x.name).join("|")
  const t = transitions.map((x) => x.name).join("|")
  const a = arcs
    .map((x) => `${x.orientation}:${x.place}->${x.transition}`)
    .join("|")
  return `${p}#${t}#${a}`
}

export function buildGraph(
  diagram: NetDiagramPayload | null | undefined,
  enactmentState: EnactmentState,
  firingEdgeIds: ReadonlySet<string> = EMPTY_FIRING_SET,
  firingDurationMs: number = DEFAULT_FIRING_DURATION_MS,
  layout: Layout = EMPTY_LAYOUT
): { nodes: Array<PlaceNode | TransitionNode>; edges: Edge[]; isEmpty: boolean } {
  const places = diagram?.places ?? []
  const transitions = diagram?.transitions ?? []
  const arcs = diagram?.arcs ?? []

  if (places.length === 0 && transitions.length === 0) {
    return { nodes: [], edges: [], isEmpty: true }
  }

  const transitionW = computeTransitionWidth(transitions)

  const enabledTransitions = new Set<string>()
  for (const t of transitions) {
    if (t.enabled_count > 0) enabledTransitions.add(t.name)
  }

  const placeNodes: PlaceNode[] = places.map((place, index) => {
    const id = placeId(place.name)
    const pos = layout.positions.get(id) ?? fallbackPos(index, 0)
    return {
      id,
      type: PLACE_NODE,
      position: pos,
      data: { ...place } as PlaceNodeData,
      sourcePosition: Position.Bottom,
      targetPosition: Position.Top,
      draggable: true,
      selectable: false
    }
  })

  const transitionNodes: TransitionNode[] = transitions.map((transition, index) => {
    const id = transitionId(transition.name)
    const pos = layout.positions.get(id) ?? fallbackPos(index, 1)
    return {
      id,
      type: TRANSITION_NODE,
      position: pos,
      data: { ...transition, enactmentState, width: transitionW } as TransitionNodeData,
      sourcePosition: Position.Bottom,
      targetPosition: Position.Top,
      draggable: true,
      selectable: true
    }
  })

  const edges: Edge[] = arcs.map((arc, index) => {
    const id = arcEdgeId(arc, index)
    const [from, to] = arcEndpoints(arc)
    const isFiring = firingEdgeIds.has(id)
    const isEnabledInput =
      !isFiring &&
      arc.orientation === "p_to_t" &&
      enabledTransitions.has(arc.transition)

    let style: CSSProperties
    let markerEnd = DEFAULT_MARKER
    let className: string | undefined

    if (isFiring) {
      style = { ...DEFAULT_EDGE_STYLE, ["--cf-edge-duration" as string]: `${firingDurationMs}ms` }
      className = "cf-edge-firing"
    } else if (isEnabledInput) {
      style = ENABLED_EDGE_STYLE
      markerEnd = ENABLED_MARKER
      className = "cf-edge-enabled"
    } else {
      style = DEFAULT_EDGE_STYLE
    }

    const points = layout.edgePoints.get(index)
    const edge: Edge = {
      id,
      source: from,
      target: to,
      type: points ? ORTHO_EDGE : "smoothstep",
      animated: false,
      style,
      markerEnd,
      data: points ? ({ points } as OrthoEdgeData) : undefined
    }
    if (className) edge.className = className
    return edge
  })

  return { nodes: [...placeNodes, ...transitionNodes], edges, isEmpty: false }
}

function fallbackPos(index: number, lane: number): { x: number; y: number } {
  // Pre-layout / failed-layout fallback: simple grid so nodes don't all
  // pile at (0,0) before ELK resolves.
  return { x: lane * 240 + (index % 4) * 60, y: Math.floor(index / 4) * 80 }
}

function arcEndpoints(arc: DiagramArc): [string, string] {
  return arc.orientation === "p_to_t"
    ? [placeId(arc.place), transitionId(arc.transition)]
    : [transitionId(arc.transition), placeId(arc.place)]
}

function arcEdgeId(arc: DiagramArc, index: number): string {
  return `arc-${arc.orientation}-${arc.place}-${arc.transition}-${index}`
}

const placeId = (name: string) => `p:${name}`
const transitionId = (name: string) => `t:${name}`

// ---------------------------------------------------------------------------
// Custom edge: orthogonal polyline driven by ELK-computed bend points
// ---------------------------------------------------------------------------

function OrthogonalEdgeImpl({ data, markerEnd, style }: EdgeProps) {
  const points = (data as OrthoEdgeData | undefined)?.points
  if (!points || points.length < 2) return null
  const d = points
    .map((p, i) => `${i === 0 ? "M" : "L"} ${p.x} ${p.y}`)
    .join(" ")
  return <BaseEdge path={d} markerEnd={markerEnd} style={style} />
}

const OrthogonalEdge = memo(OrthogonalEdgeImpl)

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
      className="flex flex-col items-center"
      style={{ width: PLACE_W, height: PLACE_H }}
    >
      <div className="relative" style={{ width: PLACE_CIRCLE, height: PLACE_CIRCLE }}>
        <Surface
          as="div"
          title={tooltip}
          className="flex h-full w-full items-center justify-center rounded-full border bg-cf-surface shadow-sm"
          style={{
            borderColor: hasTokens ? "var(--color-cf-accent)" : "var(--color-cf-border)",
            borderWidth: hasTokens ? 2 : 1.5
          }}
          data-testid={`place-node-${data.name}`}
        >
          <Handle
            type="target"
            position={Position.Top}
            style={PLACE_HANDLE_STYLE}
            isConnectable={false}
          />
          <Handle
            type="source"
            position={Position.Bottom}
            style={PLACE_HANDLE_STYLE}
            isConnectable={false}
          />
        </Surface>
        {hasTokens ? (
          <span
            data-testid={`place-token-badge-${data.name}`}
            className="absolute -right-1.5 -top-1.5"
          >
            <Badge
              variant="primary"
              className="inline-flex size-3 items-center justify-center rounded-full bg-cf-accent-tint p-0 text-[8px] font-semibold leading-none tabular-nums text-cf-accent-ink shadow-sm"
            >
              {data.tokens_count}
            </Badge>
          </span>
        ) : null}
      </div>
      <div
        data-testid={`place-label-${data.name}`}
        className="mt-1 flex w-[96px] flex-col items-center leading-tight"
      >
        <span className="max-w-full truncate font-mono text-[11px] font-medium text-cf-ink">
          {data.name}
        </span>
        {data.colour_set ? (
          <span className="max-w-full truncate font-mono text-[10px] text-cf-ink-muted">
            {data.colour_set}
          </span>
        ) : null}
      </div>
    </div>
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
      className="flex items-center justify-center rounded-md border bg-cf-surface px-3 py-1.5 text-center shadow-sm"
      style={{
        width: data.width,
        height: TRANSITION_H,
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
        position={Position.Top}
        style={PLACE_HANDLE_STYLE}
        isConnectable={false}
      />
      <span className="truncate font-mono text-xs font-medium text-cf-ink">
        {data.name}
      </span>
      <Handle
        type="source"
        position={Position.Bottom}
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

const EDGE_TYPES = {
  [ORTHO_EDGE]: OrthogonalEdge
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
