# ARAP Deformation

- **Source:** [`src/models/surface/arap.zig`](../../../src/models/surface/arap.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Exposed by:** [`SurfaceMeshDeformation`](../../../src/modules/SurfaceMeshDeformation.zig)

---

## Overview

Implements **As-Rigid-As-Possible (ARAP)** interactive surface deformation using local-global alternation: SVD-free local optimal rotation estimation via Horn's quaternion power iteration and a pre-factorized sparse cotangent Laplacian global solve.

## Key Types & Entry Points

- `ARAPContext`:
  - `init(sm, vertex_position, halfedge_cotan_weight, fixed_set, handle_set, it_ctx)` — Indexes free vs. constrained vertices (`fixed_set` and `handle_set`) and pre-factorizes the free-vertex cotangent Laplacian via `eigen.FactorizedSparseMatrix` (`SimplicialLDLT` in `f64`).
  - `solve(nb_iterations)` — Alternates parallel local rotation estimation (`ParallelVertexTaskRunner`, default 5 iterations) and global multi-RHS linear solve, updating `vertex_position`.
  - `deinit()`
- `computeVertexOneRingRotation(...)` — Computes a single vertex's optimal $3\times 3$ rotation using Horn's quaternion matrix and Gershgorin-shifted 3-step power iteration.

## Notes & Assumptions

- Optionally accepts an `it_ctx: ?*ITContext` ([`intrinsic_triangulation.zig`](intrinsic-triangulation.md)) to assemble the Laplacian from an intrinsic Delaunay triangulation; `it_ctx` must outlive `ARAPContext` and be Delaunay.
- Stores temporary per-vertex attributes under the `__arap_*` prefix; constrained vertices receive `invalid_index` in the free-vertex map.
