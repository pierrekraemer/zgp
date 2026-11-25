# Gradient & Divergence

- **Source:** [`src/models/surface/gradient.zig`](../../../src/models/surface/gradient.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Used by:** [`distance.zig`](distance.md), [`SurfaceMeshDirectionField`](../../../src/modules/SurfaceMeshDirectionField.zig)

---

## Overview

Implements discrete first-order differential operators on triangulated meshes, generic over scalar type `S` (`f32` or `f64`): per-face gradient of a vertex scalar field and per-vertex cotangent-weighted divergence of a face vector field.

## Key Entry Points

- `vertexScalarFieldFaceGradient` / `computeVertexScalarFieldFaceGradients` — Per-face 3D gradient of a vertex scalar field (`ParallelFaceTaskRunner`).
- `faceVectorFieldVertexDivergence` / `computeFaceVectorFieldVertexDivergences` — Integrated divergence at each vertex from incident face vectors (`ParallelVertexTaskRunner`).

## Notes & Assumptions

- Assumes triangular faces.
- Note that `vertexScalarFieldFaceGradient` divides by `face_area` rather than $2 \cdot \text{face\_area}$ (which does not affect consumers like the Heat Method that immediately normalize the gradient).
