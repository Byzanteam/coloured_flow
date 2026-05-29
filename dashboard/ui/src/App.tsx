import { RouterProvider } from "react-router-dom"

import { MusubiProvider, socket, useMusubiConnectionStatus } from "./musubi"
import { router } from "./routes/router"

function AppShell() {
  const status = useMusubiConnectionStatus()

  if (status.state === "connecting") {
    return (
      <div className="grid h-full place-items-center text-kumo-subtle">
        Connecting to ColouredFlow Dashboard…
      </div>
    )
  }

  if (status.state === "error") {
    return (
      <div className="grid h-full place-items-center text-red-500">
        Connect failed: {status.error.message}
      </div>
    )
  }

  return <RouterProvider router={router} />
}

export default function App() {
  return (
    <MusubiProvider socket={socket}>
      <AppShell />
    </MusubiProvider>
  )
}
