# Edge Length

- **Source:** [`src/models/surface/length.zig`](../../../src/models/surface/length.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Exposed by:** [`SurfaceMeshStdDatas`](../../../src/modules/SurfaceMeshStdDatas.zig) (`edge_length`)

---

## Overview

Computes Euclidean edge lengths $\|p_1 - p_0\|$ for individual edges or all edges of a `SurfaceMesh`.

## Key Entry Points

- `edgeLength(sm, vertex_position, edge) -> f32` — Length of a single edge.
- `computeEdgeLengths(sm, vertex_position, edge_length)` — Populates an `EdgeData(f32)` sequentially across all edges.

## Notes & Assumptions

- `computeEdgeLengths` is intentionally sequential (per-edge work is too lightweight to amortize parallel dispatch).
