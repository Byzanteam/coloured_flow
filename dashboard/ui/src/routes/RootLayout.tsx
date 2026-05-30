import { useEffect } from "react"
import { NavLink, Outlet } from "react-router-dom"
import {
  CaretRightIcon,
  GraphIcon,
  type Icon,
  TrayIcon
} from "@phosphor-icons/react"

import { useEmbedMode } from "../hooks/useEmbedMode"
import ThemeToggle from "../components/ThemeToggle"
import InboxNotifier from "../components/InboxNotifier"

// Sidebar shell. Restrained: white surface on a soft canvas, no border,
// brand chip top-left, a primary nav block, a hairline-separated secondary
// block, an operator identity card at the bottom-left. The live connection
// pill lives in each route's canvas header (see PageHeader), NOT here —
// one location for that signal, in the spot the operator's eye lands.

interface NavItem {
  to: string
  label: string
  icon: Icon
  end?: boolean
}

const PRIMARY_NAV: readonly NavItem[] = [
  { to: "/", label: "Inbox", icon: TrayIcon, end: true },
  { to: "/flows", label: "Flows", icon: GraphIcon, end: false }
]

interface SecondaryItem {
  label: string
  href?: string
}

const SECONDARY_NAV: readonly SecondaryItem[] = [
  { label: "Telemetry" },
  { label: "Settings" }
]

export default function RootLayout() {
  const { embed, exit } = useEmbedMode()

  if (embed) {
    return <EmbedShell onExit={exit} />
  }

  return (
    <div
      className="grid h-full grid-cols-[16rem_1fr] bg-cf-canvas"
      data-embed="false"
    >
      <InboxNotifier />
      <aside className="flex flex-col gap-7 bg-cf-surface px-5 py-7">
        <BrandChip />
        <ThemeToggle />
        <nav aria-label="Primary" className="flex flex-col gap-0.5">
          {PRIMARY_NAV.map((item) => (
            <PrimaryNavItem key={item.to} item={item} />
          ))}
        </nav>
        <div className="-mx-2 flex flex-col gap-2">
          <div className="mx-2 h-px bg-cf-border" />
          <nav aria-label="Secondary" className="flex flex-col">
            {SECONDARY_NAV.map((item) => (
              <SecondaryNavItem key={item.label} item={item} />
            ))}
          </nav>
        </div>
        <div className="mt-auto">
          <OperatorCard />
        </div>
      </aside>
      <main className="overflow-auto px-10 py-8">
        <Outlet />
      </main>
    </div>
  )
}

// Embed shell: chrome-free presentation surface used by `?embed=1` so the
// dashboard reads as "diagram + scrubber" in screen-share and slide-deck
// contexts. `Esc` exits, mirroring the universal "get me out of focus mode"
// affordance from full-screen viewers.
function EmbedShell({ onExit }: { onExit: () => void }) {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault()
        onExit()
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [onExit])

  return (
    <div className="relative h-full bg-cf-canvas" data-embed="true">
      <InboxNotifier />
      <button
        type="button"
        onClick={onExit}
        title="Exit embed mode (Esc)"
        aria-label="Exit embed mode"
        className="absolute right-4 top-4 z-10 inline-flex h-8 items-center gap-2 rounded-full border border-cf-border bg-cf-surface px-3 text-xs font-medium text-cf-ink-muted shadow-sm transition-colors hover:text-cf-ink"
        data-testid="exit-embed"
      >
        <span>Exit embed</span>
        <kbd
          aria-hidden
          className="rounded border border-cf-border bg-cf-surface-tint px-1.5 py-0.5 font-mono text-[10px] leading-none text-cf-ink-faint"
        >
          Esc
        </kbd>
      </button>
      <main className="h-full overflow-auto px-6 py-6">
        <Outlet />
      </main>
    </div>
  )
}

function BrandChip() {
  return (
    <div className="flex items-center gap-3">
      <div
        aria-hidden
        className="grid h-9 w-9 place-items-center rounded-lg bg-cf-ink font-mono text-[13px] font-semibold tracking-tight text-cf-surface"
      >
        cf
      </div>
      <div className="flex min-w-0 flex-col leading-tight">
        <span className="text-[15px] font-semibold text-cf-ink">ColouredFlow</span>
        <span className="text-[11px] uppercase tracking-[0.08em] text-cf-ink-faint">
          Dashboard
        </span>
      </div>
    </div>
  )
}

function PrimaryNavItem({ item }: { item: NavItem }) {
  const { to, label, icon: Icon, end } = item
  return (
    <NavLink
      to={to}
      end={end}
      className={({ isActive }) =>
        [
          "flex items-center gap-3 rounded-md px-3 py-2 text-sm transition-colors",
          isActive
            ? "bg-cf-accent-tint font-medium text-cf-accent-ink"
            : "text-cf-ink-muted hover:bg-cf-surface-tint hover:text-cf-ink"
        ].join(" ")
      }
    >
      {({ isActive }) => (
        <>
          <Icon size={16} weight={isActive ? "fill" : "regular"} />
          <span>{label}</span>
        </>
      )}
    </NavLink>
  )
}

// Secondary block: inert placeholders for now. Rendered as disabled list
// items so the affordance does not promise a link the click can't deliver;
// a "Soon" chip explains why nothing happens on click.
function SecondaryNavItem({ item }: { item: SecondaryItem }) {
  if (item.href) {
    return (
      <NavLink
        to={item.href}
        className="flex items-center gap-3 rounded-md px-3 py-2 text-[13px] text-cf-ink-muted hover:bg-cf-surface-tint hover:text-cf-ink"
      >
        <span className="grid h-4 w-4 place-items-center">
          <span className="h-1.5 w-1.5 rounded-full bg-cf-ink-faint" />
        </span>
        <span>{item.label}</span>
      </NavLink>
    )
  }
  return (
    <div
      aria-disabled="true"
      className="flex cursor-not-allowed items-center gap-3 rounded-md px-3 py-2 text-[13px] text-cf-ink-faint"
    >
      <span className="grid h-4 w-4 place-items-center">
        <span className="h-1.5 w-1.5 rounded-full bg-cf-ink-faint" />
      </span>
      <span className="flex-1">{item.label}</span>
      <span className="rounded-full border border-cf-border px-1.5 text-[10px] uppercase tracking-wide">
        Soon
      </span>
    </div>
  )
}

function OperatorCard() {
  return (
    <div className="flex items-center gap-3 rounded-xl border border-cf-border bg-cf-surface px-3 py-2.5">
      <div className="grid h-8 w-8 place-items-center rounded-full bg-cf-accent-tint text-[11px] font-semibold text-cf-accent-ink">
        OP
      </div>
      <div className="flex min-w-0 flex-1 flex-col leading-tight">
        <span className="truncate text-[13px] font-medium text-cf-ink">Operator</span>
        <span className="truncate text-[11px] text-cf-ink-muted">
          Local · all permissions
        </span>
      </div>
      <CaretRightIcon size={14} className="text-cf-ink-faint" />
    </div>
  )
}
