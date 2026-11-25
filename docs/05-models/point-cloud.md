# PointCloud

[`src/models/point/PointCloud.zig`](../../src/models/point/PointCloud.zig) represents an unstructured set of points with arbitrary typed attributes, accompanied by 4 algorithm files in [`src/models/point/`](../../src/models/point/).

---

## 1. Data Structure & Core API (`PointCloud.zig`)

`PointCloud` is a lightweight wrapper over a single `DataContainer`:

- **Element type**: `pub const Point = u32;` (index into `point_data: DataContainer`).
- **Lifecycle**: `init(allocator, io)`, `deinit()`, `clearRetainingCapacity()`.
- **Point management**: `addPoint()`, `removePoint(p)`, `nbPoints()`.
- **Iteration**: `pointIterator()` yields active `Point` indices (skipping inactive slots).
- **Typed point data**: `PointData(T)` wrapping `*Data(T)` (`value`, `valuePtr`, `name`, `gen`), managed via `addData`, `getData`, `getOrAddData`, `removeData`.
- **Parallelism**: `ParallelPointTaskRunner` and `ParallelPointTaskRunnerWithContext(Context)` delegate to `DataContainer.ParallelIndexTaskRunner*`.

### Standard Datas & Spatial Index (via [`PointCloudStore`](../../src/models/PointCloudStore.zig))
- **Standard datas**: `position: ?PointData(Vec3f)`, `normal: ?PointData(Vec3f)`, `radius: ?PointData(f32)`.
- **Spatial index**: `PointCloudInfo.kdtree: kdtree.PointsKDTree` (wrapping `clibacc`), with `kdtree_last_update` tracked against `dataLastUpdate(position)`.
- **GPU primitives**: `PointCloudInfo.points_ibo` (`IBO` of `.points`).

---

## 2. Algorithms & Computations Catalog

Each file in [`src/models/point/`](../../src/models/point/) has a dedicated documentation page under [`docs/05-models/point-cloud/`](point-cloud/):

- [Convex Hull](point-cloud/convex-hull.md) ([`convex_hull.zig`](../../src/models/point/convex_hull.zig)) — 3D Quickhull constructing a `SurfaceMesh` from a `PointCloud`.
- [Tangent Basis](point-cloud/tangent-basis.md) ([`tangent_basis.zig`](../../src/models/point/tangent_basis.zig)) — Parallel orthonormal tangent frames from point normals.
- [SQEM](point-cloud/sqem.md) ([`sqem.zig`](../../src/models/point/sqem.zig)) — Parallel per-point Spherical Quadric Error Metrics.
- [Medial Axis](point-cloud/medial-axis.md) ([`medial_axis.zig`](../../src/models/point/medial_axis.zig)) — KD-tree shrinking balls and Variational Medial Axis Skeleton (VMAS).
