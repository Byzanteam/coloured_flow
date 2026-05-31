import { useCallback } from "react"
import { useSearchParams } from "react-router-dom"

const EMBED_PARAM = "embed"
const EMBED_VALUE = "1"

/**
 * Embed mode is purely a URL concern: `?embed=1` flips the dashboard into
 * full-bleed, chrome-free presentation mode. Hooked into the URL so the
 * preference shares cleanly via copy-paste (live screen-share, iframe in
 * a slide deck, etc.) without any session state.
 */
export function useEmbedMode(): {
  embed: boolean
  exit: () => void
} {
  const [params, setParams] = useSearchParams()
  const embed = params.get(EMBED_PARAM) === EMBED_VALUE

  const exit = useCallback(() => {
    if (!params.has(EMBED_PARAM)) return
    const next = new URLSearchParams(params)
    next.delete(EMBED_PARAM)
    setParams(next, { replace: true })
  }, [params, setParams])

  return { embed, exit }
}
