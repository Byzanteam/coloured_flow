import { NavLink, Outlet } from "react-router-dom"
import {
  CaretRightIcon,
  GraphIcon,
  type Icon,
  TrayIcon
} from "@phosphor-icons/react"

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
  return (
    <div className="grid h-full grid-cols-[16rem_1fr] bg-cf-canvas">
      <aside className="flex flex-col gap-7 bg-cf-surface px-5 py-7">
        <BrandChip />
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

// Secondary block: inert placeholders for now (M7 polish wires real routes).
// Rendered as plain anchors so React Router doesn't treat them as live links.
function SecondaryNavItem({ item }: { item: SecondaryItem }) {
  return (
    <a
      href={item.href ?? "#"}
      aria-disabled={!item.href}
      onClick={(e) => {
        if (!item.href) e.preventDefault()
      }}
      className="flex items-center gap-3 rounded-md px-3 py-2 text-[13px] text-cf-ink-muted opacity-80 hover:bg-cf-surface-tint hover:opacity-100"
    >
      <span className="grid h-4 w-4 place-items-center">
        <span className="h-1.5 w-1.5 rounded-full bg-cf-ink-faint" />
      </span>
      <span>{item.label}</span>
    </a>
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
