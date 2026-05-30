// Parse-safe JSON pretty-printer. Falls back to the raw string when the
// payload is empty or not valid JSON so the rendering surface still has
// something visible for the operator to copy.
export function prettyJson(raw: string): string {
  if (!raw) return ""
  try {
    return JSON.stringify(JSON.parse(raw), null, 2)
  } catch {
    return raw
  }
}
