# IncidenceGraph

[`src/models/incidenceGraph/IncidenceGraph.zig`](../../src/models/incidenceGraph/IncidenceGraph.zig) represents a general **non-manifold 2-dimensional cellular complex** (vertices, edges, and polygonal faces) using explicit incidence lists. In `zgp`, it is currently used to represent **medial axis skeletons** (which contain non-manifold sheets, curves, and junctions that cannot be stored in a 2-manifold `SurfaceMesh`) and traced intrinsic edge graphs.

---

## 1. Data Structure & Core API (`IncidenceGraph.zig`)

### Cells & Containers
- **`CellIndex = u32`**, **`CellType = enum { vertex, edge, face }`**, typed **`Cell(cell_type)`** aliases `Vertex`, `Edge`, `Face`.
- Three `DataContainer`s (`vertex_data`, `edge_data`, `face_data`) plus a shared `index_buffer_pool: *BufferPool(u32)` owned by `IncidenceGraphStore`.

### Explicit Incidence Storage

Unlike `SurfaceMesh`'s dart-based combinatorial map, `IncidenceGraph` stores incidence relations directly as internal `Data` columns:

| Internal Column | Container | Type | Meaning |
|---|---|---|---|
| `vertex_incident_edges` | `vertex_data` | `std.ArrayList(Edge)` | All edges incident to the vertex |
| `edge_incident_vertices` | `edge_data` | `[2]Vertex` | The two endpoint vertices of the edge |
| `edge_incident_faces` | `edge_data` | `std.ArrayList(Face)` | All faces incident to the edge (arbitrary valence, supporting non-manifold junctions) |
| `face_incident_edges` | `face_data` | `std.ArrayList(Edge)` | Boundary edges of the face |
| `face_incident_edges_dir` | `face_data` | `std.ArrayList(bool)` | Orientation flag per boundary edge of the face |

### Core API
- **Lifecycle**: `init(allocator, io, index_buffer_pool)`, `deinit()` (frees all nested `ArrayList`s before tearing down containers), `clearRetainingCapacity()`.
- **Cell creation**:
  - `addVertex() !Vertex`
  - `addEdge(v0, v1) !Edge` (updates both vertices' `vertex_incident_edges`)
  - `addFace(edges: []const Edge) !Face` (updates each edge's `edge_incident_faces`; *TODO in code:* order the face edges and set `face_incident_edges_dir` accordingly — currently sets all directions to `true`).
- **Queries**: `nbCells(cell_type)`, `degree(vertex | edge)` (incident edges or faces), `codegree(edge | face)` (`2` for edges, edge count for faces).
- **Iterators**: `cellIterator(cell_type)` (`vertexIterator`, `edgeIterator`, `faceIterator`) with `next()`, `nextSafe()`, `reset()`.
- **Typed Cell Data**: `CellData(cell_type, T)` (`VertexData`, `EdgeData`, `FaceData`) via `addData`, `getData`, `getOrAddData`, `removeData`.
- **Markers**: `CellMarker(cell_type)` backed by pooled `DataContainer` markers (`mark`, `unmark`, `isMarked`, `reset`).

---

## 2. Store, Rendering & Algorithms

Managed by [`IncidenceGraphStore.zig`](../../src/models/IncidenceGraphStore.zig):
- **Standard data**: `vertex_position: ?IncidenceGraph.VertexData(Vec3f)`.
- **GPU primitive IBOs**: `points_ibo`, `lines_ibo`, `triangles_ibo` (updated on `incidenceGraphConnectivityUpdated`).
- **Modules**: [`IncidenceGraphStdDatas.zig`](../../src/modules/IncidenceGraphStdDatas.zig) and [`IncidenceGraphRenderer.zig`](../../src/modules/IncidenceGraphRenderer.zig) (supports spheres, lines/cylinders, and flat triangles with `dim_backfaces = false` so non-manifold sheets render cleanly from both sides).
- **Algorithms**: No standalone algorithm files exist under `src/models/incidenceGraph/` yet; graphs are currently produced by `surface/medial_axis.zig`, `point/medial_axis.zig`, and `surface/intrinsic_triangulation.zig`. Future algorithms will be documented under `docs/05-models/incidence-graph/`.
