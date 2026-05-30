import { useParams } from "react-router-dom"
import { LayerCard, Text } from "@cloudflare/kumo"

import PageHeader from "../components/PageHeader"

export default function FlowCatalogPage() {
  const { module } = useParams<"module">()

  return (
    <section className="flex flex-col gap-6">
      <PageHeader
        title="Flows"
        subtitle={module ? `Catalog detail for ${module}` : "Registered flows."}
      />
      <LayerCard.Primary className="px-6 py-10">
        <Text variant="secondary">
          {module
            ? "Catalog detail surface lands in a later phase."
            : "Catalog index lands in a later phase."}
        </Text>
      </LayerCard.Primary>
    </section>
  )
}
