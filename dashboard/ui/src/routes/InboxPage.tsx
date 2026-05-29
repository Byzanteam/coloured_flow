import { Text } from "@cloudflare/kumo"

export default function InboxPage() {
  return (
    <section className="flex flex-col gap-2">
      <Text variant="heading1" as="h1">
        Inbox
      </Text>
      <Text variant="secondary">
        Live workitems land here in M2 (Phase 7). Empty shell for now.
      </Text>
    </section>
  )
}
