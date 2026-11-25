# SQEM (PointCloud)

- **Source:** [`src/models/point/sqem.zig`](../../../src/models/point/sqem.zig)
- **Model:** [`PointCloud`](../point-cloud.md)

---

## Overview

Computes per-point **Spherical Quadric Error Metrics** (`SQEM`, defined in [`src/geometry/SQEM.zig`](../../../src/geometry/SQEM.zig)) over 4D spheres $(c_x, c_y, c_z, r)$ for medial axis optimization.

## Key Entry Points

- `pointSQEM(point, point_position, point_normal, point_tangent_basis, line_quadric_epsilon)` — Builds the `SQEM` of a single point.
- `computePointSQEMs(pc, point_position, point_normal, point_tangent_basis, line_quadric_epsilon, point_sqem)` — Parallel batch evaluation using `PointCloud.ParallelPointTaskRunner`.

## Notes & Assumptions

- Each point's `SQEM` sums a sphere-plane tangency quadric with two center-plane regularization terms along the point's tangent basis, weighted by `line_quadric_epsilon`.
- Currently uses a uniform weight of `1.0` per point (code notes a TODO for per-point area weighting).
- Used by [`medial_axis.zig`](medial-axis.md).
