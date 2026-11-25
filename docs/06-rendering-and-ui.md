# Rendering & UI

This document describes `zgp`'s OpenGL 4.1 Core rendering pipeline ([`src/rendering/`](../src/rendering/)), shader architecture, and SDL3 / Dear ImGui integration ([`src/ui/`](../src/ui/)).

---

## 1. Retained 3D View Pipeline ([`src/rendering/View.zig`](../src/rendering/View.zig))

Rather than re-rendering 3D geometry on every ImGui frame, `View` renders the 3D scene into an offscreen **`FBO`** (`screen_color_tex` RGBA8 + `screen_depth_tex` DEPTH_COMPONENT32F) only when `view.needs_redraw == true`:

1. If `view.needs_redraw` is `true`:
   - Bind `view.fbo`, clear color + depth, enable depth test.
   - Call `module.draw(camera.view_matrix, camera.projection_matrix)` on **every** module in `app_ctx.modules`.
   - If `view.show_grid`, draw `InfiniteGrid` with `gl.DepthMask(gl.FALSE)`.
   - Set `view.needs_redraw = false`.
2. Unbind FBO, clear the default framebuffer, and blit `screen_color_tex` to the screen using `FullscreenTexture`.
3. ImGui then renders its overlays on top in `AppContext.mainUI`.

> **Invariant:** Because the scene is cached in the FBO, **any code that changes visual state must call `app_ctx.view.requestRedraw()`**, or the viewport will keep displaying the previous frame.

### Camera & Navigation ([`Camera.zig`](../src/rendering/Camera.zig) + `View.sdlEvent`)

- Supports `.perspective` and `.orthographic` projections (toggleable from the `Camera` menu bar).
- Stores `position`, `look_dir`, `up_dir`, `pivot_position`, and cached `view_matrix`, `view_matrix_inv`, `projection_matrix`, `projection_matrix_inv` (inverses computed in `f64` via `eigen.computeInverse4d`).
- **Hardcoded clip planes**: `near = 0.01`, `far = 5.0` (mirrored in `InfiniteGrid.zig`).
- **Default mouse controls** (handled in `View.sdlEvent` when neither ImGui nor an active module consumed the event):
  - **Left Drag**: Orbit around `pivot_position` (`rotateFromScreenVec`).
  - **Shift + Left Drag**: Pan camera (`translateFromScreenVec`).
  - **Mouse Wheel**: Dolly forward/backward (`moveForward`).
  - **Shift + Left Double-Click**: Unproject clicked depth pixel (`viewToWorld`) to re-center `pivot_position` and look at it (falls back to origin on empty background).
- **Picking & unprojection helpers on `View`**:
  - `viewToWorld(x, y)` reads the FBO depth buffer at `(x, height - y)` and returns `null` if `z == 1.0`.
  - `viewToWorldRay(x, y)` / `viewToWorldRayIfGeometry(x, y)` construct a world-space `bvh.Ray` (used by `SurfaceMeshSelection`).
  - `worldToView(world_pos)` projects a 3D point into viewport coordinates.

---

## 2. OpenGL 4.1 Core Primitives (`src/rendering/`)

| Wrapper | File | Role & Notes |
|---|---|---|
| `VBO` | [`VBO.zig`](../src/rendering/VBO.zig) | Vertex buffer (`fillFrom(T, []T)` uploads `GL_STATIC_DRAW`). Cached per `*const DataGen` inside each Store. |
| `VAO` | [`VAO.zig`](../src/rendering/VAO.zig) | Vertex array (`enableVertexAttribArray`, `disableVertexAttribArray` using `VertexAttribInfo`). |
| `IBO` | [`IBO.zig`](../src/rendering/IBO.zig) | Dual buffer: `index` (`ELEMENT_ARRAY_BUFFER` vertex indices) + **`cell_index_buffer_index`** (per-primitive logical cell IDs) + `primitive` (`.points`, `.lines`, `.triangles`). Polygonal faces are fan-triangulated so every triangle of a polygon carries the same face index in `cell_index_buffer_index`. |
| `FBO` | [`FBO.zig`](../src/rendering/FBO.zig) | Offscreen framebuffer attaching `Texture2D` color/depth targets. |
| `Texture2D` | [`Texture2D.zig`](../src/rendering/Texture2D.zig) | 2D texture wrapper (`init`, `resize`, `deinit`). |
| `TextureBuffer` | [`TextureBuffer.zig`](../src/rendering/TextureBuffer.zig) | Buffer texture wrapper used with `gl.TexBuffer` so OpenGL 4.1 shaders can index per-face buffers via `texelFetch` + `gl_PrimitiveID` (replacing SSBOs, which require GL 4.3). |
| `Shader` | [`Shader.zig`](../src/rendering/Shader.zig) | Compiles/links GLSL programs and maintains a **global shader registry** (`initRegistry`, `register`, `deinitRegistry`). Automatically prepends `#version 410 core\n` (or `#version 300 es\n` for GLES), so `.glsl` files omit `#version`. |

---

## 3. Shader Architecture (`src/rendering/shaders/`)

All 17 shader wrappers follow one consistent pattern:

1. **Lazy singleton program**: `var global_instance: ?Self = null; pub fn instance() *Self` embeds its GLSL sources via `@embedFile("vs.glsl")` / `"gs.glsl"` / `"fs.glsl"`, compiles & links once on first use, caches uniform locations and `VertexAttribInfo`, and registers `&program` with `Shader.register(...)` for automatic cleanup in `AppContext.deinit()`.
2. **Per-model `Parameters` struct**: Each wrapper exposes `pub const Parameters` holding `shader: *const Self`, its own `vao: VAO`, uniform parameters, `setVertexAttribArray` / `unsetVertexAttribArray`, and `draw(...)` (which asserts `ibo.primitive` matches the shader's expected primitive).
3. **OpenGL 4.1 Core idioms**:
   - Wide lines, cylinders, spheres, and 3D cones are generated in **geometry shaders** (`gs.glsl`).
   - Per-face attributes bind two `TextureBuffer`s: unit 0 (`R32UI`) for `ibo.cell_index_buffer_index` and unit 1 (`R32F` or `RGB32F`) for the face attribute `VBO`.
   - Attribute-less draws (`FullscreenTexture`, `InfiniteGrid`) still bind an empty `VAO` as required by GL 4.1 Core.
   - Note spelling convention in existing lit shaders: `ambiant_color` / `u_ambiant_color`.

### Catalog of All 17 Shaders

| Shader | Stages | Primitive | Vertex Attribs / Buffers | Purpose |
|---|---|---|---|---|
| `FullscreenTexture` | VS, FS | `DrawArrays(3)` | `Texture2D` | Blits `View.screen_color_tex` to default framebuffer. |
| `InfiniteGrid` | VS, FS | `DrawArrays(6)` | — | Alpha-blended world XZ ground grid (`u_near = 0.01`, `u_far = 5.0`). |
| `Line` | VS, GS, FS | `.lines` | `position` | Screen-space-width colored lines (`viewport_size`, `line_width`). |
| `LineCylinder` | VS, GS, FS | `.lines` | `position` | Lit 3D cylinders for edges, boundaries, and selected edges. |
| `PointSphere` | VS, GS, FS | `.points` | `position` | Lit 3D spheres with uniform radius & color. |
| `PointSphereRadiusPerVertex` | VS, GS, FS | `.points` | `position`, `radius` | Lit spheres with per-vertex radius and uniform color. |
| `PointSphereRGBPerVertex` | VS, GS, FS | `.points` | `position`, `rgb` | Lit spheres with per-vertex RGB and uniform radius. |
| `PointSphereRGBRadiusPerVertex` | VS, GS, FS | `.points` | `position`, `rgb`, `radius` | Lit spheres with per-vertex RGB and per-vertex radius. |
| `PointSphereScalarPerVertex` | VS, GS, FS | `.points` | `position`, `scalar` | Lit spheres with scalar colormap (`min_value`/`max_value`) and uniform radius. |
| `PointSphereScalarRadiusPerVertex` | VS, GS, FS | `.points` | `position`, `scalar`, `radius` | Lit spheres with scalar colormap and per-vertex radius. |
| `PointVector` | VS, GS, FS | `.points` | `position`, `vector` | Lit 3D cones/arrows (`cone_radius`, `vector_scale`, `vector_color`). |
| `TriFlat` | VS, FS | `.triangles` | `position` | Flat-shaded triangles with uniform color & `dim_backfaces`. |
| `TriFlatRGBPerVertex` | VS, FS | `.triangles` | `position`, `rgb` | Flat-shaded triangles with interpolated per-vertex RGB. |
| `TriFlatScalarPerVertex` | VS, FS | `.triangles` | `position`, `scalar` | Flat-shaded triangles with per-vertex scalar colormap + optional isolines (`draw_isolines`, `nb_isolines`). |
| `TriFlatUVPerVertex` | VS, FS | `.triangles` | `position`, `uv` | UV checkerboard/pattern visualization with optional `radial` mode. |
| `TriFlatRGBPerFace` | VS, FS | `.triangles` | `position` + 2 `TextureBuffer`s | Flat-shaded triangles with per-face RGB (`ibo.cell_index_buffer_index` + face `VBO`). |
| `TriFlatScalarPerFace` | VS, FS | `.triangles` | `position` + 2 `TextureBuffer`s | Flat-shaded triangles with per-face scalar colormap (`min_value`/`max_value`). |

---

## 4. Window & Dear ImGui Integration (`src/ui/`)

### `Window` ([`src/ui/Window.zig`](../src/ui/Window.zig))
- Initializes `SDL_INIT_VIDEO`, configures OpenGL 4.1 Core forward-compatible attributes, creates a resizable window sized to `(desktop_w - 200, desktop_h)`, enables VSync (`SDL_GL_SetSwapInterval(1)`), and loads GL procedures into module-level `gl_procs: gl.ProcTable`.
- Exposes `Window.errify(val)` to convert SDL return values (`bool`, nullable pointer, ints) into `error{SdlError}!T`.

### `imgui` ([`src/ui/imgui.zig`](../src/ui/imgui.zig))
- `init(sdl_window, gl_context)`: Configures Dark theme, loads `DroidSans.ttf` (16px) merged with FontAwesome 7 (`fa-regular-400.ttf`, `fa-solid-900.ttf`) from `<SDL_GetBasePath()>/../share/zgp/fonts/` (installed by `build.zig`, with a `src/ui/` fallback for `zig build run`), enables keyboard nav, docking, and multi-viewports, and initializes `cImGui_ImplSDL3` + `cImGui_ImplOpenGL3` (`#version 410 core`).
- Provides reusable domain widgets returning `SelectionResult(T) = union(enum) { unchanged, cleared, changed: T }`:
  - Model list boxes: `pointCloudListBox`, `surfaceMeshListBox`, `incidenceGraphListBox` (clicking the active item returns `.cleared`).
  - Typed data combo boxes (filtered by `typedDataIterator(T)`): `pointCloudDataComboBox`, `surfaceMeshCellDataComboBox`, `incidenceGraphCellDataComboBox`.
  - Surface mesh helpers: `surfaceMeshCellSetComboBox`, `surfaceMeshCellTypeComboBox`, `incidenceGraphCellTypeComboBox`, and `tooltip(text)`.
