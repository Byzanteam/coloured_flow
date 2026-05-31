import { Link } from "react-router-dom"
import { LayerCard, Text } from "@cloudflare/kumo"

import PageHeader from "../components/PageHeader"

export default function NotFoundPage() {
  return (
    <section className="flex flex-col gap-6">
      <PageHeader title="Not found" subtitle="The page you asked for does not exist." />
      <LayerCard.Primary className="flex flex-col gap-3 px-6 py-10">
        <Text variant="secondary">
          Check the URL, or head back to the inbox to see live workitems.
        </Text>
        <Link to="/" className="text-sm font-medium text-cf-accent-ink hover:underline">
          Back to inbox →
        </Link>
      </LayerCard.Primary>
    </section>
  )
}
