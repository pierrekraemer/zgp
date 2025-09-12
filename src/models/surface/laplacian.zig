const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

/// Compute and return the cotan weight of the given edge.
pub fn edgeCotanWeight(
    sm: *const SurfaceMesh,
    edge: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
) f32 {
    assert(edge.cellType() == .edge);

    const w = 0.0;

    const d = edge.dart();
    const dd = sm.phi2(d);
    const p1 = vertex_position.value(.{ .vertex = d });
    const p2 = vertex_position.value(.{ .vertex = dd });

    if (!sm.isBoundaryDart(d)) {
        const d11 = sm.phi1(sm.phi1(d));
        const p3 = vertex_position.value(.{ .vertex = d11 });
        const vecR = vec.sub3(p1, p3);
        const vecL = vec.sub3(p2, p3);
        w += 0.5 * vec.dot3(vecR, vecL) / vec.norm3(vec.cross3(vecR, vecL));
    }
    if (!sm.isBoundaryDart(dd)) {
        const dd11 = sm.phi1(sm.phi1(dd));
        const p3 = vertex_position.value(.{ .vertex = dd11 });
        const vecR = vec.sub3(p2, p3);
        const vecL = vec.sub3(p1, p3);
        w += 0.5 * vec.dot3(vecR, vecL) / vec.norm3(vec.cross3(vecR, vecL));
    }

    return w;
}

/// Compute the cotan weights of all edges of the given SurfaceMesh
/// and store them in the given edge_cotan_weight data.
pub fn computeEdgeCotanWeights(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    edge_cotan_weight: SurfaceMesh.CellData(.edge, f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer it.deinit();
    while (it.next()) |edge| {
        edge_cotan_weight.valuePtr(edge).* = edgeCotanWeight(
            sm,
            edge,
            vertex_position,
        );
    }
}
