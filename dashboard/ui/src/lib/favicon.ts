// Favicon overlay: paint a small accent-coloured dot in the top-right corner
// of the existing favicon to surface "something happened off-screen". A
// 32×32 canvas is rendered once on first toggle-on, swapped onto the
// document's `<link rel=icon>`, and restored to the original href on
// toggle-off. Works in every modern browser without service-worker plumbing.

const ORIGINAL_HREF: { value: string | null } = { value: null }
let dotIconUrl: string | null = null

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

function buildDotIcon(baseHref: string): Promise<string> {
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
      paintDot(ctx)
      resolve(canvas.toDataURL("image/png"))
    }
    img.onerror = () => {
      ctx.fillStyle = "#f6f5f3"
      ctx.fillRect(0, 0, 32, 32)
      paintDot(ctx)
      resolve(canvas.toDataURL("image/png"))
    }
    img.src = baseHref
  })
}

function paintDot(ctx: CanvasRenderingContext2D) {
  // Accent ink ≈ oklch(0.42 0.13 38). Browsers don't paint OKLCH directly to
  // canvas in older releases, so use the same hue in sRGB hex.
  ctx.beginPath()
  ctx.arc(24, 8, 7, 0, Math.PI * 2)
  // Hex literals here are a workaround: the canvas 2D context does not
  // accept OKLCH in every browser the dashboard supports yet, so the two
  // values are the sRGB projection of `--color-cf-accent-ink` and
  // `--color-cf-surface` respectively.
  ctx.fillStyle = "#bb4d18"
  ctx.fill()
  ctx.lineWidth = 2
  ctx.strokeStyle = "#fdfdfc"
  ctx.stroke()
}

export async function setFaviconDot(on: boolean): Promise<void> {
  const link = ensureLink()
  if (!link) return
  if (!on) {
    if (ORIGINAL_HREF.value) link.href = ORIGINAL_HREF.value
    return
  }
  if (dotIconUrl === null) {
    dotIconUrl = await buildDotIcon(ORIGINAL_HREF.value ?? "/favicon.ico")
  }
  link.href = dotIconUrl
}
