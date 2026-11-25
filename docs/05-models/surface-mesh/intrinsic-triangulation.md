# Intrinsic Triangulation

- **Source:** [`src/models/surface/intrinsic_triangulation.zig`](../../../src/models/surface/intrinsic_triangulation.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Used by:** [`arap.zig`](arap.md), [`SurfaceMeshDeformation`](../../../src/modules/SurfaceMeshDeformation.zig), [`SurfaceMeshParameterization`](../../../src/modules/SurfaceMeshParameterization.zig)

---

## Overview

Implements a **signpost intrinsic triangulation** engine (`ITContext`) that maintains a cloned combinatorial triangulation (`intrinsic_surface_mesh`) alongside a read-only `extrinsic_surface_mesh`, decoupling connectivity optimization from the 3D embedding. Supports intrinsic Delaunay flipping, Delaunay circumcenter refinement, and Sharp & Crane's FlipOut geodesic shortening.

## Key Types & Entry Points

- `ITContext`:
  - `init` / `deinit` — Clones topology without cell data (`cloneWithoutCellData`) so original vertex indices match the extrinsic mesh, and initializes intrinsic edge lengths, corner angles, face areas, cotan weights, and signpost angles (`intrinsic_halfedge_extrinsic_sp_angle`).
  - `flipEdge` — Performs an intrinsic edge flip updating edge lengths (law of cosines in unfolded diamond), corner angles, areas, cotan weights, and signpost angles.
  - `flipToDelaunay` / `flipEdgesToDelaunay` — Flips non-Delaunay intrinsic edges until the intrinsic Delaunay condition holds (with optional callbacks).
  - `refineDelaunay` / `insertIntrinsicTriangleCircumcenter` / `triangleCircumradiusToShortestEdgeRatioSquared` — Intrinsic Delaunay refinement by inserting Steiner vertices at triangle circumcenters.
  - Internal `FlipOutShortestGeodesicContext` (`flipOutShortestGeodesic`) — Shortens a polyline into a geodesic using edge flips.
  - Internal `traceIntrinsicEdgesInIncidenceGraph` — Traces intrinsic edges over the extrinsic mesh into an [`IncidenceGraph`](../incidence-graph.md).

## Notes & Assumptions

- Original extrinsic vertices are never removed and share identical indices between `extrinsic_surface_mesh` and `intrinsic_surface_mesh`; Steiner vertices added during refinement get new vertex indices mapped back via extrinsic [`SurfacePoint`](surface-point.md)s.
- Creates a unique-named `angle_sum` attribute on the extrinsic mesh so multiple `ITContext` instances can coexist.
- Known TODOs in code: full boundary vertex support, trace trimming/snapping, and replacing `isFinite` guards with exact predicates.
