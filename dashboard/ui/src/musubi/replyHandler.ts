import { MusubiCommandError } from "@musubi/react"

/**
 * Shared dispatcher wrapper that collapses the resolved AND rejected paths of
 * a `useMusubiCommand` dispatch into a single `(code, reply)` switch on the
 * caller side.
 *
 * Background (P10 review): Musubi rejects every non-"ok" envelope into the
 * catch branch with a `MusubiCommandError` whose `cause.reply` carries the
 * server-side reply (`code` plus ad-hoc fields like `variable` /
 * `workitem_id` / `message`). The InboxPage drawer was the first consumer to
 * unify both paths; the same helper is now reused by the
 * EnactmentDetailPage's action bar and per-row buttons so each command keeps
 * a single decoder.
 *
 * `onReply` is called with the structured reply for both resolved AND
 * rejected envelopes. `onUnexpected` fires for non-Musubi exceptions
 * (network, runtime crash, timeout w/o reply); callers should surface a
 * generic error toast there.
 */
export interface DispatchOptions<Code extends string> {
  onReply: (code: Code, reply: Record<string, unknown>) => void
  onUnexpected?: (cause: unknown) => void
}

export async function dispatchWithReply<Code extends string>(
  dispatch: (payload: Record<string, unknown>) => Promise<{ code?: string } & Record<string, unknown>>,
  payload: Record<string, unknown>,
  { onReply, onUnexpected }: DispatchOptions<Code>
): Promise<void> {
  try {
    const reply = await dispatch(payload)
    onReply(((reply.code as Code) ?? "ok") as Code, reply as Record<string, unknown>)
  } catch (cause) {
    if (MusubiCommandError.is(cause)) {
      const reply = (cause.reply ?? { code: cause.code }) as Record<string, unknown>
      const code = ((cause.code ?? reply.code) as Code | undefined) ?? ("runner_error" as Code)
      onReply(code, reply)
      return
    }
    if (onUnexpected) {
      onUnexpected(cause)
    } else {
      throw cause
    }
  }
}
