import { Link } from "react-router-dom"
import { Text } from "@cloudflare/kumo"

export default function NotFoundPage() {
  return (
    <section className="flex flex-col gap-2">
      <Text variant="heading1" as="h1">
        Not found
      </Text>
      <Link to="/" className="text-blue-500 underline">
        Back to inbox
      </Link>
    </section>
  )
}
