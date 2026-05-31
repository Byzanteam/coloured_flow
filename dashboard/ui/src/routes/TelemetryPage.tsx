import { Component, type ReactNode, Suspense, useMemo, useState } from "react"
import {
  Badge,
  Banner,
  Button,
  Empty,
  LayerCard,
  Table,
  Text
} from "@cloudflare/kumo"
import { CodeHighlighted } from "@cloudflare/kumo/code"
import { PulseIcon } from "@phosphor-icons/react"
import { Link } from "react-router-dom"

import { useMusubiRootSuspense, useMusubiSnapshot } from "../musubi"
import PageHeader from "../components/PageHeader"
import MetricsRow from "../components/MetricsRow"
import ListControls from "../components/ListControls"
import ListPagination from "../components/ListPagination"
import { useEmbedMode } from "../hooks/useEmbedMode"
import { useListSearchParams } from "../hooks/useListSearchParams"
import { prettyJson } from "../lib/prettyJson"

const TELEMETRY_FEED_STORE = "ColouredFlowDashboardWeb.Stores.TelemetryFeedStore" as const

type Entry = ColouredFlowDashboardWeb.Views.GlobalTelemetryEntry

const EVENT_FILTER_PARAM = "event"

export default function TelemetryPage() {
  return (
    <TelemetryShell>
      <TelemetryBoundary fallback={<TelemetryFallback />}>
        <TelemetryRoot />
      </TelemetryBoundary>
    </TelemetryShell>
  )
}

function TelemetryRoot() {
  const feed = useMusubiRootSuspense({
    module: TELEMETRY_FEED_STORE,
    id: "default"
  })
  const snapshot = useMusubiSnapshot(feed)
  return <TelemetryContent snapshot={snapshot} />
}

type BoundaryProps = { fallback: ReactNode; children: ReactNode }
type BoundaryState = { error: Error | null }

class TelemetryBoundary extends Component<BoundaryProps, BoundaryState> {
  state: BoundaryState = { error: null }

  static getDerivedStateFromError(error: unknown): BoundaryState {
    return { error: error instanceof Error ? error : new Error(String(error)) }
  }

  resetError = () => this.setState({ error: null })

  render() {
    if (this.state.error)
      return <TelemetryError message={this.state.error.message} onRetry={this.resetError} />
    return <Suspense fallback={this.props.fallback}>{this.props.children}</Suspense>
  }
}

function TelemetryShell({ children }: { children: ReactNode }) {
  return (
    <section className="flex flex-col gap-6">
      <PageHeader
        title="Telemetry"
        subtitle="Live runner event stream across every enactment"
        breadcrumbs={[{ label: "Telemetry" }]}
      />
      {children}
    </section>
  )
}

function TelemetryFallback() {
  return (
    <LayerCard.Primary className="px-6 py-10">
      <Text variant="secondary">Loading telemetry feed…</Text>
    </LayerCard.Primary>
  )
}

function TelemetryError({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <div className="flex flex-col items-start gap-3" data-testid="telemetry-error">
      <Banner variant="error" title="Telemetry feed unavailable" description={message} />
      <Button
        variant="secondary"
        size="sm"
        onClick={onRetry}
        data-testid="telemetry-error-retry"
      >
        Retry
      </Button>
    </div>
  )
}

function entryMatchesQuery(entry: Entry, q: string): boolean {
  if (q === "") return true
  const needle = q.toLowerCase()
  const haystacks = [
    entry.event,
    entry.enactment_id ?? "",
    entry.flow_id ?? "",
    entry.summary
  ]
  return haystacks.some((s) => s.toLowerCase().includes(needle))
}

function TelemetryContent({
  snapshot
}: {
  snapshot: {
    entries?: readonly Entry[] | null
    total_events?: number | null
    entries_in_window?: number | null
    oldest_seq?: number | null
    newest_seq?: number | null
  }
}) {
  const { embed } = useEmbedMode()
  const params = useListSearchParams()

  const entries: readonly Entry[] = snapshot.entries ?? []
  const totalEvents = snapshot.total_events ?? 0
  const windowSize = snapshot.entries_in_window ?? entries.length

  const selectedEvents = params.readList(EVENT_FILTER_PARAM)

  const eventOptions = useMemo(() => {
    const set = new Set<string>()
    for (const entry of entries) set.add(entry.event)
    return Array.from(set).sort()
  }, [entries])

  const filteredRows = useMemo(() => {
    const eventFilter = new Set(selectedEvents)
    return entries.filter((entry) => {
      if (eventFilter.size > 0 && !eventFilter.has(entry.event)) return false
      if (!entryMatchesQuery(entry, params.q)) return false
      return true
    })
  }, [entries, params.q, selectedEvents])

  const pageRows = useMemo(() => {
    const start = (params.page - 1) * params.pageSize
    return filteredRows.slice(start, start + params.pageSize)
  }, [filteredRows, params.page, params.pageSize])

  const hasActiveFilters = params.q !== "" || selectedEvents.length > 0

  const clearFilters = () => params.clear(["q", EVENT_FILTER_PARAM])

  return (
    <>
      {embed ? null : (
        <MetricsRow
          items={[
            { label: "Events seen", value: totalEvents },
            { label: "Window", value: windowSize }
          ]}
        />
      )}

      <ListControls
        q={params.q}
        onQChange={params.setQ}
        searchPlaceholder="Search event, enactment, flow…"
        pageSize={params.pageSize}
        onPageSizeChange={params.setPageSize}
      >
        <TelemetryEventFilter
          options={eventOptions}
          selected={selectedEvents}
          onChange={(next) => params.setList(EVENT_FILTER_PARAM, next)}
        />
      </ListControls>

      <LayerCard.Primary className="overflow-x-auto p-0">
        {entries.length === 0 ? (
          <TelemetryEmpty />
        ) : filteredRows.length === 0 ? (
          <TelemetryFiltersEmpty onClear={clearFilters} canClear={hasActiveFilters} />
        ) : (
          <TelemetryTable rows={pageRows} />
        )}
      </LayerCard.Primary>

      <ListPagination
        page={params.page}
        pageSize={params.pageSize}
        totalCount={entries.length}
        filteredCount={filteredRows.length}
        setPage={params.setPage}
      />
    </>
  )
}

function TelemetryEventFilter({
  options,
  selected,
  onChange
}: {
  options: readonly string[]
  selected: ReadonlyArray<string>
  onChange: (next: string[]) => void
}) {
  if (options.length === 0 && selected.length === 0) {
    return null
  }
  return (
    <label className="flex items-center gap-2 text-[11px] font-medium uppercase tracking-[0.08em] text-cf-ink-muted">
      Event
      <select
        multiple
        size={1}
        className="min-w-[10rem] rounded-md border border-cf-border bg-cf-surface px-2 py-1 text-xs font-medium text-cf-ink outline-none focus:ring-[1.5px] focus:ring-kumo-focus/50"
        value={selected as string[]}
        onChange={(event) => {
          const next: string[] = []
          for (const opt of Array.from(event.target.selectedOptions)) {
            next.push(opt.value)
          }
          onChange(next)
        }}
        aria-label="Filter by event name"
        data-testid="telemetry-event-filter"
      >
        {options.map((name) => (
          <option key={name} value={name}>
            {name}
          </option>
        ))}
      </select>
    </label>
  )
}

function TelemetryFiltersEmpty({
  onClear,
  canClear
}: {
  onClear: () => void
  canClear: boolean
}) {
  return (
    <div className="px-6 py-10" data-testid="telemetry-filters-empty">
      <Empty
        size="sm"
        title="No events match these filters"
        description="Adjust the search or event filter to widen the result set."
        contents={
          canClear ? (
            <Button variant="secondary" size="sm" onClick={onClear}>
              Clear filters
            </Button>
          ) : null
        }
      />
    </div>
  )
}

function TelemetryEmpty() {
  return (
    <div className="flex flex-col items-center justify-center gap-3 px-6 py-16 text-center">
      <div className="grid h-10 w-10 place-items-center rounded-full bg-cf-surface-tint text-cf-ink-muted">
        <PulseIcon size={18} />
      </div>
      <div className="flex flex-col gap-1">
        <p className="text-sm font-medium text-cf-ink">No telemetry yet</p>
        <p className="text-xs text-cf-ink-muted">
          Runner events appear here as enactments fire.
        </p>
      </div>
    </div>
  )
}

function TelemetryTable({ rows }: { rows: readonly Entry[] }) {
  const [expandedId, setExpandedId] = useState<string | null>(null)
  return (
    <Table>
      <Table.Header>
        <Table.Row>
          <Table.Head>Time</Table.Head>
          <Table.Head>Event</Table.Head>
          <Table.Head>Enactment</Table.Head>
          <Table.Head>Flow</Table.Head>
          <Table.Head>Summary</Table.Head>
        </Table.Row>
      </Table.Header>
      <Table.Body>
        {rows.map((entry) => (
          <TelemetryRow
            key={entry.id}
            entry={entry}
            expanded={expandedId === entry.id}
            onToggle={() =>
              setExpandedId((prev) => (prev === entry.id ? null : entry.id))
            }
          />
        ))}
      </Table.Body>
    </Table>
  )
}

function TelemetryRow({
  entry,
  expanded,
  onToggle
}: {
  entry: Entry
  expanded: boolean
  onToggle: () => void
}) {
  return (
    <>
      <Table.Row
        data-testid={`telemetry-row-${entry.id}`}
        onClick={onToggle}
        className="cursor-pointer"
      >
        <Table.Cell>
          <span className="text-xs text-cf-ink-muted">
            {formatTimestamp(entry.occurred_at)}
          </span>
        </Table.Cell>
        <Table.Cell>
          <Badge variant={badgeVariantFor(entry.event)} className="font-mono">
            {entry.event}
          </Badge>
        </Table.Cell>
        <Table.Cell>
          {entry.enactment_id ? (
            <Link
              to={`/enactments/${entry.enactment_id}`}
              onClick={(event) => event.stopPropagation()}
              className="font-mono text-xs text-cf-ink underline-offset-2 hover:underline"
              aria-label={`Open enactment ${entry.enactment_id}`}
            >
              {shortId(entry.enactment_id)}
            </Link>
          ) : (
            <span className="text-xs text-cf-ink-faint">—</span>
          )}
        </Table.Cell>
        <Table.Cell>
          {entry.flow_id ? (
            <code className="text-xs text-cf-ink-muted">{shortId(entry.flow_id)}</code>
          ) : (
            <span className="text-xs text-cf-ink-faint">—</span>
          )}
        </Table.Cell>
        <Table.Cell>
          <span
            className="line-clamp-1 max-w-md text-xs text-cf-ink-muted"
            title={entry.summary}
          >
            {entry.summary || "—"}
          </span>
        </Table.Cell>
      </Table.Row>
      {expanded ? (
        <Table.Row data-testid={`telemetry-row-${entry.id}-expanded`}>
          <Table.Cell colSpan={5}>
            <div className="flex flex-col gap-3 bg-cf-surface-tint/30 px-3 py-3">
              <TelemetryDetailBlock label="Measurements" json={entry.measurements_json} />
              <TelemetryDetailBlock label="Metadata" json={entry.metadata_json} />
            </div>
          </Table.Cell>
        </Table.Row>
      ) : null}
    </>
  )
}

function TelemetryDetailBlock({ label, json }: { label: string; json: string }) {
  return (
    <div className="flex flex-col gap-1">
      <span className="text-[10px] font-medium uppercase tracking-[0.08em] text-cf-ink-muted">
        {label}
      </span>
      <div className="max-h-48 overflow-auto">
        <CodeHighlighted code={prettyJson(json)} lang="json" />
      </div>
    </div>
  )
}

function badgeVariantFor(event: string): "neutral" | "error" | "warning" | "info" {
  if (event.endsWith("_exception")) return "error"
  if (event === "enactment_terminate") return "warning"
  if (event === "enactment_take_snapshot") return "info"
  return "neutral"
}

function shortId(id: string): string {
  return id.length > 8 ? `${id.slice(0, 8)}…` : id
}

function formatTimestamp(iso: string): string {
  if (!iso) return ""
  try {
    return new Date(iso).toLocaleString()
  } catch {
    return iso
  }
}

