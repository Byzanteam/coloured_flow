import { Component, type ReactNode, Suspense, useEffect, useMemo, useState } from "react"
import {
  Badge,
  Banner,
  Button,
  Checkbox,
  ClipboardText,
  CodeBlock,
  Empty,
  Input,
  InputArea,
  LayerCard,
  Table,
  Text,
  useKumoToastManager
} from "@cloudflare/kumo"
import { Dialog } from "@base-ui/react/dialog"
import { TrayIcon } from "@phosphor-icons/react"
import { Link } from "react-router-dom"
import type { StoreProxy } from "@musubi/react"
import { useMusubiCommand, useMusubiRootSuspense, useMusubiSnapshot } from "../musubi"
import { dispatchWithReply } from "../musubi/replyHandler"
import PageHeader from "../components/PageHeader"
import MetricsRow from "../components/MetricsRow"
import ListControls from "../components/ListControls"
import ListPagination from "../components/ListPagination"
import { useEmbedMode } from "../hooks/useEmbedMode"
import { useListSearchParams } from "../hooks/useListSearchParams"

const INBOX_STORE = "ColouredFlowDashboardWeb.Stores.InboxStore" as const

type WorkitemRow = ColouredFlowDashboardWeb.Views.WorkitemRow
type OutputVar = ColouredFlowDashboardWeb.Views.OutputVar
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
  const inbox = useMusubiRootSuspense({ module: INBOX_STORE, id: "default" })
  return <InboxContent inbox={inbox} />
}

type StoreBoundaryProps = { fallback: ReactNode; children: ReactNode }
type StoreBoundaryState = { error: Error | null }

class StoreBoundary extends Component<StoreBoundaryProps, StoreBoundaryState> {
  state: StoreBoundaryState = { error: null }

  static getDerivedStateFromError(error: unknown): StoreBoundaryState {
    return { error: error instanceof Error ? error : new Error(String(error)) }
  }

  render() {
    if (this.state.error) return <InboxError message={this.state.error.message} />
    return <Suspense fallback={this.props.fallback}>{this.props.children}</Suspense>
  }
}

function InboxShell({ children }: { children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-6">
      <PageHeader title="Inbox" subtitle="Live workitems across every enactment" />
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

function InboxError({ message }: { message: string }) {
  return <Banner variant="error" title="Inbox unavailable" description={message} />
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
        inbox={inbox}
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

// ---------------------------------------------------------------------------
// Outputs drawer
// ---------------------------------------------------------------------------

interface OutputsDrawerProps {
  inbox: InboxProxy
  row: WorkitemRow | null
  onClose: () => void
}

function OutputsDrawer({ inbox, row, onClose }: OutputsDrawerProps) {
  const open = row !== null
  return (
    <Dialog.Root open={open} onOpenChange={(next) => { if (!next) onClose() }}>
      <Dialog.Portal>
        <Dialog.Backdrop className="fixed inset-0 bg-black/40 transition-opacity duration-200 ease-out data-[starting-style]:opacity-0 data-[ending-style]:opacity-0" />
        {row ? <OutputsDrawerBody inbox={inbox} row={row} onClose={onClose} /> : null}
      </Dialog.Portal>
    </Dialog.Root>
  )
}

function OutputsDrawerBody({
  inbox,
  row,
  onClose
}: {
  inbox: InboxProxy
  row: WorkitemRow
  onClose: () => void
}) {
  const { dispatch, isPending, reset } = useMusubiCommand(inbox, "complete_workitem")
  const toasts = useKumoToastManager()

  const schema: readonly OutputVar[] = row.output_vars ?? []
  const initialValues = useMemo(() => buildInitialValues(schema), [schema])
  const [values, setValues] = useState<Record<string, FieldValue>>(initialValues)

  // Inline banner only for *actionable* server replies the operator can fix
  // by editing the form (unknown_variable, invalid_outputs, type_mismatch).
  // Transient errors (race losses, runner exceptions) surface as toasts so
  // the drawer either closes (race) or stays open without claiming a
  // specific field is wrong.
  const [inlineBanner, setInlineBanner] = useState<{
    title: string
    description: string
  } | null>(null)

  // Per-field validation. Derived on every render so submit stays disabled
  // the instant a field becomes invalid — no blur required (the M2b r3
  // pattern carried over).
  const fieldErrors = useMemo(() => validateValues(schema, values), [schema, values])
  const isValid = useMemo(
    () => Object.values(fieldErrors).every((err) => err === null),
    [fieldErrors]
  )

  // New row → reset form + clear stale banner state.
  useEffect(() => {
    setValues(initialValues)
    setInlineBanner(null)
    reset()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [row.id, initialValues])

  const onSubmit = async () => {
    if (!isValid) return

    setInlineBanner(null)

    const outputs = serializeValues(schema, values)

    await dispatchWithReply<ReplyCode>(
      dispatch as (payload: Record<string, unknown>) => Promise<{ code?: string } & Record<string, unknown>>,
      { workitem_id: row.id, outputs },
      {
        onReply: handleReply,
        onUnexpected: (cause) => {
          toasts.add({
            variant: "error",
            title: "Submission failed",
            description:
              cause instanceof Error ? cause.message : "Command failed for an unknown reason.",
            timeout: 6000
          })
        }
      }
    )
  }

  function handleReply(code: ReplyCode, reply: Record<string, unknown>) {
    switch (code) {
      case "ok":
        onClose()
        return

      // Race: another operator (or the runner) already moved this workitem.
      // Server cleared the meta; the row is gone from the snapshot. Collapse
      // both reply codes into the same "already handled" outcome so the UI
      // does not leak server-side bookkeeping (`unknown_workitem` vs
      // `already_completed`) into the operator's mental model.
      case "already_completed":
      case "unknown_workitem":
        onClose()
        toasts.add({
          variant: "info",
          title: "Already handled",
          description: "Another operator handled this workitem before you submitted.",
          timeout: 4000
        })
        return

      // Actionable: operator can fix by editing the form. Keep the drawer
      // open and surface inline so the message sits next to the controls.
      case "unknown_variable":
      case "invalid_outputs":
      case "type_mismatch":
      case "invalid_elixir":
        setInlineBanner({
          title: replyTitle(code),
          description: replyDescription(code, reply)
        })
        return

      // Runner exception path: not actionable from the drawer (e.g. action
      // function raised). Toast — operator should consult enactment detail.
      case "runner_error":
      default:
        toasts.add({
          variant: "error",
          title: replyTitle(code),
          description: replyDescription(code, reply),
          timeout: 6000
        })
        return
    }
  }

  const submitDisabled = isPending || !isValid

  return (
    <Dialog.Popup
      className="fixed top-0 right-0 h-screen w-full sm:w-[28rem] flex flex-col bg-cf-surface border-l border-cf-border outline-none focus:outline-none shadow-2xl transition-transform duration-200 ease-out data-[starting-style]:translate-x-full data-[ending-style]:translate-x-full"
    >
      <header className="flex flex-col gap-3 border-b border-cf-border bg-cf-surface px-6 pt-6 pb-4">
        <div className="flex items-center gap-3">
          <Dialog.Title className="flex-1 text-lg font-semibold leading-tight text-cf-ink">
            Complete workitem · {row.transition}
          </Dialog.Title>
          <Badge
            variant={row.state === "started" ? "info" : "outline"}
            className="capitalize"
          >
            {row.state}
          </Badge>
        </div>
        <Dialog.Description className="text-xs leading-relaxed text-cf-ink-muted">
          Fill in the free variables the runner needs to fire this transition. Controls
          below come from the transition's output-arc inscriptions.
        </Dialog.Description>
        <div className="flex items-center gap-2">
          <span className="text-[10px] font-medium uppercase tracking-[0.08em] text-cf-ink-muted">
            Workitem
          </span>
          <ClipboardText
            text={row.id}
            size="sm"
            className="font-mono text-[11px] text-cf-ink"
            tooltip={{ text: "Copy", copiedText: "Copied" }}
            labels={{ copyAction: `Copy workitem id ${row.id}` }}
          />
        </div>
      </header>

      <section className="flex flex-col gap-3 border-b border-cf-border bg-cf-surface-tint/40 px-6 py-4">
        <DrawerMetaRow label="Enactment">
          <div className="flex items-center gap-2">
            <code className="font-mono text-xs text-cf-ink-muted">
              {shortId(row.enactment_id)}
            </code>
            <Link
              to={`/enactments/${row.enactment_id}`}
              aria-label={`Open enactment ${row.enactment_id} detail`}
              className="inline-flex h-6 items-center rounded-md border border-cf-border bg-cf-surface px-2 text-[11px] font-medium text-cf-ink-muted hover:bg-cf-surface/80"
            >
              Open detail
            </Link>
          </div>
        </DrawerMetaRow>
        <DrawerMetaRow label="Enabled at">
          <span className="text-xs text-cf-ink">{formatTimestamp(row.enabled_at)}</span>
        </DrawerMetaRow>
        {row.binding_summary ? (
          <div className="flex flex-col gap-1.5">
            <span className="text-[10px] font-medium uppercase tracking-[0.08em] text-cf-ink-muted">
              Binding
            </span>
            <div
              className="max-h-32 overflow-auto"
              data-testid="drawer-binding-code"
            >
              <CodeBlock lang="bash" code={row.binding_summary} />
            </div>
          </div>
        ) : null}
      </section>

      <div className="flex-1 overflow-y-auto px-6 py-5">
        <div className="flex flex-col gap-4">
          <div className="flex items-center justify-between">
            <h3 className="text-[10px] font-semibold uppercase tracking-[0.08em] text-cf-ink-muted">
              Outputs
            </h3>
            {schema.length > 0 ? (
              <span className="text-[11px] text-cf-ink-muted">
                {schema.length} {schema.length === 1 ? "field" : "fields"}
              </span>
            ) : null}
          </div>

          {schema.length === 0 ? (
            <Banner
              variant="default"
              title="No free variables"
              description="This transition has no operator-supplied outputs — just submit to fire."
            />
          ) : (
            <div className="flex flex-col gap-5" data-testid="outputs-form">
              {schema.map((field) => (
                <OutputField
                  key={field.name}
                  field={field}
                  value={values[field.name]}
                  error={fieldErrors[field.name] ?? null}
                  onChange={(next) =>
                    setValues((prev) => ({ ...prev, [field.name]: next }))
                  }
                />
              ))}
            </div>
          )}

          {inlineBanner ? (
            <Banner
              variant="error"
              title={inlineBanner.title}
              description={inlineBanner.description}
            />
          ) : null}
        </div>
      </div>

      <footer className="flex items-center justify-end gap-3 border-t border-cf-border bg-cf-surface px-6 py-4">
        {!isValid && !isPending && schema.length > 0 ? (
          <span
            className="mr-auto text-xs text-kumo-subtle"
            data-testid="outputs-submit-hint"
          >
            Complete required fields to submit.
          </span>
        ) : null}
        <Dialog.Close
          render={(props) => (
            <Button {...props} variant="secondary" disabled={isPending}>
              Cancel
            </Button>
          )}
        />
        <Button
          variant="primary"
          disabled={submitDisabled}
          onClick={onSubmit}
          data-testid="outputs-submit"
        >
          {isPending ? "Submitting…" : "Submit"}
        </Button>
      </footer>
    </Dialog.Popup>
  )
}

function DrawerMetaRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <span className="text-[10px] font-medium uppercase tracking-[0.08em] text-cf-ink-muted">
        {label}
      </span>
      {children}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Per-field rendering
// ---------------------------------------------------------------------------

type FieldValue = string | number | boolean | null

interface OutputFieldProps {
  field: OutputVar
  value: FieldValue
  error: string | null
  onChange: (next: FieldValue) => void
}

function OutputField({ field, value, error, onChange }: OutputFieldProps) {
  const helper = fieldHelper(field)
  const testId = `outputs-field-${field.name}`

  switch (field.kind) {
    case "integer":
      return (
        <Input
          label={field.name}
          type="number"
          step={1}
          value={value === null || value === undefined ? "" : String(value)}
          onChange={(event) => onChange(parseIntegerInput(event.target.value))}
          description={helper}
          error={error ?? undefined}
          aria-invalid={error !== null}
          data-testid={testId}
        />
      )

    case "boolean":
      return (
        <div className="flex flex-col gap-1">
          <label className="flex items-center gap-2">
            <Checkbox
              checked={value === true}
              onCheckedChange={(checked) => onChange(checked === true)}
              data-testid={testId}
            />
            <span className="text-sm font-medium text-kumo-default">{field.name}</span>
          </label>
          {helper ? (
            <span className="ml-6 text-xs text-kumo-subtle">{helper}</span>
          ) : null}
        </div>
      )

    case "enum": {
      // A native <select> sits inside Kumo-styled chrome. Kumo's `Select`
      // uses Base UI's headless primitive which renders inside a portal; that
      // works fine in production but resists deterministic interaction in
      // jsdom. The native element keeps testability + accessibility +
      // visual parity with Kumo Input (same tokens, height, text size).
      return (
        <FieldShell name={field.name} helper={helper} error={error}>
          <select
            className="h-9 w-full rounded-lg border border-kumo-line bg-kumo-control px-3 text-base text-kumo-default outline-none focus:ring-[1.5px] focus:ring-kumo-focus/50 aria-invalid:ring-[1.5px] aria-invalid:ring-kumo-danger/50"
            value={typeof value === "string" ? value : ""}
            onChange={(event) => onChange(event.target.value)}
            aria-invalid={error !== null}
            data-testid={testId}
          >
            <option value="" disabled>
              {`Select ${field.name}…`}
            </option>
            {(field.enum_values ?? []).map((choice) => (
              <option key={choice} value={choice}>
                {choice}
              </option>
            ))}
          </select>
        </FieldShell>
      )
    }

    case "elixir":
      return (
        <InputArea
          label={field.name}
          description={helper}
          error={error ?? undefined}
          value={typeof value === "string" ? value : ""}
          onChange={(event) => onChange(event.target.value)}
          placeholder={field.example ?? ":your_term"}
          rows={5}
          spellCheck={false}
          className="font-mono"
          aria-invalid={error !== null}
          data-testid={`${testId}-elixir`}
        />
      )

    case "string":
    default:
      return (
        <Input
          label={field.name}
          type="text"
          value={typeof value === "string" ? value : ""}
          onChange={(event) => onChange(event.target.value)}
          description={helper}
          error={error ?? undefined}
          aria-invalid={error !== null}
          data-testid={testId}
        />
      )
  }
}

// Shared chrome for non-Kumo controls (the native enum <select>) so labels,
// helper text, and inline errors visually match Kumo Input / Textarea.
function FieldShell({
  name,
  helper,
  error,
  children
}: {
  name: string
  helper: string | null
  error: string | null
  children: React.ReactNode
}) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-sm font-medium text-kumo-default">{name}</span>
      {children}
      {error ? (
        <span className="text-xs text-kumo-danger">{error}</span>
      ) : helper ? (
        <span className="text-xs text-kumo-subtle">{helper}</span>
      ) : null}
    </label>
  )
}

// Helper text per kind. Boolean and enum self-document via the control, so
// the colour-set jargon only surfaces when `field.hint` was provided
// explicitly. String/integer/elixir keep the colour-set fallback because the
// control alone does not communicate the value space.
function fieldHelper(field: OutputVar): string | null {
  if (field.hint) return field.hint
  if (field.kind === "boolean" || field.kind === "enum") return null
  return field.colour_set ? `Colour set: ${field.colour_set}` : null
}

// ---------------------------------------------------------------------------
// Form helpers
// ---------------------------------------------------------------------------

function buildInitialValues(schema: readonly OutputVar[]): Record<string, FieldValue> {
  const acc: Record<string, FieldValue> = {}
  for (const field of schema) {
    switch (field.kind) {
      case "boolean":
        acc[field.name] = false
        break
      case "integer":
        acc[field.name] = null
        break
      case "enum":
        // Empty string forces an explicit operator choice — the Select's
        // placeholder is visible and validation rejects until a value is
        // picked.
        acc[field.name] = ""
        break
      case "elixir":
        acc[field.name] = ""
        break
      case "string":
      default:
        acc[field.name] = ""
        break
    }
  }
  return acc
}

function validateValues(
  schema: readonly OutputVar[],
  values: Record<string, FieldValue>
): Record<string, string | null> {
  const errors: Record<string, string | null> = {}
  for (const field of schema) {
    const value = values[field.name]
    switch (field.kind) {
      case "integer":
        if (typeof value !== "number" || Number.isNaN(value)) {
          errors[field.name] = "Enter a whole number."
        } else {
          errors[field.name] = null
        }
        break

      case "boolean":
        // Initial value is always boolean; no operator action can break that
        // invariant, so this branch only exists to keep the error map dense.
        errors[field.name] = null
        break

      case "enum":
        errors[field.name] =
          typeof value === "string" && value.length > 0 && (field.enum_values ?? []).includes(value)
            ? null
            : `Choose a ${field.name}.`
        break

      case "elixir":
        errors[field.name] = validateElixirText(typeof value === "string" ? value : "")
        break

      case "string":
      default:
        errors[field.name] = null
        break
    }
  }
  return errors
}

function serializeValues(
  schema: readonly OutputVar[],
  values: Record<string, FieldValue>
): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  for (const field of schema) {
    const value = values[field.name]
    switch (field.kind) {
      case "integer":
        out[field.name] = typeof value === "number" ? value : 0
        break
      case "boolean":
        out[field.name] = value === true
        break
      case "enum":
        out[field.name] = typeof value === "string" ? value : ""
        break
      case "elixir":
        // Wire the raw Elixir source text to the backend. The store's
        // `coerce_outputs/2` path runs it through ElixirTermDecoder
        // (Code.string_to_quoted + literal-only walker). No JSON parsing or
        // eval happens on the client.
        out[field.name] = typeof value === "string" ? value : ""
        break
      case "string":
      default:
        out[field.name] = typeof value === "string" ? value : ""
        break
    }
  }
  return out
}

function parseIntegerInput(raw: string): number | null {
  const trimmed = raw.trim()
  if (trimmed === "") return null
  const parsed = Number(trimmed)
  if (Number.isNaN(parsed) || !Number.isFinite(parsed)) return null
  // Reject decimals — the integer colour set expects an Elixir integer; the
  // backend rejects floats with `:type_mismatch`. Truncating here would mask
  // the operator's typo.
  if (!Number.isInteger(parsed)) return Number.NaN
  return parsed
}

function validateElixirText(value: string): string | null {
  // The backend's literal walker is authoritative — the client only enforces
  // "non-empty" so submit can stay disabled before the operator types
  // anything. Real validation happens server-side via Code.string_to_quoted/2
  // plus the literal walker; the reply surfaces actionable errors inline.
  return value.trim() === "" ? "Provide an Elixir term literal." : null
}

type ReplyCode =
  | "ok"
  | "already_completed"
  | "unknown_workitem"
  | "unknown_variable"
  | "invalid_outputs"
  | "type_mismatch"
  | "invalid_elixir"
  | "runner_error"

function replyTitle(code: string): string {
  switch (code) {
    case "already_completed":
      return "Already handled"
    case "unknown_workitem":
      return "Workitem not found"
    case "unknown_variable":
      return "Unknown variable"
    case "invalid_outputs":
      return "Invalid outputs"
    case "type_mismatch":
      return "Wrong type"
    case "invalid_elixir":
      return "Invalid Elixir term"
    case "runner_error":
      return "Runner rejected the completion"
    default:
      return `Reply: ${code}`
  }
}

function replyDescription(code: string, reply: Record<string, unknown>): string {
  switch (code) {
    case "already_completed":
      return "Another operator (or the runner) already handled this workitem. The row will disappear shortly."
    case "unknown_workitem":
      return "The dashboard no longer tracks this workitem. Refresh the page if it should still be live."
    case "unknown_variable": {
      const variable = typeof reply.variable === "string" ? reply.variable : "(unknown)"
      return `The runner does not recognise the output variable "${variable}". Check spelling against the field labels above.`
    }
    case "invalid_outputs":
      return "The runner rejected the outputs payload shape. It must be a JSON object."
    case "type_mismatch": {
      const variable = typeof reply.variable === "string" ? reply.variable : "(unknown)"
      const expected = typeof reply.expected_kind === "string" ? reply.expected_kind : "?"
      const message =
        typeof reply.message === "string"
          ? reply.message
          : `Output "${variable}" must be a ${expected}.`
      return message
    }
    case "invalid_elixir": {
      const variable = typeof reply.variable === "string" ? reply.variable : "(unknown)"
      const message =
        typeof reply.message === "string"
          ? reply.message
          : `Output "${variable}" must be an Elixir term literal.`
      return message
    }
    case "runner_error": {
      const message = typeof reply.message === "string" ? reply.message : "No message."
      return `Runner error: ${message}`
    }
    default:
      return JSON.stringify(reply)
  }
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
