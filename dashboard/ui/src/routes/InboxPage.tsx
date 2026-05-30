import { useEffect, useMemo, useState } from "react"
import {
  Banner,
  Button,
  Checkbox,
  Dialog,
  Input,
  LayerCard,
  Table,
  Text,
  Textarea,
  useKumoToastManager
} from "@cloudflare/kumo"
import { TrayIcon } from "@phosphor-icons/react"
import { Link } from "react-router-dom"
import type { MusubiRootMount } from "@musubi/react"
import { useMusubiCommand, useMusubiRoot, useMusubiSnapshot } from "../musubi"
import { dispatchWithReply } from "../musubi/replyHandler"
import PageHeader from "../components/PageHeader"
import MetricsRow from "../components/MetricsRow"
import { useEmbedMode } from "../hooks/useEmbedMode"

const INBOX_STORE = "ColouredFlowDashboardWeb.Stores.InboxStore" as const

type WorkitemRow = ColouredFlowDashboardWeb.Views.WorkitemRow
type OutputVar = ColouredFlowDashboardWeb.Views.OutputVar
type InboxRootMount = MusubiRootMount<typeof INBOX_STORE, Musubi.Stores>
type InboxProxy = NonNullable<Extract<InboxRootMount, { status: "ready" }>["store"]>

// The page deliberately avoids `useMusubiRootSuspense` — @musubi/react@0.6.0
// schedules an orphan-sweep on every Suspense throw that races React 19's
// passive-effect flush. When the sweep wins, it tears down the mount, the
// re-render re-suspends, and the page spins at ~50% CPU pushing
// mount/unmount/mount/unmount over the WS. `useMusubiRoot` mounts inside a
// commit-phase effect and has no sweep, so the loop is impossible.
export default function InboxPage() {
  const root = useMusubiRoot({ module: INBOX_STORE, id: "default" })

  if (root.status === "error") {
    return <InboxShell><InboxError message={root.error.message} /></InboxShell>
  }

  if (root.status !== "ready") {
    return <InboxShell><InboxFallback /></InboxShell>
  }

  return (
    <InboxShell>
      <InboxContent inbox={root.store} />
    </InboxShell>
  )
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

function InboxContent({ inbox }: { inbox: InboxProxy }) {
  const snapshot = useMusubiSnapshot(inbox)
  const { embed } = useEmbedMode()

  const workitems: readonly WorkitemRow[] = snapshot.workitems ?? []
  const counts = snapshot.counts ?? { enabled: 0, started: 0, by_enactment: {} }
  const enactmentCount = Object.keys(counts.by_enactment ?? {}).length

  const [drawerRow, setDrawerRow] = useState<WorkitemRow | null>(null)

  // If the active row drops out of the snapshot (e.g. another operator
  // completed it via a sibling tab) clear the drawer state so the dialog
  // doesn't render against stale data.
  useEffect(() => {
    if (!drawerRow) return
    const stillLive = workitems.some((wi) => wi.id === drawerRow.id)
    if (!stillLive) setDrawerRow(null)
  }, [workitems, drawerRow])

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

      <LayerCard.Primary className="overflow-hidden p-0">
        {workitems.length === 0 ? (
          <InboxEmpty />
        ) : (
          <InboxTable rows={workitems} onOpen={setDrawerRow} />
        )}
      </LayerCard.Primary>

      <OutputsDrawer
        inbox={inbox}
        row={drawerRow}
        onClose={() => setDrawerRow(null)}
      />
    </>
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
      {row ? <OutputsDrawerBody inbox={inbox} row={row} onClose={onClose} /> : null}
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
    <Dialog size="lg">
      <Dialog.Title>Complete workitem · {row.transition}</Dialog.Title>
      <Dialog.Description>
        Fill in the free variables the runner needs to fire this transition.
        Controls below come from the transition's output-arc inscriptions.
      </Dialog.Description>

      <div className="mt-4 flex flex-col gap-4">
        <DetailRow label="Enactment">
          <code className="text-xs text-cf-ink-muted">{shortId(row.enactment_id)}</code>
        </DetailRow>
        <DetailRow label="State">
          <StateDot state={row.state} />
        </DetailRow>

        {schema.length === 0 ? (
          <Banner
            variant="default"
            title="No free variables"
            description="This transition has no operator-supplied outputs — just submit to fire."
          />
        ) : (
          <div
            className="-mx-1 flex max-h-[55vh] flex-col gap-5 overflow-y-auto px-1"
            data-testid="outputs-form"
          >
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

      <div className="mt-6 flex items-center justify-end gap-3">
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
      </div>
    </Dialog>
  )
}

function DetailRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-3">
      <div className="min-w-32">
        <Text variant="secondary">{label}</Text>
      </div>
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

    case "json":
      return (
        <Textarea
          label={field.name}
          description={helper}
          error={error ?? undefined}
          value={typeof value === "string" ? value : ""}
          onChange={(event) => onChange(event.target.value)}
          rows={5}
          spellCheck={false}
          aria-invalid={error !== null}
          data-testid={`${testId}-json`}
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
// explicitly. String/integer/json keep the colour-set fallback because the
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
      case "json":
        acc[field.name] = "{}"
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

      case "json":
        errors[field.name] = validateJson(typeof value === "string" ? value : "")
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
      case "json":
        try {
          out[field.name] = JSON.parse(typeof value === "string" ? value : "null")
        } catch {
          out[field.name] = null
        }
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

function validateJson(value: string): string | null {
  const trimmed = value.trim()
  if (trimmed === "") return "Provide a JSON value."
  try {
    JSON.parse(trimmed)
    return null
  } catch (cause) {
    // Trim and reframe the raw parser message so operators don't see
    // developer-flavoured "Unexpected token … at position N" prose alone.
    const detail = cause instanceof Error ? cause.message.split("\n")[0] : ""
    return detail ? `Invalid JSON: ${detail}` : "Invalid JSON."
  }
}

type ReplyCode =
  | "ok"
  | "already_completed"
  | "unknown_workitem"
  | "unknown_variable"
  | "invalid_outputs"
  | "type_mismatch"
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
