import { useMemo, useState } from "react"
import { useParams } from "react-router-dom"
import {
  Badge,
  Banner,
  Button,
  Dialog,
  LayerCard,
  Table,
  Tabs,
  Text,
  useKumoToastManager
} from "@cloudflare/kumo"
import type { MusubiRootMount } from "@musubi/react"

import { useMusubiCommand, useMusubiRoot, useMusubiSnapshot } from "../musubi"
import { dispatchWithReply } from "../musubi/replyHandler"
import PageHeader from "../components/PageHeader"
import MetricsRow from "../components/MetricsRow"
import NetDiagram from "../components/NetDiagram"

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

type DetailRootMount = MusubiRootMount<typeof ENACTMENT_DETAIL_STORE, Musubi.Stores>
type DetailProxy = NonNullable<Extract<DetailRootMount, { status: "ready" }>["store"]>

type TabId = "markings" | "workitems" | "occurrences" | "telemetry" | "debug"

const TAB_ITEMS = [
  { value: "markings", label: "Markings" },
  { value: "workitems", label: "Workitems" },
  { value: "occurrences", label: "Occurrences" },
  { value: "telemetry", label: "Telemetry" },
  { value: "debug", label: "Debug" }
] as const

// `useMusubiRoot` (commit-phase effect) instead of `useMusubiRootSuspense`
// (render-phase throw + setTimeout(0) orphan sweep) — the latter spin-loops
// against React 19 passive-effect scheduling on @musubi/react@0.6.0.
// See `InboxPage.tsx` for the full analysis.
export default function EnactmentDetailPage() {
  const { id } = useParams<"id">()

  if (!id) {
    return (
      <section className="flex flex-col gap-6">
        <PageHeader title="Enactment" />
        <Banner
          variant="error"
          title="Missing enactment id"
          description="Visit /enactments/<id> to view a specific enactment."
        />
      </section>
    )
  }

  return <DetailRoot enactmentId={id} />
}

function DetailRoot({ enactmentId }: { enactmentId: string }) {
  const root = useMusubiRoot({
    module: ENACTMENT_DETAIL_STORE,
    id: enactmentId,
    params: { id: enactmentId }
  })

  if (root.status === "error") {
    return <DetailError enactmentId={enactmentId} message={root.error.message} />
  }

  if (root.status !== "ready") {
    return <DetailFallback enactmentId={enactmentId} />
  }

  return <DetailContent detail={root.store} enactmentId={enactmentId} />
}

function DetailFallback({ enactmentId }: { enactmentId: string }) {
  return (
    <section className="flex flex-col gap-6">
      <PageHeader
        title="Enactment"
        byline={<code className="text-xs text-cf-ink-muted">{enactmentId}</code>}
      />
      <LayerCard.Primary className="px-6 py-10">
        <Text variant="secondary">Loading enactment detail…</Text>
      </LayerCard.Primary>
    </section>
  )
}

function DetailError({ enactmentId, message }: { enactmentId: string; message: string }) {
  return (
    <section className="flex flex-col gap-6">
      <PageHeader
        title="Enactment"
        byline={<code className="text-xs text-cf-ink-muted">{enactmentId}</code>}
      />
      <Banner variant="error" title="Detail unavailable" description={message} />
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

  const summary: EnactmentSummary | undefined = snapshot.summary
  const markings: readonly MarkingRow[] = snapshot.markings ?? []
  const workitems: readonly WorkitemRow[] = snapshot.workitems ?? []
  const occurrences: readonly OccurrenceRow[] = snapshot.occurrences ?? []
  const telemetry: readonly TelemetryEntry[] = snapshot.telemetry ?? []
  const transitions: readonly string[] = snapshot.transitions ?? []
  const diagram: DiagramPayload | null = snapshot.diagram ?? null

  const [activeTab, setActiveTab] = useState<TabId>("markings")

  const orderedOccurrences = useMemo(
    () => [...occurrences].sort((a, b) => b.step_number - a.step_number),
    [occurrences]
  )

  const state = summary?.state ?? "running"

  return (
    <section className="flex flex-col gap-6">
      <PageHeader
        title="Enactment"
        byline={
          <div className="flex flex-wrap items-center gap-2">
            <code className="text-xs text-cf-ink-muted">{enactmentId}</code>
            <StateBadge state={state} />
          </div>
        }
        actions={<ActionBar detail={detail} />}
      />

      <MetricsRow
        items={[
          { label: "Version", value: summary?.version ?? 0 },
          { label: "Markings", value: summary?.markings_count ?? 0 },
          { label: "Live workitems", value: summary?.workitems_count ?? 0 },
          {
            label: "Last occurrence",
            value: summary?.last_occurrence_at
              ? formatTimestamp(summary.last_occurrence_at)
              : "—"
          }
        ]}
      />

      <LayerCard.Primary
        className="overflow-hidden p-0"
        data-testid="net-diagram-card"
      >
        <div className="h-[440px] w-full">
          <NetDiagram diagram={diagram} enactmentState={state} />
        </div>
      </LayerCard.Primary>

      <div className="border-b border-cf-border">
        <Tabs
          variant="underline"
          tabs={TAB_ITEMS as unknown as Array<{ value: string; label: string }>}
          value={activeTab}
          onValueChange={(value) => setActiveTab(value as TabId)}
        />
      </div>

      <div className="flex flex-col gap-4">
        {activeTab === "markings" && <MarkingsTab rows={markings} />}
        {activeTab === "workitems" && <WorkitemsTab rows={workitems} />}
        {activeTab === "occurrences" && <OccurrencesTab rows={orderedOccurrences} />}
        {activeTab === "telemetry" && (
          <TelemetryTab
            rows={telemetry}
            state={state}
            lastExceptionBanner={summary?.last_exception_banner ?? null}
          />
        )}
        {activeTab === "debug" && (
          <DebugTab detail={detail} transitions={transitions} />
        )}
      </div>
    </section>
  )
}

// ---------------------------------------------------------------------------
// Status + summary
// ---------------------------------------------------------------------------

function StateBadge({ state }: { state: "running" | "exception" | "terminated" }) {
  const dotMap = {
    running: "bg-cf-dot-enabled",
    exception: "bg-cf-dot-exception",
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

function ActionBar({ detail }: { detail: DetailProxy }) {
  const toasts = useKumoToastManager()

  const forceTerminate = useMusubiCommand(detail, "force_terminate")
  const takeSnapshot = useMusubiCommand(detail, "take_snapshot")

  const [confirmOpen, setConfirmOpen] = useState(false)
  const [reason, setReason] = useState("")

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
    <div className="flex items-center gap-1.5">
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
              Stops the runner GenServer for this enactment. Any in-flight workitems are
              abandoned. This operation cannot be undone from the dashboard.
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

function MarkingsTab({ rows }: { rows: readonly MarkingRow[] }) {
  return (
    <div className="flex flex-col gap-3" data-testid="markings-tab">
      <Banner
        variant="alert"
        title="Markings are mount-time-accurate"
        description="Live workitem events do not refresh this view. Click Take snapshot in the action bar, then reload this page to refresh the markings after recent activity."
        data-testid="markings-stale-banner"
      />
      {rows.length === 0 ? (
        <Banner
          variant="default"
          title="No tokens"
          description="The enactment currently has no tokens on any place."
        />
      ) : (
        <LayerCard.Primary className="overflow-hidden p-0">
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

function WorkitemsTab({ rows }: { rows: readonly WorkitemRow[] }) {
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
    <LayerCard.Primary className="overflow-hidden p-0">
      <Table>
        <Table.Header>
          <Table.Row>
            <Table.Head>Transition</Table.Head>
            <Table.Head>State</Table.Head>
            <Table.Head>Binding</Table.Head>
          </Table.Row>
        </Table.Header>
        <Table.Body>
          {rows.map((row) => (
            <Table.Row key={row.id}>
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
    <LayerCard.Primary className="overflow-hidden p-0">
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
  state,
  lastExceptionBanner: bannerFromSummary
}: {
  rows: readonly TelemetryEntry[]
  state: "running" | "exception" | "terminated"
  lastExceptionBanner: string | null
}) {
  const [expanded, setExpanded] = useState<string | null>(null)

  const orderedRows = useMemo(() => rows.slice(), [rows])
  const lastExceptionBanner = useMemo(() => {
    if (state !== "exception") return null
    return bannerFromSummary ?? "Enactment is in an exception state."
  }, [bannerFromSummary, state])

  if (rows.length === 0 && !lastExceptionBanner) {
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
      {lastExceptionBanner ? (
        <Banner
          variant="error"
          title="Enactment exception"
          description={lastExceptionBanner}
          data-testid="telemetry-exception-banner"
        />
      ) : null}

      {orderedRows.length === 0 ? (
        <Banner
          variant="default"
          title="No telemetry events yet"
          description="No telemetry events yet for this enactment."
        />
      ) : (
        <LayerCard.Primary className="overflow-hidden p-0">
          <Table>
            <Table.Header>
              <Table.Row>
                <Table.Head>At</Table.Head>
                <Table.Head>Kind</Table.Head>
                <Table.Head>Severity</Table.Head>
                <Table.Head>Summary</Table.Head>
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {orderedRows.map((row) => (
                <TelemetryRow
                  key={row.id}
                  row={row}
                  expanded={expanded === row.id}
                  onToggle={() => setExpanded(expanded === row.id ? null : row.id)}
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
  onToggle
}: {
  row: TelemetryEntry
  expanded: boolean
  onToggle: () => void
}) {
  return (
    <>
      <Table.Row
        data-testid={`telemetry-row-${row.id}`}
        onClick={onToggle}
        className="cursor-pointer"
      >
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
      </Table.Row>
      {expanded ? (
        <Table.Row>
          <Table.Cell colSpan={4}>
            <pre
              className="overflow-x-auto whitespace-pre-wrap rounded-md border border-cf-border bg-cf-canvas p-3 text-xs text-cf-ink"
              data-testid={`telemetry-payload-${row.id}`}
            >
              {row.payload_json}
            </pre>
          </Table.Cell>
        </Table.Row>
      ) : null}
    </>
  )
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
  transitions
}: {
  detail: DetailProxy
  transitions: readonly string[]
}) {
  const inspect = useMusubiCommand(detail, "inspect_transition")
  const toasts = useKumoToastManager()

  const [selected, setSelected] = useState<string | null>(transitions[0] ?? null)
  const [info, setInfo] = useState<TransitionDebugInfo | null>(null)
  const [candidates, setCandidates] = useState<readonly BindingCandidate[]>([])
  const [lastCode, setLastCode] = useState<InspectCode | null>(null)

  const onInspect = async (transition: string) => {
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
  }

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
          <LayerCard.Primary className="overflow-hidden p-0">
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

function formatTimestamp(iso: string): string {
  try {
    return new Date(iso).toLocaleString()
  } catch {
    return iso
  }
}
