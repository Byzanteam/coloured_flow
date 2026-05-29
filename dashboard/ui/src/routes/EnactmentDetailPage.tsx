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
type EnactmentSummary = ColouredFlowDashboardWeb.Views.EnactmentSummary

type TabId = "markings" | "workitems" | "occurrences"

const TAB_ITEMS = [
  { value: "markings", label: "Markings" },
  { value: "workitems", label: "Workitems" },
  { value: "occurrences", label: "Occurrences" }
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
      {activeTab === "workitems" && (
        <WorkitemsTab rows={workitems} enactmentId={enactmentId} />
      )}
      {activeTab === "occurrences" && <OccurrencesTab rows={orderedOccurrences} />}
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
  if (rows.length === 0) {
    return (
      <Banner
        variant="default"
        title="No tokens"
        description="The enactment currently has no tokens on any place."
      />
    )
  }

  return (
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
  )
}

type WithdrawCode =
  | "ok"
  | "already_withdrawn"
  | "unknown_workitem"
  | "unsupported"
  | "runner_error"

function WorkitemsTab({
  rows,
  enactmentId
}: {
  rows: readonly WorkitemRow[]
  enactmentId: string
}) {
  const detail = useMusubiRootSuspense({
    module: ENACTMENT_DETAIL_STORE,
    id: enactmentId,
    params: { id: enactmentId }
  })
  const withdraw = useMusubiCommand(detail, "withdraw_workitem")
  const toasts = useKumoToastManager()

  if (rows.length === 0) {
    return (
      <Banner
        variant="default"
        title="No live workitems"
        description="As the enactment fires, pending workitems appear here."
      />
    )
  }

  const onWithdraw = async (workitemId: string) => {
    await dispatchWithReply<WithdrawCode>(
      withdraw.dispatch as (payload: Record<string, unknown>) => Promise<
        { code?: string } & Record<string, unknown>
      >,
      { workitem_id: workitemId },
      {
        onReply: (code, reply) => {
          switch (code) {
            case "ok":
              return
            case "already_withdrawn":
              toasts.add({
                variant: "info",
                title: "Already withdrawn",
                description: "Another operator (or the runner) already withdrew this workitem.",
                timeout: 4000
              })
              return
            case "unknown_workitem":
              toasts.add({
                variant: "info",
                title: "Unknown workitem",
                description: "The dashboard no longer tracks this workitem.",
                timeout: 4000
              })
              return
            case "unsupported": {
              const message =
                typeof reply.message === "string"
                  ? reply.message
                  : "Withdraw is not exposed by the current runner API."
              toasts.add({
                variant: "info",
                title: "Withdraw unsupported",
                description: message,
                timeout: 6000
              })
              return
            }
            case "runner_error":
            default:
              toasts.add({
                variant: "error",
                title: "Withdraw failed",
                description: typeof reply.message === "string" ? reply.message : "Runner error.",
                timeout: 6000
              })
              return
          }
        },
        onUnexpected: (cause) => {
          toasts.add({
            variant: "error",
            title: "Withdraw failed",
            description: cause instanceof Error ? cause.message : "Unknown error.",
            timeout: 6000
          })
        }
      }
    )
  }

  return (
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
          <Table.Row key={row.id}>
            <Table.Cell>{row.transition}</Table.Cell>
            <Table.Cell>
              <Badge variant={row.state === "started" ? "warning" : "info"}>{row.state}</Badge>
            </Table.Cell>
            <Table.Cell>
              <code className="text-xs">{row.binding_summary || "—"}</code>
            </Table.Cell>
            <Table.Cell className="text-right">
              <Button
                variant="secondary"
                size="sm"
                onClick={() => onWithdraw(row.id)}
                disabled={withdraw.isPending}
                aria-label={`Withdraw workitem ${row.id}`}
              >
                Withdraw
              </Button>
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
          <Table.Head className="text-right">Step</Table.Head>
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
