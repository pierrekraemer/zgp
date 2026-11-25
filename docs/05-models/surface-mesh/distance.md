# Shortest Paths & Geodesic Distances

- **Source:** [`src/models/surface/distance.zig`](../../../src/models/surface/distance.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Exposed by:** [`SurfaceMeshDistance`](../../../src/modules/SurfaceMeshDistance.zig)
- **Used by:** [`intrinsic_triangulation.zig`](intrinsic-triangulation.md), [`SurfaceMeshParameterization`](../../../src/modules/SurfaceMeshParameterization.zig)

---

## Overview

Provides graph-based Dijkstra shortest-path / multi-source distance queries on mesh edges and **Crane et al.'s Heat Method** for smooth geodesic distance fields on triangle meshes.

## Key Types & Entry Points

- `ShortestEdgePathContext` (`shortestEdgePathBetweenVertices`) — Single-pair Dijkstra shortest edge path returning the sequence of traversed darts.
- `multiSourceDijkstraDistancesAndSources` — Multi-source Dijkstra populating per-vertex distances and nearest source indices (used to build geodesic Voronoi partitions).
- `HeatMethodContext`:
  - `init(sm, vertex_position, vertex_area, halfedge_cotan_weight, t)` — Assembles and pre-factorizes (`eigen.FactorizedSparseMatrix` in `f64`) the cotangent Laplacian $L$ and heat operator $H = A - t L$.
  - `computeGeodesicDistancesFromSource(source_vertices, vertex_distance)` — Solves heat diffusion, computes normalized negated face gradients (`gradient.zig`), computes vertex divergences, solves the Poisson equation, and shifts the minimum distance to `0`.
  - `deinit()`

## Notes & Assumptions

- Uses `eigen.Scalar` (`f64`) internally for numerical stability of the sparse linear solves.
- Assumes triangular faces for the Heat Method.
- Temporary attributes use `__incoming_dart` and `__heat_method_*` prefixes; code notes a TODO to add intrinsic triangulation support to `HeatMethodContext`.
