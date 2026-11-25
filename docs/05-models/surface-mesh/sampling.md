# Surface Sampling

- **Source:** [`src/models/surface/sampling.zig`](../../../src/models/surface/sampling.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md) → outputs a [`PointCloud`](../point-cloud.md)
- **Exposed by:** [`SurfaceMeshSampling`](../../../src/modules/SurfaceMeshSampling.zig), [`SurfaceMeshParameterization`](../../../src/modules/SurfaceMeshParameterization.zig)

---

## Overview

Samples points on a triangulated `SurfaceMesh` into a `PointCloud` (recording both 3D positions and intrinsic [`SurfacePoint`](surface-point.md)s) via either area-weighted uniform sampling or Bridson-style 3D Poisson-disk sampling.

## Key Entry Points

- `uniformlySamplePointsOnSurface(sm, vertex_position, face_area, pc, point_position, point_sp, nb_samples, rng)` — Selects triangles with probability proportional to `face_area` and samples uniform barycentric points.
- `poissonDiskSamplePointsOnSurface(sm, vertex_position, face_normal, bvh, pc, point_position, point_sp, poisson_radius, rng)` — Generates well-spaced samples using tangent-plane annulus proposals (`[r, 2r]`, 20 attempts per active point) projected onto `TrianglesBVH` and accelerated by a 3D hash grid (`cell_size = r / sqrt(3)` with 5×5×5 neighborhood checks).

## Notes & Assumptions

- Expects `pc` to be empty and assumes triangular faces.
- `uniformlySamplePointsOnSurface` calls `face_area.data.fillInactive(0.0)` before weighted random indexing so inactive slots in `face_data` are never selected.
