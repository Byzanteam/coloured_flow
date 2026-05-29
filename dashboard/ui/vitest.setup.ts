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
