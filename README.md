# zgp — Zig Geometry Processing

**zgp** is an interactive 3D geometry processing framework and viewer written in **Zig (`0.17.0`)**, built around SDL3, OpenGL 4.1 Core, and Dear ImGui (`cimgui`), with native C/C++ bindings for Eigen (`ceigen`), `libacc` (`clibacc`), and Shewchuk's exact geometric predicates (`predicates`).

It provides a modular, event-driven architecture for inspecting, rendering, and processing multiple geometric model families:
- **Surface Meshes** (`SurfaceMesh`) — 2-manifold combinatorial maps with a broad suite of differential geometry, remeshing, decimation, geodesic, deformation, medial axis, sampling, and parameterization algorithms.
- **Point Clouds** (`PointCloud`) — attribute-rich point sets with KD-tree queries, convex hull construction, tangent basis estimation, SQEM, and variational medial axis computation.
- **Incidence Graphs** (`IncidenceGraph`) — non-manifold cellular complexes (vertices, edges, faces) used for skeletons and general topological graphs.
- **Volume Meshes** (`VolumeMesh`) — planned (stubbed).

---

## Building & Running

Requires **Zig 0.17.0** (see [`build.zig.zon`](build.zig.zon)).

```sh
# Build the application
zig build

# Run with one or more surface mesh files (.off)
# Flags (must precede file paths):
#   -n   Normalize mesh positions to unit bounding-box extent
#   -c   Center mesh around the origin
zig build run -- -n -c path/to/mesh.off

# Run unit tests
zig build test
```

> **Note:** `imgui.zig` loads fonts from relative paths under `src/ui/` (`DroidSans.ttf`, `fa-regular-400.ttf`, `fa-solid-900.ttf`), so run the executable from the repository root.

---

## Documentation

The documentation is organized by architectural layer and designed for both human contributors and AI agents (see [`AGENTS.md`](AGENTS.md) for the compact agent quick-start and invariants checklist):

| Document | Contents |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Compact orientation for AI agents: build/test, Zig 0.17 idioms, critical invariants, and doc routing table |
| [`docs/glossary.md`](docs/glossary.md) | Canonical shared vocabulary (combinatorial maps, data containers, stores, modules, rendering) |
| [`docs/01-architecture.md`](docs/01-architecture.md) | Application lifecycle (SDL3 callbacks), `AppContext` ownership & two-phase wiring, frame/event loop, third-party stack |
| [`docs/02-core-foundations.md`](docs/02-core-foundations.md) | `DataContainer` / `Data(T)` / `DataGen`, markers, `BufferPool`, parallel task runners, `src/geometry/`, `src/utils/` |
| [`docs/03-stores-and-events.md`](docs/03-stores-and-events.md) | `*Store` registries: model lifecycle, `StdDatas`, lazy GPU VBO/IBO sync, BVH/KDTree, timestamps, observer events |
| [`docs/04-modules.md`](docs/04-modules.md) | `Module` vtable & `@fieldParentPtr` pattern, `SupportedModels` filtering, catalog of all 19 modules |
| [`docs/05-models/surface-mesh.md`](docs/05-models/surface-mesh.md) | `SurfaceMesh` combinatorial map, illustrated topological operators, and catalog linking to [`docs/05-models/surface-mesh/`](docs/05-models/surface-mesh/) |
| [`docs/05-models/point-cloud.md`](docs/05-models/point-cloud.md) | `PointCloud` structure, `PointData`, parallel runner, and catalog linking to [`docs/05-models/point-cloud/`](docs/05-models/point-cloud/) |
| [`docs/05-models/incidence-graph.md`](docs/05-models/incidence-graph.md) | `IncidenceGraph` non-manifold cellular representation |
| [`docs/05-models/volume-mesh.md`](docs/05-models/volume-mesh.md) | Planned `VolumeMesh` status and integration roadmap |
| [`docs/06-rendering-and-ui.md`](docs/06-rendering-and-ui.md) | `View` retained FBO rendering, `Camera`, OpenGL 4.1 wrappers, `Shader` registry & catalog of 17 shaders, ImGui helpers |
| [`docs/recipes.md`](docs/recipes.md) | Step-by-step checklists for adding a Module, SurfaceMesh algorithm, `StdData`, or Shader |
