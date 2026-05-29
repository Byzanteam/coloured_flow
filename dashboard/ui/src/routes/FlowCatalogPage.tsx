import { useParams } from "react-router-dom"
import { Text } from "@cloudflare/kumo"

export default function FlowCatalogPage() {
  const { module } = useParams<"module">()

  return (
    <section className="flex flex-col gap-2">
      <Text variant="heading1" as="h1">
        Flows
      </Text>
      <Text variant="secondary">
        {module ? `Catalog detail for ${module}` : "Catalog index — list of registered flows."}
      </Text>
    </section>
  )
}
