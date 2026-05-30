import {
  forwardRef,
  useCallback,
  useEffect,
  useState,
  type AnchorHTMLAttributes
} from "react"
import { Link, Outlet, useLocation } from "react-router-dom"
import {
  GraphIcon,
  type Icon,
  ListChecksIcon,
  ListIcon,
  PulseIcon,
  TrayIcon
} from "@phosphor-icons/react"
import {
  LinkProvider,
  Sidebar,
  SidebarProvider,
  useSidebar
} from "@cloudflare/kumo"

import { useEmbedMode } from "../hooks/useEmbedMode"
import { useMusubiConnectionStatus } from "../musubi"
import ThemeToggle from "../components/ThemeToggle"
import InboxNotifier from "../components/InboxNotifier"
import { APP_VERSION } from "../lib/version"

// Magic UI gradient text. The dashboard design laws ban decorative gradient
// text; user explicitly overrode that ban for the brand mark + the footer
// status line. Two intentional accents, no more.
import { AuroraText } from "../components/magicui/aurora-text"
import { AnimatedShinyText } from "../components/magicui/animated-shiny-text"

const SIDEBAR_STORAGE_KEY = "cf-sidebar-collapsed"

interface NavItem {
  to: string
  label: string
  icon: Icon
  end?: boolean
}

const PRIMARY_NAV: readonly NavItem[] = [
  { to: "/", label: "Inbox", icon: TrayIcon, end: true },
  { to: "/enactments", label: "Enactments", icon: ListChecksIcon, end: false },
  { to: "/flows", label: "Flows", icon: GraphIcon, end: false },
  { to: "/telemetry", label: "Telemetry", icon: PulseIcon, end: false }
]

function readPersistedCollapsed(): boolean {
  if (typeof window === "undefined") return false
  try {
    return window.localStorage.getItem(SIDEBAR_STORAGE_KEY) === "true"
  } catch {
    return false
  }
}

function writePersistedCollapsed(collapsed: boolean): void {
  if (typeof window === "undefined") return
  try {
    window.localStorage.setItem(SIDEBAR_STORAGE_KEY, collapsed ? "true" : "false")
  } catch {
    // ignore
  }
}

// Bridge Kumo's `href`-based MenuButton into React Router so nav clicks stay
// client-side. LinkProvider wires every Kumo link in the subtree to this
// component.
const RouterAppLink = forwardRef<HTMLAnchorElement, AnchorHTMLAttributes<HTMLAnchorElement>>(
  ({ href, children, ...rest }, ref) => (
    <Link ref={ref} to={href ?? ""} {...rest}>
      {children}
    </Link>
  )
)
RouterAppLink.displayName = "RouterAppLink"

export default function RootLayout() {
  const { embed, exit } = useEmbedMode()
  const [open, setOpen] = useState<boolean>(() => !readPersistedCollapsed())

  const handleOpenChange = useCallback((next: boolean) => {
    setOpen(next)
    writePersistedCollapsed(!next)
  }, [])

  if (embed) {
    return <EmbedShell onExit={exit} />
  }

  return (
    <LinkProvider component={RouterAppLink}>
      <SidebarProvider
        open={open}
        onOpenChange={handleOpenChange}
        collapsible="icon"
        side="left"
        variant="sidebar"
      >
        <InboxNotifier />
        <div className="flex h-svh w-full bg-cf-canvas" data-embed="false">
          <Sidebar>
            <Sidebar.Header className="gap-3">
              <BrandHeader />
            </Sidebar.Header>
            <Sidebar.Content>
              <Sidebar.Group>
                <Sidebar.Menu>
                  {PRIMARY_NAV.map((item) => (
                    <PrimaryNavItem key={item.to} item={item} />
                  ))}
                </Sidebar.Menu>
              </Sidebar.Group>
            </Sidebar.Content>
            <Sidebar.Footer className="mt-auto gap-2 border-t border-cf-border">
              <SidebarFooterContent />
            </Sidebar.Footer>
          </Sidebar>
          <main className="relative isolate flex-1 overflow-auto px-10 py-8">
            <MobileSidebarTrigger />
            <Outlet />
          </main>
        </div>
      </SidebarProvider>
    </LinkProvider>
  )
}

function MobileSidebarTrigger() {
  const { toggleSidebar } = useSidebar()
  return (
    <button
      type="button"
      onClick={toggleSidebar}
      aria-label="Open navigation"
      data-testid="mobile-sidebar-trigger"
      className="fixed left-3 top-3 z-50 inline-flex h-9 w-9 items-center justify-center rounded-md border border-cf-border bg-cf-surface text-cf-ink shadow-sm md:hidden"
    >
      <ListIcon size={18} />
    </button>
  )
}

function BrandHeader() {
  const { state } = useSidebar()
  const collapsed = state === "collapsed"

  if (collapsed) {
    return (
      <div className="flex w-full flex-col items-center gap-1.5">
        <span
          data-testid="brand-wordmark"
          aria-label="Coloured Flow"
          className="grid h-7 w-7 place-items-center rounded-md bg-cf-accent-tint"
        >
          <AuroraText className="text-[13px] font-semibold tracking-tight">
            C
          </AuroraText>
        </span>
      </div>
    )
  }

  return (
    <div className="flex w-full items-start gap-2">
      <div
        className="flex min-w-0 flex-col leading-tight"
        data-testid="brand-wordmark"
      >
        <AuroraText className="text-[18px] font-bold tracking-tight">
          Coloured Flow
        </AuroraText>
        <span className="text-[10px] font-medium uppercase tracking-[0.16em] text-cf-ink-faint">
          Dashboard
        </span>
      </div>
    </div>
  )
}

function PrimaryNavItem({ item }: { item: NavItem }) {
  const { pathname } = useLocation()
  const { to, label, icon, end } = item
  const isActive = end ? pathname === to : pathname === to || pathname.startsWith(`${to}/`)

  return (
    <Sidebar.MenuItem>
      <Sidebar.MenuButton
        href={to}
        icon={icon}
        active={isActive}
        tooltip={label}
      >
        {label}
      </Sidebar.MenuButton>
    </Sidebar.MenuItem>
  )
}

type ConnectionView = {
  label: string
  dotClass: string
  shimmer: boolean
  textClass: string
}

function connectionView(state: "connecting" | "ready" | "error"): ConnectionView {
  switch (state) {
    case "ready":
      return {
        label: "Connected",
        dotClass: "bg-cf-dot-enabled",
        shimmer: false,
        textClass: "text-cf-accent-ink"
      }
    case "error":
      return {
        label: "Disconnected",
        dotClass: "bg-cf-dot-exception",
        shimmer: false,
        textClass: "text-cf-exception-ink"
      }
    case "connecting":
    default:
      return {
        label: "Connecting…",
        dotClass: "bg-cf-dot-started",
        shimmer: true,
        textClass: "text-cf-ink-muted"
      }
  }
}

function SidebarFooterContent() {
  const { state } = useSidebar()
  const collapsed = state === "collapsed"
  const status = useMusubiConnectionStatus()
  const view = connectionView(status.state)

  if (collapsed) {
    return (
      <div
        className="flex w-full flex-col items-center gap-2 py-1"
        data-testid="sidebar-footer-collapsed"
      >
        <span
          data-testid="connection-status"
          aria-label={`Connection ${view.label}. v${APP_VERSION}`}
          title={`${view.label} · v${APP_VERSION}`}
          className={`h-2 w-2 rounded-full ${view.dotClass}`}
        />
        <ThemeToggle iconOnly />
        <Sidebar.Trigger
          data-testid="sidebar-toggle"
          aria-label="Expand sidebar"
        />
      </div>
    )
  }

  return (
    <div
      className="flex w-full flex-row items-center gap-2 px-1 leading-tight"
      data-testid="sidebar-footer-expanded"
    >
      <span
        data-testid="connection-status"
        className="inline-flex min-w-0 flex-1 items-center gap-1.5 rounded-md border border-cf-border bg-cf-surface px-2 py-1 text-cf-ink"
      >
        <span
          aria-hidden="true"
          className={`h-1.5 w-1.5 shrink-0 rounded-full ${view.dotClass}`}
        />
        {view.shimmer ? (
          <AnimatedShinyText
            className={`text-[11px] font-medium ${view.textClass}`}
            duration={2.4}
          >
            {view.label}
          </AnimatedShinyText>
        ) : (
          <span className={`text-[11px] font-medium ${view.textClass}`}>
            {view.label}
          </span>
        )}
        <span aria-hidden="true" className="text-[11px] text-cf-ink-faint">
          ·
        </span>
        <span
          data-testid="app-version"
          aria-label={`App version ${APP_VERSION}`}
          className="text-[11px] font-medium text-cf-ink-muted"
        >
          v{APP_VERSION}
        </span>
      </span>
      <ThemeToggle iconOnly />
      <Sidebar.Trigger
        data-testid="sidebar-toggle"
        aria-label="Collapse sidebar"
      />
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
