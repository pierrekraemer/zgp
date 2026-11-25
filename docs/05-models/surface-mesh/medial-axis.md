# Medial Axis / VMAS (SurfaceMesh)

- **Source:** [`src/models/surface/medial_axis.zig`](../../../src/models/surface/medial_axis.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md) → outputs medial spheres ([`PointCloud`](../point-cloud.md)) and skeleton ([`IncidenceGraph`](../incidence-graph.md))
- **Exposed by:** [`SurfaceMeshMedialAxis`](../../../src/modules/SurfaceMeshMedialAxis.zig)

---

## Overview

Computes a medial axis representation for a `SurfaceMesh` via BVH-accelerated **shrinking balls** and the **Variational Medial Axis Skeleton (VMAS)** iterative clustering, sphere optimization, and skeleton extraction pipeline.

## Key Types & Entry Points

- `shrinkingBall(...)` / `computeVertexShrinkingBalls(...)` — Initializes inward medial balls via inward raycasting against `TrianglesBVH` and shrinks iteratively (`ParallelVertexTaskRunner`).
- `VMASContext`:
  - `init` / `deinit` / `clearRetainingCapacity`
  - `createFirstSphere`, `updateVertexSQEMs`, `updateSpheres`, `updateSkeleton`, `worstSphere`, `splitSphere`

## Notes & Assumptions

- Requires `TrianglesBVH` (`geometry/bvh.zig`) plus standard vertex/face geometric attributes (`vertex_position`, `vertex_area`, `vertex_normal`, `vertex_tangent_basis`, `face_area`, `face_normal`).
- Uses per-vertex `SQEM`s (`sqem.zig`) and mesh edges for cluster adjacency, prunes clusters with `< 4` vertices, optimizes spheres via `SQEM.optimalSphere()`, and builds a non-manifold skeleton `IncidenceGraph`.
- `deinit` cleans up internal helper attributes while preserving output `sphere_center`, `sphere_radius`, and `skeleton_vertex_position`.
- `shrinkingBall` currently uses hardcoded convergence epsilon (`1e-4`) and separation angle (`45°`).
