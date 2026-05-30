import { Component, type ReactNode, Suspense, useState } from "react"
import { Link, useNavigate, useParams } from "react-router-dom"
import {
  Badge,
  Banner,
  Button,
  Dialog,
  LayerCard,
  Table,
  Text,
  useKumoToastManager
} from "@cloudflare/kumo"
import type { StoreProxy } from "@musubi/react"

import { useMusubiCommand, useMusubiRootSuspense, useMusubiSnapshot } from "../musubi"
import { dispatchWithReply } from "../musubi/replyHandler"
import PageHeader from "../components/PageHeader"
import NetDiagram from "../components/NetDiagram"

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

export default function FlowDetailPage() {
  const { flow_id } = useParams<"flow_id">()
  const id = flow_id ?? ""

  return (
    <DetailShell>
      <DetailBoundary fallback={<DetailFallback />}>
        <DetailRoot flowId={id} />
      </DetailBoundary>
    </DetailShell>
  )
}

function DetailRoot({ flowId }: { flowId: string }) {
  // Reuses the FlowCatalogStore singleton root (per Requirements: "/flows,
  // /flows/:module → FlowCatalogStore"). The store streams every flow into
  // `flows`; we filter to the requested id client-side.
  const catalog = useMusubiRootSuspense({
    module: FLOW_CATALOG_STORE,
    id: "default"
  })
  return <DetailContent catalog={catalog} flowId={flowId} />
}

type BoundaryProps = { fallback: ReactNode; children: ReactNode }
type BoundaryState = { error: Error | null }

class DetailBoundary extends Component<BoundaryProps, BoundaryState> {
  state: BoundaryState = { error: null }

  static getDerivedStateFromError(error: unknown): BoundaryState {
    return { error: error instanceof Error ? error : new Error(String(error)) }
  }

  render() {
    if (this.state.error) return <DetailError message={this.state.error.message} />
    return <Suspense fallback={this.props.fallback}>{this.props.children}</Suspense>
  }
}

function DetailShell({ children }: { children: ReactNode }) {
  return <section className="flex flex-col gap-6">{children}</section>
}

function DetailFallback() {
  return (
    <LayerCard.Primary className="px-6 py-10">
      <Text variant="secondary">Loading flow…</Text>
    </LayerCard.Primary>
  )
}

function DetailError({ message }: { message: string }) {
  return (
    <>
      <PageHeader
        title="Flow"
        breadcrumbs={[{ label: "Flows", to: "/flows" }, { label: "Error" }]}
      />
      <Banner variant="error" title="Flow detail unavailable" description={message} />
    </>
  )
}

function DetailContent({ catalog, flowId }: { catalog: CatalogProxy; flowId: string }) {
  const snapshot = useMusubiSnapshot(catalog)
  const flows: readonly FlowSummary[] = snapshot.flows ?? []
  const flow = flows.find((f) => f.id === flowId) ?? null

  if (!flow) return <NotFoundBody flowId={flowId} />

  return <FoundBody catalog={catalog} flow={flow} />
}

function NotFoundBody({ flowId }: { flowId: string }) {
  return (
    <>
      <PageHeader
        title="Flow not found"
        breadcrumbs={[{ label: "Flows", to: "/flows" }, { label: "Not found" }]}
      />
      <Banner
        variant="alert"
        title="No flow matches that id"
        description={
          flowId
            ? `The dashboard does not track a flow with id ${flowId}.`
            : "Missing flow id in the URL."
        }
      />
      <Link
        to="/flows"
        className="text-sm font-medium text-cf-accent-ink hover:underline"
        data-testid="flow-detail-back-to-flows"
      >
        ← Back to Flows
      </Link>
    </>
  )
}

function FoundBody({ catalog, flow }: { catalog: CatalogProxy; flow: FlowSummary }) {
  const [startOpen, setStartOpen] = useState(false)
  const startable = flow.name !== "(unknown)" && flow.name !== ""

  return (
    <>
      <PageHeader
        title={flow.name || "(unnamed)"}
        breadcrumbs={[{ label: "Flows", to: "/flows" }, { label: flow.name || "(unnamed)" }]}
        subtitle={
          <span className="text-xs text-cf-ink-muted">
            {flow.place_count} {flow.place_count === 1 ? "place" : "places"} ·{" "}
            {flow.transition_count}{" "}
            {flow.transition_count === 1 ? "transition" : "transitions"}
          </span>
        }
        byline={
          <div className="flex items-center gap-2">
            {flow.version ? (
              <Badge variant="outline" className="text-[10px]">
                v{flow.version}
              </Badge>
            ) : null}
            <Badge
              variant={flow.live_enactments > 0 ? "info" : "outline"}
              className="bg-cf-accent-tint text-cf-accent-ink"
              data-testid="flow-detail-live-count"
            >
              {flow.live_enactments} live
            </Badge>
          </div>
        }
        actions={
          <Button
            variant="primary"
            size="sm"
            disabled={!startable}
            onClick={() => setStartOpen(true)}
            aria-label={`Start a new enactment of ${flow.name}`}
            data-testid="flow-detail-start"
          >
            Start enactment
          </Button>
        }
      />

      <LayerCard.Primary
        className="flex h-[420px] flex-col overflow-hidden p-0"
        data-testid="flow-detail-diagram-card"
      >
        <div className="flex-1 min-h-0">
          <NetDiagram diagram={flow.diagram} />
        </div>
      </LayerCard.Primary>

      <EnactmentsSection rows={flow.enactments ?? []} />

      <StartEnactmentDialog
        catalog={catalog}
        flow={startOpen ? flow : null}
        onClose={() => setStartOpen(false)}
      />
    </>
  )
}

function EnactmentsSection({ rows }: { rows: readonly FlowEnactmentEntry[] }) {
  return (
    <LayerCard.Primary
      className="overflow-hidden p-0"
      data-testid="flow-detail-enactments"
    >
      <div className="flex items-center justify-between border-b border-cf-border px-5 py-3">
        <div className="flex flex-col">
          <span className="text-sm font-semibold text-cf-ink">Enactments</span>
          <span className="text-[11px] text-cf-ink-muted">
            {rows.length} {rows.length === 1 ? "enactment" : "enactments"}
          </span>
        </div>
      </div>
      {rows.length === 0 ? (
        <div className="px-6 py-8 text-center">
          <p className="text-sm text-cf-ink-muted">No enactments yet for this flow.</p>
        </div>
      ) : (
        <Table>
          <Table.Header>
            <Table.Row>
              <Table.Head>Enactment</Table.Head>
              <Table.Head>State</Table.Head>
              <Table.Head>Started</Table.Head>
            </Table.Row>
          </Table.Header>
          <Table.Body>
            {rows.map((row) => (
              <Table.Row
                key={row.id}
                data-testid={`flow-detail-enactment-row-${row.id}`}
              >
                <Table.Cell>
                  <Link
                    to={`/enactments/${row.id}`}
                    aria-label={`Open enactment ${row.id} detail`}
                    className="font-mono text-xs text-cf-ink hover:underline"
                  >
                    {shortId(row.id)}
                  </Link>
                </Table.Cell>
                <Table.Cell>
                  <StateBadge state={row.state} />
                </Table.Cell>
                <Table.Cell>
                  <span className="text-xs text-cf-ink-muted">
                    {formatTimestamp(row.inserted_at)}
                  </span>
                </Table.Cell>
              </Table.Row>
            ))}
          </Table.Body>
        </Table>
      )}
    </LayerCard.Primary>
  )
}

function StateBadge({ state }: { state: "running" | "exception" | "terminated" }) {
  const dot =
    state === "running"
      ? "bg-cf-dot-started"
      : state === "exception"
        ? "bg-cf-dot-exception"
        : "bg-cf-dot-terminated"
  return (
    <span className="inline-flex items-center gap-1.5 text-xs capitalize text-cf-ink">
      <span className={`h-1.5 w-1.5 rounded-full ${dot}`} />
      {state}
    </span>
  )
}

// ---------------------------------------------------------------------------
// Start-enactment dialog (mirrors FlowCatalogPage's dialog)
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
      {flow ? (
        <StartEnactmentDialogBody catalog={catalog} flow={flow} onClose={onClose} />
      ) : null}
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
          data-testid="flow-detail-start-confirm"
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
