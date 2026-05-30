import { useEffect, useId, useMemo, useState } from "react"
import {
  Badge,
  Banner,
  Button,
  Dialog,
  LayerCard,
  Table,
  Text,
  Textarea,
  useKumoToastManager
} from "@cloudflare/kumo"
import type { MusubiRootMount } from "@musubi/react"
import { useMusubiCommand, useMusubiRoot, useMusubiSnapshot } from "../musubi"
import { dispatchWithReply } from "../musubi/replyHandler"

const INBOX_STORE = "ColouredFlowDashboardWeb.Stores.InboxStore" as const

type WorkitemRow = ColouredFlowDashboardWeb.Views.WorkitemRow
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
    return <InboxError message={root.error.message} />
  }

  if (root.status !== "ready") {
    return <InboxFallback />
  }

  return <InboxContent inbox={root.store} />
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

function InboxError({ message }: { message: string }) {
  return (
    <section className="flex flex-col gap-4">
      <Text variant="heading1" as="h1">
        Inbox
      </Text>
      <Banner variant="error" title="Inbox unavailable" description={message} />
    </section>
  )
}

function InboxContent({ inbox }: { inbox: InboxProxy }) {
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
        inbox={inbox}
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
  const textareaId = useId()

  const initialJson = useMemo(
    () => buildOutputsTemplate(row.output_vars ?? []),
    [row.output_vars]
  )
  const [json, setJson] = useState(initialJson)
  // Inline banner only for *actionable* server replies the operator can fix
  // by editing the JSON (unknown_variable, invalid_outputs). Transient errors
  // (race losses, runner exceptions) surface as toasts so the drawer either
  // closes (race) or stays open without claiming the textarea is wrong.
  const [inlineBanner, setInlineBanner] = useState<{
    title: string
    description: string
  } | null>(null)

  // Derive parse state on every render so submit stays disabled the instant
  // the textarea contents become invalid — no blur required.
  const parseError = useMemo(() => validateJson(json), [json])

  // New row → reset textarea + clear stale banner state.
  useEffect(() => {
    setJson(initialJson)
    setInlineBanner(null)
    reset()
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [row.id, initialJson])

  const onSubmit = async () => {
    if (parseError) return

    setInlineBanner(null)

    let outputs: Record<string, unknown>
    try {
      outputs = JSON.parse(json) as Record<string, unknown>
    } catch {
      // useMemo above already covered this; defensive guard.
      return
    }

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

      // Actionable: operator can fix by editing the JSON. Keep the drawer
      // open and surface inline so the message sits next to the textarea.
      case "unknown_variable":
      case "invalid_outputs":
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
            onChange={(event) => setJson(event.target.value)}
            rows={8}
            spellCheck={false}
            aria-invalid={parseError !== null}
            data-testid="outputs-textarea"
          />
        </label>

        {parseError ? (
          <Banner variant="error" title="JSON invalid" description={parseError} />
        ) : null}

        {inlineBanner ? (
          <Banner
            variant="error"
            title={inlineBanner.title}
            description={inlineBanner.description}
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

type ReplyCode =
  | "ok"
  | "already_completed"
  | "unknown_workitem"
  | "unknown_variable"
  | "invalid_outputs"
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
