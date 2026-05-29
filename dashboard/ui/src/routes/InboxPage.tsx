import { Suspense, useEffect, useId, useMemo, useState } from "react"
import {
  Badge,
  Banner,
  Button,
  Dialog,
  LayerCard,
  Table,
  Text,
  Textarea
} from "@cloudflare/kumo"
import { MusubiCommandError } from "@musubi/react"

import { useMusubiCommand, useMusubiRootSuspense, useMusubiSnapshot } from "../musubi"

const INBOX_STORE = "ColouredFlowDashboardWeb.Stores.InboxStore" as const

type WorkitemRow = ColouredFlowDashboardWeb.Views.WorkitemRow

export default function InboxPage() {
  return (
    <Suspense fallback={<InboxFallback />}>
      <InboxContent />
    </Suspense>
  )
}

function InboxFallback() {
  return (
    <section className="flex flex-col gap-4">
      <Text variant="heading1" as="h1">
        Inbox
      </Text>
      <Text variant="secondary">Loading live workitems…</Text>
    </section>
  )
}

function InboxContent() {
  const inbox = useMusubiRootSuspense({ module: INBOX_STORE, id: "default" })
  const snapshot = useMusubiSnapshot(inbox)

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
    <section className="flex flex-col gap-4">
      <header className="flex items-center justify-between">
        <Text variant="heading1" as="h1">
          Inbox
        </Text>
        <Text variant="secondary">{workitems.length} live workitems</Text>
      </header>

      <LayerCard className="flex flex-wrap items-center gap-3 p-4">
        <CountBadge label="Enabled" value={counts.enabled} tone="info" />
        <CountBadge label="Started" value={counts.started} tone="warning" />
        <CountBadge label="Enactments" value={enactmentCount} tone="neutral" />
      </LayerCard>

      {workitems.length === 0 ? (
        <Banner
          variant="default"
          title="No live workitems"
          description="As enactments fire, their pending workitems appear here."
        />
      ) : (
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
            {workitems.map((row) => (
              <Table.Row key={row.id}>
                <Table.Cell>{row.transition}</Table.Cell>
                <Table.Cell>
                  <code className="text-xs">{shortId(row.enactment_id)}</code>
                </Table.Cell>
                <Table.Cell>
                  <StateBadge state={row.state} />
                </Table.Cell>
                <Table.Cell>
                  <code className="text-xs">{row.binding_summary || "—"}</code>
                </Table.Cell>
                <Table.Cell>{formatTimestamp(row.enabled_at)}</Table.Cell>
                <Table.Cell className="text-right">
                  <Button
                    variant="secondary"
                    size="sm"
                    aria-label={`Open outputs drawer for workitem ${row.id}`}
                    onClick={() => setDrawerRow(row)}
                  >
                    Action ▸
                  </Button>
                </Table.Cell>
              </Table.Row>
            ))}
          </Table.Body>
        </Table>
      )}

      <OutputsDrawer
        row={drawerRow}
        onClose={() => setDrawerRow(null)}
      />
    </section>
  )
}

type Tone = "info" | "warning" | "neutral"

function CountBadge({ label, value, tone }: { label: string; value: number; tone: Tone }) {
  return (
    <div className="flex items-center gap-2">
      <Text variant="secondary">{label}</Text>
      <Badge variant={tone}>{value}</Badge>
    </div>
  )
}

function StateBadge({ state }: { state: "enabled" | "started" }) {
  return <Badge variant={state === "started" ? "warning" : "info"}>{state}</Badge>
}

// ---------------------------------------------------------------------------
// Outputs drawer
// ---------------------------------------------------------------------------

interface OutputsDrawerProps {
  row: WorkitemRow | null
  onClose: () => void
}

function OutputsDrawer({ row, onClose }: OutputsDrawerProps) {
  const open = row !== null
  return (
    <Dialog.Root open={open} onOpenChange={(next) => { if (!next) onClose() }}>
      {row ? <OutputsDrawerBody row={row} onClose={onClose} /> : null}
    </Dialog.Root>
  )
}

function OutputsDrawerBody({ row, onClose }: { row: WorkitemRow; onClose: () => void }) {
  const inbox = useMusubiRootSuspense({ module: INBOX_STORE, id: "default" })
  const { dispatch, isPending, error, reset } = useMusubiCommand(inbox, "complete_workitem")
  const textareaId = useId()

  const initialJson = useMemo(
    () => buildOutputsTemplate(row.output_vars ?? []),
    [row.output_vars]
  )
  const [json, setJson] = useState(initialJson)
  const [parseError, setParseError] = useState<string | null>(null)
  const [serverBanner, setServerBanner] = useState<{
    title: string
    description: string
  } | null>(null)

  // New row → reset textarea + clear stale banner/error state.
  useEffect(() => {
    setJson(initialJson)
    setParseError(null)
    setServerBanner(null)
    reset()
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [row.id, initialJson])

  const onBlur = () => {
    setParseError(validateJson(json))
  }

  const onSubmit = async () => {
    const parseIssue = validateJson(json)
    if (parseIssue) {
      setParseError(parseIssue)
      return
    }

    setParseError(null)
    setServerBanner(null)

    let outputs: Record<string, unknown>
    try {
      outputs = JSON.parse(json) as Record<string, unknown>
    } catch (cause) {
      setParseError(cause instanceof Error ? cause.message : String(cause))
      return
    }

    try {
      const reply = await dispatch({ workitem_id: row.id, outputs })
      if (reply.code === "ok") {
        onClose()
        return
      }

      setServerBanner({
        title: replyTitle(reply.code),
        description: replyDescription(reply.code, reply)
      })
    } catch (cause) {
      // dispatch throws a MusubiCommandError; render its code + extracted reply.
      const code = MusubiCommandError.is(cause) ? cause.code ?? "runner_error" : "runner_error"
      const description =
        cause instanceof Error ? cause.message : "Command failed for an unknown reason."

      setServerBanner({
        title: replyTitle(code),
        description
      })
    }
  }

  const submitDisabled = isPending || parseError !== null

  return (
    <Dialog size="lg">
      <Dialog.Title>Complete workitem · {row.transition}</Dialog.Title>
      <Dialog.Description>
        Submit the JSON object the runner needs to bind the transition's free
        variables. Hint: only the variables listed below are required;
        everything else is ignored.
      </Dialog.Description>

      <div className="mt-4 flex flex-col gap-4">
        <DetailRow label="Enactment">
          <code className="text-xs">{shortId(row.enactment_id)}</code>
        </DetailRow>
        <DetailRow label="State">
          <StateBadge state={row.state} />
        </DetailRow>
        <DetailRow label="Expected variables">
          <ExpectedVars vars={row.output_vars ?? []} />
        </DetailRow>

        <label htmlFor={textareaId} className="flex flex-col gap-1">
          <Text variant="secondary">Outputs (JSON object)</Text>
          <Textarea
            id={textareaId}
            value={json}
            onChange={(event) => {
              setJson(event.target.value)
              if (parseError) setParseError(null)
            }}
            onBlur={onBlur}
            rows={8}
            spellCheck={false}
            aria-invalid={parseError !== null}
            data-testid="outputs-textarea"
          />
        </label>

        {parseError ? (
          <Banner variant="error" title="JSON invalid" description={parseError} />
        ) : null}

        {error && !serverBanner ? (
          <Banner
            variant="error"
            title="Command failed"
            description={error.message}
          />
        ) : null}

        {serverBanner ? (
          <Banner
            variant="error"
            title={serverBanner.title}
            description={serverBanner.description}
          />
        ) : null}
      </div>

      <div className="mt-6 flex justify-end gap-2">
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

function ExpectedVars({ vars }: { vars: readonly string[] }) {
  if (vars.length === 0) {
    return <Text variant="secondary">(no free variables)</Text>
  }
  return (
    <div className="flex flex-wrap gap-1">
      {vars.map((name) => (
        <Badge key={name} variant="neutral">
          {name}
        </Badge>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function buildOutputsTemplate(vars: readonly string[]): string {
  if (vars.length === 0) return "{}"
  const body = vars.map((v) => `  ${JSON.stringify(v)}: ""`).join(",\n")
  return `{\n${body}\n}`
}

function validateJson(value: string): string | null {
  const trimmed = value.trim()
  if (trimmed === "") return "Outputs must be a JSON object."
  try {
    const parsed = JSON.parse(trimmed)
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
      return "Outputs must be a JSON object, not a list or primitive."
    }
    return null
  } catch (cause) {
    return cause instanceof Error ? cause.message : "Invalid JSON."
  }
}

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
      return `The runner does not recognise the output variable "${variable}". Check spelling against the expected variables above.`
    }
    case "invalid_outputs":
      return "The runner rejected the outputs payload shape. It must be a JSON object."
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
