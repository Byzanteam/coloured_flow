import pkg from "../../package.json" with { type: "json" }

export const APP_VERSION: string = (pkg as { version?: string }).version ?? "0.0.0"
