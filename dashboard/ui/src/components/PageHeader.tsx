import type { ReactNode } from "react"

import ConnectionPill from "./ConnectionPill"
import { useEmbedMode } from "../hooks/useEmbedMode"

interface PageHeaderProps {
  title: ReactNode
  subtitle?: ReactNode
  /** Right-aligned content placed after the connection pill. */
  actions?: ReactNode
  /** Slot below the title row, e.g. a short stat / id readout. */
  byline?: ReactNode
}

/**
 * Canvas-level header used at the top of each route. Title + optional byline
 * sit on the left; the connection pill (and any contextual actions) sit on
 * the right. Padding lives on the route container, not here.
 */
export default function PageHeader({ title, subtitle, byline, actions }: PageHeaderProps) {
  const { embed } = useEmbedMode()

  // Embed mode keeps the live status + action chips so operators can still
  // act mid-demo, but drops the wordmark / title block so the canvas reads
  // as just "diagram + scrubber + tabs" — the requirement is full-bleed
  // chrome reduction.
  if (embed) {
    return (
      <header
        className="flex items-center justify-end gap-2"
        data-testid="page-header-embed"
      >
        <ConnectionPill />
        {actions}
      </header>
    )
  }

  return (
    <header className="flex flex-wrap items-start justify-between gap-4">
      <div className="flex min-w-0 flex-col gap-1.5">
        <h1 className="text-[26px] font-semibold leading-tight tracking-tight text-cf-ink">
          {title}
        </h1>
        {subtitle ? <p className="text-sm text-cf-ink-muted">{subtitle}</p> : null}
        {byline ? <div className="pt-1">{byline}</div> : null}
      </div>
      <div className="flex items-center gap-2">
        <ConnectionPill />
        {actions}
      </div>
    </header>
  )
}
