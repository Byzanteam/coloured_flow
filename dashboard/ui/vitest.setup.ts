import React from "react"
import { vi } from "vitest"

// `@cloudflare/kumo/code` pulls in Shiki via dynamic imports inside a
// `useEffect`. Under jsdom that resolves at unpredictable timing and the
// component's `useShikiHighlighter` hook throws when no ShikiProvider is
// in the tree. Tests don't care about syntax-highlighted output — they
// assert on the JSON payload content. Stub both exports so the surfaces
// render the code as plain text (a `<pre data-testid="code-highlighted">`)
// and ShikiProvider is a transparent passthrough.
vi.mock("@cloudflare/kumo/code", () => {
  return {
    ShikiProvider: ({ children }: { children: React.ReactNode }) =>
      React.createElement(React.Fragment, null, children),
    CodeHighlighted: ({ code }: { code: string }) =>
      React.createElement(
        "pre",
        { "data-testid": "code-highlighted" },
        code
      )
  }
})

// JSDOM lacks ResizeObserver. Kumo's Tabs component (and any Kumo primitive
// backed by Base UI) relies on it to measure indicator geometry. Stub a noop
// so the Tabs render does not throw inside `useEffect`.
class ResizeObserverStub {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}

if (typeof globalThis.ResizeObserver === "undefined") {
  globalThis.ResizeObserver = ResizeObserverStub as unknown as typeof ResizeObserver
}

if (typeof window !== "undefined" && typeof (window as unknown as { ResizeObserver?: unknown }).ResizeObserver === "undefined") {
  ;(window as unknown as { ResizeObserver: unknown }).ResizeObserver = ResizeObserverStub
}

// JSDOM lacks PointerEvent. Kumo's Base UI primitives (Checkbox, Dialog,
// Select) call `new PointerEvent(...)` inside their interaction handlers; the
// outputs drawer's Checkbox click would otherwise throw
// `PointerEvent is not a constructor`. Reuse MouseEvent — the underlying
// React synthetic-event shape is rich enough that the Base UI handlers do
// not actually inspect pointer-specific fields in the click path.
if (typeof globalThis.PointerEvent === "undefined") {
  class PointerEventStub extends (globalThis.MouseEvent as unknown as typeof MouseEvent) {
    constructor(type: string, init?: MouseEventInit) {
      super(type, init)
    }
  }
  ;(globalThis as unknown as { PointerEvent: unknown }).PointerEvent = PointerEventStub
  if (typeof window !== "undefined") {
    ;(window as unknown as { PointerEvent: unknown }).PointerEvent = PointerEventStub
  }
}

// JSDOM Element lacks `hasPointerCapture` / `setPointerCapture` /
// `releasePointerCapture`. Base UI Select reads them during open/close. Stub
// them as noops to dodge `is not a function` crashes during interaction.
if (typeof window !== "undefined") {
  const proto = (window.Element as unknown as { prototype: Record<string, unknown> }).prototype
  if (typeof proto.hasPointerCapture !== "function") proto.hasPointerCapture = () => false
  if (typeof proto.setPointerCapture !== "function") proto.setPointerCapture = () => {}
  if (typeof proto.releasePointerCapture !== "function") proto.releasePointerCapture = () => {}
}
