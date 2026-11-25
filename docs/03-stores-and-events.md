# Model Stores & Event System

The model stores ([`SurfaceMeshStore.zig`](../src/models/SurfaceMeshStore.zig), [`PointCloudStore.zig`](../src/models/PointCloudStore.zig), [`IncidenceGraphStore.zig`](../src/models/IncidenceGraphStore.zig), and stubbed [`VolumeMeshStore.zig`](../src/models/VolumeMeshStore.zig)) are the central hubs connecting pure geometric models to GPU buffers, spatial acceleration structures, UI selection, and listener modules.

---

## 1. Responsibilities of a Store

Every store follows the exact same structural blueprint:

1. **Model Ownership & Naming**:
   - Owns all heap-allocated models in a `StringArrayHashMapUnmanaged(*Model)` keyed by a duplicated null-terminated name (`dupeSentinel`).
   - Provides `create*` (allocates, initializes, registers, and pre-creates all standard data columns), `register*` (adopts an already-created model), `destroy*`, and `unregister*`.
   - Clears `selected_model.* = .none` if the currently selected model is unregistered.
2. **Per-Model Metadata (`*Info`)**:
   - Stored in `AutoHashMapUnmanaged(*const Model, *Info)`, accessed via `surfaceMeshInfo(sm)` / `pointCloudInfo(pc)` / `incidenceGraphInfo(ig)`.
   - Contains the model's `std_datas`, primitive `IBO`s, and optional spatial index (`TrianglesBVH` or `PointsKDTree`) with its own `*_last_update` timestamp.
3. **Lazy GPU Buffer Caching**:
   - `data_vbo: AutoHashMapUnmanaged(*const DataGen, VBO)`: Created lazily on first call to `store.dataVBO(...)` (filling from `data.data.storage.items`) and automatically re-uploaded whenever `store.*DataUpdated(...)` is called.
   - `cell_set_ibo` (`SurfaceMeshStore` only): Maps `*const SurfaceMesh.CellSetGen` → `IBO`, lazily created in `cellSetIBO(...)` and updated on `surfaceMeshCellSetUpdated(...)`.
4. **Timestamp Tracking (`data_last_update`)**:
   - Maps `*const DataGen` → `std.Io.Timestamp`, refreshed on every `store.*DataUpdated(...)` call.
   - Enables reactive staleness checks across `*StdDatas` modules, BVH buttons, and KDTree buttons without manual dirty flags scattered across algorithms.
5. **Shared Parallel Buffer Pool**:
   - Owns a `BufferPool` (`u32` or `PointCloud.Point`, sized `1024 × 64`, 32 pre-allocated) passed by pointer to every model created in that store.
6. **Observer Pattern (`listeners: ArrayList(*Module)`)**:
   - Modules call `store.addListener(&self.module)` in `init` and `store.removeListener(&self.module)` in `deinit`.
   - Stores broadcast lifecycle and mutation events to every registered listener.
7. **Store Left-Panel UI (`leftPanel`)**:
   - Rendered in `AppContext.mainUI` whenever a model of that store's type is selected: shows cell counts table, a "Create cell data" modal (`bool`, `u32`, `f32`, `Vec3f`), Build/Update BVH or KDTree button (green when up to date, red when stale relative to positions), and a Delete button.

---

## 2. Comparison Across Stores

| Feature | `SurfaceMeshStore` | `PointCloudStore` | `IncidenceGraphStore` |
|---|---|---|---|
| **Standard Datas (`*StdDatas`)** | `corner_angle` (`f32`), `halfedge_cotan_weight` (`f32`), `vertex_position` (`Vec3f`), `vertex_area` (`f32`), `vertex_normal` (`Vec3f`), `vertex_tangent_basis` (`[2]Vec3f`), `edge_length` (`f32`), `edge_dihedral_angle` (`f32`), `face_area` (`f32`), `face_normal` (`Vec3f`) | `position` (`Vec3f`), `normal` (`Vec3f`), `radius` (`f32`) | `vertex_position` (`Vec3f`) |
| **Spatial Index in `*Info`** | `TrianglesBVH` (`bvh`, `bvh_last_update`) | `PointsKDTree` (`kdtree`, `kdtree_last_update`) | None |
| **Primitive IBOs in `*Info`** | `points_ibo`, `lines_ibo`, `triangles_ibo`, `boundaries_ibo` | `points_ibo` | `points_ibo`, `lines_ibo`, `triangles_ibo` |
| **CellSet IBO Cache** | `cell_set_ibo` | — | — |
| **Buffer Pool Element** | `u32` | `PointCloud.Point` (`u32`) | `u32` |
| **File Loading** | `loadSurfaceMeshFromFile` (`.off` implemented; `.obj`/`.ply` stubbed) | `loadPointCloudFromFile` (stub) | `loadIncidenceGraphFromFile` (stub) |
| **Debug Integrity Check** | `sm.checkIntegrity()` on load & `surfaceMeshConnectivityUpdated` | — | — |

---

## 3. Standard Datas Pattern (`*StdDatas` / `*StdData`)

Each store defines a struct of optional handles (e.g., `SurfaceMeshStdDatas`), and uses `utils/types.zig`'s `UnionFromStruct` to generate a matching tagged union (`SurfaceMeshStdData`) and tag enum (`SurfaceMeshStdDataTag`):

```zig
// Example: binding a vertex position attribute as the standard position slot
sm_store.setSurfaceMeshStdData(sm, .{ .vertex_position = my_pos_data });
```

When `createSurfaceMesh` / `createPointCloud` / `createIncidenceGraph` creates a model:
1. It registers the model first (broadcasting `*Created` to listeners).
2. It uses `inline for` reflection over `*StdData` to allocate every standard data column on the model (named after its field, e.g., `"vertex_position"`) and binds it via `set*StdData` (broadcasting `*StdDataChanged`).

> **Note on `register*` vs. `create*`:** `create*` pre-allocates and binds all standard datas automatically. If you construct a model manually (e.g., via `sm.clone()`) and pass it to `register*`, you must bind its standard datas explicitly via `set*StdData`.

---

## 4. Event & Synchronization Contract

```text
Algorithm / Module mutates SurfaceMesh
  |
  +--> Attribute values changed:
  |      call store.surfaceMeshDataUpdated(sm, cell_type, T, data)
  |        |-- 1. re-upload VBO if cached in data_vbo
  |        |-- 2. update data_last_update[data.gen()] = now()
  |        +-- 3. notify listeners: module.surfaceMeshDataUpdated(...)
  |
  +--> Topology changed:
  |      call store.surfaceMeshConnectivityUpdated(sm)
  |        |-- 1. run sm.checkIntegrity() (debug builds) + recount nb_boundary_darts
  |        |-- 2. rebuild points / lines / triangles / boundaries IBOs
  |        |-- 3. rebuild all CellSets + fire surfaceMeshCellSetUpdated(...)
  |        +-- 4. notify listeners: module.surfaceMeshConnectivityUpdated(sm)
  |
  +--> Visual state changed:
         call app_ctx.view.requestRedraw()
```

### Mandatory Caller Rules

| What you modified | What you **must** call afterward |
|---|---|
| Values inside any `CellData` / `PointData` | `store.*DataUpdated(model, [cell_type,] T, data)` |
| Topology (added/removed/flipped/split/collapsed cells or points) | `store.*ConnectivityUpdated(model)` (plus `*DataUpdated` for any modified attributes like `vertex_position`) |
| Standard data slot binding | `store.set*StdData(model, .{ .field = data_or_null })` |
| Membership of a `SurfaceMesh.CellSet` | `surface_mesh_store.surfaceMeshCellSetUpdated(sm, cell_type, cell_set)` |
| Anything affecting what appears on screen | `app_ctx.view.requestRedraw()` |

### Event Dispatch Order on Lifecycle Changes

- **Creation (`register*`)**: Adds model and `*Info` to maps *before* calling `module.*Created(model)` — listeners can safely query `store.*Info(model)` and `store.*Name(model)` inside their `*Created` hook.
- **Destruction (`unregister*`)**: Clears `selected_model` if needed, calls `module.*Destroyed(model)` *while `*Info` and name still exist*, then deinits and removes `*Info` and the map entry.
- **Gotcha (GPU buffer cleanup)**: `data_vbo` and `cell_set_ibo` entries are freed when the store itself deinits, not individually evicted on `removeData`/`destroy*`. Avoid creating/destroying unbounded temporary `Data`s that also have `dataVBO` requested on them.

---

## 5. File I/O Note

Currently, `.off` mesh loading lives at the bottom of [`SurfaceMeshStore.zig`](../src/models/SurfaceMeshStore.zig) (`loadSurfaceMeshFromFile`):
1. Parses ASCII OFF vertices and polygonal faces into `SurfaceMeshImportData`.
2. Creates a `SurfaceMesh`, populates `vertex_position`, creates unbounded faces (`addUnboundedFace`), stitches interior opposite halfedges (`phi2Sew`), and calls `sm.close()` if boundary edges exist.
3. Calls `initCells(.vertex)`, `initCells(.edge)`, `initCells(.face)` and validates `sm.checkIntegrity()` in debug mode.

`PointCloudStore.loadPointCloudFromFile` and `IncidenceGraphStore.loadIncidenceGraphFromFile` are currently stubs (with a TODO across all three stores to extract I/O into a dedicated module).
