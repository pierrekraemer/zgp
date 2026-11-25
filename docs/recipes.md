# Developer Recipes & Checklists

Quick, repeatable checklists for common extension tasks in `zgp`.

---

## 1. Add a New Module

1. **Create `src/modules/<MyModule>.zig`**:
   - Start with `const MyModule = @This();`.
   - Embed `app_ctx: *AppContext = undefined` and `module: Module = .{ .name = "...", .supported_models = .{ ... }, .vtable = &.{ ... } }`.
   - If you keep per-model state, store it in `std.AutoHashMapUnmanaged(*Model, MyModelData) = .empty` and manage entries in `*Created` / `*Destroyed`.
   - In `init(self, app_ctx)`, store `app_ctx` and call `try app_ctx.<store>.addListener(&self.module)` for each store whose events you handle.
   - In `deinit(self)`, free all per-model state and call `removeListener(&self.module)`.
   - Inside every `VTable` callback, recover `self` via `@alignCast(@fieldParentPtr("module", m))`.
2. **Wire it into [`src/AppContext.zig`](../src/AppContext.zig)** (4 places):
   - Import the module at the top of `AppContext.zig`.
   - Add a default-initialized field: `my_module: MyModule = .{},`.
   - In `wireUp()`: call `try app_ctx.my_module.init(app_ctx);` and `try app_ctx.modules.append(app_ctx.allocator, &app_ctx.my_module.module);`.
   - In `deinit()`: call `app_ctx.my_module.deinit();`.
3. **Sync stores & view**:
   - After modifying any attribute or topology from a UI button or event handler, call `store.*DataUpdated(...)` / `store.*ConnectivityUpdated(...)` and `app_ctx.view.requestRedraw()`.

---

## 2. Add a New `SurfaceMesh` Algorithm

1. **Keep it pure under `src/models/surface/<algo>.zig`**:
   - Accept `*SurfaceMesh` (or `*const SurfaceMesh`), explicit `CellData` / `CellSet` / `TrianglesBVH` handles, and any needed `allocator` / `io`. Do **not** import `AppContext`, `ui/`, or `rendering/`.
2. **Follow `SurfaceMesh` & `DataContainer` conventions**:
   - Name temporary cell attributes with a `__<algo>_*` prefix and clean them up with `defer sm.removeData(tmp);`.
   - Clean up markers with `defer marker.deinit();`.
   - Filter out boundary darts (`if (sm.isBoundaryDart(d)) continue;`) when iterating `dartIterator()`, `halfedgeIterator()`, `cornerIterator()`, or vertex/edge orbits (`vertexDartIterator`, `edgeDartIterator`) whenever an operation assumes an interior dart (e.g., accessing `sm.face(d)`).
   - Use `nextSafe()` if an iteration loop removes cells.
   - Use `ParallelCellTaskRunner` (or `ParallelCellTaskRunnerWithContext` for per-thread scratch state) for independent per-cell work.
   - When assembling Eigen sparse/dense linear systems, cast `f32` quantities to `eigen.Scalar` (`f64`).
3. **Expose it through a Module**:
   - Call the algorithm from an existing or new `SurfaceMesh*` module, then invoke `surfaceMeshDataUpdated` / `surfaceMeshConnectivityUpdated` and `app_ctx.view.requestRedraw()`.
   - In debug builds, `surfaceMeshConnectivityUpdated` automatically runs `sm.checkIntegrity()`.
4. **Document it**:
   - Add a matching page under `docs/05-models/surface-mesh/<algo>.md` and link it from [`docs/05-models/surface-mesh.md`](05-models/surface-mesh.md).

---

## 3. Add a New Standard Data (`StdData`) to `SurfaceMesh`

1. **Declare the slot** in `SurfaceMeshStdDatas` in [`src/models/SurfaceMeshStore.zig`](../src/models/SurfaceMeshStore.zig) (e.g., `vertex_foo: ?SurfaceMesh.VertexData(f32) = null`).
   - `SurfaceMeshStdData` (union) and `SurfaceMeshStdDataTag` (enum) update automatically via `UnionFromStruct`, and `createSurfaceMesh` will automatically allocate and bind the new column.
2. **Register its computation** in [`src/modules/SurfaceMeshStdDatas.zig`](../src/modules/SurfaceMeshStdDatas.zig):
   - Write a wrapper function matching `fn (*AppContext, *SurfaceMesh, <ReadCellDatas>..., *<ComputedCellData>) anyerror!void` that computes the data and calls `app_ctx.surface_mesh_store.surfaceMeshDataUpdated(...)`.
   - Add an entry to `std_data_computations` in **topological order** (after everything listed in its `.reads`).
   - The left-panel selector, staleness coloring, and `updateComputableStdDatas()` will pick it up automatically.

---

## 4. Add a New Shader

1. **Create `src/rendering/shaders/<shader_name>/`**:
   - Add `vs.glsl`, optional `gs.glsl`, and `fs.glsl` **without** `#version` directives (`Shader.setShader` injects `#version 410 core\n`).
   - Add `<ShaderName>.zig` following an existing wrapper (e.g., `PointSphere.zig` or `TriFlatScalarPerFace.zig`):
     - Lazy singleton `global_instance` + `pub fn instance() *Self` that compiles embedded shaders, caches uniform locations + `VertexAttribInfo`, and calls `Shader.register(&global_instance.?.program)`.
     - Nested `pub const Parameters` owning its `vao: VAO`, uniform fields, `init()`, `deinit()`, `setVertexAttribArray` / `unsetVertexAttribArray`, and `draw(...)`.
2. **OpenGL 4.1 Core reminders**:
   - Upload `Mat4f` matrices with `gl.UniformMatrix4fv(loc, 1, gl.FALSE, @ptrCast(&mat))` (`mat.zig` is already column-major).
   - For per-face data, bind `ibo.cell_index_buffer_index` (`R32UI`) and the face `VBO` (`R32F`/`RGB32F`) via `TextureBuffer`s rather than SSBOs.
   - Always bind a `VAO` (even an empty one) before any draw call.

---

## 5. Add a New Model Type (e.g., `VolumeMesh`)

When implementing a new model family such as [`VolumeMesh`](05-models/volume-mesh.md):
1. Implement the core model struct in `src/models/<kind>/<Model>.zig` using `DataContainer`s and a shared `BufferPool`.
2. Implement `src/models/<Model>Store.zig` mirroring `SurfaceMeshStore.zig` (`*StdDatas`, `*StdData`, `*Info`, `data_vbo`, `data_last_update`, `listeners`, `leftPanel`).
3. Add the new variant to `AppContext.ModelSelection` and `Module.SupportedModels`, plus lifecycle/update hooks to `Module.VTable`.
4. Add `imgui.<model>ListBox` and `<model>CellDataComboBox` helpers in `src/ui/imgui.zig`.
5. Add `<Model>StdDatas.zig` and `<Model>Renderer.zig` modules and wire the store + modules into `AppContext.zig`.
