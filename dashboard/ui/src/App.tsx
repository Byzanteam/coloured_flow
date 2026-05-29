import { Component, type ReactNode, Suspense, use } from "react"
import { RouterProvider } from "react-router-dom"
import { Banner, Button, Toasty } from "@cloudflare/kumo"

import { MusubiProvider, connect, socket } from "./musubi"
import { router } from "./routes/router"

// Module-scope: `connect(socket)` runs exactly once, regardless of how many
// times React mounts/unmounts <App /> (notably under StrictMode's intentional
// double-invoke). The resolved Connection is shared across every route, so
// React Router navigation can never tear down or recreate the socket.
const connectionPromise = connect(socket)

function ConnectedApp() {
  const connection = use(connectionPromise)
  return (
    <MusubiProvider connection={connection}>
      <Toasty>
        <RouterProvider router={router} />
      </Toasty>
    </MusubiProvider>
  )
}

type ConnectionErrorBoundaryProps = { children: ReactNode }
type ConnectionErrorBoundaryState = { error: Error | null }

// React 19 ships no ErrorBoundary primitive; a small class component is the
// least-deps option (react-error-boundary would add a package for ~10 lines).
// Suspense catches pending thenables but not rejected ones, so without this
// boundary a `connect()` failure crashes the root render to a blank screen.
class ConnectionErrorBoundary extends Component<
  ConnectionErrorBoundaryProps,
  ConnectionErrorBoundaryState
> {
  state: ConnectionErrorBoundaryState = { error: null }

  static getDerivedStateFromError(error: unknown): ConnectionErrorBoundaryState {
    return {
      error: error instanceof Error ? error : new Error(String(error))
    }
  }

  render() {
    const { error } = this.state
    if (!error) return this.props.children

    // Retry forces a full reload: `connectionPromise` is module-scope and a
    // rejected promise cannot be re-awaited. A page reload re-evaluates the
    // module and gets a fresh promise. Structured in-app retry lands later
    // alongside the telemetry bridge.
    return (
      <div className="grid h-full place-items-center p-6">
        <Banner
          variant="error"
          title="Connect failed"
          description={error.message}
          action={
            <Button
              variant="primary"
              size="sm"
              onClick={() => window.location.reload()}
            >
              Retry
            </Button>
          }
        />
      </div>
    )
  }
}

export default function App() {
  return (
    <ConnectionErrorBoundary>
      <Suspense
        fallback={
          <div className="grid h-full place-items-center text-kumo-subtle">
            Connecting to ColouredFlow Dashboard…
          </div>
        }
      >
        <ConnectedApp />
      </Suspense>
    </ConnectionErrorBoundary>
  )
}
