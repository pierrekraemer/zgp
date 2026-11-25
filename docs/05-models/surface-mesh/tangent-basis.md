# Tangent Basis (SurfaceMesh)

- **Source:** [`src/models/surface/tangent_basis.zig`](../../../src/models/surface/tangent_basis.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Exposed by:** [`SurfaceMeshStdDatas`](../../../src/modules/SurfaceMeshStdDatas.zig) (`vertex_tangent_basis`)

---

## Overview

Constructs an orthonormal tangent frame (`[2]Vec3f`) at each vertex of a `SurfaceMesh`, aligned with the vertex's representative outgoing edge.

## Key Entry Points

- `vertexTangentBasis(sm, vertex_position, vertex_normal, vertex) -> [2]Vec3f`
- `computeVertexTangentBases(sm, vertex_position, vertex_normal, vertex_tangent_basis)` — Parallel computation via `ParallelVertexTaskRunner`.

## Notes & Assumptions

- Projects the outgoing edge of `sm.dart(v)` onto the tangent plane orthogonal to `vertex_normal` to form $X$, then sets $Y = n \times X$.
- Assumes `vertex_normal` is normalized.
