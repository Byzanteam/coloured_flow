import { Suspense, use } from "react"
import { RouterProvider } from "react-router-dom"

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
      <RouterProvider router={router} />
    </MusubiProvider>
  )
}

export default function App() {
  return (
    <Suspense
      fallback={
        <div className="grid h-full place-items-center text-kumo-subtle">
          Connecting to ColouredFlow Dashboard…
        </div>
      }
    >
      <ConnectedApp />
    </Suspense>
  )
}
