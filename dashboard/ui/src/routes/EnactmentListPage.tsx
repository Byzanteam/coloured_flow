import { Component, type ReactNode, Suspense, useMemo } from "react"
import { Link } from "react-router-dom"
import {
  Badge,
  Banner,
  Button,
  Empty,
  LayerCard,
  Table,
  Text
} from "@cloudflare/kumo"
import { ListChecksIcon } from "@phosphor-icons/react"

import { useMusubiRootSuspense, useMusubiSnapshot } from "../musubi"
import PageHeader from "../components/PageHeader"
import MetricsRow from "../components/MetricsRow"
import ListControls from "../components/ListControls"
import ListPagination from "../components/ListPagination"
import { useEmbedMode } from "../hooks/useEmbedMode"
import { useListSearchParams } from "../hooks/useListSearchParams"

const ENACTMENT_LIST_STORE =
  "ColouredFlowDashboardWeb.Stores.EnactmentListStore" as const

type EnactmentRow = ColouredFlowDashboardWeb.Views.EnactmentRow
type StateValue = EnactmentRow["state"]

const STATE_OPTIONS: readonly StateValue[] = ["running", "exception", "terminated"]
const STATE_PARAM = "state"
const FLOW_PARAM = "flow"

export default function EnactmentListPage() {
  return (
    <ListShell>
      <ListBoundary fallback={<ListFallback />}>
        <ListRoot />
      </ListBoundary>
    </ListShell>
  )
}

function ListRoot() {
  const store = useMusubiRootSuspense({
    module: ENACTMENT_LIST_STORE,
    id: "enactment-list"
  })
  return <ListContent store={store} />
}

type BoundaryProps = { fallback: ReactNode; children: ReactNode }
type BoundaryState = { error: Error | null }

class ListBoundary extends Component<BoundaryProps, BoundaryState> {
  state: BoundaryState = { error: null }

  static getDerivedStateFromError(error: unknown): BoundaryState {
    return { error: error instanceof Error ? error : new Error(String(error)) }
  }

  render() {
    if (this.state.error) return <ListError message={this.state.error.message} />
    return <Suspense fallback={this.props.fallback}>{this.props.children}</Suspense>
  }
}

function ListShell({ children }: { children: ReactNode }) {
  return (
    <section className="flex flex-col gap-6">
      <PageHeader
        title="Enactments"
        subtitle="Every running, terminated, or excepted enactment"
        breadcrumbs={[{ label: "Enactments" }]}
      />
      {children}
    </section>
  )
}

function ListFallback() {
  return (
    <LayerCard.Primary className="px-6 py-10">
      <Text variant="secondary">Loading enactments…</Text>
    </LayerCard.Primary>
  )
}

function ListError({ message }: { message: string }) {
  return <Banner variant="error" title="Enactment list unavailable" description={message} />
}

function rowMatchesQuery(row: EnactmentRow, q: string): boolean {
  if (q === "") return true
  const needle = q.toLowerCase()
  return (
    row.id.toLowerCase().includes(needle) ||
    (row.flow_name ?? "").toLowerCase().includes(needle)
  )
}

function ListContent({
  store
}: {
  store: ReturnType<typeof useMusubiRootSuspense<typeof ENACTMENT_LIST_STORE>>
}) {
  const snapshot = useMusubiSnapshot(store)
  const { embed } = useEmbedMode()
  const params = useListSearchParams()

  const rows: readonly EnactmentRow[] = snapshot.enactments ?? []
  const total = snapshot.total_enactments ?? 0
  const running = snapshot.running_count ?? 0
  const exception = snapshot.exception_count ?? 0
  const terminated = snapshot.terminated_count ?? 0

  const selectedStates = params.readList(STATE_PARAM)
  const selectedFlows = params.readList(FLOW_PARAM)

  const flowOptions = useMemo(() => {
    const set = new Set<string>()
    for (const row of rows) {
      if (row.flow_name) set.add(row.flow_name)
    }
    return Array.from(set).sort()
  }, [rows])

  const filteredRows = useMemo(() => {
    const stateSet = new Set(selectedStates)
    const flowSet = new Set(selectedFlows)
    return rows.filter((row) => {
      if (stateSet.size > 0 && !stateSet.has(row.state)) return false
      if (flowSet.size > 0 && !flowSet.has(row.flow_name)) return false
      if (!rowMatchesQuery(row, params.q)) return false
      return true
    })
  }, [rows, params.q, selectedStates, selectedFlows])

  const pageRows = useMemo(() => {
    const start = (params.page - 1) * params.pageSize
    return filteredRows.slice(start, start + params.pageSize)
  }, [filteredRows, params.page, params.pageSize])

  const hasActiveFilters =
    params.q !== "" || selectedStates.length > 0 || selectedFlows.length > 0

  const clearFilters = () => params.clear(["q", STATE_PARAM, FLOW_PARAM])

  return (
    <>
      {embed ? null : (
        <MetricsRow
          items={[
            { label: "Total", value: total },
            { label: "Running", value: running },
            { label: "Exception", value: exception },
            { label: "Terminated", value: terminated }
          ]}
        />
      )}

      <ListControls
        q={params.q}
        onQChange={params.setQ}
        searchPlaceholder="Search id or flow name…"
        pageSize={params.pageSize}
        onPageSizeChange={params.setPageSize}
      >
        <StateFilter
          selected={selectedStates}
          onChange={(next) => params.setList(STATE_PARAM, next)}
        />
        <FlowFilter
          options={flowOptions}
          selected={selectedFlows}
          onChange={(next) => params.setList(FLOW_PARAM, next)}
        />
      </ListControls>

      <LayerCard.Primary className="overflow-x-auto p-0">
        {rows.length === 0 ? (
          <ListEmpty />
        ) : filteredRows.length === 0 ? (
          <FiltersEmpty onClear={clearFilters} canClear={hasActiveFilters} />
        ) : (
          <RowTable rows={pageRows} />
        )}
      </LayerCard.Primary>

      <ListPagination
        page={params.page}
        pageSize={params.pageSize}
        totalCount={rows.length}
        filteredCount={filteredRows.length}
        setPage={params.setPage}
      />
    </>
  )
}

function StateFilter({
  selected,
  onChange
}: {
  selected: ReadonlyArray<string>
  onChange: (next: string[]) => void
}) {
  const set = new Set(selected)
  const toggle = (value: string) => {
    const next = new Set(set)
    if (next.has(value)) next.delete(value)
    else next.add(value)
    onChange(Array.from(next))
  }
  return (
    <div
      className="flex items-center gap-1.5"
      role="group"
      aria-label="Filter by state"
      data-testid="enactment-state-filter"
    >
      {STATE_OPTIONS.map((value) => {
        const active = set.has(value)
        return (
          <button
            key={value}
            type="button"
            onClick={() => toggle(value)}
            aria-pressed={active}
            data-testid={`enactment-state-filter-${value}`}
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

function FlowFilter({
  options,
  selected,
  onChange
}: {
  options: readonly string[]
  selected: ReadonlyArray<string>
  onChange: (next: string[]) => void
}) {
  if (options.length === 0 && selected.length === 0) return null
  return (
    <label className="flex items-center gap-2 text-[11px] font-medium uppercase tracking-[0.08em] text-cf-ink-muted">
      Flow
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
        aria-label="Filter by flow"
        data-testid="enactment-flow-filter"
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

function FiltersEmpty({
  onClear,
  canClear
}: {
  onClear: () => void
  canClear: boolean
}) {
  return (
    <div className="px-6 py-10" data-testid="enactment-list-filters-empty">
      <Empty
        size="sm"
        title="No enactments match these filters"
        description="Adjust the search, state, or flow filters to widen the result set."
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

function ListEmpty() {
  return (
    <div className="flex flex-col items-center justify-center gap-3 px-6 py-16 text-center">
      <div className="grid h-10 w-10 place-items-center rounded-full bg-cf-surface-tint text-cf-ink-muted">
        <ListChecksIcon size={18} />
      </div>
      <div className="flex flex-col gap-1">
        <p className="text-sm font-medium text-cf-ink">No enactments yet</p>
        <p className="text-xs text-cf-ink-muted">
          Start one from the Flows catalog to populate this list.
        </p>
      </div>
    </div>
  )
}

function RowTable({ rows }: { rows: readonly EnactmentRow[] }) {
  return (
    <Table>
      <Table.Header>
        <Table.Row>
          <Table.Head>Enactment</Table.Head>
          <Table.Head>Flow</Table.Head>
          <Table.Head>State</Table.Head>
          <Table.Head className="text-right">Live workitems</Table.Head>
          <Table.Head>Last activity</Table.Head>
          <Table.Head>Inserted</Table.Head>
        </Table.Row>
      </Table.Header>
      <Table.Body>
        {rows.map((row) => (
          <Table.Row key={row.id} data-testid={`enactment-row-${row.id}`}>
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
              {row.flow_name ? (
                <span className="text-sm font-medium text-cf-ink">{row.flow_name}</span>
              ) : (
                <code className="text-xs text-cf-ink-muted">{shortId(row.flow_id)}</code>
              )}
            </Table.Cell>
            <Table.Cell>
              <StateBadge state={row.state} />
            </Table.Cell>
            <Table.Cell className="text-right">
              <Badge variant={row.live_workitems > 0 ? "info" : "outline"}>
                {row.live_workitems}
              </Badge>
            </Table.Cell>
            <Table.Cell>
              <span className="text-xs text-cf-ink-muted">
                {formatTimestamp(row.updated_at)}
              </span>
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
  )
}

function StateBadge({ state }: { state: StateValue }) {
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
