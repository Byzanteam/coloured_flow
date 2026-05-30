import { useState } from "react"
import { LayerCard } from "@cloudflare/kumo"

type ColourSetDef = ColouredFlowDashboardWeb.Views.ColourSetDef

interface Props {
  colourSets: readonly ColourSetDef[]
  defaultOpen?: boolean
}

// Shared colour-sets panel mounted on /enactments/:id and /flows/:id. Lets
// operators see the *shape* of each token type, not just the bare name on a
// place node (e.g. `outcome :: {verdict_t(), note_t()}`). Sorted in cpnet
// declaration order — backend is the source of truth.
export default function ColourSetsPanel({ colourSets, defaultOpen = false }: Props) {
  const [open, setOpen] = useState(defaultOpen)

  if (colourSets.length === 0) return null

  return (
    <LayerCard.Primary
      className="overflow-hidden p-0"
      data-testid="colour-sets-panel"
    >
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        aria-controls="colour-sets-panel-body"
        data-testid="colour-sets-toggle"
        className="flex w-full items-center justify-between border-b border-cf-border px-5 py-3 text-left transition-colors hover:bg-cf-surface-muted"
      >
        <div className="flex flex-col">
          <span className="text-sm font-semibold text-cf-ink">Colour sets</span>
          <span className="text-[11px] text-cf-ink-muted">
            {colourSets.length}{" "}
            {colourSets.length === 1 ? "definition" : "definitions"}
          </span>
        </div>
        <span
          aria-hidden="true"
          className={`text-xs text-cf-ink-muted transition-transform ${open ? "rotate-90" : ""}`}
        >
          ›
        </span>
      </button>
      {open ? (
        <dl
          id="colour-sets-panel-body"
          className="grid grid-cols-[max-content_1fr] gap-x-6 gap-y-2 px-5 py-4"
          data-testid="colour-sets-list"
        >
          {colourSets.map((cs) => (
            <ColourSetRow key={cs.name} entry={cs} />
          ))}
        </dl>
      ) : null}
    </LayerCard.Primary>
  )
}

function ColourSetRow({ entry }: { entry: ColourSetDef }) {
  return (
    <>
      <dt
        className="font-mono text-xs text-cf-ink"
        data-testid={`colour-set-name-${entry.name}`}
      >
        {entry.name}
      </dt>
      <dd
        className="font-mono text-xs text-cf-ink-muted"
        data-testid={`colour-set-type-${entry.name}`}
      >
        {entry.type_summary}
        {entry.description ? (
          <span className="ml-3 font-sans text-cf-ink-muted">
            — {entry.description}
          </span>
        ) : null}
      </dd>
    </>
  )
}
