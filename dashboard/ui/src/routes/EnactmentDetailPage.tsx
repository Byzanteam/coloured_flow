import {
  Component,
  type ReactNode,
  Suspense,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState
} from "react"
import { useParams } from "react-router-dom"
import {
  Badge,
  Banner,
  Button,
  Checkbox,
  Dialog,
  LayerCard,
  Table,
  Tabs,
  Text,
  useKumoToastManager
} from "@cloudflare/kumo"
import { CodeHighlighted } from "@cloudflare/kumo/code"
import type { StoreProxy } from "@musubi/react"

import { useMusubiCommand, useMusubiRootSuspense, useMusubiSnapshot } from "../musubi"
import { dispatchWithReply } from "../musubi/replyHandler"
import PageHeader from "../components/PageHeader"
import NetDiagram, { type FiringProgress } from "../components/NetDiagram"
import ColourSetsPanel from "../components/ColourSetsPanel"
import OutputsDrawer from "../components/OutputsDrawer"
import TimelineScrubber, { SPEED_DURATION_MS, type SpeedKey } from "../components/TimelineScrubber"
import { useEmbedMode } from "../hooks/useEmbedMode"
import { prettyJson } from "../lib/prettyJson"

const ENACTMENT_DETAIL_STORE =
  "ColouredFlowDashboardWeb.Stores.EnactmentDetailStore" as const

type DiagramPayload = ColouredFlowDashboardWeb.Views.NetDiagram
type MarkingRow = ColouredFlowDashboardWeb.Views.MarkingRow
type WorkitemRow = ColouredFlowDashboardWeb.Views.WorkitemRow
type OccurrenceRow = ColouredFlowDashboardWeb.Views.OccurrenceRow
type TelemetryEntry = ColouredFlowDashboardWeb.Views.TelemetryEntry
type BindingCandidate = ColouredFlowDashboardWeb.Views.BindingCandidate
type TransitionDebugInfo = ColouredFlowDashboardWeb.Views.TransitionDebugInfo
type EnactmentSummary = ColouredFlowDashboardWeb.Views.EnactmentSummary

type DetailProxy = StoreProxy<typeof ENACTMENT_DETAIL_STORE, Musubi.Stores>

type TabId = "markings" | "workitems" | "occurrences" | "telemetry" | "debug"

// Firing animation timeline reuses SPEED_DURATION_MS so the autoplay tick AND
// scrubber thumb glide finish in lock-step. The window splits into THREE
// intervals so the transition itself has visible dwell time (avoids the
// "input-arrives / output-leaves instantly" flash):
//
//   [0, inputEndMs)            Phase A — input arc fills 0→1.
//   [inputEndMs, outputStartMs) Dwell  — input fill done, transition node
//                                        highlights. Intermediate diagram
//                                        (drained inputs) is visible.
//   [outputStartMs, fullMs)     Phase B — output arc fills 0→1.
//
// Marking + enabled-transition state commits at TWO boundaries:
//   * inputEndMs (drain visible): displayed diagram flips to intermediate
//     (input places drained, output places still pre-fire). Intermediate
//     enabled set computed client-side (T enabled iff every input place of T
//     still has ≥1 token).
//   * fullMs (arrival visible): displayed diagram flips to post-fire
//     (server-pushed). Post-fire enabled set from `:replay_to_version` reply
//     in replay mode, or from the post-fire diagram's `enabled_count` in
//     live mode.

const INPUT_FRACTION = 0.4
const DWELL_FRACTION = 0.2
const EMPTY_TRANSITION_SET: ReadonlySet<string> = new Set()
const ZERO_FIRING_PROGRESS: FiringProgress = { input: 0, output: 0 }

type FiringPhase = {
  transition: string
  startedAt: number
  inputEndMs: number
  outputStartMs: number
  fullMs: number
}

// Phase B intermediate diagram: take the pre-fire diagram and, for each input
// arc of the firing transition, swap that place's row with its post-fire count
// (drained). Output-arc places keep their pre-fire row (token not yet arrived).
// Everything else uses post-fire (no behavioural change for unrelated places).
function buildIntermediateDiagram(
  pre: DiagramPayload,
  post: DiagramPayload,
  firingTransition: string
): DiagramPayload {
  const outputArcPlaces = new Set<string>()
  for (const arc of pre.arcs) {
    if (arc.transition !== firingTransition) continue
    if (arc.orientation === "t_to_p") outputArcPlaces.add(arc.place)
  }
  const postMap = new Map(post.places.map((p) => [p.name, p]))
  const places = pre.places.map((prePlace) => {
    if (outputArcPlaces.has(prePlace.name)) return prePlace
    return postMap.get(prePlace.name) ?? prePlace
  })
  const preNames = new Set(pre.places.map((p) => p.name))
  for (const p of post.places) {
    if (preNames.has(p.name)) continue
    if (outputArcPlaces.has(p.name)) continue
    places.push(p)
  }
  return { ...post, places }
}

// Client-side intermediate enabled set: T is enabled iff every p_to_t arc's
// place has ≥1 token in the supplied diagram. Matches plan option (b) — no
// wire change; the brief intermediate-phase glow approximates engine truth.
function computeEnabledFromDiagramTokens(diagram: DiagramPayload): ReadonlySet<string> {
  const tokens = new Map<string, number>()
  for (const p of diagram.places) tokens.set(p.name, p.tokens_count)
  const inputs = new Map<string, string[]>()
  for (const arc of diagram.arcs) {
    if (arc.orientation !== "p_to_t") continue
    const list = inputs.get(arc.transition) ?? []
    list.push(arc.place)
    inputs.set(arc.transition, list)
  }
  const enabled = new Set<string>()
  for (const t of diagram.transitions) {
    const inputList = inputs.get(t.name)
    if (!inputList || inputList.length === 0) continue
    if (inputList.every((p) => (tokens.get(p) ?? 0) >= 1)) enabled.add(t.name)
  }
  return enabled
}

// Markings tab rows derived from a diagram. Mirrors the backend's
// `diagram_places ← marking_index` build path so the rows stay shape-compatible
// with the live `:markings` stream.
function diagramToMarkingRows(diagram: DiagramPayload): MarkingRow[] {
  return diagram.places
    .filter((p) => p.tokens_count > 0)
    .map((p) => ({
      place: p.name,
      colour_set: p.colour_set,
      tokens_count: p.tokens_count,
      tokens_summary: p.tokens_summary
    }))
}

const TAB_ITEMS = [
  { value: "markings", label: "Markings" },
  { value: "workitems", label: "Workitems" },
  { value: "occurrences", label: "Occurrences" },
  { value: "telemetry", label: "Telemetry" },
  { value: "debug", label: "Debug" }
] as const

export default function EnactmentDetailPage() {
  const { id } = useParams<"id">()

  if (!id) {
    return (
      <section className="flex flex-col gap-6">
        <PageHeader
          title="Enactment"
          breadcrumbs={[
            { label: "Enactments", to: "/enactments" },
            { label: "—" }
          ]}
        />
        <Banner
          variant="error"
          title="Missing enactment id"
          description="Visit /enactments/<id> to view a specific enactment."
        />
      </section>
    )
  }

  return (
    <DetailBoundary enactmentId={id} fallback={<DetailFallback enactmentId={id} />}>
      <DetailRoot enactmentId={id} />
    </DetailBoundary>
  )
}

function DetailRoot({ enactmentId }: { enactmentId: string }) {
  const detail = useMusubiRootSuspense({
    module: ENACTMENT_DETAIL_STORE,
    id: enactmentId,
    params: { id: enactmentId }
  })

  return <DetailContent detail={detail} enactmentId={enactmentId} />
}

type DetailBoundaryProps = { enactmentId: string; fallback: ReactNode; children: ReactNode }
type DetailBoundaryState = { error: Error | null }

class DetailBoundary extends Component<DetailBoundaryProps, DetailBoundaryState> {
  state: DetailBoundaryState = { error: null }

  static getDerivedStateFromError(error: unknown): DetailBoundaryState {
    return { error: error instanceof Error ? error : new Error(String(error)) }
  }

  resetError = () => this.setState({ error: null })

  render() {
    if (this.state.error) {
      return (
        <DetailError
          enactmentId={this.props.enactmentId}
          message={this.state.error.message}
          onRetry={this.resetError}
        />
      )
    }
    return <Suspense fallback={this.props.fallback}>{this.props.children}</Suspense>
  }
}

function DetailFallback({ enactmentId }: { enactmentId: string }) {
  return (
    <section className="flex flex-col gap-6">
      <PageHeader
        title="Enactment"
        byline={<code className="text-xs text-cf-ink-muted">{enactmentId}</code>}
        breadcrumbs={detailBreadcrumbs(enactmentId)}
      />
      <LayerCard.Primary className="px-6 py-10">
        <Text variant="secondary">Loading enactment detail…</Text>
      </LayerCard.Primary>
    </section>
  )
}

function DetailError({
  enactmentId,
  message,
  onRetry
}: {
  enactmentId: string
  message: string
  onRetry: () => void
}) {
  return (
    <section className="flex flex-col gap-6" data-testid="detail-error">
      <PageHeader
        title="Enactment"
        byline={<code className="text-xs text-cf-ink-muted">{enactmentId}</code>}
        breadcrumbs={detailBreadcrumbs(enactmentId)}
      />
      <Banner variant="error" title="Detail unavailable" description={message} />
      <div>
        <Button
          variant="secondary"
          size="sm"
          onClick={onRetry}
          data-testid="detail-error-retry"
        >
          Retry
        </Button>
      </div>
    </section>
  )
}

function DetailContent({
  detail,
  enactmentId
}: {
  detail: DetailProxy
  enactmentId: string
}) {
  const snapshot = useMusubiSnapshot(detail)
  const toasts = useKumoToastManager()
  const { embed } = useEmbedMode()

  // Playback speed is lifted out of TimelineScrubber so the diagram's edge
  // firing animation duration can scale to match the cadence the operator
  // picked. TimelineScrubber still owns its own speed-ref logic for autoplay
  // ticks; this state mirrors the latest choice via `onSpeedChange`.
  const [speed, setSpeed] = useState<SpeedKey>("1")
  const firingDurationMs = SPEED_DURATION_MS[speed]

  const summary: EnactmentSummary | undefined = snapshot.summary
  const liveMarkings: readonly MarkingRow[] = snapshot.markings ?? []
  const workitems: readonly WorkitemRow[] = snapshot.workitems ?? []
  const occurrences: readonly OccurrenceRow[] = snapshot.occurrences ?? []
  const telemetry: readonly TelemetryEntry[] = snapshot.telemetry ?? []
  const transitions: readonly string[] = snapshot.transitions ?? []
  const diagram: DiagramPayload | null = snapshot.diagram ?? null

  const replayState = summary?.replay_state ?? null
  const versionRange: ColouredFlowDashboardWeb.Views.VersionRange =
    summary?.version_range ?? { min: 0, max: summary?.version ?? 0 }

  const replayCmd = useMusubiCommand(detail, "replay_to_version")
  const exitReplayCmd = useMusubiCommand(detail, "exit_replay")

  // Derived markings live client-side so the live `:markings` stream keeps
  // its mount-time-accurate behavior. Cleared on exit-replay.
  const [derivedMarkings, setDerivedMarkings] = useState<readonly MarkingRow[]>([])
  // Enabled-transition set returned by `:replay_to_version` for the derived
  // marking at version v. Sourced from the engine's own
  // `EnabledBindingElements.list/3` — never accumulated, never unioned with
  // the live `enabled_count`. Cleared on exit-replay.
  const [replayEnabledTransitions, setReplayEnabledTransitions] = useState<
    ReadonlySet<string>
  >(EMPTY_TRANSITION_SET)

  // When the server clears replay_state (e.g., exit_replay), drop any
  // cached derived rows so the Markings tab snaps back to live.
  useEffect(() => {
    if (replayState === null) {
      setDerivedMarkings([])
      setReplayEnabledTransitions(EMPTY_TRANSITION_SET)
    }
  }, [replayState])

  // Refs accessed by the reply callback (which closes over its creation-time
  // state) so it always reads the latest snapshot/derivation. Refs avoid
  // re-creating the callback (and re-dispatching its useMusubiCommand binding)
  // on every snapshot tick.
  const occurrencesRef = useRef(occurrences)
  const diagramRef = useRef<DiagramPayload | null>(diagram)
  const activeVersionRef = useRef(0)
  const firingPhaseRef = useRef<FiringPhase | null>(null)
  // Post-fire markings + enabled set committed at Phase B end (fullMs). Drains
  // are NOT a separate pending — they are rendered live from the intermediate
  // diagram via a useMemo, so derivedMarkings/replayEnabledTransitions state
  // stays at the pre-fire value through Phases A+B and snaps to post-fire on
  // applyFinalPendings.
  const pendingFinalMarkingsRef = useRef<readonly MarkingRow[] | null>(null)
  const pendingFinalEnabledRef = useRef<ReadonlySet<string> | null>(null)

  // Mirror of the diagram one render behind the current one. Pinned while a
  // firing phase is active so Phase A renders the pre-fire token counts. The
  // server pushes the post-fire diagram via assign broadcast at firing trigger
  // time, so without this pin the diagram tokens would snap to post-fire
  // instantly and we'd animate the arc over the wrong state.
  const previousDiagramRef = useRef<DiagramPayload | null>(null)
  const diagramSeenRef = useRef<DiagramPayload | null>(diagram)

  useEffect(() => {
    occurrencesRef.current = occurrences
  }, [occurrences])
  useEffect(() => {
    if (firingPhaseRef.current === null) {
      previousDiagramRef.current = diagramSeenRef.current
    }
    diagramSeenRef.current = diagram
    diagramRef.current = diagram
  }, [diagram])

  const [firingPhase, setFiringPhase] = useState<FiringPhase | null>(null)
  const [firingProgress, setFiringProgress] = useState<FiringProgress>(ZERO_FIRING_PROGRESS)
  // Snapshot of the pre-fire diagram captured when firingPhase becomes
  // non-null. Used to derive the intermediate diagram + intermediate enabled
  // set. Cleared when the phase ends.
  const [firingPreDiagram, setFiringPreDiagram] = useState<DiagramPayload | null>(null)

  useEffect(() => {
    firingPhaseRef.current = firingPhase
    if (firingPhase === null) {
      setFiringPreDiagram(null)
    } else {
      setFiringPreDiagram(previousDiagramRef.current)
    }
  }, [firingPhase])

  const applyFinalPendings = useCallback(() => {
    if (pendingFinalMarkingsRef.current !== null) {
      setDerivedMarkings(pendingFinalMarkingsRef.current)
      pendingFinalMarkingsRef.current = null
    }
    if (pendingFinalEnabledRef.current !== null) {
      setReplayEnabledTransitions(pendingFinalEnabledRef.current)
      pendingFinalEnabledRef.current = null
    }
  }, [])

  const startFiringPhase = useCallback((transition: string, durationMs: number) => {
    const inputEndMs = durationMs * INPUT_FRACTION
    const outputStartMs = inputEndMs + durationMs * DWELL_FRACTION
    setFiringPhase({
      transition,
      startedAt: performance.now(),
      inputEndMs,
      outputStartMs,
      fullMs: durationMs
    })
  }, [])

  const onScrub = useCallback(
    (version: number) => {
      void dispatchWithReply<ReplayToVersionCode>(
        replayCmd.dispatch as unknown as (
          payload: Record<string, unknown>
        ) => Promise<{ code?: string } & Record<string, unknown>>,
        { version },
        {
          onReply: (code, reply) => {
            if (code === "ok") {
              const r = reply as ReplayToVersionReply
              const nextMarkings = r.markings ?? []
              const nextEnabled = new Set(r.enabled_transitions ?? [])
              const prevVersion = activeVersionRef.current
              const occurrence = occurrencesRef.current.find(
                (o) => o.step_number === version
              )
              const arcs = diagramRef.current?.arcs ?? []
              const hasMatchingArc =
                occurrence !== undefined &&
                arcs.some((arc) => arc.transition === occurrence.transition)
              // Single-step forward AND occurrence on a visible transition →
              // run the two-phase animation. Defer the final marking/enabled
              // commit until Phase B end (fullMs); the intermediate (drained)
              // state is computed live from firingPreDiagram + the latest
              // diagram, so derivedMarkings/replayEnabledTransitions stay at
              // the pre-fire value through Phase A. Multi-step jumps + initial
              // replay entry apply immediately — no occurrence to visualise.
              if (
                occurrence !== undefined &&
                hasMatchingArc &&
                version === prevVersion + 1
              ) {
                pendingFinalMarkingsRef.current = nextMarkings
                pendingFinalEnabledRef.current = nextEnabled
                startFiringPhase(occurrence.transition, firingDurationMs)
              } else {
                setDerivedMarkings(nextMarkings)
                setReplayEnabledTransitions(nextEnabled)
              }
            } else if (code === "invalid_version") {
              const r = reply as ReplayToVersionReply
              const floor = r.snapshot_floor ?? versionRange.min
              const cap = r.available_max_version ?? versionRange.max
              toasts.add({
                variant: "info",
                title: "Version out of range",
                description: `Pick a version between v${floor} and v${cap}.`,
                timeout: 4000
              })
            } else {
              toasts.add({
                variant: "error",
                title: "Replay failed",
                description: "Runner rejected the replay request.",
                timeout: 6000
              })
            }
          },
          onUnexpected: (cause) => {
            toasts.add({
              variant: "error",
              title: "Replay failed",
              description: cause instanceof Error ? cause.message : "Unknown error.",
              timeout: 6000
            })
          }
        }
      )
    },
    [replayCmd.dispatch, toasts, versionRange.min, versionRange.max]
  )

  const onExitReplay = useCallback(() => {
    void dispatchWithReply<"ok">(
      exitReplayCmd.dispatch as (payload: Record<string, unknown>) => Promise<
        { code?: string } & Record<string, unknown>
      >,
      {},
      {
        onReply: () => {
          setDerivedMarkings([])
          setReplayEnabledTransitions(EMPTY_TRANSITION_SET)
        },
        onUnexpected: (cause) => {
          toasts.add({
            variant: "error",
            title: "Exit replay failed",
            description: cause instanceof Error ? cause.message : "Unknown error.",
            timeout: 6000
          })
        }
      }
    )
  }, [exitReplayCmd.dispatch, toasts])

  // Three-phase intermediate state. Computed once per (firingPhase,
  // firingPreDiagram, diagram) tuple. `firingPhase === null` short-circuits so
  // off-firing renders pay nothing.
  const intermediateState = useMemo(() => {
    if (firingPhase === null || firingPreDiagram === null || diagram === null) {
      return null
    }
    const interDiag = buildIntermediateDiagram(
      firingPreDiagram,
      diagram,
      firingPhase.transition
    )
    return {
      diagram: interDiag,
      markings: diagramToMarkingRows(interDiag),
      enabled: computeEnabledFromDiagramTokens(interDiag)
    }
  }, [firingPhase, firingPreDiagram, diagram])

  // Three-phase selectors. RAF ticks update firingProgress so these recompute
  // on every frame the phase advances; identity changes only at the boundaries
  // (pre→intermediate at inputEndMs, intermediate→post at fullMs). The dwell
  // window [inputEndMs, outputStartMs) is inside "intermediate" (input == 1,
  // output == 0); `firingDwell` narrows that to the dwell-only sub-interval so
  // the transition node can highlight without affecting marking visuals.
  const firingDisplayPhase: "pre" | "intermediate" | "post" =
    firingPhase === null
      ? "post"
      : firingProgress.input < 1
        ? "pre"
        : firingProgress.output < 1
          ? "intermediate"
          : "post"

  const firingDwell =
    firingPhase !== null && firingProgress.input === 1 && firingProgress.output === 0

  const displayedDiagram: DiagramPayload | null = (() => {
    if (firingPhase === null) return diagram
    if (firingDisplayPhase === "pre") return firingPreDiagram ?? diagram
    if (firingDisplayPhase === "intermediate") {
      return intermediateState?.diagram ?? diagram
    }
    return diagram
  })()

  const markings: readonly MarkingRow[] = (() => {
    if (replayState === null) return liveMarkings
    if (firingPhase !== null && firingDisplayPhase === "intermediate" && intermediateState) {
      return intermediateState.markings
    }
    return derivedMarkings
  })()

  // `activeVersion` drives the LIVE-mode firing trigger. Replay-mode firing is
  // driven directly by the `:replay_to_version` reply (onScrub above) so the
  // marking/enabled-state swap can be deferred exactly to the Phase A → B
  // boundary; piggy-backing on the version-bump effect would race with the
  // assign broadcast.
  const activeVersion = replayState?.version ?? summary?.version ?? 0
  const lastVersionRef = useRef<number | null>(null)

  useEffect(() => {
    activeVersionRef.current = activeVersion
    const prev = lastVersionRef.current
    lastVersionRef.current = activeVersion
    if (prev === null) return
    if (activeVersion <= prev) return
    if (replayState !== null) return

    const occurrence = occurrences.find((o) => o.step_number === activeVersion)
    if (!occurrence) return
    const arcs = diagram?.arcs ?? []
    const hasMatchingArc = arcs.some((arc) => arc.transition === occurrence.transition)
    if (!hasMatchingArc) return
    startFiringPhase(occurrence.transition, firingDurationMs)
  }, [activeVersion, occurrences, diagram?.arcs, firingDurationMs, replayState, startFiringPhase])

  // RAF loop drives `firingProgress` over the three-interval window. The
  // final marking + enabled-transition commit lands at fullMs so output-token
  // arrivals stay in lock-step with the output-arc fill. The intermediate
  // (drained-inputs) view is rendered live via useMemo against firingPreDiagram
  // + the current diagram — no state mutation required at the inputEndMs
  // boundary. The dwell interval [inputEndMs, outputStartMs) keeps progress
  // at { input: 1, output: 0 } so the transition node stays highlighted.
  useEffect(() => {
    if (firingPhase === null) {
      setFiringProgress(ZERO_FIRING_PROGRESS)
      return
    }
    let raf = 0
    let appliedFinal = false
    const tick = () => {
      const elapsed = performance.now() - firingPhase.startedAt
      if (elapsed >= firingPhase.fullMs) {
        setFiringProgress({ input: 1, output: 1 })
        applyFinalPendings()
        appliedFinal = true
        setFiringPhase(null)
        return
      }
      if (elapsed < firingPhase.inputEndMs) {
        setFiringProgress({ input: elapsed / firingPhase.inputEndMs, output: 0 })
      } else if (elapsed < firingPhase.outputStartMs) {
        setFiringProgress({ input: 1, output: 0 })
      } else {
        setFiringProgress({
          input: 1,
          output:
            (elapsed - firingPhase.outputStartMs) /
            (firingPhase.fullMs - firingPhase.outputStartMs)
        })
      }
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => {
      cancelAnimationFrame(raf)
      // Operator scrubbed again mid-animation, or the component unmounted.
      // Apply the final-pending so the diagram never lingers on stale state.
      if (!appliedFinal) applyFinalPendings()
    }
  }, [firingPhase, applyFinalPendings])

  // Enabled-transition override resolution:
  //   * Phase B (intermediate): client-computed set against drained inputs.
  //     Drives BOTH live and replay glow during the brief intermediate window.
  //   * Replay (non-firing OR Phase A/post): replay reply's enabled set.
  //     `replayEnabledTransitions` holds the PRE-fire value through Phases A+B
  //     and snaps to post-fire when applyFinalPendings runs at fullMs.
  //   * Live (non-firing OR Phase A/post): undefined → NetDiagram derives from
  //     the displayedDiagram's transitions[].enabled_count. Pre-fire diagram
  //     carries pre-fire counts (Phase A), post-fire diagram carries post-fire
  //     counts (post).
  const enabledTransitionsOverride: ReadonlySet<string> | undefined = (() => {
    if (
      firingPhase !== null &&
      firingDisplayPhase === "intermediate" &&
      intermediateState
    ) {
      return intermediateState.enabled
    }
    return replayState === null ? undefined : replayEnabledTransitions
  })()

  const [activeTab, setActiveTab] = useState<TabId>("markings")
  // Pending inspect target driven by NetDiagram node click. Cleared by
  // DebugTab once the dispatch fires so re-clicking the same transition
  // re-inspects.
  const [pendingInspect, setPendingInspect] = useState<string | null>(null)

  const completeCommand = useMusubiCommand(detail, "complete_workitem")
  const [drawerRow, setDrawerRow] = useState<WorkitemRow | null>(null)

  // Race-collapse: if another operator completes the workitem while this
  // drawer is open, the live workitems stream drops the row. Close the
  // drawer + toast so the operator does not submit against stale data.
  useEffect(() => {
    if (!drawerRow) return
    const stillLive = workitems.some((wi) => wi.id === drawerRow.id)
    if (!stillLive) {
      setDrawerRow(null)
      toasts.add({
        variant: "info",
        title: "Already handled",
        description: "Another operator handled this workitem.",
        timeout: 4000
      })
    }
  }, [workitems, drawerRow, toasts])

  const onSelectTransition = useCallback((name: string) => {
    setActiveTab("debug")
    setPendingInspect(name)
  }, [])

  const onInspectConsumed = useCallback(() => setPendingInspect(null), [])

  const orderedOccurrences = useMemo(
    () => [...occurrences].sort((a, b) => b.step_number - a.step_number),
    [occurrences]
  )

  const state = summary?.state ?? "running"
  const exceptionBanner = summary?.last_exception_banner ?? null

  return (
    <section className="flex flex-col gap-6">
      <PageHeader
        title={detailTitle(summary?.flow_name ?? null, enactmentId)}
        breadcrumbs={detailBreadcrumbs(enactmentId)}
        byline={
          <div className="flex flex-wrap items-center gap-2">
            <code className="text-xs text-cf-ink-muted">{enactmentId}</code>
            <StateBadge state={state} />
          </div>
        }
        subtitle={
          state === "exception"
            ? "This enactment cannot make progress until terminated or reset."
            : undefined
        }
        actions={<ActionBar detail={detail} state={state} />}
      />

      {state === "exception" ? (
        <div data-testid="detail-exception-banner">
          <Banner
            variant="error"
            title="Enactment exception"
            description={exceptionBanner ?? "Enactment is in an exception state."}
          />
        </div>
      ) : null}

      <TimelineScrubber
        range={versionRange}
        liveVersion={summary?.version ?? 0}
        replayState={replayState}
        onScrub={onScrub}
        onExit={onExitReplay}
        isPending={replayCmd.isPending || exitReplayCmd.isPending}
        onSpeedChange={setSpeed}
      />

      {/* Left = diagram, right = metrics + colour sets + tabs. Stack on
          screens narrower than lg (1024px) so the diagram doesn't crush on
          mobile. */}
      <div
        className="flex flex-col gap-6 lg:flex-row lg:items-stretch lg:min-h-[640px]"
        data-testid="detail-split"
      >
        <LayerCard.Primary
          className="overflow-hidden p-0 lg:basis-3/5 lg:flex-shrink-0 lg:self-stretch"
          data-testid="net-diagram-card"
        >
          <div className="h-[440px] min-h-[440px] w-full lg:h-full lg:min-h-[640px]">
            <NetDiagram
              diagram={displayedDiagram}
              enactmentState={state}
              onSelectTransition={onSelectTransition}
              firingTransition={firingPhase?.transition ?? null}
              firingProgress={firingProgress}
              firingDwell={firingDwell}
              enabledTransitions={enabledTransitionsOverride}
            />
          </div>
        </LayerCard.Primary>

        <div
          className="flex min-w-0 flex-col gap-4 lg:basis-2/5 lg:flex-1"
          data-testid="detail-tabs-pane"
        >
          {embed ? null : (
            <MetricsPills
              items={[
                { label: "Version", value: `v${summary?.version ?? 0}` },
                { label: "Markings", value: summary?.markings_count ?? 0 },
                { label: "Live workitems", value: summary?.workitems_count ?? 0 },
                {
                  label: "Last occ",
                  value: summary?.last_occurrence_at
                    ? formatTimestamp(summary.last_occurrence_at)
                    : "—"
                }
              ]}
            />
          )}
          {embed ? null : (
            <ColourSetsPanel colourSets={diagram?.colour_sets ?? []} />
          )}
          <div className="overflow-x-auto border-b border-cf-border">
            <Tabs
              variant="underline"
              tabs={TAB_ITEMS as unknown as Array<{ value: string; label: string }>}
              value={activeTab}
              onValueChange={(value) => setActiveTab(value as TabId)}
            />
          </div>

          <div className="flex flex-col gap-4">
            {activeTab === "markings" && (
              <MarkingsTab
                rows={markings}
                replayState={replayState}
                isPending={replayCmd.isPending}
              />
            )}
            {activeTab === "workitems" && (
              <WorkitemsTab rows={workitems} onOpen={setDrawerRow} />
            )}
            {activeTab === "occurrences" && <OccurrencesTab rows={orderedOccurrences} />}
            {activeTab === "telemetry" && (
              <TelemetryTab
                rows={telemetry}
                onOpenInDebug={(transition) => {
                  setActiveTab("debug")
                  if (transition) setPendingInspect(transition)
                }}
              />
            )}
            {activeTab === "debug" && (
              <DebugTab
                detail={detail}
                transitions={transitions}
                pendingInspect={pendingInspect}
                onInspectConsumed={onInspectConsumed}
              />
            )}
          </div>
        </div>
      </div>

      <OutputsDrawer
        command={completeCommand}
        row={drawerRow}
        onClose={() => setDrawerRow(null)}
      />
    </section>
  )
}

// ---------------------------------------------------------------------------
// Metrics pill row
// ---------------------------------------------------------------------------

interface MetricPill {
  label: string
  value: ReactNode
}

/**
 * Compact metric strip for the detail page's constrained right column. Each
 * pill renders an uppercase label and a monospaced single-line value. Wraps
 * on narrow screens. Other surfaces (InboxPage / EnactmentList / FlowCatalog
 * / TelemetryPage) keep the shared `MetricsRow` cards because they have
 * full-width room.
 */
function MetricsPills({ items }: { items: readonly MetricPill[] }) {
  if (items.length === 0) return null

  return (
    <div
      className="flex flex-wrap items-center gap-1.5"
      data-testid="metrics-pills"
    >
      {items.map((item) => (
        <span
          key={item.label}
          className="inline-flex items-center gap-1.5 rounded-full border border-cf-border bg-cf-surface px-2.5 py-1"
        >
          <span className="text-[10px] font-medium uppercase tracking-[0.08em] text-cf-ink-faint">
            {item.label}
          </span>
          <span className="font-mono text-xs tabular-nums text-cf-ink">
            {item.value}
          </span>
        </span>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Status + summary
// ---------------------------------------------------------------------------

function StateBadge({
  state
}: {
  state: "running" | "exception" | "terminated"
}) {
  if (state === "exception") {
    return (
      <span
        className="inline-flex items-center gap-1.5 rounded-full border border-cf-exception-ink/50 bg-cf-exception-bg px-2 py-0.5 text-xs font-medium text-cf-exception-ink"
        data-testid="state-badge-exception"
      >
        <span className="h-1.5 w-1.5 rounded-full bg-cf-dot-exception" />
        Exception
      </span>
    )
  }

  const dotMap = {
    running: "bg-cf-dot-enabled",
    terminated: "bg-cf-dot-terminated"
  } as const
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full border border-cf-border bg-cf-surface px-2 py-0.5 text-xs text-cf-ink">
      <span className={`h-1.5 w-1.5 rounded-full ${dotMap[state]}`} />
      {state}
    </span>
  )
}

// ---------------------------------------------------------------------------
// Action bar
// ---------------------------------------------------------------------------

type ForceTerminateCode = "ok" | "already_terminated" | "runner_error"
type TakeSnapshotCode = "ok" | "not_running" | "runner_error"
type RetryEnactmentCode =
  | "ok"
  | "not_exception"
  | "already_terminated"
  | "runner_error"
type ReplayToVersionCode = "ok" | "invalid_version" | "runner_error"

interface ReplayToVersionReply extends Record<string, unknown> {
  code?: ReplayToVersionCode
  markings?: readonly MarkingRow[]
  enabled_transitions?: readonly string[]
  replay_state?: ColouredFlowDashboardWeb.Views.ReplayState | null
  available_max_version?: number | null
  snapshot_floor?: number | null
}

function ActionBar({
  detail,
  state
}: {
  detail: DetailProxy
  state: "running" | "exception" | "terminated"
}) {
  const toasts = useKumoToastManager()

  const forceTerminate = useMusubiCommand(detail, "force_terminate")
  const takeSnapshot = useMusubiCommand(detail, "take_snapshot")
  const retryEnactment = useMusubiCommand(detail, "retry_enactment")

  const [confirmOpen, setConfirmOpen] = useState(false)
  const [reason, setReason] = useState("")

  const onRetry = async () => {
    await dispatchWithReply<RetryEnactmentCode>(
      retryEnactment.dispatch as (payload: Record<string, unknown>) => Promise<
        { code?: string } & Record<string, unknown>
      >,
      {},
      {
        onReply: (code) => {
          if (code === "ok") {
            toasts.add({
              variant: "success",
              title: "Retry requested",
              description: "Runner is bringing the enactment back online.",
              timeout: 4000
            })
          } else if (code === "not_exception") {
            toasts.add({
              variant: "info",
              title: "Not in exception",
              description: "The enactment is already running.",
              timeout: 4000
            })
          } else if (code === "already_terminated") {
            toasts.add({
              variant: "info",
              title: "Already terminated",
              description: "Terminated enactments cannot be retried.",
              timeout: 4000
            })
          } else {
            toasts.add({
              variant: "error",
              title: "Retry failed",
              description: "Runner rejected the retry request.",
              timeout: 6000
            })
          }
        },
        onUnexpected: (cause) => {
          toasts.add({
            variant: "error",
            title: "Retry failed",
            description: cause instanceof Error ? cause.message : "Unknown error.",
            timeout: 6000
          })
        }
      }
    )
  }

  const onTakeSnapshot = async () => {
    await dispatchWithReply<TakeSnapshotCode>(
      takeSnapshot.dispatch as (payload: Record<string, unknown>) => Promise<
        { code?: string } & Record<string, unknown>
      >,
      {},
      {
        onReply: (code) => {
          if (code === "ok") {
            toasts.add({
              variant: "success",
              title: "Snapshot scheduled",
              description: "The enactment will persist its current marking shortly.",
              timeout: 4000
            })
          } else if (code === "not_running") {
            toasts.add({
              variant: "info",
              title: "Not running",
              description: "The enactment GenServer is not active; nothing to snapshot.",
              timeout: 4000
            })
          } else {
            toasts.add({
              variant: "error",
              title: "Snapshot failed",
              description: "Runner rejected the snapshot request.",
              timeout: 6000
            })
          }
        },
        onUnexpected: (cause) => {
          toasts.add({
            variant: "error",
            title: "Snapshot failed",
            description: cause instanceof Error ? cause.message : "Unknown error.",
            timeout: 6000
          })
        }
      }
    )
  }

  const onForceTerminate = async () => {
    await dispatchWithReply<ForceTerminateCode>(
      forceTerminate.dispatch as (payload: Record<string, unknown>) => Promise<
        { code?: string } & Record<string, unknown>
      >,
      { reason: reason || "operator-triggered" },
      {
        onReply: (code) => {
          setConfirmOpen(false)
          setReason("")
          if (code === "ok") {
            toasts.add({
              variant: "success",
              title: "Enactment terminated",
              description: "The runner has stopped this enactment.",
              timeout: 4000
            })
          } else if (code === "already_terminated") {
            toasts.add({
              variant: "info",
              title: "Already terminated",
              description: "The enactment was no longer running.",
              timeout: 4000
            })
          } else {
            toasts.add({
              variant: "error",
              title: "Termination failed",
              description: "Runner rejected the force-terminate request.",
              timeout: 6000
            })
          }
        },
        onUnexpected: (cause) => {
          toasts.add({
            variant: "error",
            title: "Termination failed",
            description: cause instanceof Error ? cause.message : "Unknown error.",
            timeout: 6000
          })
        }
      }
    )
  }

  return (
    <div className="flex items-center gap-2">
      {state === "exception" ? (
        <Button
          variant="primary"
          size="sm"
          onClick={onRetry}
          disabled={retryEnactment.isPending}
          data-testid="action-retry-enactment"
        >
          {retryEnactment.isPending ? "Retrying…" : "Retry"}
        </Button>
      ) : null}
      <Button
        variant="secondary"
        size="sm"
        onClick={onTakeSnapshot}
        disabled={takeSnapshot.isPending}
        data-testid="action-take-snapshot"
      >
        {takeSnapshot.isPending ? "Snapshotting…" : "Take snapshot"}
      </Button>
      <Button
        variant="destructive"
        size="sm"
        onClick={() => setConfirmOpen(true)}
        disabled={forceTerminate.isPending}
        data-testid="action-force-terminate"
      >
        Force terminate
      </Button>

      <Dialog.Root
        open={confirmOpen}
        onOpenChange={(next) => {
          if (!next) setConfirmOpen(false)
        }}
      >
        {confirmOpen ? (
          <Dialog>
            <Dialog.Title>Force terminate enactment?</Dialog.Title>
            <Dialog.Description>
              This will terminate the enactment immediately. All in-flight workitems will
              be lost. This operation cannot be undone from the dashboard.
            </Dialog.Description>
            <div className="mt-4 flex flex-col gap-2">
              <Text variant="secondary">Termination reason (optional)</Text>
              <input
                className="rounded-md border border-cf-border bg-cf-surface px-3 py-2 text-sm text-cf-ink placeholder:text-cf-ink-faint focus:border-cf-accent focus:outline-none"
                value={reason}
                onChange={(event) => setReason(event.target.value)}
                placeholder="e.g. stuck workitem, demo reset"
                data-testid="force-terminate-reason"
              />
            </div>
            <div className="mt-6 flex justify-end gap-2">
              <Dialog.Close
                render={(props) => (
                  <Button {...props} variant="secondary">
                    Cancel
                  </Button>
                )}
              />
              <Button
                variant="destructive"
                onClick={onForceTerminate}
                disabled={forceTerminate.isPending}
                data-testid="force-terminate-confirm"
              >
                {forceTerminate.isPending ? "Terminating…" : "Confirm terminate"}
              </Button>
            </div>
          </Dialog>
        ) : null}
      </Dialog.Root>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------

function MarkingsTab({
  rows,
  replayState,
  isPending
}: {
  rows: readonly MarkingRow[]
  replayState: ColouredFlowDashboardWeb.Views.ReplayState | null
  isPending: boolean
}) {
  return (
    <div
      className={`flex flex-col gap-3 transition-opacity duration-150 ${
        isPending ? "pointer-events-none opacity-60" : "opacity-100"
      }`}
      data-testid="markings-tab"
      data-replay={replayState ? "true" : "false"}
      aria-busy={isPending}
    >
      {replayState ? (
        <div data-testid="markings-replay-banner">
          <Banner
            variant="default"
            title={
              isPending
                ? `Loading derived markings at v${replayState.version}…`
                : `Showing derived markings at v${replayState.version}`
            }
            description="Markings and diagram place tokens are pinned to this version. Workitems, occurrences, and telemetry continue to update live."
          />
        </div>
      ) : null}
      {rows.length === 0 ? (
        <Banner
          variant="default"
          title="No tokens"
          description="The enactment currently has no tokens on any place."
        />
      ) : (
        <LayerCard.Primary className="overflow-x-auto p-0">
          <Table>
            <Table.Header>
              <Table.Row>
                <Table.Head>Place</Table.Head>
                <Table.Head className="text-right">Tokens</Table.Head>
                <Table.Head>Summary</Table.Head>
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {rows.map((row) => (
                <Table.Row key={row.place}>
                  <Table.Cell>
                    <code className="text-xs text-cf-ink">{row.place}</code>
                  </Table.Cell>
                  <Table.Cell className="text-right">{row.tokens_count}</Table.Cell>
                  <Table.Cell>
                    <code className="text-xs text-cf-ink-muted">
                      {row.tokens_summary || "—"}
                    </code>
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table.Body>
          </Table>
        </LayerCard.Primary>
      )}
    </div>
  )
}

function WorkitemsTab({
  rows,
  onOpen
}: {
  rows: readonly WorkitemRow[]
  onOpen: (row: WorkitemRow) => void
}) {
  if (rows.length === 0) {
    return (
      <Banner
        variant="default"
        title="No live workitems"
        description="As the enactment fires, pending workitems appear here."
      />
    )
  }

  return (
    <LayerCard.Primary className="overflow-x-auto p-0">
      <Table>
        <Table.Header>
          <Table.Row>
            <Table.Head>Transition</Table.Head>
            <Table.Head>State</Table.Head>
            <Table.Head>Binding</Table.Head>
            <Table.Head className="text-right">Action</Table.Head>
          </Table.Row>
        </Table.Header>
        <Table.Body>
          {rows.map((row) => (
            <Table.Row key={row.id} data-testid={`workitem-row-${row.id}`}>
              <Table.Cell>
                <span className="font-medium text-cf-ink">{row.transition}</span>
              </Table.Cell>
              <Table.Cell>
                <WorkitemStateDot state={row.state} />
              </Table.Cell>
              <Table.Cell>
                <code className="text-xs text-cf-ink-muted">
                  {row.binding_summary || "—"}
                </code>
              </Table.Cell>
              <Table.Cell className="text-right">
                <Button
                  variant="secondary"
                  size="sm"
                  aria-label={`Open outputs drawer for workitem ${row.id}`}
                  onClick={() => onOpen(row)}
                >
                  Open
                </Button>
              </Table.Cell>
            </Table.Row>
          ))}
        </Table.Body>
      </Table>
    </LayerCard.Primary>
  )
}

function WorkitemStateDot({ state }: { state: "enabled" | "started" }) {
  const dot = state === "started" ? "bg-cf-dot-started" : "bg-cf-dot-enabled"
  return (
    <span className="inline-flex items-center gap-1.5 text-xs text-cf-ink">
      <span className={`h-1.5 w-1.5 rounded-full ${dot}`} />
      {state}
    </span>
  )
}

function OccurrencesTab({ rows }: { rows: readonly OccurrenceRow[] }) {
  if (rows.length === 0) {
    return (
      <Banner
        variant="default"
        title="No occurrences yet"
        description="Completed transitions appear here, newest first."
      />
    )
  }

  return (
    <LayerCard.Primary className="overflow-x-auto p-0">
      <Table>
        <Table.Header>
          <Table.Row>
            <Table.Head className="text-right">
              <abbr
                title="Per-mount stable index; not a persistent identifier. May shift across reloads."
                className="cursor-help no-underline"
              >
                Position
              </abbr>
            </Table.Head>
            <Table.Head>Transition</Table.Head>
            <Table.Head>Binding</Table.Head>
            <Table.Head>Outputs</Table.Head>
            <Table.Head>At</Table.Head>
          </Table.Row>
        </Table.Header>
        <Table.Body>
          {rows.map((row) => (
            <Table.Row key={row.id}>
              <Table.Cell className="text-right tabular-nums text-cf-ink-muted">
                {row.step_number}
              </Table.Cell>
              <Table.Cell>
                <span className="font-medium text-cf-ink">{row.transition}</span>
              </Table.Cell>
              <Table.Cell>
                <code className="text-xs text-cf-ink-muted">
                  {row.binding_summary || "—"}
                </code>
              </Table.Cell>
              <Table.Cell>
                <code className="text-xs text-cf-ink-muted">
                  {row.outputs_summary || "—"}
                </code>
              </Table.Cell>
              <Table.Cell>
                <span className="text-xs text-cf-ink-muted">
                  {row.occurred_at ? formatTimestamp(row.occurred_at) : "—"}
                </span>
              </Table.Cell>
            </Table.Row>
          ))}
        </Table.Body>
      </Table>
    </LayerCard.Primary>
  )
}

// ---------------------------------------------------------------------------
// Telemetry tab
// ---------------------------------------------------------------------------

function TelemetryTab({
  rows,
  onOpenInDebug
}: {
  rows: readonly TelemetryEntry[]
  onOpenInDebug: (transition: string | null) => void
}) {
  const [expanded, setExpanded] = useState<string | null>(null)
  const [errorsOnly, setErrorsOnly] = useState(false)

  const visibleRows = useMemo(
    () => (errorsOnly ? rows.filter((row) => row.severity === "error") : rows.slice()),
    [errorsOnly, rows]
  )

  if (rows.length === 0) {
    return (
      <Banner
        variant="default"
        title="No telemetry events yet"
        description="No telemetry events yet for this enactment."
        data-testid="telemetry-empty"
      />
    )
  }

  return (
    <div className="flex flex-col gap-3" data-testid="telemetry-tab">
      <div className="flex items-center justify-between gap-3 px-1">
        <Text variant="secondary">
          {visibleRows.length} of {rows.length} event{rows.length === 1 ? "" : "s"}
        </Text>
        <label
          className="flex items-center gap-2 text-xs text-cf-ink"
          data-testid="telemetry-errors-only-toggle"
        >
          <Checkbox
            checked={errorsOnly}
            onCheckedChange={(next) => setErrorsOnly(next === true)}
            data-testid="telemetry-errors-only-checkbox"
          />
          Errors only
        </label>
      </div>

      {visibleRows.length === 0 ? (
        <Banner
          variant="default"
          title={errorsOnly ? "No error events" : "No telemetry events yet"}
          description={
            errorsOnly
              ? "No telemetry events with error severity match the filter."
              : "No telemetry events yet for this enactment."
          }
        />
      ) : (
        <LayerCard.Primary className="overflow-x-auto p-0">
          <Table>
            <Table.Header>
              <Table.Row>
                <Table.Head className="w-6" />
                <Table.Head>At</Table.Head>
                <Table.Head>Kind</Table.Head>
                <Table.Head>Severity</Table.Head>
                <Table.Head>Summary</Table.Head>
                <Table.Head className="text-right">Action</Table.Head>
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {visibleRows.map((row) => (
                <TelemetryRow
                  key={row.id}
                  row={row}
                  expanded={expanded === row.id}
                  onToggle={() => setExpanded(expanded === row.id ? null : row.id)}
                  onOpenInDebug={onOpenInDebug}
                />
              ))}
            </Table.Body>
          </Table>
        </LayerCard.Primary>
      )}
    </div>
  )
}

function TelemetryRow({
  row,
  expanded,
  onToggle,
  onOpenInDebug
}: {
  row: TelemetryEntry
  expanded: boolean
  onToggle: () => void
  onOpenInDebug: (transition: string | null) => void
}) {
  const isError = row.severity === "error"
  return (
    <>
      <Table.Row
        data-testid={`telemetry-row-${row.id}`}
        onClick={onToggle}
        onKeyDown={(event) => {
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault()
            onToggle()
          }
        }}
        tabIndex={0}
        role="button"
        aria-expanded={expanded}
        className="cursor-pointer"
      >
        <Table.Cell>
          <span
            aria-hidden
            className={`inline-block text-cf-ink-muted transition-transform ${
              expanded ? "rotate-90" : ""
            }`}
          >
            ›
          </span>
        </Table.Cell>
        <Table.Cell>
          <span className="text-xs text-cf-ink-muted">{formatTimestamp(row.at)}</span>
        </Table.Cell>
        <Table.Cell>
          <code className="text-xs text-cf-ink">{row.kind}</code>
        </Table.Cell>
        <Table.Cell>
          <SeverityDot severity={row.severity} />
        </Table.Cell>
        <Table.Cell>{row.summary || "—"}</Table.Cell>
        <Table.Cell className="text-right">
          {isError ? (
            <Button
              variant="secondary"
              size="sm"
              onClick={(event) => {
                event.stopPropagation()
                onOpenInDebug(extractTransitionFromPayload(row.payload_json))
              }}
              data-testid={`telemetry-open-debug-${row.id}`}
            >
              Open in Debug
            </Button>
          ) : null}
        </Table.Cell>
      </Table.Row>
      {expanded ? (
        <Table.Row>
          <Table.Cell colSpan={6}>
            <div data-testid={`telemetry-payload-${row.id}`}>
              <CodeHighlighted code={prettyJson(row.payload_json)} lang="json" />
            </div>
          </Table.Cell>
        </Table.Row>
      ) : null}
    </>
  )
}

// Best-effort transition extractor: bridge payloads vary by event kind, but
// workitem-shaped events stash the bound transition under `binding_element`
// or `workitems[*].binding_element`. Falls back to null when the payload
// can't be decoded or no transition field is present — the Debug tab then
// just switches without an auto-inspect target.
function extractTransitionFromPayload(payloadJson: string): string | null {
  try {
    const payload = JSON.parse(payloadJson)
    if (!payload || typeof payload !== "object") return null
    const direct = (payload as Record<string, unknown>).transition
    if (typeof direct === "string") return direct
    const be = (payload as Record<string, unknown>).binding_element
    if (be && typeof be === "object") {
      const name = (be as Record<string, unknown>).transition
      if (typeof name === "string") return name
    }
    const items = (payload as Record<string, unknown>).workitems
    if (Array.isArray(items) && items.length > 0) {
      const first = items[0] as Record<string, unknown>
      const beFirst = first?.binding_element as Record<string, unknown> | undefined
      const name = beFirst?.transition
      if (typeof name === "string") return name
    }
    return null
  } catch {
    return null
  }
}

function SeverityDot({ severity }: { severity: "info" | "warning" | "error" }) {
  const dotMap = {
    info: "bg-cf-dot-enabled",
    warning: "bg-cf-dot-started",
    error: "bg-cf-dot-exception"
  } as const
  return (
    <span className="inline-flex items-center gap-1.5 text-xs text-cf-ink">
      <span className={`h-1.5 w-1.5 rounded-full ${dotMap[severity]}`} />
      {severity}
    </span>
  )
}

// ---------------------------------------------------------------------------
// Debug tab
// ---------------------------------------------------------------------------

type InspectCode = "ok" | "unknown_transition" | "cpnet_unavailable"

interface InspectReply extends Record<string, unknown> {
  code?: InspectCode
  info?: TransitionDebugInfo | null
  candidates?: readonly BindingCandidate[]
  transition?: string | null
}

function DebugTab({
  detail,
  transitions,
  pendingInspect,
  onInspectConsumed
}: {
  detail: DetailProxy
  transitions: readonly string[]
  pendingInspect?: string | null
  onInspectConsumed?: () => void
}) {
  const inspect = useMusubiCommand(detail, "inspect_transition")
  const toasts = useKumoToastManager()

  const [selected, setSelected] = useState<string | null>(transitions[0] ?? null)
  const [info, setInfo] = useState<TransitionDebugInfo | null>(null)
  const [candidates, setCandidates] = useState<readonly BindingCandidate[]>([])
  const [lastCode, setLastCode] = useState<InspectCode | null>(null)

  const onInspect = useCallback(async (transition: string) => {
    setSelected(transition)
    await dispatchWithReply<InspectCode>(
      inspect.dispatch as unknown as (payload: Record<string, unknown>) => Promise<InspectReply>,
      { transition },
      {
        onReply: (code, reply) => {
          const r = reply as InspectReply
          setLastCode(code)
          if (code === "ok") {
            setInfo(r.info ?? null)
            setCandidates(r.candidates ?? [])
          } else {
            setInfo(null)
            setCandidates([])
            if (code === "unknown_transition") {
              toasts.add({
                variant: "info",
                title: "Unknown transition",
                description: `No transition named "${transition}" in the cpnet.`,
                timeout: 4000
              })
            } else {
              toasts.add({
                variant: "info",
                title: "CPN definition unavailable",
                description: "Net definition has not loaded yet. Reload once telemetry arrives.",
                timeout: 4000
              })
            }
          }
        },
        onUnexpected: (cause) => {
          toasts.add({
            variant: "error",
            title: "Inspector failed",
            description: cause instanceof Error ? cause.message : "Unknown error.",
            timeout: 6000
          })
        }
      }
    )
  }, [inspect.dispatch, toasts])

  // When the parent passes a `pendingInspect` (e.g. from a NetDiagram node
  // click), auto-fire the inspector for that transition then signal the
  // parent to clear the request.
  useEffect(() => {
    if (!pendingInspect) return
    void onInspect(pendingInspect)
    onInspectConsumed?.()
  }, [pendingInspect, onInspect, onInspectConsumed])

  if (transitions.length === 0) {
    return (
      <Banner
        variant="default"
        title="No transitions to inspect"
        description="Transition list loads after the first telemetry event. Reload once the diagram appears above."
        data-testid="debug-empty"
      />
    )
  }

  return (
    <div className="flex flex-col gap-4" data-testid="debug-tab">
      <div className="flex flex-wrap items-center gap-2 rounded-xl border border-cf-border bg-cf-surface p-3">
        <Text variant="secondary">Transition</Text>
        {transitions.map((name) => (
          <Button
            key={name}
            variant={selected === name ? "primary" : "secondary"}
            size="sm"
            onClick={() => onInspect(name)}
            disabled={inspect.isPending}
            data-testid={`debug-transition-${name}`}
          >
            {name}
          </Button>
        ))}
      </div>

      {info ? <DebugInfoCard info={info} /> : null}

      {lastCode === "ok" ? (
        candidates.length === 0 ? (
          <Banner
            variant="default"
            title="No candidate bindings"
            description="The current marking produces no bindings for this transition."
            data-testid="debug-no-candidates"
          />
        ) : (
          <LayerCard.Primary className="overflow-x-auto p-0">
            <Table>
              <Table.Header>
                <Table.Row>
                  <Table.Head>Status</Table.Head>
                  <Table.Head>Binding</Table.Head>
                  <Table.Head>Reason</Table.Head>
                </Table.Row>
              </Table.Header>
              <Table.Body>
                {candidates.map((row, index) => (
                  <Table.Row key={`${row.transition}-${index}`}>
                    <Table.Cell>
                      <GuardStatusBadge status={row.guard_status} />
                    </Table.Cell>
                    <Table.Cell>
                      <code className="text-xs text-cf-ink-muted">
                        {row.binding_summary || "—"}
                      </code>
                    </Table.Cell>
                    <Table.Cell>
                      <span className="text-xs text-cf-ink-muted">
                        {row.reason ?? "—"}
                      </span>
                    </Table.Cell>
                  </Table.Row>
                ))}
              </Table.Body>
            </Table>
          </LayerCard.Primary>
        )
      ) : null}
    </div>
  )
}

function DebugInfoCard({ info }: { info: TransitionDebugInfo }) {
  return (
    <div
      className="flex flex-wrap items-center gap-3 rounded-xl border border-cf-border bg-cf-surface p-3"
      data-testid="debug-info-card"
    >
      <span className="font-medium text-cf-ink">{info.transition}</span>
      <Badge variant="neutral">candidates {info.candidates_count}</Badge>
      <Badge variant="info">enabled {info.enabled_count}</Badge>
      <Badge variant="warning">guard {info.rejected_by_guard_count}</Badge>
      <Badge variant="error">arc_eval {info.rejected_by_arc_eval_count}</Badge>
      <Badge variant="error">marking {info.rejected_by_marking_count}</Badge>
    </div>
  )
}

function GuardStatusBadge({
  status
}: {
  status: "enabled" | "rejected_by_guard" | "rejected_by_arc_eval" | "rejected_by_marking"
}) {
  switch (status) {
    case "enabled":
      return <Badge variant="info">enabled</Badge>
    case "rejected_by_guard":
      return <Badge variant="warning">rejected_by_guard</Badge>
    case "rejected_by_arc_eval":
      return <Badge variant="error">rejected_by_arc_eval</Badge>
    case "rejected_by_marking":
      return <Badge variant="error">rejected_by_marking</Badge>
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function detailBreadcrumbs(enactmentId: string) {
  return [
    { label: "Enactments", to: "/enactments" },
    { label: shortEnactmentId(enactmentId) }
  ] as const
}

// When the flow name has loaded, surface it in the H1 alongside a short id
// so operators get information density before they read the byline. When it
// hasn't loaded yet (initial mount, or the store could not resolve a name)
// fall back to the generic "Enactment" title.
function detailTitle(flowName: string | null, enactmentId: string): string {
  if (flowName && flowName !== "") {
    return `${flowName} · ${shortEnactmentId(enactmentId)}`
  }
  return "Enactment"
}

function shortEnactmentId(id: string): string {
  // Six-char prefix keeps the breadcrumb crumb visibly shorter than the full
  // id rendered below in the byline, so the two never collide visually.
  return id.length > 6 ? id.slice(0, 6) : id
}

function formatTimestamp(iso: string): string {
  try {
    return new Date(iso).toLocaleString()
  } catch {
    return iso
  }
}
