# QEM (SurfaceMesh)

- **Source:** [`src/models/surface/qem.zig`](../../../src/models/surface/qem.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Used by:** [`decimation.zig`](decimation.md)

---

## Overview

Computes **Garland–Heckbert Quadric Error Metrics** (`Mat4f`) per vertex, regularized with normal line quadrics (following SGP 2025 *"Controlling Quadric Error Simplification with Line Quadrics"*), and solves for the optimal collapse position.

## Key Entry Points

- `vertexQEM` / `computeVertexQEMs` — Accumulates incident face plane quadrics weighted by `face_area / 3.0` plus normal line-quadric regularization (`line_quadric_epsilon = 1e-4`).
- `optimalPoint(qem: Mat4f) -> ?Vec3f` — Solves for the point minimizing $p^T Q p$ via Cramer's rule with cross products, returning `null` if $|\det| < 10^{-6}$.

## Notes & Assumptions

- Assumes normalized `face_normal`s.
- Currently divides face area by `3.0` (code notes a TODO to divide by `sm.codegree(face)` for general polygons).
- `computeVertexQEMs` runs sequentially in a face-centric pass.
