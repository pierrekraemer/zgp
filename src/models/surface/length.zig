const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

/// Compute and return the length of the given edge.
pub fn edgeLength(
    sm: *const SurfaceMesh,
    edge: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
) f32 {
    assert(edge.cellType() == .edge);
    const d = edge.dart();
    return vec.norm3(
        vec.sub3(
            vertex_position.value(.{ .vertex = sm.phi1(d) }),
            vertex_position.value(.{ .vertex = d }),
        ),
    );
}

/// Compute the lengths of all edges of the given SurfaceMesh
/// and store them in the given edge_length data.
pub fn computeEdgeLengths(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    edge_length: SurfaceMesh.CellData(.edge, f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer it.deinit();
    while (it.next()) |edge| {
        edge_length.valuePtr(edge).* = edgeLength(
            sm,
            edge,
            vertex_position,
        );
    }
}
