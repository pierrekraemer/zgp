# Medial Axis / VMAS (PointCloud)

- **Source:** [`src/models/point/medial_axis.zig`](../../../src/models/point/medial_axis.zig)
- **Model:** [`PointCloud`](../point-cloud.md) → outputs medial spheres (`PointCloud`) and skeleton ([`IncidenceGraph`](../incidence-graph.md))
- **Exposed by:** [`PointCloudMedialAxis`](../../../src/modules/PointCloudMedialAxis.zig)

---

## Overview

Computes a medial axis representation for an oriented `PointCloud` using the **shrinking-ball** algorithm and the **Variational Medial Axis Skeleton (VMAS)** iterative clustering and sphere-splitting pipeline.

## Key Types & Entry Points

- `shrinkingBall(...)` / `computePointShrinkingBalls(...)` — Computes inward medial balls per point in parallel using `PointsKDTree` nearest-neighbor queries.
- `VMASContext`:
  - `init` / `deinit` / `clearRetainingCapacity`
  - `createFirstSphere`, `updatePointSQEMs`, `computeClusters`, `updateSpheres`, `updateSkeleton`, `worstSphere`, `splitSphere`

## Notes & Assumptions

- Requires `PointsKDTree` (`geometry/kdtree.zig`) plus point `position` and `normal` attributes.
- Builds a 6-nearest-neighbor graph, point tangent bases (`tangent_basis.zig`), per-point `SQEM`s (`sqem.zig`), and shrinking balls; clusters points to medial spheres (pruning clusters with `< 4` points), optimizes each sphere via `SQEM.optimalSphere()` + shrinking-ball projection, and extracts a non-manifold skeleton `IncidenceGraph` (vertices, edges, and triangle faces).
- `deinit` cleans up internal helper attributes while intentionally preserving output `sphere_center`, `sphere_radius`, and `skeleton_vertex_position`.
- `shrinkingBall` currently uses hardcoded initial radius (`0.5`), convergence epsilon (`1e-4`), and separation angle (`35°`).
