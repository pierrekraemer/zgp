# Within-Sphere Selection

- **Source:** [`src/models/surface/selection.zig`](../../../src/models/surface/selection.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Used by:** [`curvature.zig`](curvature.md), [`SurfaceMeshSelection`](../../../src/modules/SurfaceMeshSelection.zig)

---

## Overview

Collects all mesh vertices, edges, and faces lying within a Euclidean sphere around a seed vertex via breadth-first traversal, along with outgoing darts crossing the sphere boundary.

## Key Types & Entry Points

- `WithinSphereSelectionContext`:
  - `init(sm)` / `deinit()` / `reset()`
  - `cellsWithinSphereAroundVertex(sm, vertex_position, center_vertex, radius)` — Populates `vertex_buffer`, `edge_buffer`, `face_buffer`, and `crossed_dart_buffer`.

## Notes & Assumptions

- Uses a `SurfaceMesh.DartMarker` and reusable `ArrayList` buffers allocated from `sm.allocator`.
- Exposes `initialized: bool` and `deinit()` so it can be lazily initialized per worker slot inside `SurfaceMesh.ParallelVertexTaskRunnerWithContext` (as done in `curvature.zig`).
