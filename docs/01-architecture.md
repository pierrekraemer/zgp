# System Architecture

This document explains how `zgp` boots, owns state, runs its main frame and event loops, and integrates its Zig and C/C++ dependencies.

---

## 1. Layered Design

`zgp` separates pure geometric data structures and algorithms from application state, GPU synchronization, and UI modules:

```text
                     +------------------------------------+
                     | src/main.zig (SDL3 App Callbacks)  |
                     +-----------------+------------------+
                                       |
                                       v
+-------------------------------------------------------------------------+
|              src/AppContext.zig (Root Owner & Event Router)             |
+---------------+-------------------+-------------------------------------+
        |                 |                            |
        v                 v                            v
+---------------+ +---------------+     +---------------------------------+
| src/ui/       | | src/rendering |     | 19 Concrete Modules             |
| Window.zig    | | View.zig      |<----+ (via *Module VTable)            |
| imgui.zig     | | (FBO+Camera)  |draw/+---------------+-----------------+
+---------------+ +---------------+req. | subscribe/    |
                                  redraw| notify        | invoke algorithms
                                        v               |
                  +-------------------------------+     |
                  | Model Stores                  |     |
                  | (SurfaceMesh/PointCloud/IG)   |     |
                  | own & cache VBO/IBO/BVH/KDTree|     |
                  +---------------+---------------+     |
                                  |                     |
                                  v                     v
                  +-------------------------------------------+
                  | Models & Algorithms                       |
                  | (surface/, point/, incidenceGraph/)       |
                  +---------------------+---------------------+
                                        |
                                        v
                  +-------------------------------------------+
                  | Foundations (utils/data.zig, BufferPool,  |
                  | geometry/)                                |
                  +---------------------+---------------------+
                                        |
                                        v
                  +-------------------------------------------+
                  | C/C++ Stack (ceigen, clibacc, predicates) |
                  +-------------------------------------------+
```

**Design principle:** Code under `src/models/<kind>/` (e.g., `SurfaceMesh.zig`, `arap.zig`, `PointCloud.zig`) depends only on `src/utils/` and `src/geometry/`. It never imports `AppContext`, `ui/`, or `rendering/`. Stores bridge models to GPU resources and event listeners; Modules bridge stores, algorithms, rendering, and Dear ImGui.

---

## 2. Entrypoint & SDL3 Callback Lifecycle

[`src/main.zig`](../src/main.zig) uses Zig `0.17.0`'s `pub fn main(init: std.process.Init) !u8` and drives the application through **SDL3's callback API** (`SDL_RunApp` → `SDL_EnterAppMainCallbacks`):

1. **`main(init)`**:
   - Captures `init.io` and `init.gpa` into module-level `io` and `allocator`.
   - Parses command-line arguments via [`src/utils/CLIArgs.zig`](../src/utils/CLIArgs.zig) (`-n` normalize, `-c` center, followed by one or more mesh file paths).
   - Launches `SDL_RunApp(..., sdlMainC, null)`.
2. **`sdlAppInit`**:
   - Calls `app_ctx = try AppContext.init(io, allocator)` (phase 1).
   - Calls `try app_ctx.wireUp()` (phase 2).
   - Calls `try app_ctx.readArgs(cli_args)` to load initial `.off` mesh files, optionally normalizing/centering them, and firing `surfaceMeshDataUpdated` + `surfaceMeshConnectivityUpdated`.
3. **`sdlAppIterate`**:
   - Calls `app_ctx.mainUI()`; returning `false` cleanly terminates with `SDL_APP_SUCCESS`.
4. **`sdlAppEvent`**:
   - Handles `SDL_EVENT_QUIT` and `Escape` (`SDLK_ESCAPE`) to quit.
   - Forwards all other events to `app_ctx.sdlEvent(event)`.
5. **`sdlAppQuit`**:
   - Logs any `error.SdlError` via `SDL_GetError()`, calls `imgui.deinit()`, and calls `app_ctx.deinit()`.

Because SDL callbacks cross a `callconv(.c)` boundary, `main.zig` uses an atomic `ErrorStore` (`SDL_AtomicInt`) to capture any Zig error and its `@errorReturnTrace()` addresses so `main()` can propagate the Zig error after `SDL_RunApp` returns.

---

## 3. `AppContext`: Ownership & Two-Phase Wiring

[`src/AppContext.zig`](../src/AppContext.zig) is the single root state container:

| Category | Fields on `AppContext` |
|---|---|
| Core runtime | `io: std.Io`, `allocator: std.mem.Allocator`, `rng: std.Random.DefaultPrng` |
| Window & 3D view | `window: Window`, `view: View` |
| Model stores | `point_cloud_store`, `surface_mesh_store`, `incidence_graph_store` |
| Selection state | `selected_model: ModelSelection` (`.none`, `.surface_mesh`, `.point_cloud`, `.incidence_graph`) |
| Concrete modules | 19 module structs stored inline as value fields (default-initialized via `.{}`) |
| Polymorphic list | `modules: std.ArrayList(*Module)` pointing to `&<concrete_module>.module` |

### Why Two-Phase Initialization (`init` then `wireUp`)?

Modules store a back-pointer `app_ctx: *AppContext` and register `&self.module` with stores during initialization. Because `AppContext.init()` returns `AppContext` **by value**, pointers to fields inside it are only stable once the caller stores it in its final location (`var app_ctx` in `main.zig`).

- **Phase 1 — `AppContext.init(io, allocator)`**: Seeds the PRNG, initializes `Shader.initRegistry(allocator)`, creates `Window`, `View`, and the three stores, and default-initializes all 19 module structs.
- **Phase 2 — `AppContext.wireUp()`**:
  1. Calls `module.init(app_ctx)` on all 19 modules (which subscribe to store listeners).
  2. Appends `&<module>.module` to `app_ctx.modules` (defining UI, rendering, and SDL event priority order).
  3. Connects each store's `selected_model` pointer to `&app_ctx.selected_model`.
  4. Resizes `view` to match `window` pixel dimensions and initializes Dear ImGui (`imgui.init(...)`).

> **Invariant:** `AppContext` must not be moved in memory after `wireUp()` is called, since modules hold `*AppContext` and stores/arrays hold `*Module` pointers derived from inline struct fields.

### Teardown Order (`AppContext.deinit`)

Destruction runs in reverse dependency order:
1. `deinit()` all 19 modules (unsubscribing listeners and freeing per-model parameters/contexts).
2. Free `modules` list.
3. `deinit()` all three stores (destroying owned models, `*Info` BVH/KDTree/IBOs, and VBOs).
4. `Shader.deinitRegistry()` (deleting all compiled OpenGL shader programs while the GL context is still alive).
5. `view.deinit()` and finally `window.deinit()` (destroying the GL context and SDL window).

---

## 4. Frame Loop & UI Layout (`AppContext.mainUI`)

Each call to `app_ctx.mainUI()` executes in this exact sequence:

```text
sdlAppIterate -> AppContext.mainUI()
  |
  +-> 1. View.draw(modules)
  |        |-- if view.needs_redraw:
  |        |     bind FBO -> module.draw(V, P) for ALL modules
  |        |     draw infinite grid -> clear needs_redraw
  |        +-- blit FBO color texture to screen
  |
  +-> 2. ImGui NewFrame()
  |        |-- Right-click context menu  -> active modules.rightClickMenu()
  |        |-- Main menu bar             -> View, Stores, active modules.menuBar(), FPS
  |        |-- Left panel                -> model lists -> selected Store.leftPanel()
  |        |                                -> active modules.leftPanel()
  |        +-- Right panel               -> collapsing headers for active modules
  |                                         with custom rightPanel()
  |
  +-> 3. ImGui Render + RenderDrawData + platform viewports
  |
  +-> 4. SDL_GL_MakeCurrent + SDL_GL_SwapWindow
```

Key UI layout conventions:
- **Left Panel** (22% viewport width, 50% opacity):
  1. Model selection list boxes (`Point Clouds`, `Surface Meshes`, `Incidence Graphs`). Changing selection calls `module.selectedModelChanged()` on every module and `view.requestRedraw()`.
  2. Selected model's **Store** `leftPanel()` (cell count stats, "Create cell data" modal, Build/Update BVH or KDTree button, Delete button).
  3. Active modules' `leftPanel()` (primarily the `*StdDatas` panels).
- **Right Panel** (22% viewport width, right edge):
  - Displays the selected model's name and renders a green collapsing header (`module.name`) for each active module whose `vtable.rightPanel != Module.defaultRightPanel`.
- **Right-Click Context Menu**: Opens when right-clicking on the 3D viewport (not captured by ImGui) and dispatches `module.rightClickMenu()` to active modules.
- **Active Module Filtering (`shouldCallOnModule`)**:
  - A module with all `supported_models` flags `false` is global (always called).
  - Otherwise it is only called when `selected_model` matches a `true` flag in `module.supported_models`.
  - **Exception**: `View.draw()` invokes `module.draw()` on **all** modules unconditionally so unselected models remain visible in the 3D scene.

---

## 5. SDL Event Routing (`AppContext.sdlEvent`)

1. Forward event to Dear ImGui (`cImGui_ImplSDL3_ProcessEvent`).
2. Handle `SDL_EVENT_WINDOW_RESIZED` (query pixel size, resize `view`, request redraw).
3. If ImGui wants the mouse (`WantCaptureMouse` or any ImGui window hovered), **stop propagation**.
4. Iterate `app_ctx.modules` in registration order: for each active module (`shouldCallOnModule`), call `module.sdlEvent(event)`. The first module returning `true` consumes the event and stops propagation.
5. Otherwise, forward the event to `app_ctx.view.sdlEvent(event)` (camera orbit, pan, zoom, double-click pivot).

---

## 6. Build System & Dependency Stack

[`build.zig`](../build.zig) and [`build.zig.zon`](../build.zig.zon) target **Zig `0.17.0`** and assemble the `zgp` executable (`src/main.zig`) with two imported modules:

- **`@import("gl")`**: Generated at build time by `zigglgen` for **OpenGL 4.1 Core**.
- **`@import("c")`**: Produced by `translate_c` from [`src/c.h`](../src/c.h), linking all C/C++ libraries and collecting their include paths via `addIncludePathsToTranslateC`:

| Dependency | Origin | Role |
|---|---|---|
| `sdl` | External Zig pkg (`SDL3`) | Windowing, GL context, event/app lifecycle |
| `cimgui_zig` | External Zig pkg (`dcimgui`) | Dear ImGui (SDL3 + OpenGL3 backends, internal, docking, viewports) |
| `IconsFontAwesome7.h` | `src/thirdparty/` | Icon codepoints merged into ImGui font |
| `ceigen` | Local pkg `src/thirdparty/ceigen` | C wrapper for Eigen (`f64`, `i32`, column-major): 3D/4D ops, dense least-squares, sparse `SimplicialLDLT` & CG |
| `clibacc` | Local pkg `src/thirdparty/clibacc` | C wrapper for `libacc` (`f32`, `u32`): triangle BVH & 3D KD-tree |
| `predicates` | Local pkg `src/thirdparty/predicates` | Shewchuk exact geometric predicates (`orient2d`, `orient3d`, `incircle`, `insphere`) in single precision (`float`) |
