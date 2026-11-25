# Isotropic Remeshing

- **Source:** [`src/models/surface/remeshing.zig`](../../../src/models/surface/remeshing.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Exposed by:** [`SurfaceMeshConnectivity`](../../../src/modules/SurfaceMeshConnectivity.zig)

---

## Overview

Implements uniform and curvature-adaptive **isotropic remeshing** (based on Dunyach et al., EG 2013) with optional sharp-feature preservation and surface re-projection via `TrianglesBVH`.

## Key Entry Points

- `isotropicRemeshing(...)` — Performs triangulate → remove flat degree-3 vertices → priority-queue edge splitting (`> 1.33 * L`) → priority-queue edge collapsing (`< 0.75 * L`) → valence-6 edge flipping → tangential Laplacian smoothing with BVH surface projection. In adaptive mode, runs a second pass driven by a principal-curvature sizing field.

## Notes & Assumptions

- Requires a `TrianglesBVH` built on the original surface for tangential relaxation re-projection.
- When `adaptive == true`, expects all fields of `SurfaceMeshCurvatureDatas` (`curvature.zig`) to be non-null.
- Preserves sharp feature edges/corners exceeding a `75°` dihedral angle threshold (hardcoded; noted as a TODO to expose as a parameter).
- Uses temporary attributes `__vertex_sizing_field`, `__cut_edge_queue_index`, and `__collapse_edge_queue_index`.
