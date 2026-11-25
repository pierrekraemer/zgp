# Convex Hull (PointCloud)

- **Source:** [`src/models/point/convex_hull.zig`](../../../src/models/point/convex_hull.zig)
- **Model:** [`PointCloud`](../point-cloud.md) → outputs a [`SurfaceMesh`](../surface-mesh.md)
- **Exposed by:** [`SurfaceMeshConnectivity`](../../../src/modules/SurfaceMeshConnectivity.zig)

---

## Overview

Implements 3D Quickhull to construct the convex hull of a `PointCloud` as a closed, triangulated `SurfaceMesh`.

## Key Entry Points

- `generateConvexHull(pc, point_position, sm, vertex_position)` — Builds the convex hull of `pc` into an empty `SurfaceMesh`.

## Notes & Assumptions

- Requires at least 4 points in `pc` and an empty destination `SurfaceMesh`.
- Seeds the initial tetrahedron from `geometry/utils.zig` (`extremePoints`) and handles the 4-point base case directly.
- Iteratively selects the farthest exterior point per active face, identifies visible faces and the boundary horizon (`buildHorizon`), removes visible faces, and stitches a new fan via `sm.closeHoleWithUmbrella`.
- Uses temporary face data (`"points_on_positive_side"`, `"most_distant_point_dist"`, `"most_distant_point_index"`) and a `FaceMarker`, cleaned up via `defer`.
