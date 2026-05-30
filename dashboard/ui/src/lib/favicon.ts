// Favicon overlay: paint a small accent-coloured dot in the top-right corner
// of the existing favicon to surface "something happened off-screen". A
// 32×32 canvas is rendered once per theme mode and cached; swapping themes
// invalidates the cache so the dot tracks the active palette.

const ORIGINAL_HREF: { value: string | null } = { value: null }
const ICON_CACHE = new Map<string, string>()

function ensureLink(): HTMLLinkElement | null {
  if (typeof document === "undefined") return null
  let link = document.querySelector<HTMLLinkElement>("link[rel~='icon']")
  if (!link) {
    link = document.createElement("link")
    link.rel = "icon"
    document.head.appendChild(link)
  }
  if (ORIGINAL_HREF.value === null) {
    ORIGINAL_HREF.value = link.getAttribute("href") ?? "/favicon.ico"
  }
  return link
}

// Light + dark palette projections of `--color-cf-accent-ink` and
// `--color-cf-surface`. Canvas 2D rejects OKLCH in some supported browsers,
// so the values are the sRGB closest match held in code.
const PALETTE = {
  light: { dot: "#bb4d18", ring: "#fdfdfc" },
  dark: { dot: "#f08a4d", ring: "#2a2438" }
} as const
type ModeKey = keyof typeof PALETTE

function activeMode(): ModeKey {
  if (typeof document === "undefined") return "light"
  const attr = document.documentElement.getAttribute("data-mode")
  if (attr === "dark") return "dark"
  return "light"
}

function buildDotIcon(baseHref: string, mode: ModeKey): Promise<string> {
  return new Promise((resolve) => {
    if (typeof document === "undefined") {
      resolve(baseHref)
      return
    }
    const canvas = document.createElement("canvas")
    canvas.width = 32
    canvas.height = 32
    const ctx = canvas.getContext("2d")
    if (!ctx) {
      resolve(baseHref)
      return
    }
    const img = new Image()
    img.crossOrigin = "anonymous"
    img.onload = () => {
      ctx.drawImage(img, 0, 0, 32, 32)
      paintDot(ctx, mode)
      resolve(canvas.toDataURL("image/png"))
    }
    img.onerror = () => {
      ctx.fillStyle = mode === "dark" ? "#2a2438" : "#f6f5f3"
      ctx.fillRect(0, 0, 32, 32)
      paintDot(ctx, mode)
      resolve(canvas.toDataURL("image/png"))
    }
    img.src = baseHref
  })
}

function paintDot(ctx: CanvasRenderingContext2D, mode: ModeKey) {
  const { dot, ring } = PALETTE[mode]
  ctx.beginPath()
  ctx.arc(24, 8, 7, 0, Math.PI * 2)
  ctx.fillStyle = dot
  ctx.fill()
  ctx.lineWidth = 2
  ctx.strokeStyle = ring
  ctx.stroke()
}

export async function setFaviconDot(on: boolean): Promise<void> {
  const link = ensureLink()
  if (!link) return
  if (!on) {
    if (ORIGINAL_HREF.value) link.href = ORIGINAL_HREF.value
    return
  }
  const mode = activeMode()
  let cached = ICON_CACHE.get(mode)
  if (!cached) {
    cached = await buildDotIcon(ORIGINAL_HREF.value ?? "/favicon.ico", mode)
    ICON_CACHE.set(mode, cached)
  }
  link.href = cached
}
