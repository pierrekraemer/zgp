const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const SurfaceMeshData = SurfaceMesh.SurfaceMeshData;
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

pub fn edgeLength(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMeshData(.vertex, Vec3),
    edge: SurfaceMesh.Cell,
) f32 {
    assert(edge.cellType() == .edge);
    const d = edge.dart();
    const v1: SurfaceMesh.Cell = .{ .vertex = d };
    const v2: SurfaceMesh.Cell = .{ .vertex = sm.phi1(d) };
    return vec.norm3(vec.sub3(vertex_position.value(v2), vertex_position.value(v1)));
}

pub fn computeEdgeLengths(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMeshData(.vertex, Vec3),
    edge_length: SurfaceMeshData(.edge, f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer it.deinit();
    while (it.next()) |edge| {
        edge_length.valuePtr(edge).* = edgeLength(sm, vertex_position, edge);
    }
}
