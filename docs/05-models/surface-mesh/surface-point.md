# SurfacePoint

- **Source:** [`src/models/surface/SurfacePoint.zig`](../../../src/models/surface/SurfacePoint.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Used by:** [`geodesic.zig`](geodesic.md), [`intrinsic_triangulation.zig`](intrinsic-triangulation.md), [`sampling.zig`](sampling.md), [`bvh.zig`](../../../src/geometry/bvh.zig), [`SurfaceMeshSampling`](../../../src/modules/SurfaceMeshSampling.zig)

---

## Overview

Represents an arbitrary intrinsic location on a `SurfaceMesh` relative to a reference `Dart` — either at a vertex, along an edge, or inside a triangular face — and provides generic attribute interpolation (`readData`).

## Key Types & Entry Points

- `SurfacePointType` (tagged union):
  - `.vertex: SurfaceMesh.Vertex`
  - `.edge: struct { dart: SurfaceMesh.Dart, t: f32 }` ($t \in [0, 1]$ from `vertex(dart)` to `vertex(phi1(dart))`)
  - `.face: struct { dart: SurfaceMesh.Dart, bcoords: Vec3f }` (barycentric coordinates for `{dart, phi1(dart), phi_1(dart)}`)
- `SurfacePoint.readData(sm, cell_data)` — Reads or linearly/barycentrically interpolates any vertex, edge, or face `CellData` (scalar or 1D–4D float arrays) at the surface point.

## Notes & Assumptions

- Assumes triangular faces for `.face` interpolation.
- Reading face data from a `.vertex` or `.edge` point selects an incident interior face via `orbitNonBoundaryDart`.
