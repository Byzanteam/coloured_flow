#!/usr/bin/env node
// Live-runtime smoke for the dashboard SPA.
//
// Pins two regressions the unit tests can't catch (they mock @musubi/client):
//
//   1. Bundle dedupe — without `resolve.dedupe` in vite.config.ts, the
//      workspace-linked `@musubi/react` drags its own react@18 copy into the
//      production bundle alongside the top-level react@19. React then throws
//      minified #525 in the browser (legacy element from older React).
//
//   2. WebSocket boot — opens a real Phoenix Socket against the running
//      dashboard and runs the same `connect()` call the SPA performs at
//      module-scope. Catches handshake-level regressions (e.g. the Musubi
//      0.6 `connect_info` crash fixed in P11.5) that JSDOM unit tests miss.
//
// Usage:
//   pnpm smoke                        # uses SMOKE_BASE_URL or http://127.0.0.1:4112
//   SMOKE_BASE_URL=http://127.0.0.1:4111 pnpm smoke
//
// Prereqs:
//   - `pnpm build` has produced ../priv/static/assets/index-*.js
//   - A Phoenix server is running at SMOKE_BASE_URL with /socket reachable
//
// Exit 0 on success, 1 on any failure. Each step logs a [smoke] line.

import { readFileSync, readdirSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const here = dirname(fileURLToPath(import.meta.url))
const assetsDir = join(here, "..", "..", "priv", "static", "assets")
const baseUrl = process.env.SMOKE_BASE_URL ?? "http://127.0.0.1:4112"

function log(msg) {
  process.stdout.write(`[smoke] ${msg}\n`)
}

function die(msg) {
  process.stderr.write(`[smoke] FAIL: ${msg}\n`)
  process.exit(1)
}

// ---------------------------------------------------------------------------
// Step 1: Bundle dedupe
// ---------------------------------------------------------------------------

function findBundle() {
  let entries
  try {
    entries = readdirSync(assetsDir)
  } catch (cause) {
    die(`no built bundle at ${assetsDir} (run \`pnpm build\` first): ${cause.message}`)
  }
  const js = entries.filter((f) => f.startsWith("index-") && f.endsWith(".js"))
  if (js.length !== 1) {
    die(`expected exactly one index-*.js in ${assetsDir}, found: ${js.join(", ") || "none"}`)
  }
  return join(assetsDir, js[0])
}

function assertSingleReactCopy(bundlePath) {
  const src = readFileSync(bundlePath, "utf8")
  // React injects its version literal into the runtime export. Two different
  // copies in one bundle ⇒ two version strings.
  const versions = Array.from(src.matchAll(/"(1[0-9]\.\d+\.\d+)"/g))
    .map((m) => m[1])
    .filter((v) => /^(18|19|20)\./.test(v))
  const unique = Array.from(new Set(versions))
  if (unique.length === 0) {
    die(`no React version string in ${bundlePath}; check the bundle is the real SPA build`)
  }
  if (unique.length > 1) {
    die(
      `bundle has ${unique.length} React copies (${unique.join(", ")}). ` +
        `vite.config.ts \`resolve.dedupe\` likely regressed.`
    )
  }
  log(`bundle dedupe ok — single React (${unique[0]})`)
}

// ---------------------------------------------------------------------------
// Step 2: Live WebSocket boot — exercises the same connect path as the SPA
// ---------------------------------------------------------------------------

async function assertConnectSucceeds() {
  if (typeof WebSocket === "undefined") {
    die("Node lacks global WebSocket; this script requires Node 22+")
  }

  const wsUrl = baseUrl.replace(/^http/, "ws") + "/socket"
  log(`opening Phoenix socket at ${wsUrl}`)

  const { Socket } = await import("phoenix")
  const socket = new Socket(wsUrl, {})

  // Mirror @musubi/client.connect(): open the socket and join the default
  // `musubi:connection` topic. That join is the exact handshake the SPA
  // performs at module-scope; any server-side regression on that path
  // (e.g. the Musubi 0.6 connect_info nil-session crash) fails here.
  socket.connect()
  const channel = socket.channel("musubi:connection", {})

  const joined = await new Promise((resolve) => {
    const timer = setTimeout(() => resolve({ ok: false, reason: "timeout (10s)" }), 10_000)
    channel
      .join()
      .receive("ok", () => {
        clearTimeout(timer)
        resolve({ ok: true })
      })
      .receive("error", (reason) => {
        clearTimeout(timer)
        resolve({ ok: false, reason: JSON.stringify(reason) })
      })
      .receive("timeout", () => {
        clearTimeout(timer)
        resolve({ ok: false, reason: "phoenix join timeout" })
      })
  })

  try {
    channel.leave()
    socket.disconnect()
  } catch {
    /* shutdown best-effort */
  }

  if (!joined.ok) die(`musubi:connection join failed: ${joined.reason}`)
  log("WS join ok — musubi:connection channel ready")
}

// ---------------------------------------------------------------------------
// Step 3: Mount InboxStore root and prove the page server stays mounted
// ---------------------------------------------------------------------------
//
// Pins the regression behind the `useMusubiRoot` swap on InboxPage /
// EnactmentDetailPage: with `useMusubiRootSuspense`, @musubi/react@0.6.0's
// `scheduleSuspenseOrphanSweep` races React 19's passive-effect flush and
// the client tears down + re-mounts the InboxStore root forever (~25ms per
// cycle, ~50% CPU on the BEAM, page stuck on the Suspense fallback). The
// SPA itself no longer takes that path, but a real Phoenix Socket can still
// drive the loop end-to-end. Mount once, watch for `patch` envelopes for a
// short observation window, and FAIL if the server unmounts us — that would
// only happen if a subsequent `mount` call returned `already_mounted`, which
// is the loop's tell on the wire.

async function assertInboxRootStaysMounted() {
  const { Socket } = await import("phoenix")
  const wsUrl = baseUrl.replace(/^http/, "ws") + "/socket"
  const socket = new Socket(wsUrl, {})
  socket.connect()
  const channel = socket.channel("musubi:connection", {})

  const joined = await new Promise((resolve) => {
    const timer = setTimeout(() => resolve({ ok: false, reason: "timeout (10s)" }), 10_000)
    channel
      .join()
      .receive("ok", () => {
        clearTimeout(timer)
        resolve({ ok: true })
      })
      .receive("error", (reason) => {
        clearTimeout(timer)
        resolve({ ok: false, reason: JSON.stringify(reason) })
      })
  })

  if (!joined.ok) {
    try { socket.disconnect() } catch { /* best-effort */ }
    die(`musubi:connection join failed: ${joined.reason}`)
  }

  let patches = 0
  channel.on("patch", () => { patches += 1 })

  const mounted = await new Promise((resolve) => {
    const timer = setTimeout(() => resolve({ ok: false, reason: "mount timeout (5s)" }), 5_000)
    channel
      .push("mount", {
        module: "ColouredFlowDashboardWeb.Stores.InboxStore",
        id: "default",
        params: {}
      })
      .receive("ok", (reply) => {
        clearTimeout(timer)
        resolve({ ok: true, reply })
      })
      .receive("error", (reason) => {
        clearTimeout(timer)
        resolve({ ok: false, reason: JSON.stringify(reason) })
      })
  })

  if (!mounted.ok) {
    try { socket.disconnect() } catch { /* best-effort */ }
    die(`InboxStore mount failed: ${mounted.reason}`)
  }

  // Observe for 1.5s. With a healthy mount the page server sends the initial
  // patch envelope within a few ms and then idles. With the broken Suspense
  // path the client would have sent another `mount` long before now — and the
  // server would reply with `already_mounted` — but we only mount once here,
  // so the spin signature is a second `mount` reply via push race. The robust
  // tell is: did a SECOND mount push succeed? If yes, the server unmounted us
  // (root already gone) and the loop's foot-shot would have repeated.
  await new Promise((r) => setTimeout(r, 1_500))

  // Re-mount and expect `already_mounted` — that's how we know the first mount
  // is still alive. If the page server is gone (would happen if the server
  // had unmounted us mid-window), this would succeed instead.
  const remount = await new Promise((resolve) => {
    const timer = setTimeout(() => resolve({ ok: false, reason: "remount timeout (3s)" }), 3_000)
    channel
      .push("mount", {
        module: "ColouredFlowDashboardWeb.Stores.InboxStore",
        id: "default",
        params: {}
      })
      .receive("ok", () => {
        clearTimeout(timer)
        resolve({ ok: true })
      })
      .receive("error", (reason) => {
        clearTimeout(timer)
        resolve({ ok: false, reason })
      })
  })

  try {
    channel.push("unmount", { root_id: "default" })
    await new Promise((r) => setTimeout(r, 50))
    channel.leave()
    socket.disconnect()
  } catch { /* best-effort */ }

  if (patches < 1) {
    die(`InboxStore mounted but no initial patch envelope arrived (patches=${patches})`)
  }
  if (remount.ok) {
    die(
      "InboxStore second mount returned ok — first mount is gone. The page server " +
        "was unmounted from under us, which is the broken Suspense-sweep symptom."
    )
  }
  const reason = remount.reason
  const reasonText =
    typeof reason === "string"
      ? reason
      : reason && typeof reason === "object" && typeof reason.reason === "string"
        ? reason.reason
        : JSON.stringify(reason)
  if (!/already.?mounted/i.test(reasonText)) {
    die(`unexpected remount rejection: ${reasonText}`)
  }
  log(`InboxStore mount stable — patches=${patches}, remount rejected with "${reasonText}"`)
}

// ---------------------------------------------------------------------------

const bundle = findBundle()
log(`scanning ${bundle}`)
assertSingleReactCopy(bundle)
await assertConnectSucceeds()
await assertInboxRootStaysMounted()
log("OK")
