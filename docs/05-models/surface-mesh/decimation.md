# QEM Decimation

- **Source:** [`src/models/surface/decimation.zig`](../../../src/models/surface/decimation.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Exposed by:** [`SurfaceMeshConnectivity`](../../../src/modules/SurfaceMeshConnectivity.zig)

---

## Overview

Simplifies a `SurfaceMesh` by iteratively collapsing lowest-cost edges guided by [`qem.zig`](qem.md) Quadric Error Metrics until a target number of vertices has been removed.

## Key Entry Points

- `decimateQEM(sm, vertex_position, face_area, face_normal, nb_vertices_to_remove)` — Runs QEM edge-collapse decimation in place.

## Notes & Assumptions

- Triangulates the mesh first (`subdivision.triangulateFaces`), computes per-vertex QEMs (`qem.computeVertexQEMs`), and indexes collapsible edges in a min-heap (`utils/PriorityQueue.zig` tracked via `__edge_queue_index`).
- Re-validates `sm.canCollapseEdge` on pop, updates QEMs and adjacent edge costs after each collapse, anchors boundary vertices when collapsing an interior edge touching a boundary vertex, and falls back to the edge midpoint if the summed QEM is singular.
- Uses deterministic tie-breaking by edge index. Code notes a TODO to check for face flips before collapsing.
