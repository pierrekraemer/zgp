# Subdivision & Triangulation

- **Source:** [`src/models/surface/subdivision.zig`](../../../src/models/surface/subdivision.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Exposed by:** [`SurfaceMeshConnectivity`](../../../src/modules/SurfaceMeshConnectivity.zig)
- **Used by:** [`decimation.zig`](decimation.md), [`remeshing.zig`](remeshing.md)

---

## Overview

Provides basic mesh-wide topological subdivision operations: triangulating polygonal faces and splitting all edges at their midpoints.

## Key Entry Points

- `triangulateFaces(sm)` — Splits every face with `codegree > 3` into triangles via a triangle fan using `sm.cutFace`.
- `cutAllEdges(sm, vertex_position)` — Splits every existing edge at its midpoint via `sm.cutEdge`.

## Notes & Assumptions

- Collects existing faces or edges into a temporary buffer before modifying topology so newly inserted cells are not re-visited during the pass.
- `triangulateFaces` currently uses a simple triangle fan (code notes a TODO for ear-triangulation on non-convex polygons).
