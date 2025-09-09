const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

pub fn edgeLength(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
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
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    edge_length: SurfaceMesh.CellData(.edge, f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer it.deinit();
    while (it.next()) |edge| {
        edge_length.valuePtr(edge).* = edgeLength(sm, vertex_position, edge);
    }
}

pub fn meanEdgeLength(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
) f32 {
    const nb_edges = sm.nbCells(.edge);
    if (nb_edges == 0) {
        return 0.0;
    }

    var total_length: f32 = 0.0;
    var it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer it.deinit();
    while (it.next()) |edge| {
        total_length += edgeLength(sm, vertex_position, edge);
    }
    return total_length / @as(f32, nb_edges);
}
