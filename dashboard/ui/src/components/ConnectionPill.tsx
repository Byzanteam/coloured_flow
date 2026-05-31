import { useMusubiConnectionStatus } from "../musubi"

type ConnectionState = "connecting" | "ready" | "error"

type Variant = "dark" | "light"

interface ConnectionView {
  label: string
  dotClass: string
}

function viewFor(state: ConnectionState): ConnectionView {
  switch (state) {
    case "ready":
      return { label: "Live", dotClass: "bg-cf-dot-enabled" }
    case "error":
      return { label: "Offline", dotClass: "bg-cf-dot-exception" }
    case "connecting":
    default:
      return { label: "Reconnecting…", dotClass: "bg-cf-dot-started" }
  }
}

/**
 * Single canvas-header connection status chip. Mirrors the reference's
 * black "Published" pill. The pill is the *only* place this status surfaces;
 * the sidebar bottom card carries the operator identity, not the connection.
 */
export default function ConnectionPill({ variant = "dark" }: { variant?: Variant }) {
  const status = useMusubiConnectionStatus()
  const view = viewFor(status.state)

  const styles =
    variant === "dark"
      ? "bg-cf-pill-bg text-cf-pill-ink"
      : "border border-cf-border bg-cf-surface text-cf-ink"

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium ${styles}`}
      data-testid="connection-pill"
    >
      <span className={`h-1.5 w-1.5 rounded-full ${view.dotClass}`} />
      {view.label}
    </span>
  )
}
