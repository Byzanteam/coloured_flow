import { Fragment, type ReactNode, useEffect, useMemo, useState } from "react"
import {
  Badge,
  Banner,
  Button,
  Checkbox,
  ClipboardText,
  Input,
  InputArea,
  useKumoToastManager
} from "@cloudflare/kumo"
import { Dialog } from "@base-ui/react/dialog"
import { Link } from "react-router-dom"
import { dispatchWithReply } from "../musubi/replyHandler"

type WorkitemRow = ColouredFlowDashboardWeb.Views.WorkitemRow
type OutputVar = ColouredFlowDashboardWeb.Views.OutputVar

export type CompleteWorkitemDispatch = (payload: {
  workitem_id: string
  outputs: Record<string, unknown>
}) => Promise<{ code?: string } & Record<string, unknown>>

export interface OutputsDrawerCommand {
  dispatch: CompleteWorkitemDispatch
  isPending: boolean
  reset: () => void
}

export interface OutputsDrawerProps {
  command: OutputsDrawerCommand
  row: WorkitemRow | null
  onClose: () => void
}

export default function OutputsDrawer({ command, row, onClose }: OutputsDrawerProps) {
  const open = row !== null
  return (
    <Dialog.Root
      open={open}
      onOpenChange={(next) => {
        if (!next) onClose()
      }}
      modal={false}
    >
      <Dialog.Portal>
        {row ? <OutputsDrawerBody command={command} row={row} onClose={onClose} /> : null}
      </Dialog.Portal>
    </Dialog.Root>
  )
}

function OutputsDrawerBody({
  command,
  row,
  onClose
}: {
  command: OutputsDrawerCommand
  row: WorkitemRow
  onClose: () => void
}) {
  const { dispatch, isPending, reset } = command
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

  const fieldErrors = useMemo(() => validateValues(schema, values), [schema, values])
  const isValid = useMemo(
    () => Object.values(fieldErrors).every((err) => err === null),
    [fieldErrors]
  )

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
      dispatch as unknown as (
        payload: Record<string, unknown>
      ) => Promise<{ code?: string } & Record<string, unknown>>,
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

      case "unknown_variable":
      case "invalid_outputs":
      case "type_mismatch":
      case "invalid_elixir":
        setInlineBanner({
          title: replyTitle(code),
          description: replyDescription(code, reply)
        })
        return

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
    <Dialog.Popup className="fixed top-0 right-0 z-50 h-screen w-full sm:w-[28rem] flex flex-col bg-cf-surface border-l border-cf-border outline-none focus:outline-none shadow-2xl transition-transform duration-200 ease-out data-[starting-style]:translate-x-full data-[ending-style]:translate-x-full">
      <header className="flex flex-col gap-3 border-b border-cf-border bg-cf-surface px-6 pt-6 pb-4">
        <div className="flex items-center gap-3">
          <Dialog.Title className="flex-1 text-lg font-semibold leading-tight text-cf-ink">
            Complete workitem · {row.transition}
          </Dialog.Title>
          <Badge variant={row.state === "started" ? "info" : "outline"} className="capitalize">
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
        <div className="flex flex-col gap-1.5">
          <span className="text-[10px] font-medium uppercase tracking-[0.08em] text-cf-ink-muted">
            Binding
          </span>
          <div className="max-h-32 overflow-auto" data-testid="drawer-binding-pairs">
            {row.binding_pairs.length === 0 ? (
              <span className="text-xs italic text-cf-ink-muted">no bindings</span>
            ) : (
              <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
                {row.binding_pairs.map((pair) => (
                  <Fragment key={pair.name}>
                    <dt className="font-mono text-cf-ink-muted">{pair.name}</dt>
                    <dd className="font-mono text-cf-ink break-all">{pair.value}</dd>
                  </Fragment>
                ))}
              </dl>
            )}
          </div>
        </div>
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
  if (!Number.isInteger(parsed)) return Number.NaN
  return parsed
}

function validateElixirText(value: string): string | null {
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
