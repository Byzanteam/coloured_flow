import { Suspense, useMemo, useState } from "react"
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

import { useMusubiCommand, useMusubiRootSuspense, useMusubiSnapshot } from "../musubi"
import { dispatchWithReply } from "../musubi/replyHandler"

const ENACTMENT_DETAIL_STORE =
  "ColouredFlowDashboardWeb.Stores.EnactmentDetailStore" as const

type MarkingRow = ColouredFlowDashboardWeb.Views.MarkingRow
type WorkitemRow = ColouredFlowDashboardWeb.Views.WorkitemRow
type OccurrenceRow = ColouredFlowDashboardWeb.Views.OccurrenceRow
type TelemetryEntry = ColouredFlowDashboardWeb.Views.TelemetryEntry
type BindingCandidate = ColouredFlowDashboardWeb.Views.BindingCandidate
type TransitionDebugInfo = ColouredFlowDashboardWeb.Views.TransitionDebugInfo
type EnactmentSummary = ColouredFlowDashboardWeb.Views.EnactmentSummary

type TabId = "markings" | "workitems" | "occurrences" | "telemetry" | "debug"

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
      <section className="flex flex-col gap-4">
        <Text variant="heading1" as="h1">
          Enactment
        </Text>
        <Banner
          variant="error"
          title="Missing enactment id"
          description="Visit /enactments/<id> to view a specific enactment."
        />
      </section>
    )
  }

  return (
    <Suspense fallback={<DetailFallback enactmentId={id} />}>
      <DetailContent enactmentId={id} />
    </Suspense>
  )
}

function DetailFallback({ enactmentId }: { enactmentId: string }) {
  return (
    <section className="flex flex-col gap-4">
      <Text variant="heading1" as="h1">
        Enactment {shortId(enactmentId)}
      </Text>
      <Text variant="secondary">Loading enactment detail…</Text>
    </section>
  )
}

function DetailContent({ enactmentId }: { enactmentId: string }) {
  const detail = useMusubiRootSuspense({
    module: ENACTMENT_DETAIL_STORE,
    id: enactmentId,
    params: { id: enactmentId }
  })
  const snapshot = useMusubiSnapshot(detail)

  const summary: EnactmentSummary | undefined = snapshot.summary
  const markings: readonly MarkingRow[] = snapshot.markings ?? []
  const workitems: readonly WorkitemRow[] = snapshot.workitems ?? []
  const occurrences: readonly OccurrenceRow[] = snapshot.occurrences ?? []
  const telemetry: readonly TelemetryEntry[] = snapshot.telemetry ?? []
  const transitions: readonly string[] = snapshot.transitions ?? []

  const [activeTab, setActiveTab] = useState<TabId>("markings")

  const orderedOccurrences = useMemo(
    () => [...occurrences].sort((a, b) => b.step_number - a.step_number),
    [occurrences]
  )

  return (
    <section className="flex flex-col gap-4">
      <Header summary={summary} enactmentId={enactmentId} />
      <ActionBar enactmentId={enactmentId} />

      <Tabs
        tabs={TAB_ITEMS as unknown as Array<{ value: string; label: string }>}
        value={activeTab}
        onValueChange={(value) => setActiveTab(value as TabId)}
      />

      {activeTab === "markings" && <MarkingsTab rows={markings} />}
      {activeTab === "workitems" && <WorkitemsTab rows={workitems} />}
      {activeTab === "occurrences" && <OccurrencesTab rows={orderedOccurrences} />}
      {activeTab === "telemetry" && (
        <TelemetryTab
          rows={telemetry}
          state={summary?.state ?? "running"}
          lastExceptionBanner={summary?.last_exception_banner ?? null}
        />
      )}
      {activeTab === "debug" && (
        <DebugTab enactmentId={enactmentId} transitions={transitions} />
      )}
    </section>
  )
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

function Header({
  summary,
  enactmentId
}: {
  summary: EnactmentSummary | undefined
  enactmentId: string
}) {
  const state = summary?.state ?? "running"
  const version = summary?.version ?? 0
  const markingsCount = summary?.markings_count ?? 0
  const workitemsCount = summary?.workitems_count ?? 0

  return (
    <LayerCard className="flex flex-col gap-3 p-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-col gap-1">
          <Text variant="heading1" as="h1">
            Enactment
          </Text>
          <code className="text-xs">{enactmentId}</code>
        </div>
        <StateBadge state={state} />
      </div>
      <div className="flex flex-wrap items-center gap-4">
        <SummaryStat label="Version" value={version} />
        <SummaryStat label="Markings" value={markingsCount} />
        <SummaryStat label="Live workitems" value={workitemsCount} />
        <SummaryStat
          label="Last occurrence"
          value={summary?.last_occurrence_at ? formatTimestamp(summary.last_occurrence_at) : "—"}
        />
      </div>
    </LayerCard>
  )
}

function SummaryStat({ label, value }: { label: string; value: number | string }) {
  return (
    <div className="flex items-center gap-2">
      <Text variant="secondary">{label}</Text>
      <Text variant="body">{value}</Text>
    </div>
  )
}

function StateBadge({ state }: { state: "running" | "exception" | "terminated" }) {
  switch (state) {
    case "running":
      return <Badge variant="info">running</Badge>
    case "exception":
      return <Badge variant="warning">exception</Badge>
    case "terminated":
      return <Badge variant="neutral">terminated</Badge>
  }
}

// ---------------------------------------------------------------------------
// Action bar
// ---------------------------------------------------------------------------

type ForceTerminateCode = "ok" | "already_terminated" | "runner_error"
type TakeSnapshotCode = "ok" | "not_running" | "runner_error"

function ActionBar({ enactmentId }: { enactmentId: string }) {
  const detail = useMusubiRootSuspense({
    module: ENACTMENT_DETAIL_STORE,
    id: enactmentId,
    params: { id: enactmentId }
  })
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
    <LayerCard className="flex flex-wrap items-center justify-end gap-2 p-3">
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
                className="rounded border px-2 py-1"
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
    </LayerCard>
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
                  <code className="text-xs">{row.place}</code>
                </Table.Cell>
                <Table.Cell className="text-right">{row.tokens_count}</Table.Cell>
                <Table.Cell>
                  <code className="text-xs">{row.tokens_summary || "—"}</code>
                </Table.Cell>
              </Table.Row>
            ))}
          </Table.Body>
        </Table>
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
            <Table.Cell>{row.transition}</Table.Cell>
            <Table.Cell>
              <Badge variant={row.state === "started" ? "warning" : "info"}>{row.state}</Badge>
            </Table.Cell>
            <Table.Cell>
              <code className="text-xs">{row.binding_summary || "—"}</code>
            </Table.Cell>
          </Table.Row>
        ))}
      </Table.Body>
    </Table>
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
            <Table.Cell className="text-right">{row.step_number}</Table.Cell>
            <Table.Cell>{row.transition}</Table.Cell>
            <Table.Cell>
              <code className="text-xs">{row.binding_summary || "—"}</code>
            </Table.Cell>
            <Table.Cell>
              <code className="text-xs">{row.outputs_summary || "—"}</code>
            </Table.Cell>
            <Table.Cell>{row.occurred_at ? formatTimestamp(row.occurred_at) : "—"}</Table.Cell>
          </Table.Row>
        ))}
      </Table.Body>
    </Table>
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
        <Table.Cell>{formatTimestamp(row.at)}</Table.Cell>
        <Table.Cell>
          <Badge variant="neutral">{row.kind}</Badge>
        </Table.Cell>
        <Table.Cell>
          <SeverityBadge severity={row.severity} />
        </Table.Cell>
        <Table.Cell>{row.summary || "—"}</Table.Cell>
      </Table.Row>
      {expanded ? (
        <Table.Row>
          <Table.Cell colSpan={4}>
            <pre
              className="overflow-x-auto whitespace-pre-wrap rounded border bg-neutral-50 p-2 text-xs"
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

function SeverityBadge({ severity }: { severity: "info" | "warning" | "error" }) {
  switch (severity) {
    case "error":
      return <Badge variant="error">error</Badge>
    case "warning":
      return <Badge variant="warning">warning</Badge>
    case "info":
      return <Badge variant="info">info</Badge>
  }
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
  enactmentId,
  transitions
}: {
  enactmentId: string
  transitions: readonly string[]
}) {
  const detail = useMusubiRootSuspense({
    module: ENACTMENT_DETAIL_STORE,
    id: enactmentId,
    params: { id: enactmentId }
  })
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
                description: "Bridge cache has no flow for this enactment yet.",
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
        description="The CPN definition is not yet available. Reload after the bridge caches it."
        data-testid="debug-empty"
      />
    )
  }

  return (
    <div className="flex flex-col gap-3" data-testid="debug-tab">
      <LayerCard className="flex flex-wrap items-center gap-2 p-3">
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
      </LayerCard>

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
                    <code className="text-xs">{row.binding_summary || "—"}</code>
                  </Table.Cell>
                  <Table.Cell>{row.reason ?? "—"}</Table.Cell>
                </Table.Row>
              ))}
            </Table.Body>
          </Table>
        )
      ) : null}
    </div>
  )
}

function DebugInfoCard({ info }: { info: TransitionDebugInfo }) {
  return (
    <LayerCard className="flex flex-wrap items-center gap-3 p-3" data-testid="debug-info-card">
      <Text variant="secondary">{info.transition}</Text>
      <Badge variant="neutral">candidates {info.candidates_count}</Badge>
      <Badge variant="info">enabled {info.enabled_count}</Badge>
      <Badge variant="warning">guard {info.rejected_by_guard_count}</Badge>
      <Badge variant="error">arc_eval {info.rejected_by_arc_eval_count}</Badge>
      <Badge variant="error">marking {info.rejected_by_marking_count}</Badge>
    </LayerCard>
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

function shortId(id: string): string {
  return id.length > 8 ? `${id.slice(0, 8)}…` : id
}

function formatTimestamp(iso: string): string {
  try {
    return new Date(iso).toLocaleString()
  } catch {
    return iso
  }
}
