import { useEffect, useRef } from "react"
import { useLocation } from "react-router-dom"
import { useKumoToastManager } from "@cloudflare/kumo"

import { useMusubiRoot, useMusubiSnapshot } from "../musubi"
import type { MusubiRootMount } from "@musubi/react"
import { setFaviconDot } from "../lib/favicon"

const INBOX_STORE = "ColouredFlowDashboardWeb.Stores.InboxStore" as const
type WorkitemRow = ColouredFlowDashboardWeb.Views.WorkitemRow
type InboxRootMount = MusubiRootMount<typeof INBOX_STORE, Musubi.Stores>
type InboxProxy = NonNullable<Extract<InboxRootMount, { status: "ready" }>["store"]>

/**
 * Cross-route inbox awareness: while the operator is on any non-inbox page
 * (`/enactments/:id`, `/flows/...`), surface a Kumo toast + a favicon dot
 * the moment a new workitem appears on the live inbox stream. The toast
 * links back to `/`. The dot clears when the inbox page is visited.
 *
 * Backed by a refcounted `useMusubiRoot({ id: "default" })` mount that the
 * inbox page also subscribes to — Musubi's shared-mount table guarantees a
 * single server-side root regardless of how many React subscribers exist.
 */
export default function InboxNotifier() {
  const root = useMusubiRoot({ module: INBOX_STORE, id: "default" })
  if (root.status !== "ready") return null
  return <InboxNotifierBody inbox={root.store} />
}

function InboxNotifierBody({ inbox }: { inbox: InboxProxy }) {
  const snapshot = useMusubiSnapshot(inbox)
  const location = useLocation()
  const toasts = useKumoToastManager()

  const workitems: readonly WorkitemRow[] = snapshot.workitems ?? []

  // The first snapshot the notifier observes is the catch-up batch loaded at
  // mount, not "new" — record those ids so the operator does not get spammed
  // on first navigation off the inbox.
  const seenRef = useRef<Set<string> | null>(null)
  const onInbox = location.pathname === "/"

  useEffect(() => {
    if (onInbox) {
      setFaviconDot(false)
    }
  }, [onInbox])

  useEffect(() => {
    const ids = new Set(workitems.map((wi) => wi.id))
    const prior = seenRef.current
    if (prior === null) {
      seenRef.current = ids
      return
    }
    const additions: WorkitemRow[] = []
    for (const wi of workitems) {
      if (!prior.has(wi.id)) additions.push(wi)
    }
    seenRef.current = ids

    if (additions.length === 0) return
    if (onInbox) return

    void setFaviconDot(true)
    toasts.add({
      variant: "info",
      title:
        additions.length === 1
          ? "1 new workitem waiting"
          : `${additions.length} new workitems waiting`,
      description: "Live inbox stream picked up new items. View inbox to act.",
      timeout: 6000
    })
  }, [workitems, onInbox, toasts])

  return null
}
