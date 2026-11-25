# Tangent Basis (PointCloud)

- **Source:** [`src/models/point/tangent_basis.zig`](../../../src/models/point/tangent_basis.zig)
- **Model:** [`PointCloud`](../point-cloud.md)

---

## Overview

Computes an orthonormal tangent frame (`[2]Vec3f`) for every point in a `PointCloud` from its unit normal vector.

## Key Entry Points

- `computePointTangentBases(pc, point_normal, point_tangent_basis)` — Parallel computation over all points via `PointCloud.ParallelPointTaskRunner`.

## Notes & Assumptions

- Delegates per-point frame construction to `geometry/utils.zig` (`tangentBasis`).
- Assumes `point_normal` vectors are normalized.
- Used internally by [`medial_axis.zig`](medial-axis.md) to construct tangent-plane regularization terms for point SQEMs.
