import type { ReactNode } from "react"
import { Breadcrumbs } from "@cloudflare/kumo"

import ConnectionPill from "./ConnectionPill"
import { useEmbedMode } from "../hooks/useEmbedMode"

export interface BreadcrumbItem {
  label: string
  to?: string
}

interface PageHeaderProps {
  title: ReactNode
  subtitle?: ReactNode
  /** Right-aligned content placed after the connection pill. */
  actions?: ReactNode
  /** Slot below the title row, e.g. a short stat / id readout. */
  byline?: ReactNode
  /**
   * Optional breadcrumb trail rendered above the title. The last item is
   * treated as the current page (non-link); earlier items render as links
   * when `to` is provided, otherwise as plain labels.
   */
  breadcrumbs?: ReadonlyArray<BreadcrumbItem>
}

/**
 * Canvas-level header used at the top of each route. Title + optional byline
 * sit on the left; the connection pill (and any contextual actions) sit on
 * the right. Padding lives on the route container, not here.
 */
export default function PageHeader({
  title,
  subtitle,
  byline,
  actions,
  breadcrumbs
}: PageHeaderProps) {
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
    <div className="flex flex-col gap-1">
      {breadcrumbs && breadcrumbs.length > 1 ? (
        <BreadcrumbTrail items={breadcrumbs} />
      ) : null}
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex min-w-0 flex-col">
          <h1 className="text-xl font-semibold leading-tight tracking-tight text-cf-ink">
            {title}
          </h1>
          {subtitle ? <p className="mt-1 text-sm text-cf-ink-muted">{subtitle}</p> : null}
          {byline ? <div className="mt-1">{byline}</div> : null}
        </div>
        <div className="flex items-center gap-2">
          <ConnectionPill />
          {actions}
        </div>
      </header>
    </div>
  )
}

function BreadcrumbTrail({ items }: { items: ReadonlyArray<BreadcrumbItem> }) {
  const lastIndex = items.length - 1
  return (
    <div data-testid="page-header-breadcrumbs">
      <Breadcrumbs size="sm">
        {items.flatMap((item, index) => {
          const isCurrent = index === lastIndex
          const nodes: ReactNode[] = []
          if (index > 0) {
            nodes.push(<Breadcrumbs.Separator key={`sep-${index}`} />)
          }
          if (isCurrent) {
            nodes.push(
              <Breadcrumbs.Current key={`crumb-${index}`}>{item.label}</Breadcrumbs.Current>
            )
          } else if (item.to) {
            nodes.push(
              <Breadcrumbs.Link key={`crumb-${index}`} href={item.to}>
                {item.label}
              </Breadcrumbs.Link>
            )
          } else {
            nodes.push(
              <Breadcrumbs.Current key={`crumb-${index}`}>{item.label}</Breadcrumbs.Current>
            )
          }
          return nodes
        })}
      </Breadcrumbs>
    </div>
  )
}
