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
import { Surface } from "@cloudflare/kumo"

type NetDiagramPayload = ColouredFlowDashboardWeb.Views.NetDiagram
type DiagramPlace = ColouredFlowDashboardWeb.Views.NetDiagramPlace
type DiagramTransition = ColouredFlowDashboardWeb.Views.NetDiagramTransition
type DiagramArc = ColouredFlowDashboardWeb.Views.NetDiagramArc

type EnactmentState = "running" | "exception" | "terminated"

export type FiringProgress = { input: number; output: number }

interface NetDiagramProps {
  diagram: NetDiagramPayload | null | undefined
  enactmentState?: EnactmentState
  onSelectTransition?: (name: string) => void
  // Name of the transition currently mid-fire. Its `p_to_t` arcs animate at
  // `firingProgress.input` and `t_to_p` arcs animate at `firingProgress.output`
  // — fill is driven by inline `stroke-dasharray`/`stroke-dashoffset` plus the
  // `pathLength="1"` trick so the dash math is path-length agnostic.
  firingTransition?: string | null
  firingProgress?: FiringProgress
  // True during the dwell interval between input-fill end and output-fill
  // start. Triggers a stronger highlight on the firing transition node so the
  // operator sees the transition actually take time to fire (avoids the
  // input-arrives / output-leaves instant flash).
  firingDwell?: boolean
  // Override for the enabled set. When supplied, BOTH the input-arc accent
  // and the transition-node glow derive from this set instead of the live
  // `transition.enabled_count` field. Required in replay mode where the live
  // count reflects a different version than the displayed marking.
  enabledTransitions?: ReadonlySet<string>
}

const ZERO_PROGRESS: FiringProgress = { input: 0, output: 0 }

const EMPTY_PLACES: ReadonlyArray<DiagramPlace> = []
const EMPTY_TRANSITIONS: ReadonlyArray<DiagramTransition> = []
const EMPTY_ARCS: ReadonlyArray<DiagramArc> = []

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
const TRANSITION_H = 28
const TRANSITION_MIN_W = 56
const TRANSITION_CHAR_PX = 7
const TRANSITION_PAD_PX = 20

// No upper clamp: transition names in this codebase are short enough that an
// explicit cap risked truncating a legitimate label. Single shared width is
// still applied to every transition node so the grid stays consistent.
function computeTransitionWidth(transitions: ReadonlyArray<DiagramTransition>): number {
  let maxLen = 0
  for (const t of transitions) {
    if (t.name.length > maxLen) maxLen = t.name.length
  }
  const raw = maxLen * TRANSITION_CHAR_PX + TRANSITION_PAD_PX
  return Math.max(TRANSITION_MIN_W, raw)
}

const EDGE_CORNER_RADIUS = 8

type PlaceNodeData = DiagramPlace & Record<string, unknown>
type TransitionNodeData = DiagramTransition & {
  enactmentState: EnactmentState
  width: number
  isEnabled: boolean
  isFiringDwell: boolean
} & Record<string, unknown>

type PlaceNode = Node<PlaceNodeData, typeof PLACE_NODE>
type TransitionNode = Node<TransitionNodeData, typeof TRANSITION_NODE>

type OrthoEdgeData = {
  points: ReadonlyArray<ElkPoint>
  // 0..1 fraction; undefined means no firing animation on this edge.
  firingProgress?: number
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

const DEFAULT_EDGE_OPTIONS = { style: DEFAULT_EDGE_STYLE, markerEnd: DEFAULT_MARKER } as const
const FIT_VIEW_OPTIONS = { padding: 0.12, minZoom: 0.1, maxZoom: 1.5 } as const
const PRO_OPTIONS = { hideAttribution: true } as const

// Single ELK instance reused across renders — constructing one allocates the
// fake-worker bundle (~200 kB), so we share it. ELK.layout is async; concurrent
// callers each get their own promise back, so reuse is safe.
const elk = new ELK()

export default function NetDiagram({
  diagram,
  enactmentState = "running",
  onSelectTransition,
  firingTransition = null,
  firingProgress = ZERO_PROGRESS,
  firingDwell = false,
  enabledTransitions
}: NetDiagramProps) {
  const layout = useElkLayout(diagram)

  const places = diagram?.places ?? EMPTY_PLACES
  const transitions = diagram?.transitions ?? EMPTY_TRANSITIONS
  const arcs = diagram?.arcs ?? EMPTY_ARCS

  const transitionWidth = useMemo(() => computeTransitionWidth(transitions), [transitions])

  // Place nodes: data is a function of place rows + layout positions only.
  // Token counts arrive through `place.tokens_count`; they update naturally
  // when the server pushes a new `diagram.places`, but stay reference-stable
  // across RAF firing ticks (firingProgress changes don't enter here).
  const placeNodes = useMemo(
    () => buildPlaceNodes(places, layout),
    [places, layout]
  )

  // Transition nodes depend on enactmentState + the enabled override + the
  // firing-dwell signal for the currently-firing transition. Dwell flips on
  // and off inside an animation frame window, so this memo intentionally
  // recomputes per RAF tick during that interval — node identity churns only
  // for the firing transition; React Flow re-renders just that one node.
  const transitionNodes = useMemo(
    () =>
      buildTransitionNodes(
        transitions,
        layout,
        transitionWidth,
        enactmentState,
        enabledTransitions,
        firingTransition,
        firingDwell
      ),
    [
      transitions,
      layout,
      transitionWidth,
      enactmentState,
      enabledTransitions,
      firingTransition,
      firingDwell
    ]
  )

  const nodes = useMemo(
    () => [...placeNodes, ...transitionNodes],
    [placeNodes, transitionNodes]
  )

  // Edges DO depend on firingProgress (arc-fill animation). Non-firing
  // arc data is recomputed per tick but produces an equivalent shape — the
  // OrthogonalEdge memo absorbs the cost without remounting the SVG path.
  const edges = useMemo(
    () =>
      buildEdges(
        arcs,
        layout,
        transitions,
        enabledTransitions,
        firingTransition,
        firingProgress
      ),
    [arcs, layout, transitions, enabledTransitions, firingTransition, firingProgress]
  )

  const isEmpty = places.length === 0 && transitions.length === 0

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
        defaultEdgeOptions={DEFAULT_EDGE_OPTIONS}
        proOptions={PRO_OPTIONS}
        fitView
        minZoom={0.1}
        maxZoom={1.5}
        fitViewOptions={FIT_VIEW_OPTIONS}
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

function buildPlaceNodes(
  places: ReadonlyArray<DiagramPlace>,
  layout: Layout
): PlaceNode[] {
  return places.map((place, index) => {
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
}

function buildTransitionNodes(
  transitions: ReadonlyArray<DiagramTransition>,
  layout: Layout,
  width: number,
  enactmentState: EnactmentState,
  enabledTransitionsOverride: ReadonlySet<string> | undefined,
  firingTransition: string | null,
  firingDwell: boolean
): TransitionNode[] {
  return transitions.map((transition, index) => {
    const id = transitionId(transition.name)
    const pos = layout.positions.get(id) ?? fallbackPos(index, 1)
    const isEnabled = enabledTransitionsOverride
      ? enabledTransitionsOverride.has(transition.name)
      : transition.enabled_count > 0
    const isFiringDwell = firingDwell && firingTransition === transition.name
    return {
      id,
      type: TRANSITION_NODE,
      position: pos,
      data: {
        ...transition,
        enactmentState,
        width,
        isEnabled,
        isFiringDwell
      } as TransitionNodeData,
      sourcePosition: Position.Bottom,
      targetPosition: Position.Top,
      draggable: true,
      selectable: true
    }
  })
}

function buildEdges(
  arcs: ReadonlyArray<DiagramArc>,
  layout: Layout,
  transitions: ReadonlyArray<DiagramTransition>,
  enabledTransitionsOverride: ReadonlySet<string> | undefined,
  firingTransition: string | null,
  firingProgress: FiringProgress
): Edge[] {
  const liveEnabledCounts = new Map<string, number>()
  for (const t of transitions) liveEnabledCounts.set(t.name, t.enabled_count)

  const isTransitionEnabled = (name: string): boolean =>
    enabledTransitionsOverride
      ? enabledTransitionsOverride.has(name)
      : (liveEnabledCounts.get(name) ?? 0) > 0

  return arcs.map((arc, index) => {
    const id = arcEdgeId(arc, index)
    const [from, to] = arcEndpoints(arc)

    const isOnFiringTransition = firingTransition !== null && arc.transition === firingTransition
    const edgeFiringProgress = isOnFiringTransition
      ? arc.orientation === "p_to_t"
        ? clamp01(firingProgress.input)
        : clamp01(firingProgress.output)
      : undefined

    const isEnabledInput =
      arc.orientation === "p_to_t" && isTransitionEnabled(arc.transition)

    let style: CSSProperties
    let markerEnd = DEFAULT_MARKER
    let className: string | undefined

    if (isEnabledInput) {
      style = ENABLED_EDGE_STYLE
      markerEnd = ENABLED_MARKER
      className = "cf-edge-enabled"
    } else {
      style = DEFAULT_EDGE_STYLE
    }

    const points = layout.edgePoints.get(index)
    // `data` always carries `firingProgress` (even when undefined) so test
    // callers and the smoothstep fallback path can both read it without
    // narrowing on `data`.
    const data: OrthoEdgeData = {
      points: points ?? [],
      firingProgress: edgeFiringProgress
    }
    const edge: Edge = {
      id,
      source: from,
      target: to,
      type: points ? ORTHO_EDGE : "smoothstep",
      animated: false,
      style,
      markerEnd,
      data
    }
    if (className) edge.className = className
    return edge
  })
}

export function buildGraph(
  diagram: NetDiagramPayload | null | undefined,
  enactmentState: EnactmentState,
  firingTransition: string | null = null,
  firingProgress: FiringProgress = ZERO_PROGRESS,
  layout: Layout = EMPTY_LAYOUT,
  enabledTransitionsOverride?: ReadonlySet<string>,
  firingDwell: boolean = false
): { nodes: Array<PlaceNode | TransitionNode>; edges: Edge[]; isEmpty: boolean } {
  const places = diagram?.places ?? EMPTY_PLACES
  const transitions = diagram?.transitions ?? EMPTY_TRANSITIONS
  const arcs = diagram?.arcs ?? EMPTY_ARCS

  if (places.length === 0 && transitions.length === 0) {
    return { nodes: [], edges: [], isEmpty: true }
  }

  const transitionW = computeTransitionWidth(transitions)
  const placeNodes = buildPlaceNodes(places, layout)
  const transitionNodes = buildTransitionNodes(
    transitions,
    layout,
    transitionW,
    enactmentState,
    enabledTransitionsOverride,
    firingTransition,
    firingDwell
  )
  const edges = buildEdges(
    arcs,
    layout,
    transitions,
    enabledTransitionsOverride,
    firingTransition,
    firingProgress
  )

  return { nodes: [...placeNodes, ...transitionNodes], edges, isEmpty: false }
}

function clamp01(value: number): number {
  if (value <= 0) return 0
  if (value >= 1) return 1
  return value
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
  const oedata = data as OrthoEdgeData | undefined
  const points = oedata?.points
  if (!points || points.length < 2) return null
  const path = roundedPolylinePath(points, EDGE_CORNER_RADIUS)
  const progress = oedata?.firingProgress
  const isFiring = progress !== undefined

  // Overlay path renders unconditionally so the opacity transition can blend
  // the cf-accent fill in and out smoothly instead of snapping on the firing
  // boundary. dashoffset drives the fill direction; opacity drives the colour
  // emergence. When not firing, opacity=0 hides it entirely (no hit testing,
  // no visual cost beyond the offscreen path).
  const overlayStyle: CSSProperties = {
    ...style,
    stroke: "var(--color-cf-accent)",
    strokeDasharray: 1,
    strokeDashoffset: isFiring ? 1 - progress : 1,
    opacity: isFiring ? 1 : 0,
    transition: "opacity 200ms ease-out",
    pointerEvents: "none"
  }
  return (
    <g data-testid="cf-edge-firing-path">
      <BaseEdge path={path} markerEnd={markerEnd} style={style} />
      <path
        d={path}
        className="react-flow__edge-path cf-edge-overlay"
        fill="none"
        pathLength={1}
        style={overlayStyle}
        data-firing={isFiring ? "true" : "false"}
        data-testid="cf-edge-firing-overlay"
      />
    </g>
  )
}

// Build an SVG path from a polyline, replacing each interior 90° corner with
// a quadratic-bezier arc. The corner radius is capped at half of the shorter
// adjacent segment so very-short legs do not overshoot the bend.
function roundedPolylinePath(points: ReadonlyArray<ElkPoint>, radius: number): string {
  if (points.length < 2) return ""
  if (points.length === 2 || radius <= 0) {
    return points.map((p, i) => `${i === 0 ? "M" : "L"} ${p.x} ${p.y}`).join(" ")
  }
  let d = `M ${points[0].x} ${points[0].y}`
  for (let i = 1; i < points.length - 1; i++) {
    const prev = points[i - 1]
    const curr = points[i]
    const next = points[i + 1]
    const len1 = Math.hypot(curr.x - prev.x, curr.y - prev.y)
    const len2 = Math.hypot(next.x - curr.x, next.y - curr.y)
    const r = Math.max(0, Math.min(radius, len1 / 2, len2 / 2))
    if (r === 0) {
      d += ` L ${curr.x} ${curr.y}`
      continue
    }
    const t1 = (len1 - r) / len1
    const ax = prev.x + (curr.x - prev.x) * t1
    const ay = prev.y + (curr.y - prev.y) * t1
    const t2 = r / len2
    const bx = curr.x + (next.x - curr.x) * t2
    const by = curr.y + (next.y - curr.y) * t2
    d += ` L ${ax} ${ay} Q ${curr.x} ${curr.y} ${bx} ${by}`
  }
  const last = points[points.length - 1]
  d += ` L ${last.x} ${last.y}`
  return d
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
          className="flex h-full w-full items-center justify-center rounded-full bg-cf-surface shadow-sm"
          style={{
            borderStyle: "solid",
            borderColor: hasTokens
              ? "var(--color-cf-accent)"
              : "var(--color-cf-border-strong)",
            borderWidth: 1.5
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
      </div>
      <div
        data-testid={`place-label-${data.name}`}
        className="mt-1 flex w-[96px] flex-col items-center leading-tight"
      >
        <div className="flex max-w-full items-baseline justify-center gap-1">
          <span className="truncate font-mono text-[11px] font-medium text-cf-ink">
            {data.name}
          </span>
          {hasTokens ? (
            <span
              data-testid={`place-token-badge-${data.name}`}
              className="font-mono text-[11px] font-bold tabular-nums text-cf-accent"
            >
              {data.tokens_count}
            </span>
          ) : null}
        </div>
        {data.colour_set ? (
          <code className="mt-0.5 max-w-full truncate rounded border border-cf-border bg-cf-canvas px-1 font-mono text-[10px] text-cf-ink-muted">
            {data.colour_set}
          </code>
        ) : null}
      </div>
    </div>
  )
}

const PlaceNodeView = memo(PlaceNodeViewImpl)

function TransitionNodeViewImpl({ data }: NodeProps<TransitionNode>) {
  // `data.last_fired_at` change → 220ms server-driven pulse. `data.isFiringDwell`
  // → sustained highlight bridging the input-drain and output-produce phases
  // so the operator sees the transition take real time to fire. The two are
  // independent: dwell is RAF-driven and lasts the dwell-fraction window;
  // pulsing reacts to backend telemetry events.
  const pulsing = usePulseOnChange(data.last_fired_at)
  const dwelling = data.isFiringDwell

  const glowKind: "exception" | "enabled" | "none" = useMemo(() => {
    if (data.enactmentState === "exception") return "exception"
    if (data.isEnabled) return "enabled"
    return "none"
  }, [data.enactmentState, data.isEnabled])

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
  const dwellShadow = dwelling
    ? `0 0 0 4px color-mix(in oklab, var(--color-cf-accent) 32%, transparent)`
    : null
  const elevatedShadow = dwellShadow ?? pulseShadow ?? baseShadow
  const elevated = pulsing

  return (
    <Surface
      as="div"
      className="flex items-center justify-center rounded-md border px-2.5 py-1 text-center shadow-sm"
      style={{
        width: data.width,
        height: TRANSITION_H,
        backgroundColor: dwelling
          ? "var(--color-cf-accent-tint)"
          : "var(--color-cf-surface)",
        borderColor: dwelling
          ? "var(--color-cf-accent)"
          : "var(--color-cf-border-strong)",
        borderWidth: 1.5,
        boxShadow: elevatedShadow,
        transform: elevated ? "scale(1.05)" : "scale(1)",
        transition:
          "background-color 240ms ease-out, border-color 240ms ease-out, box-shadow 240ms ease-out, transform 200ms cubic-bezier(0.16, 1, 0.3, 1)"
      }}
      data-testid={`transition-node-${data.name}`}
      data-pulsing={pulsing ? "true" : "false"}
      data-dwelling={dwelling ? "true" : "false"}
      data-enabled={data.isEnabled ? "true" : "false"}
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
