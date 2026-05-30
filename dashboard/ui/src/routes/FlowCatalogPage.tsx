import { Component, type ReactNode, Suspense, useState } from "react"
import { Link, useNavigate, useParams } from "react-router-dom"
import {
  Badge,
  Banner,
  Button,
  Dialog,
  LayerCard,
  Text,
  useKumoToastManager
} from "@cloudflare/kumo"
import { GraphIcon } from "@phosphor-icons/react"
import type { StoreProxy } from "@musubi/react"

import { useMusubiCommand, useMusubiRootSuspense, useMusubiSnapshot } from "../musubi"
import { dispatchWithReply } from "../musubi/replyHandler"
import PageHeader from "../components/PageHeader"
import MetricsRow from "../components/MetricsRow"
import { useEmbedMode } from "../hooks/useEmbedMode"

const FLOW_CATALOG_STORE = "ColouredFlowDashboardWeb.Stores.FlowCatalogStore" as const

type FlowSummary = ColouredFlowDashboardWeb.Views.FlowSummary
type FlowEnactmentEntry = ColouredFlowDashboardWeb.Views.FlowEnactmentEntry
type CatalogProxy = StoreProxy<typeof FLOW_CATALOG_STORE, Musubi.Stores>

type StartReplyCode =
  | "ok"
  | "unknown_flow"
  | "no_initial_markings"
  | "storage_error"
  | "runner_error"

export default function FlowCatalogPage() {
  // The catalog index and per-flow detail share a placeholder route at
  // `/flows/:module`. Detail surface is out of scope for this phase; the
  // shell below renders the same catalog with a banner pointing the
  // operator back to the index. Avoids a second placeholder file while
  // keeping the route mapping live.
  const { module } = useParams<"module">()

  return (
    <CatalogShell>
      <CatalogBoundary fallback={<CatalogFallback />}>
        <CatalogRoot detailModule={module ?? null} />
      </CatalogBoundary>
    </CatalogShell>
  )
}

function CatalogRoot({ detailModule }: { detailModule: string | null }) {
  const catalog = useMusubiRootSuspense({
    module: FLOW_CATALOG_STORE,
    id: "default"
  })

  return <CatalogContent catalog={catalog} detailModule={detailModule} />
}

type BoundaryProps = { fallback: ReactNode; children: ReactNode }
type BoundaryState = { error: Error | null }

class CatalogBoundary extends Component<BoundaryProps, BoundaryState> {
  state: BoundaryState = { error: null }

  static getDerivedStateFromError(error: unknown): BoundaryState {
    return { error: error instanceof Error ? error : new Error(String(error)) }
  }

  render() {
    if (this.state.error) return <CatalogError message={this.state.error.message} />
    return <Suspense fallback={this.props.fallback}>{this.props.children}</Suspense>
  }
}

function CatalogShell({ children }: { children: ReactNode }) {
  return (
    <section className="flex flex-col gap-6">
      <PageHeader
        title="Flows"
        subtitle="Reusable workflow definitions and their running enactments"
      />
      {children}
    </section>
  )
}

function CatalogFallback() {
  return (
    <LayerCard.Primary className="px-6 py-10">
      <Text variant="secondary">Loading catalog…</Text>
    </LayerCard.Primary>
  )
}

function CatalogError({ message }: { message: string }) {
  return <Banner variant="error" title="Catalog unavailable" description={message} />
}

function CatalogContent({
  catalog,
  detailModule
}: {
  catalog: CatalogProxy
  detailModule: string | null
}) {
  const snapshot = useMusubiSnapshot(catalog)
  const { embed } = useEmbedMode()

  const flows: readonly FlowSummary[] = snapshot.flows ?? []
  const counts = snapshot.counts ?? { total_flows: 0, total_live_enactments: 0 }

  const [startTarget, setStartTarget] = useState<FlowSummary | null>(null)

  return (
    <>
      {embed ? null : (
        <MetricsRow
          items={[
            { label: "Flows", value: counts.total_flows },
            { label: "Live enactments", value: counts.total_live_enactments }
          ]}
        />
      )}

      {detailModule ? (
        <Banner
          variant="default"
          title={`Flow detail (${detailModule})`}
          description="A per-flow detail surface is not part of this phase. Use the catalog cards below."
        />
      ) : null}

      {flows.length === 0 ? (
        <CatalogEmpty />
      ) : (
        <div
          className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3"
          data-testid="flow-catalog-grid"
        >
          {flows.map((flow) => (
            <FlowCard key={flow.id} flow={flow} onStart={() => setStartTarget(flow)} />
          ))}
        </div>
      )}

      <StartEnactmentDialog
        catalog={catalog}
        flow={startTarget}
        onClose={() => setStartTarget(null)}
      />
    </>
  )
}

function CatalogEmpty() {
  return (
    <LayerCard.Primary className="px-6 py-10">
      <div className="flex flex-col items-center gap-3 text-center">
        <div className="grid h-10 w-10 place-items-center rounded-full bg-cf-surface-tint text-cf-ink-muted">
          <GraphIcon size={18} />
        </div>
        <div className="flex flex-col gap-1">
          <p className="text-sm font-medium text-cf-ink">No flows registered</p>
          <p className="text-xs text-cf-ink-muted">
            Seed flows on app start to populate the catalog.
          </p>
        </div>
      </div>
    </LayerCard.Primary>
  )
}

function FlowCard({
  flow,
  onStart
}: {
  flow: FlowSummary
  onStart: () => void
}) {
  const startable = flow.name !== "(unknown)" && flow.name !== ""
  return (
    <LayerCard.Primary
      className="flex h-full flex-col gap-4 px-5 py-5"
      data-testid={`flow-card-${flow.id}`}
    >
      <div className="flex flex-col gap-1">
        <div className="flex items-start justify-between gap-2">
          <h2 className="truncate text-lg font-semibold leading-tight text-cf-ink">
            {flow.name || "(unnamed)"}
          </h2>
          {flow.version ? (
            <Badge variant="outline" className="shrink-0 text-[10px]">
              v{flow.version}
            </Badge>
          ) : null}
        </div>
        <p className="text-[11px] text-cf-ink-muted">
          {flow.place_count} {flow.place_count === 1 ? "place" : "places"} ·{" "}
          {flow.transition_count}{" "}
          {flow.transition_count === 1 ? "transition" : "transitions"}
        </p>
      </div>

      <div className="flex items-center gap-2">
        <span className="text-[10px] font-medium uppercase tracking-[0.08em] text-cf-ink-faint">
          Live
        </span>
        <Badge
          variant={flow.live_enactments > 0 ? "info" : "outline"}
          className="bg-cf-accent-tint text-cf-accent-ink"
          data-testid={`flow-card-${flow.id}-live`}
        >
          {flow.live_enactments}
        </Badge>
        {flow.last_started_at ? (
          <span className="text-[11px] text-cf-ink-muted">
            · started {formatTimestamp(flow.last_started_at)}
          </span>
        ) : null}
      </div>

      <RecentEnactments rows={flow.recent_enactments ?? []} />

      <div className="mt-auto flex items-center justify-end">
        <Button
          variant="primary"
          size="sm"
          onClick={onStart}
          disabled={!startable}
          aria-label={`Start a new enactment of ${flow.name}`}
          data-testid={`flow-card-${flow.id}-start`}
        >
          Start enactment
        </Button>
      </div>
    </LayerCard.Primary>
  )
}

function RecentEnactments({ rows }: { rows: readonly FlowEnactmentEntry[] }) {
  if (rows.length === 0) {
    return (
      <p className="text-[11px] text-cf-ink-muted">
        No enactments yet for this flow.
      </p>
    )
  }
  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-[10px] font-medium uppercase tracking-[0.08em] text-cf-ink-faint">
        Recent
      </span>
      <ul className="flex flex-col gap-1">
        {rows.map((row) => (
          <li
            key={row.id}
            className="flex items-center gap-2 text-[11px] text-cf-ink-muted"
          >
            <StateDot state={row.state} />
            <Link
              to={`/enactments/${row.id}`}
              className="font-mono text-cf-ink hover:underline"
              aria-label={`Open enactment ${row.id} detail`}
            >
              {shortId(row.id)}
            </Link>
            <span className="text-[10px] text-cf-ink-faint">
              {formatTimestamp(row.inserted_at)}
            </span>
          </li>
        ))}
      </ul>
    </div>
  )
}

function StateDot({ state }: { state: "running" | "exception" | "terminated" }) {
  const dot =
    state === "running"
      ? "bg-cf-dot-started"
      : state === "exception"
        ? "bg-cf-dot-exception"
        : "bg-cf-dot-terminated"
  return <span className={`h-1.5 w-1.5 rounded-full ${dot}`} aria-label={state} />
}

// ---------------------------------------------------------------------------
// Start-enactment dialog
// ---------------------------------------------------------------------------

interface StartEnactmentDialogProps {
  catalog: CatalogProxy
  flow: FlowSummary | null
  onClose: () => void
}

function StartEnactmentDialog({ catalog, flow, onClose }: StartEnactmentDialogProps) {
  const open = flow !== null
  return (
    <Dialog.Root
      open={open}
      onOpenChange={(next) => {
        if (!next) onClose()
      }}
    >
      {flow ? <StartEnactmentDialogBody catalog={catalog} flow={flow} onClose={onClose} /> : null}
    </Dialog.Root>
  )
}

function StartEnactmentDialogBody({
  catalog,
  flow,
  onClose
}: {
  catalog: CatalogProxy
  flow: FlowSummary
  onClose: () => void
}) {
  const { dispatch, isPending } = useMusubiCommand(catalog, "start_enactment")
  const toasts = useKumoToastManager()
  const navigate = useNavigate()

  const onConfirm = async () => {
    await dispatchWithReply<StartReplyCode>(
      dispatch as unknown as (payload: Record<string, unknown>) => Promise<
        { code?: string } & Record<string, unknown>
      >,
      { flow_id: flow.id },
      {
        onReply: (code, reply) => handleReply(code, reply),
        onUnexpected: (cause) =>
          toasts.add({
            variant: "error",
            title: "Start failed",
            description:
              cause instanceof Error ? cause.message : "Command failed for an unknown reason.",
            timeout: 6000
          })
      }
    )
  }

  function handleReply(code: StartReplyCode, reply: Record<string, unknown>) {
    switch (code) {
      case "ok": {
        const enactmentId = typeof reply.enactment_id === "string" ? reply.enactment_id : null
        onClose()
        toasts.add({
          variant: "info",
          title: "Enactment started",
          description: enactmentId
            ? `Open ${shortId(enactmentId)} in the inbox or the detail page.`
            : "A new enactment is now running.",
          timeout: 5000
        })
        if (enactmentId) navigate(`/enactments/${enactmentId}`)
        return
      }
      case "unknown_flow":
      case "no_initial_markings":
      case "storage_error":
      case "runner_error":
      default: {
        const message = typeof reply.message === "string" ? reply.message : null
        onClose()
        toasts.add({
          variant: "error",
          title: replyTitle(code),
          description: message ?? replyDescription(code),
          timeout: 6000
        })
      }
    }
  }

  return (
    <Dialog size="base">
      <header className="flex flex-col gap-2 border-b border-cf-border px-6 pt-6 pb-4">
        <Dialog.Title className="text-lg font-semibold text-cf-ink">
          Start a new enactment
        </Dialog.Title>
        <Dialog.Description className="text-sm text-cf-ink-muted">
          A new enactment of <span className="font-medium text-cf-ink">{flow.name}</span>{" "}
          {flow.version ? <>(v{flow.version}) </> : null}
          will be created. You can complete its workitems from the inbox.
        </Dialog.Description>
      </header>

      <footer className="flex items-center justify-end gap-3 px-6 py-4">
        <Dialog.Close
          render={(props) => (
            <Button {...props} variant="secondary" disabled={isPending}>
              Cancel
            </Button>
          )}
        />
        <Button
          variant="primary"
          onClick={onConfirm}
          disabled={isPending}
          data-testid="flow-start-confirm"
        >
          {isPending ? "Starting…" : "Start enactment"}
        </Button>
      </footer>
    </Dialog>
  )
}

function replyTitle(code: StartReplyCode | string): string {
  switch (code) {
    case "unknown_flow":
      return "Flow not found"
    case "no_initial_markings":
      return "No initial markings"
    case "storage_error":
      return "Storage rejected the new enactment"
    case "runner_error":
      return "Runner failed to start the enactment"
    default:
      return `Reply: ${code}`
  }
}

function replyDescription(code: StartReplyCode | string): string {
  switch (code) {
    case "unknown_flow":
      return "The dashboard no longer tracks this flow. Try refreshing the catalog."
    case "no_initial_markings":
      return "This flow has no seeded initial markings, so the dashboard cannot start an enactment from it."
    case "storage_error":
      return "Storage rejected the new enactment row."
    case "runner_error":
      return "The runner returned an error while starting the enactment."
    default:
      return "Unexpected reply from the server."
  }
}

function shortId(id: string): string {
  return id.length > 8 ? `${id.slice(0, 8)}…` : id
}

function formatTimestamp(iso: string | null | undefined): string {
  if (!iso) return ""
  try {
    return new Date(iso).toLocaleString()
  } catch {
    return iso
  }
}
