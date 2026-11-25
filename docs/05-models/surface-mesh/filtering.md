# Mesh Filtering & Averaging

- **Source:** [`src/models/surface/filtering.zig`](../../../src/models/surface/filtering.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Exposed by:** [`SurfaceMeshFiltering`](../../../src/modules/SurfaceMeshFiltering.zig), [`SurfaceMeshDirectionField`](../../../src/modules/SurfaceMeshDirectionField.zig)

---

## Overview

Provides parallel face-to-vertex attribute averaging and **implicit feature-preserving anisotropic Laplacian filtering** for scalar (`f32`) or vector (`Vec3f`) vertex fields.

## Key Entry Points

- `faceDataVertexAverage` / `computeFaceDataVertexAverages` — Generic over scalar or array types; averages incident face values at each vertex (`ParallelVertexTaskRunner`).
- `anisotropicLaplacianFiltering(sm, vertex_position, vertex_area, vertex_normal, halfedge_cotan_weight, vertex_data, ...)` — Solves $(A - t L_c(f)) x = A f$ using `eigen.SparseMatrix`'s iterative conjugate gradient solver, modulating cotangent weights with a data-discrepancy Gaussian range kernel (`sensitivity_r`) and a normal-slope geometric kernel (`angle_g`).

## Notes & Assumptions

- Performs sparse assembly and solving in `eigen.Scalar` (`f64`).
- Uses temporary `__filtering_vertex_index` vertex data. Code notes a TODO for intrinsic triangulation support.
