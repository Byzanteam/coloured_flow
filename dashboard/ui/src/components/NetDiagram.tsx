import { ReactFlow, Background, Controls } from "@xyflow/react"

// Placeholder. M4 (Phase 15) wires real places / transitions / arcs
// from cpnet, custom Kumo Surface node renderers, and the badge/glow
// overlays. For now an empty canvas proves the dep is installed and
// renders without console errors.
export default function NetDiagram() {
  return (
    <ReactFlow nodes={[]} edges={[]} fitView>
      <Background />
      <Controls />
    </ReactFlow>
  )
}
