import type { ReactNode } from "react"

export interface Metric {
  label: ReactNode
  value: ReactNode
}

/**
 * Restrained dashboard counts row. Each cell renders a small uppercase
 * caption above a 2xl number; hairline dividers split cells. The card is the
 * only enclosure — no pill-wrapped counts, no nested cards.
 */
export default function MetricsRow({ items }: { items: readonly Metric[] }) {
  if (items.length === 0) return null

  return (
    <div
      className="grid divide-x divide-cf-border overflow-hidden rounded-xl border border-cf-border bg-cf-surface"
      style={{ gridTemplateColumns: `repeat(${items.length}, minmax(0, 1fr))` }}
    >
      {items.map((item, index) => (
        <div key={index} className="flex flex-col gap-1 px-5 py-4">
          <span className="text-[11px] font-medium uppercase tracking-[0.08em] text-cf-ink-faint">
            {item.label}
          </span>
          <span className="text-2xl font-semibold leading-tight text-cf-ink">
            {item.value}
          </span>
        </div>
      ))}
    </div>
  )
}
