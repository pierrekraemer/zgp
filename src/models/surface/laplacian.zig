const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

/// Compute and return the cotan weight of the given halfedge.
pub fn halfedgeCotanWeight(
    sm: *const SurfaceMesh,
    halfedge: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
) f32 {
    assert(halfedge.cellType() == .halfedge);

    if (sm.isBoundaryDart(halfedge.dart())) {
        return 0.0;
    }

    const d = halfedge.dart();
    const d1 = sm.phi1(d);
    const d_1 = sm.phi_1(d);
    const p1 = vertex_position.value(.{ .vertex = d });
    const p2 = vertex_position.value(.{ .vertex = d1 });
    const p3 = vertex_position.value(.{ .vertex = d_1 });
    const vecR = vec.sub3(p1, p3);
    const vecL = vec.sub3(p2, p3);
    return 0.5 * (vec.dot3(vecR, vecL) / vec.norm3(vec.cross3(vecR, vecL)));
}

/// Compute the cotan weights of all halfedges of the given SurfaceMesh
/// and store them in the given halfedge_cotan_weight data.
pub fn computeHalfedgeCotanWeights(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.halfedge).init(sm);
    defer it.deinit();
    while (it.next()) |halfedge| {
        halfedge_cotan_weight.valuePtr(halfedge).* = halfedgeCotanWeight(
            sm,
            halfedge,
            vertex_position,
        );
    }
}

/// Compute and return the cotan weight of the given edge.
pub fn edgeCotanWeight(
    sm: *const SurfaceMesh,
    edge: SurfaceMesh.Cell,
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
) f32 {
    assert(edge.cellType() == .edge);

    var w: f32 = 0.0;
    const d = edge.dart();
    if (!sm.isBoundaryDart(d)) {
        w += halfedge_cotan_weight.value(.{ .halfedge = d });
    }
    const dd = sm.phi2(d);
    if (!sm.isBoundaryDart(dd)) {
        w += halfedge_cotan_weight.value(.{ .halfedge = dd });
    }
    return w;
}
