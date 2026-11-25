# Curvature Estimation

- **Source:** [`src/models/surface/curvature.zig`](../../../src/models/surface/curvature.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Exposed by:** [`SurfaceMeshCurvature`](../../../src/modules/SurfaceMeshCurvature.zig) (also consumed by [`remeshing.zig`](remeshing.md))

---

## Overview

Computes principal curvatures and principal directions via the **Cohen-Steiner & Morvan normal-cycle curvature tensor** integrated over a local Euclidean sphere, as well as discrete **Gaussian curvature** via vertex angle defect.

## Key Types & Entry Points

- `SurfaceMeshCurvatureDatas` — Groups optional `vertex_kmin`, `vertex_Kmin`, `vertex_kmax`, `vertex_Kmax` attributes.
- `vertexCurvature` / `computeVertexCurvatures` — Integrates dihedral edge tensors within a ball of radius `mean_edge_length * radius_ratio` using `WithinSphereSelectionContext` (`selection.zig`), solves the 3×3 symmetric eigenproblem via `eigen.eigenSolver`, and extracts $(k_{\min}, K_{\min}, k_{\max}, K_{\max})$ in parallel (`ParallelVertexTaskRunnerWithContext`).
- `vertexGaussianCurvature` / `computeVertexGaussianCurvatures` — Angle-defect Gaussian curvature ($2\pi - \sum \theta$ interior, $\pi - \sum \theta$ on boundary; `ParallelVertexTaskRunner`).

## Notes & Assumptions

- `computeVertexCurvatures` assumes all four optional fields of `SurfaceMeshCurvatureDatas` are non-null.
- Identifies the normal eigenvector as the one with smallest $|\lambda|$ and orders tangent eigenpairs so $k_{\min} \le k_{\max}$.
