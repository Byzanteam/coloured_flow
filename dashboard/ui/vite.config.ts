import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"
import tailwindcss from "@tailwindcss/vite"

export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: {
    outDir: "../priv/static",
    emptyOutDir: true,
    assetsDir: "assets"
  },
  server: {
    port: 4103,
    strictPort: false,
    proxy: {
      "/socket": {
        target: "http://localhost:4000",
        ws: true,
        changeOrigin: true
      },
      "/api": {
        target: "http://localhost:4000",
        changeOrigin: true
      }
    }
  },
  test: {
    environment: "jsdom",
    globals: true,
    include: ["src/**/*.test.{ts,tsx}"]
  }
})
