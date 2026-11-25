# Face & Vertex Areas

- **Source:** [`src/models/surface/area.zig`](../../../src/models/surface/area.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Exposed by:** [`SurfaceMeshStdDatas`](../../../src/modules/SurfaceMeshStdDatas.zig) (`face_area`, `vertex_area`)

---

## Overview

Computes face areas (extrinsically via triangle fan or intrinsically via Heron's formula) and barycentric dual vertex areas.

## Key Entry Points

- `faceArea` / `computeFaceAreas` — Extrinsic face areas (`ParallelFaceTaskRunner`).
- `faceAreaIntrinsic` / `computeFaceAreasIntrinsic` — Intrinsic triangle areas from `edge_length` (`ParallelFaceTaskRunner`).
- `vertexArea` / `computeVertexAreas` — Barycentric vertex area $\sum_{f \ni v} A_f / \text{codegree}(f)$ (batch function runs sequentially in a face-centric pass).

## Notes & Assumptions

- `faceArea` currently uses a simple triangle fan on polygonal faces (code notes a TODO for ear-triangulation).
- `faceAreaIntrinsic` assumes triangular faces.
