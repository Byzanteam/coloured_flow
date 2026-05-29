import { describe, expect, it } from "vitest"

import { routes } from "./router"

function collect(rs: typeof routes, prefix = ""): string[] {
  const out: string[] = []
  for (const r of rs) {
    const here = r.index ? prefix || "/" : joinPath(prefix, r.path ?? "")
    if (r.element) out.push(here)
    if (r.children) out.push(...collect(r.children, here))
  }
  return out
}

function joinPath(a: string, b: string): string {
  if (!b) return a || "/"
  if (b.startsWith("/")) return b
  const left = a.replace(/\/$/, "")
  return left + "/" + b
}

describe("router config", () => {
  const paths = collect(routes)

  it("mounts the inbox at /", () => {
    expect(paths).toContain("/")
  })

  it("mounts the enactment detail at /enactments/:id", () => {
    expect(paths).toContain("/enactments/:id")
  })

  it("mounts the flow catalog index and detail", () => {
    expect(paths).toContain("/flows")
    expect(paths).toContain("/flows/:module")
  })

  it("has a fallback route", () => {
    expect(paths).toContain("/*")
  })
})
