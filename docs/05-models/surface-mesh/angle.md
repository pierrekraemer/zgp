# Corner & Dihedral Angles

- **Source:** [`src/models/surface/angle.zig`](../../../src/models/surface/angle.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Exposed by:** [`SurfaceMeshStdDatas`](../../../src/modules/SurfaceMeshStdDatas.zig) (`corner_angle`, `edge_dihedral_angle`)

---

## Overview

Computes interior corner angles (both extrinsically from vertex positions and intrinsically from edge lengths via the law of cosines) as well as signed dihedral angles across interior edges.

## Key Entry Points

- `cornerAngle` / `computeCornerAngles` — Extrinsic corner angles (`ParallelCornerTaskRunner`).
- `cornerAngleIntrinsic` / `computeCornerAnglesIntrinsic` — Intrinsic triangle corner angles from `edge_length` (`ParallelCornerTaskRunner`).
- `edgeDihedralAngle` / `computeEdgeDihedralAngles` — Signed angle between adjacent face normals (`ParallelEdgeTaskRunner`).

## Notes & Assumptions

- `edgeDihedralAngle` assumes normalized `face_normal`s and returns `0.0` for boundary edges.
- `cornerAngleIntrinsic` assumes triangular faces and clamps cosine inputs to $[-1, 1]$.
