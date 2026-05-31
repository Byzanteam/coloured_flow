import { Socket } from "phoenix"
import { createMusubi } from "@musubi/react"

// Relative URL — phoenix.js Socket() prepends ws://<window.location.host>.
// Dev: vite proxy at /socket forwards to phx:4000 (works for LAN clients too).
// Prod: phx serves /socket directly.
const SOCKET_URL = "/socket"

export const socket = new Socket(SOCKET_URL, {})

export const {
  connect,
  MusubiProvider,
  useMusubiCommand,
  useMusubiConnection,
  useMusubiConnectionStatus,
  useMusubiRoot,
  useMusubiRootSuspense,
  useMusubiSnapshot
} = createMusubi<Musubi.Stores>()
