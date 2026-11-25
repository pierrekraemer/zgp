# Discrete Geodesic Tracing

- **Source:** [`src/models/surface/geodesic.zig`](../../../src/models/surface/geodesic.zig)
- **Model:** [`SurfaceMesh`](../surface-mesh.md)
- **Used by:** [`intrinsic_triangulation.zig`](intrinsic-triangulation.md)

---

## Overview

Traces straight-line discrete geodesics across a triangulated `SurfaceMesh` from any [`SurfacePoint`](surface-point.md) given an initial tangent-space direction angle and target arc length.

## Key Entry Points

- `traceGeodesic(sm, edge_length, corner_angle, angle_sum, start_sp, angle, length, trace_points)` — Walks triangle-by-triangle, unfolding each triangle into 2D via `geometry/utils.zig` (`layoutTriangleVertex`), intersecting the ray with triangle edges, and crossing `phi2` until `remaining_length` reaches zero. Returns `.{ destination_sp, final_angle, remaining_length }`.

## Notes & Assumptions

- Assumes a triangulated mesh and operates purely intrinsically using `edge_length` (plus `corner_angle` and vertex `angle_sum` for angular conversions).
- Tangent angle convention: $[0, \text{angle\_sum})$ CCW from the vertex representative dart for `.vertex`, and $[0, 2\pi)$ for `.edge` and `.face`.
- Optionally appends intermediate `SurfacePoint`s to a caller-supplied list. Exits early with a warning on boundary hits or degenerate intersections.
