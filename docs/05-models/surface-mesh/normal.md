# Face & Vertex Normals

- **Source:** [`src/models/surface/normal.zig`](../../../src/models/surface/normal.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Exposed by:** [`SurfaceMeshStdDatas`](../../../src/modules/SurfaceMeshStdDatas.zig) (`face_normal`, `vertex_normal`)

---

## Overview

Computes unit face normals for triangles or general polygons and angle-weighted unit vertex normals.

## Key Entry Points

- `faceNormal` / `computeFaceNormals` — Normalized sum of consecutive edge cross products around each face, with an early path for triangles (`ParallelFaceTaskRunner`).
- `vertexNormal` / `computeVertexNormals` — Sum of incident `face_normal`s weighted by `corner_angle`, normalized (`ParallelVertexTaskRunner`).

## Notes & Assumptions

- `vertexNormal` / `computeVertexNormals` assume `face_normal` is already normalized and `corner_angle` is up to date.
