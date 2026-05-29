import { useParams } from "react-router-dom"
import { Text } from "@cloudflare/kumo"

import NetDiagram from "../components/NetDiagram"

export default function EnactmentDetailPage() {
  const { id } = useParams<"id">()

  return (
    <section className="flex h-full flex-col gap-4">
      <Text variant="heading1" as="h1">
        Enactment {id ?? "(none)"}
      </Text>
      <Text variant="secondary">
        Markings · Workitems · Occurrences · Telemetry · Debug arrive in M3.
      </Text>
      <div className="h-96 rounded border">
        <NetDiagram />
      </div>
    </section>
  )
}
