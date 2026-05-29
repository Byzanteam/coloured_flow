import { Suspense } from "react"
import {
  Badge,
  Banner,
  Button,
  LayerCard,
  Table,
  Text
} from "@cloudflare/kumo"

import { useMusubiRootSuspense, useMusubiSnapshot } from "../musubi"

const INBOX_STORE = "ColouredFlowDashboardWeb.Stores.InboxStore" as const

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

  const workitems = snapshot.workitems ?? []
  const counts = snapshot.counts ?? { enabled: 0, started: 0, by_enactment: {} }
  const enactmentCount = Object.keys(counts.by_enactment ?? {}).length

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
                  <Button variant="secondary" size="sm" disabled aria-label="Open workitem drawer">
                    Action ▸
                  </Button>
                </Table.Cell>
              </Table.Row>
            ))}
          </Table.Body>
        </Table>
      )}
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
