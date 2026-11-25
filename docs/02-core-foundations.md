# Core Foundations

This document covers the shared substrate underneath all models, stores, and modules: `DataContainer` attribute storage, pooled buffers & parallel task runners, `src/geometry/`, and `src/utils/`.

---

## 1. Index-Based Property Storage (`src/utils/data.zig`)

Every geometric model (`SurfaceMesh`, `PointCloud`, `IncidenceGraph`) stores its elements and arbitrary typed attributes in one or more **`DataContainer`** instances.

### Architecture: `DataContainer`, `Data(T)`, and `DataGen`

```text
DataContainer
  |-- datas: StringHashMap(*DataGen)
  |     |-- "position" -> DataGen header inside Data(Vec3f)
  |     |-- "scalar"   -> DataGen header inside Data(f32)
  |     +-- ...
  |-- internal columns
  |     |-- __is_active : *Data(bool)   (active vs. free-list slots)
  |     +-- __nb_refs   : *Data(u32)    (ref-count if active; next free idx if inactive)
  +-- pooled markers (guarded by std.Io.Mutex)
        +-- markers / available_markers : []*Data(bool)
```

- **`DataGen`** is a type-erased interface struct embedded inside every `Data(T)` (`data_gen` field). It carries:
  - `name: []const u8` (null-terminated, owned by the `DataContainer`),
  - `container: *DataContainer`,
  - `type_id: *const anyopaque` (from `utils/types.zig`'s `typeId(T)` for runtime type-checked lookups),
  - `vtable` (`deinit`, `ensureSize`, `clearRetainingCapacity`, `clone`).
- **`Data(T)`** wraps `data_gen: DataGen` and `storage: std.ArrayList(T)`. It provides:
  - Direct indexing: `value(index)` / `valuePtr(index)` (const-aware return type `*const T` vs `*T`).
  - Bulk ops: `fill(val)`, `fillInactive(val)` (useful before weighted random sampling), `copyFrom(src)`.
  - Active-only iterators: `iterator()`, `constIterator()`, `valueIterator()`, `constValueIterator()`.
  - Reductions over active elements: `minValue`, `maxValue`, `minMaxValues`, `meanValue` (supports scalars and numeric arrays).
- **`DataContainer`** keeps all registered `Data(T)` arrays and all pooled markers synchronized to length `dc.size`.

### Slot Lifetime, Free-List, and Reference Counting

`DataContainer` does **not** compact arrays on deletion; indices stay stable while alive:

- `size` is the high-water mark of allocated indices; `nbElements() == size - nb_inactive_indices`.
- `__is_active: *Data(bool)` tracks whether an index is currently live.
- `__nb_refs: *Data(u32)` serves a dual purpose:
  - For **active** indices: counts references via `refIndex(idx)` / `unrefIndex(idx)`. When `unrefIndex` drops the count to `0`, `releaseIndex(idx)` is called automatically. (`SurfaceMesh` uses this so a vertex/edge/face cell is automatically freed when its last dart is detached, and `nb_refs` directly gives `degree(vertex)` and `codegree(face)` in $O(1)$!)
  - For **inactive** indices: forms an intrusive singly-linked free-list headed by `first_inactive_index` (terminated by `invalid_index = maxInt(u32)`).
- On `acquireIndex()`: reuses `first_inactive_index` if `nb_inactive_indices > 0` (clearing all markers at that slot to `false`), otherwise increments `size` and grows every `Data(T)` and marker. Sets `is_active = true`, `nb_refs = 0`.

### Iteration & Deletion Safety

- `indexIterator()` yields active `u32` indices from `firstIndex()` to `lastIndex()` (one past the last slot, i.e., `dc.size`).
- **`nextSafe()`**: Checks `isActiveIndex(it.index)` before advancing — use this whenever the loop body may delete cells/indices during iteration (e.g., edge collapses or face removals).

### Pooled Thread-Safe Markers

`acquireMarker()` / `releaseMarker(marker)` maintain a pool of unnamed `*Data(bool)` arrays protected by `dc.mutex: std.Io.Mutex`:
- Reused markers are zeroed (`fill(false)`) before returning.
- Newly acquired indices automatically clear all existing markers at that slot.
- Always pair `acquireMarker()` (or `DartMarker.init` / `CellMarker.init`) with `defer ...deinit()`.

### Cloning (`initFrom`)

`DataContainer.initFrom(src, copy_data, allocator)`:
- `copy_data = true`: Clones all `Data(T)` columns (including `__is_active` and `__nb_refs`).
- `copy_data = false`: Copies only the slot layout (`size`, free-list, `__is_active`, `__nb_refs`).
- Pooled markers are **never** copied.

---

## 2. `BufferPool` & Double-Buffered Parallel Task Runners

### `BufferPool(T)` ([`src/utils/BufferPool.zig`](../src/utils/BufferPool.zig))

A thread-safe LIFO pool of fixed-size slices (`[]T`), guarded by `std.Io.Mutex`:
- Initialized in each model store (`init(io, allocator, 1024, 64, 32)` → 32 pre-allocated buffers of 1024 elements, max cached 64) and shared by pointer across all models in that store.
- `acquire()` pops from `free_list` or allocates a fresh slice outside the lock, returning `Buffer { data: []T, pool }`.
- Buffers are returned "dirty" (contents are not zeroed).
- `Buffer.release()` returns the slice to `free_list` if below `max_pool_size`, else frees it. Note `release()` returns `!void` and `deinit()` only frees idle buffers currently in `free_list`.

### Double-Buffered `Parallel*TaskRunner` Pattern

Used by `SurfaceMesh.ParallelCellTaskRunner(cell_type)`, `SurfaceMesh.ParallelCellTaskRunnerWithContext(cell_type, Context)`, and `PointCloud.ParallelPointTaskRunner`:

1. Acquires `2 × nb_workers` buffers (up to `max_workers = 32`, defaulting to `std.Thread.getCpuCount()`) organized into two buffer groups (`group 0` and `group 1`), each paired with a `std.Io.Group` (`wg[0]`, `wg[1]`).
2. The main thread iterates cells/points and fills buffers in the active group.
3. As soon as a buffer fills (1024 indices), it schedules `wg[group].async(io, ...)` to run `task.run(cell)` (or `task.run(ctx, cell)`) over that slice.
4. When all `nb_workers` buffers in the active group are dispatched, it flips `group = (group + 1) % 2` and awaits the previous batch on that group (`try wg[group].await(io)`) before reusing its buffers.
5. After iteration ends, it dispatches any partially filled buffer and awaits both `wg[0]` and `wg[1]`.

For tasks needing thread-local scratch memory (e.g., `WithinSphereSelectionContext` in `curvature.zig`), `ParallelCellTaskRunnerWithContext` provides a per-buffer-slot `Context` struct (requiring `initialized: bool` and `deinit(*Self) void`).

---

## 3. Geometry & Linear Algebra (`src/geometry/` & `src/thirdparty/`)

| File | Key Types / Functions | Conventions & Notes |
|---|---|---|
| [`vec.zig`](../src/geometry/vec.zig) | `Vec(N, Scalar) = [N]Scalar`; `Vec2f/3f/4f`, `Vec2d/3d/4d`; arithmetic, `dot`, `cross`, `det`, `norm`, `normalized`, `cast`, `truncate`, `splat`, `random` | `normalized` returns zero vector when `norm == 0`. |
| [`mat.zig`](../src/geometry/mat.zig) | `Mat(N, Scalar) = [N]Vec(N, Scalar)`; `Mat2f/3f/4f`, `Mat2d/3d/4d`; `mul`, `mulVec`, `preMulVec`, `outerProduct`, `transpose`, `lookAt`, `perspective`, `orthographic`, `rotMat3From*AxisAndAngle` | **Column-major** (`m[col][row]`), matching OpenGL and Eigen. `lookAt(eyepos, eyedir, updir)` takes a **direction**, not a target point. |
| [`utils.zig`](../src/geometry/utils.zig) | Elementary `f32` geometry (`epsilon = 1e-5`): `angle`, `cosAngle`, `triangleArea`, `triangleAreaIntrinsic` (Heron), `triangleNormal`, `layoutTriangleVertex`, `barycentricCoordinates`, distances, `planeOrientation`, `pointInSphere`, `intersectionSphereSegment`, `rotateVectorByQuaternion`, `removeComponent`, `tangentBasis`; plus `Data(Vec3f)` helpers (`boundingBox`, `extremePoints`, `scale`, `centerAround`) | `triangleNormal` is **unnormalized**; quaternions use `[w, x, y, z]` layout; `removeComponent` requires a unit normal. |
| [`SQEM.zig`](../src/geometry/SQEM.zig) | `SQEM { A: Mat4f, b: Vec4f, c: f32 }` over 4D sphere $(c_x, c_y, c_z, r)$: `initSpherePlaneDistance`, `initCenterPlaneDistance`, `add`, `mulScalar`, `eval`, `optimalSphere` | `optimalSphere()` promotes to `f64` and inverts via `eigen.computeInverse4d`. |
| [`eigen.zig`](../src/geometry/eigen.zig) | Wraps `ceigen` (`Scalar = f64`, `Index = i32`): `computeInverse4d`, `solveSymmetricLinearSystem4d`, `eigenSolver` (self-adjoint 3×3), `svd3d`, `DenseMatrix` (least squares via LDLT), `SparseMatrix` (`Triplet`, direct `SimplicialLDLT`, iterative CG), `FactorizedSparseMatrix` (reusable `SimplicialLDLT`) | Iterative CG uses `solveWithGuess` — the provided output vector is read as initial guess! Always use `eigen.Scalar` (`f64`) when assembling systems. |
| [`bvh.zig`](../src/geometry/bvh.zig) | `TrianglesBVH`, `Ray`, `Hit` wrapping `clibacc` (`bvh.h`): `intersect`, `intersectedTriangle/Edge/Vertex/SurfacePoint`, `closestPoint`, `closestPointWithSurfacePoint` | **Assumes triangulated `SurfaceMesh`**. Uses a temporary `__vertex_index` attribute during `init` and maps triangle IDs back to `SurfaceMesh.Face`. |
| [`kdtree.zig`](../src/geometry/kdtree.zig) | `PointsKDTree` wrapping `clibacc` (`kd.h`): `nearestNeighbor`, `nearestNeighborIndex`, `nearestNeighbors(alloc, pt, n)` | Indexes `PointCloud` positions; `nearestNeighbors` returns a caller-owned `ArrayList(Point)`. |

### Exact Predicates (`src/thirdparty/predicates`)

Shewchuk's adaptive predicates (`exactinit`, `orient2d`, `orient3d`, `incircle`, `insphere`) are linked into `@import("c")` in **single precision (`float`)**. Call `c.exactinit()` before invoking predicates.

---

## 4. General Utilities (`src/utils/`)

| File | Purpose & Key Notes |
|---|---|
| [`data.zig`](../src/utils/data.zig) | `DataContainer`, `Data(T)`, `DataGen`, `invalid_index` (documented above). |
| [`BufferPool.zig`](../src/utils/BufferPool.zig) | Thread-safe fixed-size slice pool (documented above). |
| [`CLIArgs.zig`](../src/utils/CLIArgs.zig) | Minimal CLI parser: flags `-n` (normalize), `-c` (center) must precede one or more positional `mesh_files`. |
| [`DisjointSets.zig`](../src/utils/DisjointSets.zig) | Generic union-find (`addElement`, `find` with path compression, `merge`, `sameSet`, `nbSets`). |
| [`PriorityQueue.zig`](../src/utils/PriorityQueue.zig) | Indexed binary min-heap (`PriorityQueue(T, Context, compareFn, setElemIndexFn)`) enabling $O(\log n)$ `updateIndex` and `popIndex` (used in decimation, remeshing, Dijkstra, and intrinsic triangulation). *Note:* `popIndex` does not invoke `setElemIndexFn` to invalidate the removed item's stored index. |
| [`color.zig`](../src/utils/color.zig) | `perceptualOppositeRGB(Vec3f)` (HSL hue + 0.5) and `hslToRgb(Vec3f)`. Used for selection hover highlights. |
| [`types.zig`](../src/utils/types.zig) | Comptime metaprogramming: `typeId(T)`, `UnionFromStruct(S)` (generates `*StdData` unions from `*StdDatas` structs), `StructFromUnion(U)`, `collectionElementType(T)`. |
