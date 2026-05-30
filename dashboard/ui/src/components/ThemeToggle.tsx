import { useEffect, useState } from "react"
import { MoonIcon, SunIcon } from "@phosphor-icons/react"

type Theme = "light" | "dark" | "system"

const STORAGE_KEY = "cf-theme"

function readStored(): Theme {
  if (typeof window === "undefined") return "system"
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY)
    if (raw === "light" || raw === "dark" || raw === "system") return raw
  } catch {
    // ignore
  }
  return "system"
}

function resolvedMode(theme: Theme): "light" | "dark" {
  if (theme !== "system") return theme
  if (typeof window === "undefined" || !window.matchMedia) return "light"
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
}

function applyTheme(theme: Theme) {
  if (typeof document === "undefined") return
  const root = document.documentElement
  if (theme === "system") {
    root.removeAttribute("data-theme")
  } else {
    root.setAttribute("data-theme", theme)
  }
  // `data-mode` mirrors the resolved (system-or-manual) mode so Kumo's
  // `[data-mode="dark"]` rules and the dashboard's own `:root[data-mode]`
  // overrides flip together. Required because CSS media queries cannot set
  // attribute state, only properties.
  root.setAttribute("data-mode", resolvedMode(theme))
}

// Apply the persisted theme at module-import time so the page paints in the
// correct palette on first render (avoids a single-frame light-on-dark flash
// while the React tree commits).
if (typeof document !== "undefined") {
  applyTheme(readStored())
}

/**
 * Manual dark/light/system toggle. Persisted in localStorage and applied via
 * `data-theme="dark|light"` on `<html>`. The CSS in `app.css` flips the
 * `--color-cf-*` tokens when the attribute is set; absence falls back to
 * `prefers-color-scheme`.
 */
export default function ThemeToggle() {
  const [theme, setTheme] = useState<Theme>(() => readStored())

  useEffect(() => {
    applyTheme(theme)
    try {
      window.localStorage.setItem(STORAGE_KEY, theme)
    } catch {
      // ignore
    }
  }, [theme])

  // While the user is on "system", track OS-level dark/light flips at runtime
  // so the dashboard recolors without a refresh. Disconnected when the user
  // picks an explicit theme.
  useEffect(() => {
    if (theme !== "system") return
    if (typeof window === "undefined" || !window.matchMedia) return
    const mq = window.matchMedia("(prefers-color-scheme: dark)")
    const onChange = () => applyTheme("system")
    mq.addEventListener?.("change", onChange)
    return () => mq.removeEventListener?.("change", onChange)
  }, [theme])

  const next: Theme = theme === "dark" ? "light" : theme === "light" ? "system" : "dark"
  const label =
    theme === "dark"
      ? "Switch to light theme"
      : theme === "light"
        ? "Use system theme"
        : "Switch to dark theme"

  return (
    <button
      type="button"
      onClick={() => setTheme(next)}
      aria-label={label}
      title={label}
      data-testid="theme-toggle"
      data-theme-current={theme}
      className="flex items-center gap-2 rounded-md border border-cf-border bg-cf-surface px-2.5 py-1.5 text-xs text-cf-ink-muted hover:text-cf-ink"
    >
      {theme === "dark" ? (
        <SunIcon size={14} weight="bold" aria-hidden />
      ) : (
        <MoonIcon size={14} weight="bold" aria-hidden />
      )}
      <span className="capitalize">{theme}</span>
    </button>
  )
}
