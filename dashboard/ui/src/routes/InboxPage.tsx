import { Component, type ReactNode, Suspense, useEffect, useMemo, useState } from "react"
import {
  Banner,
  Button,
  Empty,
  LayerCard,
  Table,
  Text
} from "@cloudflare/kumo"
import { TrayIcon } from "@phosphor-icons/react"
import { Link } from "react-router-dom"
import type { StoreProxy } from "@musubi/react"
import { useMusubiCommand, useMusubiRootSuspense, useMusubiSnapshot } from "../musubi"
import PageHeader from "../components/PageHeader"
import MetricsRow from "../components/MetricsRow"
import ListControls from "../components/ListControls"
import ListPagination from "../components/ListPagination"
import OutputsDrawer from "../components/OutputsDrawer"
import { useEmbedMode } from "../hooks/useEmbedMode"
import { useListSearchParams } from "../hooks/useListSearchParams"

const INBOX_STORE = "ColouredFlowDashboardWeb.Stores.InboxStore" as const

type WorkitemRow = ColouredFlowDashboardWeb.Views.WorkitemRow
type InboxProxy = StoreProxy<typeof INBOX_STORE, Musubi.Stores>

export default function InboxPage() {
  return (
    <InboxShell>
      <StoreBoundary fallback={<InboxFallback />}>
        <InboxRoot />
      </StoreBoundary>
    </InboxShell>
  )
}

function InboxRoot() {
  const inbox = useMusubiRootSuspense({ module: INBOX_STORE, id: "inbox" })
  return <InboxContent inbox={inbox} />
}

type StoreBoundaryProps = { fallback: ReactNode; children: ReactNode }
type StoreBoundaryState = { error: Error | null }

class StoreBoundary extends Component<StoreBoundaryProps, StoreBoundaryState> {
  state: StoreBoundaryState = { error: null }

  static getDerivedStateFromError(error: unknown): StoreBoundaryState {
    return { error: error instanceof Error ? error : new Error(String(error)) }
  }

  resetError = () => this.setState({ error: null })

  render() {
    if (this.state.error)
      return <InboxError message={this.state.error.message} onRetry={this.resetError} />
    return <Suspense fallback={this.props.fallback}>{this.props.children}</Suspense>
  }
}

function InboxShell({ children }: { children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-6">
      <PageHeader
        title="Inbox"
        subtitle="Live workitems across every enactment"
        breadcrumbs={[{ label: "Inbox" }]}
      />
      {children}
    </section>
  )
}

function InboxFallback() {
  return (
    <LayerCard.Primary className="px-6 py-10">
      <Text variant="secondary">Loading live workitems…</Text>
    </LayerCard.Primary>
  )
}

function InboxError({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <div className="flex flex-col items-start gap-3" data-testid="inbox-error">
      <Banner variant="error" title="Inbox unavailable" description={message} />
      <Button
        variant="secondary"
        size="sm"
        onClick={onRetry}
        data-testid="inbox-error-retry"
      >
        Retry
      </Button>
    </div>
  )
}

const INBOX_STATE_OPTIONS: ReadonlyArray<WorkitemRow["state"] | "exception" | "terminated"> = [
  "enabled",
  "started",
  "exception",
  "terminated"
]
const INBOX_STATE_PARAM = "state"
const INBOX_TRANSITION_PARAM = "transition"

function rowMatchesState(
  row: WorkitemRow,
  selected: ReadonlyArray<string>
): boolean {
  if (selected.length === 0) return true
  // A row "matches" the enactment lifecycle pills when its enactment_state
  // appears in the selection — that way operators can filter to e.g. just
  // exception-enactment rows even though the workitem itself is still
  // enabled/started.
  if (selected.includes(row.enactment_state)) return true
  return selected.includes(row.state)
}

function rowMatchesQuery(row: WorkitemRow, q: string): boolean {
  if (q === "") return true
  const needle = q.toLowerCase()
  const haystacks = [
    row.transition,
    row.enactment_id.slice(0, 8),
    row.binding_summary ?? ""
  ]
  return haystacks.some((s) => s.toLowerCase().includes(needle))
}

function InboxContent({ inbox }: { inbox: InboxProxy }) {
  const snapshot = useMusubiSnapshot(inbox)
  const { embed } = useEmbedMode()
  const params = useListSearchParams()
  const completeCommand = useMusubiCommand(inbox, "complete_workitem")

  const workitems: readonly WorkitemRow[] = snapshot.workitems ?? []
  const counts = snapshot.counts ?? { enabled: 0, started: 0, by_enactment: {} }
  const enactmentCount = Object.keys(counts.by_enactment ?? {}).length

  const selectedStates = params.readList(INBOX_STATE_PARAM)
  const selectedTransitions = params.readList(INBOX_TRANSITION_PARAM)

  const transitionOptions = useMemo(() => {
    const set = new Set<string>()
    for (const wi of workitems) set.add(wi.transition)
    return Array.from(set).sort()
  }, [workitems])

  const filteredRows = useMemo(() => {
    const transitionFilter = new Set(selectedTransitions)
    const stateFilter = selectedStates
    return workitems.filter((row) => {
      if (transitionFilter.size > 0 && !transitionFilter.has(row.transition)) return false
      if (!rowMatchesState(row, stateFilter)) return false
      if (!rowMatchesQuery(row, params.q)) return false
      return true
    })
  }, [workitems, params.q, selectedStates, selectedTransitions])

  const pageRows = useMemo(() => {
    const start = (params.page - 1) * params.pageSize
    return filteredRows.slice(start, start + params.pageSize)
  }, [filteredRows, params.page, params.pageSize])

  const [drawerRow, setDrawerRow] = useState<WorkitemRow | null>(null)

  // If the active row drops out of the snapshot (e.g. another operator
  // completed it via a sibling tab) clear the drawer state so the dialog
  // doesn't render against stale data.
  useEffect(() => {
    if (!drawerRow) return
    const stillLive = workitems.some((wi) => wi.id === drawerRow.id)
    if (!stillLive) setDrawerRow(null)
  }, [workitems, drawerRow])

  const hasActiveFilters =
    params.q !== "" || selectedStates.length > 0 || selectedTransitions.length > 0

  const clearFilters = () =>
    params.clear([
      "q",
      INBOX_STATE_PARAM,
      INBOX_TRANSITION_PARAM
    ])

  return (
    <>
      {embed ? null : (
        <MetricsRow
          items={[
            { label: "Enabled", value: counts.enabled },
            { label: "Started", value: counts.started },
            { label: "Enactments", value: enactmentCount }
          ]}
        />
      )}

      <ListControls
        q={params.q}
        onQChange={params.setQ}
        searchPlaceholder="Search transition, enactment, binding…"
        pageSize={params.pageSize}
        onPageSizeChange={params.setPageSize}
      >
        <InboxStateFilter
          selected={selectedStates}
          onChange={(next) => params.setList(INBOX_STATE_PARAM, next)}
        />
        <InboxTransitionFilter
          options={transitionOptions}
          selected={selectedTransitions}
          onChange={(next) => params.setList(INBOX_TRANSITION_PARAM, next)}
        />
      </ListControls>

      <LayerCard.Primary className="overflow-hidden p-0">
        {workitems.length === 0 ? (
          <InboxEmpty />
        ) : filteredRows.length === 0 ? (
          <InboxFiltersEmpty onClear={clearFilters} canClear={hasActiveFilters} />
        ) : (
          <InboxTable rows={pageRows} onOpen={setDrawerRow} />
        )}
      </LayerCard.Primary>

      <ListPagination
        page={params.page}
        pageSize={params.pageSize}
        totalCount={workitems.length}
        filteredCount={filteredRows.length}
        setPage={params.setPage}
      />

      <OutputsDrawer
        command={completeCommand}
        row={drawerRow}
        onClose={() => setDrawerRow(null)}
      />
    </>
  )
}

function InboxStateFilter({
  selected,
  onChange
}: {
  selected: ReadonlyArray<string>
  onChange: (next: string[]) => void
}) {
  const selectedSet = new Set(selected)
  const toggle = (value: string) => {
    const next = new Set(selectedSet)
    if (next.has(value)) next.delete(value)
    else next.add(value)
    onChange(Array.from(next))
  }
  return (
    <div
      className="flex items-center gap-1.5"
      role="group"
      aria-label="Filter by state"
      data-testid="inbox-state-filter"
    >
      {INBOX_STATE_OPTIONS.map((value) => {
        const active = selectedSet.has(value)
        return (
          <button
            key={value}
            type="button"
            onClick={() => toggle(value)}
            aria-pressed={active}
            data-testid={`inbox-state-filter-${value}`}
            className={
              "inline-flex h-7 items-center rounded-full border px-2.5 text-[11px] font-medium capitalize transition-colors " +
              (active
                ? "border-cf-accent-ink/60 bg-cf-accent-tint text-cf-accent-ink"
                : "border-cf-border bg-cf-surface text-cf-ink-muted hover:bg-cf-surface-tint/60")
            }
          >
            {value}
          </button>
        )
      })}
    </div>
  )
}

function InboxTransitionFilter({
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
      Transition
      <select
        multiple
        size={1}
        className="min-w-[8rem] rounded-md border border-cf-border bg-cf-surface px-2 py-1 text-xs font-medium text-cf-ink outline-none focus:ring-[1.5px] focus:ring-kumo-focus/50"
        value={selected as string[]}
        onChange={(event) => {
          const next: string[] = []
          for (const opt of Array.from(event.target.selectedOptions)) {
            next.push(opt.value)
          }
          onChange(next)
        }}
        aria-label="Filter by transition"
        data-testid="inbox-transition-filter"
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

function InboxFiltersEmpty({
  onClear,
  canClear
}: {
  onClear: () => void
  canClear: boolean
}) {
  return (
    <div className="px-6 py-10" data-testid="inbox-filters-empty">
      <Empty
        size="sm"
        title="No workitems match these filters"
        description="Adjust the search, state, or transition filters to widen the result set."
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

function InboxEmpty() {
  return (
    <div className="flex flex-col items-center justify-center gap-3 px-6 py-16 text-center">
      <div className="grid h-10 w-10 place-items-center rounded-full bg-cf-surface-tint text-cf-ink-muted">
        <TrayIcon size={18} />
      </div>
      <div className="flex flex-col gap-1">
        <p className="text-sm font-medium text-cf-ink">No live workitems</p>
        <p className="text-xs text-cf-ink-muted">
          Pending workitems appear here as enactments fire.
        </p>
      </div>
    </div>
  )
}

function InboxTable({
  rows,
  onOpen
}: {
  rows: readonly WorkitemRow[]
  onOpen: (row: WorkitemRow) => void
}) {
  return (
    <Table>
      <Table.Header>
        <Table.Row>
          <Table.Head>Transition</Table.Head>
          <Table.Head>Enactment</Table.Head>
          <Table.Head>State</Table.Head>
          <Table.Head>Binding</Table.Head>
          <Table.Head>Enabled at</Table.Head>
          <Table.Head className="text-right">Action</Table.Head>
        </Table.Row>
      </Table.Header>
      <Table.Body>
        {rows.map((row) => (
          <Table.Row key={row.id} data-testid={`inbox-row-${row.id}`}>
            <Table.Cell>
              <span className="font-medium text-cf-ink">{row.transition}</span>
            </Table.Cell>
            <Table.Cell>
              <div className="flex items-center gap-2">
                <code className="text-xs text-cf-ink-muted">
                  {shortId(row.enactment_id)}
                </code>
                <EnactmentChip state={row.enactment_state} />
              </div>
            </Table.Cell>
            <Table.Cell>
              <StateDot state={row.state} />
            </Table.Cell>
            <Table.Cell>
              <code className="text-xs text-cf-ink-muted">
                {row.binding_summary || "—"}
              </code>
            </Table.Cell>
            <Table.Cell>
              <span className="text-xs text-cf-ink-muted">
                {formatTimestamp(row.enabled_at)}
              </span>
            </Table.Cell>
            <Table.Cell className="text-right">
              {row.enactment_state !== "running" ? (
                <Link
                  to={`/enactments/${row.enactment_id}`}
                  aria-label={`Open enactment ${row.enactment_id} detail`}
                  data-testid={`inbox-open-detail-${row.id}`}
                  className={
                    row.enactment_state === "exception"
                      ? "inline-flex h-7 items-center rounded-md border border-cf-exception-ink/60 bg-cf-exception-bg px-2.5 text-xs font-medium text-cf-exception-ink hover:bg-cf-exception-bg/80"
                      : "inline-flex h-7 items-center rounded-md border border-cf-border bg-cf-surface px-2.5 text-xs font-medium text-cf-ink-muted hover:bg-cf-surface/80"
                  }
                >
                  Open detail
                </Link>
              ) : (
                <Button
                  variant="secondary"
                  size="sm"
                  aria-label={`Open outputs drawer for workitem ${row.id}`}
                  onClick={() => onOpen(row)}
                >
                  Open
                </Button>
              )}
            </Table.Cell>
          </Table.Row>
        ))}
      </Table.Body>
    </Table>
  )
}

function StateDot({ state }: { state: "enabled" | "started" }) {
  const dot = state === "started" ? "bg-cf-dot-started" : "bg-cf-dot-enabled"
  return (
    <span className="inline-flex items-center gap-1.5 text-xs text-cf-ink">
      <span className={`h-1.5 w-1.5 rounded-full ${dot}`} />
      {state}
    </span>
  )
}

function EnactmentChip({
  state
}: {
  state: "running" | "exception" | "terminated"
}) {
  if (state === "running") return null
  if (state === "exception") {
    return (
      <span
        className="inline-flex items-center gap-1.5 rounded-full border border-cf-exception-ink/50 bg-cf-exception-bg px-2 py-0.5 text-[11px] font-medium text-cf-exception-ink"
        data-testid="inbox-enactment-chip-exception"
      >
        <span className="h-1.5 w-1.5 rounded-full bg-cf-dot-exception" />
        Exception
      </span>
    )
  }
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full border border-cf-border bg-cf-surface px-2 py-0.5 text-[11px] font-medium text-cf-ink-muted"
      data-testid="inbox-enactment-chip-terminated"
    >
      <span className="h-1.5 w-1.5 rounded-full bg-cf-dot-terminated" />
      Terminated
    </span>
  )
}


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
