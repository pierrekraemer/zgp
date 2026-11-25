# Modular Feature System

Features in `zgp` — renderers, standard-data managers, and interactive geometry-processing tools — are organized as independent **Modules** under [`src/modules/`](../src/modules/).

---

## 1. The `Module` Interface ([`src/modules/Module.zig`](../src/modules/Module.zig))

`zgp` uses Zig's intrusive struct + static `VTable` idiom for zero-allocation runtime polymorphism:

```zig
pub const MyModule = struct {
    app_ctx: *AppContext = undefined,
    module: Module = .{
        .name = "My Module",
        .supported_models = .{ .surface_mesh = true },
        .vtable = &.{
            .surfaceMeshCreated = surfaceMeshCreated,
            .rightPanel = rightPanel,
        },
    },
    // module-specific per-model state (e.g., AutoHashMapUnmanaged(*SurfaceMesh, MyData))
};
```

Inside any `VTable` callback, recover the concrete struct pointer via:

```zig
const self: *MyModule = @alignCast(@fieldParentPtr("module", m));
```

### `VTable` Hooks

Every hook defaults to a no-op (`default*` in `Module.zig`), so a module only specifies the hooks it cares about:

| Category | Hooks | Dispatched By |
|---|---|---|
| **PointCloudStore** | `pointCloudCreated`, `pointCloudDestroyed`, `pointCloudConnectivityUpdated`, `pointCloudStdDataChanged`, `pointCloudDataUpdated` | `PointCloudStore` (subscribed listeners) |
| **SurfaceMeshStore** | `surfaceMeshCreated`, `surfaceMeshDestroyed`, `surfaceMeshConnectivityUpdated`, `surfaceMeshStdDataChanged`, `surfaceMeshDataUpdated`, `surfaceMeshCellSetUpdated` | `SurfaceMeshStore` (subscribed listeners) |
| **IncidenceGraphStore** | `incidenceGraphCreated`, `incidenceGraphDestroyed`, `incidenceGraphConnectivityUpdated`, `incidenceGraphStdDataChanged`, `incidenceGraphDataUpdated` | `IncidenceGraphStore` (subscribed listeners) |
| **UI** | `leftPanel`, `rightPanel`, `menuBar`, `rightClickMenu` | `AppContext.mainUI` (filtered by `shouldCallOnModule`) |
| **App** | `selectedModelChanged` | `AppContext.mainUI` (all modules) |
| **View** | `draw(m, view_matrix, projection_matrix)` | `View.draw` (all modules, whenever `needs_redraw`) |
| **Window** | `sdlEvent(m, event) bool` | `AppContext.sdlEvent` (filtered; first `true` consumes event) |

### Filtering & UI Behavior

- **`supported_models`** (`Module.SupportedModels`): Declares `.point_cloud`, `.surface_mesh`, `.incidence_graph`. If all are `false`, `AppContext.shouldCallOnModule()` treats the module as global.
- **Right panel detection**: `AppContext.mainUI` checks `module.vtable.rightPanel == Module.defaultRightPanel` to skip rendering an empty collapsing header for modules without a `rightPanel`.
- **Store subscription**: Declaring `supported_models` does **not** automatically subscribe a module to store events — the module must explicitly call `try app_ctx.<store>.addListener(&self.module)` in `init` and `removeListener` in `deinit`.

---

## 2. Standard Data Managers (`*StdDatas`)

The three `*StdDatas` modules (`SurfaceMeshStdDatas`, `PointCloudStdDatas`, `IncidenceGraphStdDatas`) live in the **left panel** and manage binding & recomputation of each store's `*StdData` slots.

### How `SurfaceMeshStdDatas` Dependency Resolution Works

[`SurfaceMeshStdDatas.zig`](../src/modules/SurfaceMeshStdDatas.zig) uses a comptime-typed dependency table (`std_data_computations`):
- Each `StdDataComputation` specifies `reads: []const SurfaceMeshStdDataTag`, `computes: SurfaceMeshStdDataTag`, and a type-erased `func: *const anyopaque` whose exact function signature is synthesized at comptime via `@Fn`.
- **9 computations in topological order**:
  1. `corner_angle` ← `[vertex_position]`
  2. `halfedge_cotan_weight` ← `[vertex_position]`
  3. `face_area` ← `[vertex_position]`
  4. `face_normal` ← `[vertex_position]`
  5. `edge_length` ← `[vertex_position]`
  6. `edge_dihedral_angle` ← `[vertex_position, face_normal]`
  7. `vertex_area` ← `[face_area]`
  8. `vertex_normal` ← `[corner_angle, face_normal]`
  9. `vertex_tangent_basis` ← `[vertex_position, vertex_normal]`
- **Timestamp-based staleness (`dataComputableAndUpToDate`)**: Recursively compares `surface_mesh_store.dataLastUpdate(...)` timestamps. An attribute is stale if it or any input has no timestamp, if its timestamp is older than any input's timestamp, or if any upstream input is itself stale. UI gear buttons turn **green** when up to date and **red** when stale.
- `updateComputableStdDatas(sm)` runs all computable, out-of-date entries in topological order.

`PointCloudStdDatas` and `IncidenceGraphStdDatas` share the same scaffolding (`StdDataComputation` + `dataComputableAndUpToDate`), with empty `std_data_computations` tables for now (UI currently allows binding/clearing slots).

---

## 3. Catalog of All 19 Modules

All concrete modules are instantiated and wired in [`src/AppContext.zig`](../src/AppContext.zig).

### Standard Data Managers
| Module | `supported_models` | Store Listeners | Hooks | Summary |
|---|---|---|---|---|
| [`PointCloudStdDatas`](../src/modules/PointCloudStdDatas.zig) | `PC` | `PC` | `leftPanel` | Bind/clear `PointCloudStdData` slots in left panel (computation table currently empty). |
| [`SurfaceMeshStdDatas`](../src/modules/SurfaceMeshStdDatas.zig) | `SM` | `SM` | `leftPanel` | Bind/clear `SurfaceMeshStdData` slots, show staleness status, and recompute 9 standard geometric attributes in dependency order. |
| [`IncidenceGraphStdDatas`](../src/modules/IncidenceGraphStdDatas.zig) | `IG` | `IG` | `leftPanel` | Bind/clear `IncidenceGraphStdData` slots in left panel (computation table currently empty). |

### Renderers
| Module | `supported_models` | Store Listeners | Hooks | Summary |
|---|---|---|---|---|
| [`PointCloudRenderer`](../src/modules/PointCloudRenderer.zig) | `PC` | `PC` | `pcCreated/Destroyed/StdDataChanged/DataUpdated`, `draw`, `rightPanel` | Renders all `PointCloud`s as spheres with global or per-point radius and global/scalar/RGB coloring (`PointSphere*` shaders). Auto-syncs scalar min/max on data updates. |
| [`SurfaceMeshRenderer`](../src/modules/SurfaceMeshRenderer.zig) | `SM` | `SM` | `smCreated/Destroyed/StdDataChanged/DataUpdated`, `draw`, `rightPanel` | Renders all `SurfaceMesh`es: vertices (spheres), edges (lines or cylinders), faces (flat triangles with global, per-vertex scalar/UV/RGB, or per-face scalar/RGB coloring + isolines/radial UV), and boundary cylinders. |
| [`IncidenceGraphRenderer`](../src/modules/IncidenceGraphRenderer.zig) | `IG` | `IG` | `igCreated/Destroyed/StdDataChanged/DataUpdated`, `draw`, `rightPanel` | Renders all `IncidenceGraph`s: vertices (spheres), edges (lines/cylinders), and faces (flat triangles, `dim_backfaces = false`), with global, per-vertex, and per-face scalar/RGB coloring. |
| [`VectorPerVertexRenderer`](../src/modules/VectorPerVertexRenderer.zig) | `PC`, `SM` | `PC`, `SM` | `pcCreated/Destroyed/StdDataChanged`, `smCreated/Destroyed/StdDataChanged`, `draw`, `rightPanel` | Renders per-vertex `Vec3f` fields (normals, curvature directions, gradients) as 3D cones/arrows via `PointVector`. (`IncidenceGraph` support is marked TODO.) |

### Processing & Interactive Feature Modules
| Module | `supported_models` | Store Listeners | Hooks | Summary |
|---|---|---|---|---|
| [`SurfaceMeshConnectivity`](../src/modules/SurfaceMeshConnectivity.zig) | `SM` | `SM` | `rightClickMenu` | Topology-modifying right-click actions: cut all edges, triangulate faces, QEM decimation, uniform/adaptive isotropic remeshing (optionally pulling curvature from `app_ctx.surface_mesh_curvature`), and convex hull mesh generation. |
| [`SurfaceMeshCurvature`](../src/modules/SurfaceMeshCurvature.zig) | `SM` | `SM` | `smCreated/Destroyed`, `rightClickMenu` | Manages per-mesh `SurfaceMeshCurvatureDatas` (`kmin`, `Kmin`, `kmax`, `Kmax`, shared with other modules via `surfaceMeshCurvatureDatas()`) and computes normal-cycle principal curvatures. |
| [`SurfaceMeshDeformation`](../src/modules/SurfaceMeshDeformation.zig) | `SM` | `SM` | `smCreated/Destroyed`, `sdlEvent`, `rightPanel` | Interactive handle-based deformation in Direct Manipulation or ARAP mode (with optional intrinsic Delaunay triangulation). Uses handle/fixed `VertexSet`s; `D` drags in view plane, `R` rotates around handle centroid. |
| [`SurfaceMeshDirectionField`](../src/modules/SurfaceMeshDirectionField.zig) | `SM` | `SM` | `smCreated/Destroyed`, `rightPanel` | Computes a per-vertex `Vec3f` direction field as the face-averaged gradient of a selected vertex `f32` scalar field (`gradient.zig` + `filtering.zig`). |
| [`SurfaceMeshDistance`](../src/modules/SurfaceMeshDistance.zig) | `SM` | `SM` | `smCreated/Destroyed`, `rightClickMenu` | Manages per-mesh `HeatMethodContext`s and provides right-click controls to pick a source `VertexSet`, configure diffusion time, initialize/deinitialize, and solve geodesic distances (`distance.zig`). |
| [`SurfaceMeshFiltering`](../src/modules/SurfaceMeshFiltering.zig) | `SM` | `SM` | `smCreated/Destroyed`, `rightClickMenu` | Right-click controls for feature-preserving implicit anisotropic Laplacian filtering on vertex `f32` scalar or `Vec3f` vector fields (`filtering.zig`). |
| [`SurfaceMeshMedialAxis`](../src/modules/SurfaceMeshMedialAxis.zig) | `SM` | `SM` | `smCreated/Destroyed`, `rightPanel` | Drives `surface/medial_axis.zig` (`VMASContext`) using the mesh's `TrianglesBVH`, spawning companion `<name>_spheres` (`PointCloud`) and `<name>_skeleton` (`IncidenceGraph`) models. |
| [`PointCloudMedialAxis`](../src/modules/PointCloudMedialAxis.zig) | `PC` | `PC` | `pcCreated/Destroyed`, `rightPanel` | Drives `point/medial_axis.zig` (`VMASContext`) using the cloud's `PointsKDTree`, spawning companion `<name>_spheres` (`PointCloud`) and `<name>_skeleton` (`IncidenceGraph`) models. |
| [`SurfaceMeshParameterization`](../src/modules/SurfaceMeshParameterization.zig) | `SM` | `PC`, `SM` | `smCreated/Destroyed/ConnectivityUpdated`, `pcDestroyed`, `rightPanel` | Multi-stage overlapping geodesic patch UV parameterization: Poisson-disk vertex sampling, dual geodesic Voronoi sample mesh + intrinsic Delaunay triangulation, 1-ring tangent UV lifting, and patch UV visualization. |
| [`SurfaceMeshProceduralTexturing`](../src/modules/SurfaceMeshProceduralTexturing.zig) | `SM` | `SM` | `smCreated/Destroyed`, `sdlEvent`, `rightPanel` | Early scaffold (`TnBData`) that initializes a `__vertex_ref_dart` vertex attribute; `sdlEvent` is currently a no-op stub. |
| [`SurfaceMeshSampling`](../src/modules/SurfaceMeshSampling.zig) | `SM` | `PC`, `SM` | `smCreated/Destroyed`, `pcDestroyed`, `rightPanel` | Uniform or Poisson-disk sampling of a `SurfaceMesh` into a companion `PointCloud` (storing `SurfacePoint`s), plus parallel attribute interpolation (`u32`/`f32`/`Vec3f`) from mesh cells to sampled points. |
| [`SurfaceMeshSelection`](../src/modules/SurfaceMeshSelection.zig) | `SM` | `SM` | `smCreated/Destroyed/StdDataChanged`, `selectedModelChanged`, `draw`, `sdlEvent`, `rightPanel` | Interactive BVH ray-casting selection of vertices/edges/faces into named `CellSet`s (single cell or within-sphere: `S`+click adds, `Shift+S`+click removes, scroll adjusts radius), with hover preview rendering. |

---

## 4. Inter-Module Communication Patterns

Modules stay decoupled by default through **Model Stores**, with two deliberate exceptions:
1. **Via Stores (preferred)**: Modules communicate indirectly by reading/writing named `CellData`, `StdData`, `CellSet`s, or companion models (`<name>_spheres`, `<name>_skeleton`) and notifying the store.
2. **Direct `AppContext` sibling access (rare, explicit)**: E.g., `SurfaceMeshConnectivity` reads `app_ctx.surface_mesh_curvature.surfaceMeshCurvatureDatas(sm)` when adaptive remeshing needs principal curvatures, and calls `app_ctx.surface_mesh_std_datas.updateComputableStdDatas(sm)` after topology edits.

See [`docs/recipes.md`](recipes.md#1-add-a-new-module) for the step-by-step checklist to add a new module.
