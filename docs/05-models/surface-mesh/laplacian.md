# Cotangent Laplacian Weights

- **Source:** [`src/models/surface/laplacian.zig`](../../../src/models/surface/laplacian.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Exposed by:** [`SurfaceMeshStdDatas`](../../../src/modules/SurfaceMeshStdDatas.zig) (`halfedge_cotan_weight`)
- **Used by:** [`arap.zig`](arap.md), [`distance.zig`](distance.md), [`filtering.zig`](filtering.md), [`intrinsic_triangulation.zig`](intrinsic-triangulation.md)

---

## Overview

Computes halfedge cotangent weights $\frac{1}{2}\cot\theta$ (both extrinsically from vertex positions and intrinsically from edge lengths and face areas) and undirected edge cotangent weights.

## Key Entry Points

- `halfedgeCotanWeight` / `computeHalfedgeCotanWeights` — Extrinsic halfedge cotan weights (`ParallelHalfedgeTaskRunner`).
- `halfedgeCotanWeightIntrinsic` / `computeHalfedgeCotanWeightsIntrinsic` — Intrinsic halfedge cotan weights from `edge_length` and `face_area` (`ParallelHalfedgeTaskRunner`).
- `edgeCotanWeight(sm, halfedge_cotan_weight, edge) -> f32` — Sum of weights on the edge's non-boundary halfedges.

## Notes & Assumptions

- Assumes triangular faces.
- Boundary darts receive weight `0.0`.
