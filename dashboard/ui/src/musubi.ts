import { Socket } from "phoenix"
import { createMusubi } from "@musubi/react"

const SOCKET_URL = import.meta.env.DEV ? "ws://localhost:4000/socket" : "/socket"

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
