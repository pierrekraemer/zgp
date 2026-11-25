# SQEM (SurfaceMesh)

- **Source:** [`src/models/surface/sqem.zig`](../../../src/models/surface/sqem.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Used by:** [`medial_axis.zig`](medial-axis.md)

---

## Overview

Computes per-vertex **Spherical Quadric Error Metrics** (`SQEM`, defined in [`src/geometry/SQEM.zig`](../../../src/geometry/SQEM.zig)) over 4D spheres $(c_x, c_y, c_z, r)$ for surface-mesh medial axis optimization.

## Key Entry Points

- `vertexSQEM(...)` — Computes a single vertex's `SQEM`.
- `computeVertexSQEMs(...)` — Parallel batch computation across all vertices via `ParallelVertexTaskRunner`.

## Notes & Assumptions

- Sums incident face sphere-plane distance quadrics weighted by `face_area / 3.0` (code notes a TODO to divide by `sm.codegree(face)` for general polygons) plus two tangent-basis center-plane regularization terms scaled by `line_quadric_epsilon * vertex_area`.
