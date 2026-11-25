# AGENTS.md — zgp Codebase Guide

Compact reference for AI agents working on **zgp** (Zig Geometry Processing). Read this first, then consult only the relevant `docs/` file(s) from the routing table below.

---

## 1. Project Snapshot & Commands

- **Language / Toolchain**: Zig **`0.17.0`** (`minimum_zig_version = "0.17.0"` in `build.zig.zon`). Uses Zig 0.17 APIs (`std.process.Init`, `std.Io`, `std.Io.Mutex`, `std.Io.Group`, `std.Io.Timestamp`, `@Fn`, unmanaged containers `.empty`). Do not downgrade to older Zig `std` APIs.
- **Graphics / Windowing / UI**: SDL3 (callback lifecycle `SDL_EnterAppMainCallbacks`), OpenGL **4.1 Core** (`zigglgen`), Dear ImGui (`cimgui_zig` + FontAwesome 7).
- **C/C++ Interop**: All C headers are aggregated in [`src/c.h`](src/c.h) and imported via `@import("c")` (translated with `translate_c`). Local third-party libraries in `src/thirdparty/`:
  - `ceigen` — Eigen C wrapper (`f64` scalar, `i32` index, column-major). Wrapped in `src/geometry/eigen.zig`.
  - `clibacc` — `libacc` BVH & KD-Tree C wrapper (`f32` scalar, `u32` index). Wrapped in `src/geometry/bvh.zig` & `kdtree.zig`.
  - `predicates` — Shewchuk exact geometric predicates (**single precision `float`**; requires `exactinit()` before use).
- **Commands** (run from repo root so `src/ui/*.ttf` relative font paths resolve):
  - Build: `zig build`
  - Run: `zig build run -- [-n] [-c] <mesh.off> [...]`
  - Test: `zig build test`

---

## 2. Core Mental Model

`zgp` has a strict 5-layer architecture:

1. **Foundations** (`src/utils/`, `src/geometry/`): Index-based SoA property storage (`DataContainer` / `Data(T)` / `DataGen`), `BufferPool`, math (`vec`, `mat`, `SQEM`), Eigen & spatial acceleration wrappers.
2. **Models** (`src/models/<kind>/`): Pure geometric/topological data structures + standalone algorithm files (`SurfaceMesh`, `PointCloud`, `IncidenceGraph`; `VolumeMesh` is an empty stub). Models do **not** depend on UI, OpenGL, or `AppContext`.
3. **Model Stores** (`src/models/*Store.zig`): Central owners of models, per-model `*Info` (standard datas, BVH/KDTree, primitive IBOs), lazy GPU `VBO`/`IBO` caches, data update timestamps, and observer listener lists.
4. **Modules** (`src/modules/`): Type-erased feature units (`Module` + `VTable`, recovered via `@alignCast(@fieldParentPtr("module", m))`) that subscribe to store events, render into `View`, provide ImGui panels/menus, and handle SDL input.
5. **App Shell & Rendering** (`src/main.zig`, `src/AppContext.zig`, `src/rendering/`, `src/ui/`): `AppContext` owns everything, wires modules in two phases (`init` then `wireUp`), drives retained FBO rendering (`View`), and dispatches ImGui + SDL events.

---

## 3. Critical Invariants & Gotchas

Always respect these when reading or modifying code:

1. **Notify the Store after mutating data or topology**:
   - After writing to any `CellData` / `PointData`, call `store.*DataUpdated(...)`. This refreshes cached GPU `VBO`s, updates `data_last_update` timestamps (used for `StdDatas`/BVH/KDTree staleness), and notifies listener modules (e.g., renderer scalar min/max).
   - After modifying topology, call `store.*ConnectivityUpdated(...)`. For `SurfaceMesh`, this also runs `sm.checkIntegrity()` in `.debug` mode, recounts `nb_boundary_darts`, rebuilds primitive `IBO`s, updates all `CellSet`s, and notifies listeners.
   - After mutating a `SurfaceMesh.CellSet`, call `surface_mesh_store.surfaceMeshCellSetUpdated(...)`.
2. **Retained 3D rendering requires `requestRedraw()`**:
   - `View.draw()` renders into an offscreen FBO **only when `view.needs_redraw == true`**, otherwise it just blits the cached texture. Call `app_ctx.view.requestRedraw()` whenever visual state changes.
3. **Two-phase `AppContext` module wiring**:
   - Concrete modules live as value fields on `AppContext` (default-initialized), then `AppContext.wireUp()` calls `.init(app_ctx)` and appends `&module` to `app_ctx.modules`. Do not move `AppContext` after `wireUp()` (module pointers and `@fieldParentPtr` rely on stable addresses).
4. **`SurfaceMesh` combinatorial map rules**:
   - Boundary faces exist explicitly as cycles of **boundary darts** (`isBoundaryDart(d) == true`, `face(d).index == invalid_index`). Boundary faces have **no** `Face` cell in `face_data`.
   - Representative darts (`vertex_dart`, `edge_dart`, `face_dart`) must **never** be boundary darts.
   - `dartIterator()`, `halfedgeIterator()`, `cornerIterator()`, and vertex/edge orbit iterators (`vertexDartIterator`, `edgeDartIterator`) all include **boundary darts** — filter with `if (sm.isBoundaryDart(d)) continue;` whenever an operation requires an interior dart (e.g., accessing `sm.face(d)`).
   - Never assume dense indices `0..nbElements()` in a `DataContainer`; deleted slots form an inactive free-list. Always use iterators (`cellIterator`, `pointIterator`, `indexIterator`), or `nextSafe()` when deleting during iteration.
5. **OpenGL 4.1 Core & math conventions**:
   - `mat.zig` matrices are **column-major** (`m[col][row]`), matching OpenGL and Eigen.
   - `mat.lookAt(eyepos, eyedir, updir)` takes a **direction**, not a look-at target point.
   - OpenGL 4.1 has no SSBOs: per-face shader attributes use `TextureBuffer` (`GL_TEXTURE_BUFFER`) + `IBO.cell_index_buffer_index`. Wide lines and spheres use geometry shaders.
   - Shaders omit `#version` in `.glsl` files (`Shader.setShader` prepends `#version 410 core\n`).
6. **Numerical & C-interop gotchas**:
   - `eigen.zig` uses `f64` (`eigen.Scalar`) and `i32` (`eigen.Index`); cast `f32` mesh quantities when assembling linear systems.
   - `ceigen`'s iterative CG solver uses `solveWithGuess` — the caller's output vector is read as the initial guess.
   - `bvh.TrianglesBVH` and most `surface/` algorithms (geodesics, curvature, ARAP, heat method, decimation, remeshing, sampling) assume **triangulated** faces.

---

## 4. Documentation Routing Table

Read the specific doc below before making changes in that area:

| Task / Area | Read First | Key Code Paths |
|---|---|---|
| Terminology & naming | [`docs/glossary.md`](docs/glossary.md) | — |
| App startup, CLI args, event routing, build/deps | [`docs/01-architecture.md`](docs/01-architecture.md) | `src/main.zig`, `src/AppContext.zig`, `build.zig`, `src/c.h` |
| `DataContainer`, markers, `BufferPool`, math, Eigen, BVH/KDTree | [`docs/02-core-foundations.md`](docs/02-core-foundations.md) | `src/utils/`, `src/geometry/`, `src/thirdparty/` |
| Model lifecycle, `StdDatas`, GPU sync, store events | [`docs/03-stores-and-events.md`](docs/03-stores-and-events.md) | `src/models/*Store.zig` |
| Creating/editing UI or feature modules | [`docs/04-modules.md`](docs/04-modules.md) | `src/modules/Module.zig`, `src/modules/*.zig` |
| `SurfaceMesh` topology & surface algorithms | [`docs/05-models/surface-mesh.md`](docs/05-models/surface-mesh.md) (+ [`surface-mesh/`](docs/05-models/surface-mesh/)) | `src/models/surface/` |
| `PointCloud` & point algorithms | [`docs/05-models/point-cloud.md`](docs/05-models/point-cloud.md) (+ [`point-cloud/`](docs/05-models/point-cloud/)) | `src/models/point/` |
| `IncidenceGraph` topology | [`docs/05-models/incidence-graph.md`](docs/05-models/incidence-graph.md) | `src/models/incidenceGraph/` |
| `VolumeMesh` (planned) | [`docs/05-models/volume-mesh.md`](docs/05-models/volume-mesh.md) | `src/models/volume/`, `src/models/VolumeMeshStore.zig` |
| Shaders, `View`, `Camera`, OpenGL, ImGui widgets | [`docs/06-rendering-and-ui.md`](docs/06-rendering-and-ui.md) | `src/rendering/`, `src/ui/` |
| Step-by-step checklists (new module/algo/StdData/shader) | [`docs/recipes.md`](docs/recipes.md) | — |
