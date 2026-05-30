import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"
import tailwindcss from "@tailwindcss/vite"

export default defineConfig({
  plugins: [react(), tailwindcss()],
  // @musubi/react is linked from the arbor workspace; its local
  // node_modules/react resolves to react@18.3.1 (a devDep of that package),
  // while dashboard/ui pulls react@19.2.6 at top level. Without dedupe,
  // Vite bundles both copies and React throws minified #525
  // (element from older React version mounted by newer reconciler).
  // The scripts/smoke.mjs bundle scan pins this invariant.
  resolve: {
    dedupe: ["react", "react-dom", "react/jsx-runtime"]
  },
  build: {
    outDir: "../priv/static",
    emptyOutDir: true,
    assetsDir: "assets",
    rollupOptions: {
      output: {
        // Split heavy third-party deps off the app chunk so the SPA bundle
        // stays cache-friendly when only product code changes. React + ReactDOM
        // sit in their own chunk because they're touched every page; the
        // diagram and chrome bundles load conditionally with their routes.
        manualChunks: {
          "vendor-react": ["react", "react-dom", "react/jsx-runtime", "react-router-dom"],
          "vendor-diagram": ["@xyflow/react", "@dagrejs/dagre"],
          "vendor-chrome": ["@cloudflare/kumo", "@phosphor-icons/react"]
        }
      }
    }
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
    include: ["src/**/*.test.{ts,tsx}"],
    setupFiles: ["./vitest.setup.ts"]
  }
})
