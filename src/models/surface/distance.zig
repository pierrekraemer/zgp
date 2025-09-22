const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const geometry_utils = @import("../../geometry/utils.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

pub fn computeGeodesicDistance(
    allocator: std.mem.Allocator,
    sm: *SurfaceMesh,
    source_vertex: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    vertex_areas: SurfaceMesh.CellData(.vertex, f32),
    edge_length: SurfaceMesh.CellData(.edge, f32),
    vertex_distance: SurfaceMesh.CellData(.vertex, f32),
) !void {
    var vertex_index = try sm.addData(.vertex, u32, "__vertex_index");
    defer sm.removeData(.vertex, vertex_index.gen());

    var vertex_it = try SurfaceMesh.CellIterator(.vertex).init(sm);
    defer vertex_it.deinit();

    var nb_vertices: u32 = 0;
    while (vertex_it.next()) |v| : (nb_vertices += 1) {
        vertex_index.valuePtr(v).* = nb_vertices;
    }

    var massMatrix: std.ArrayList(f32) = std.ArrayList(f32).initCapacity(allocator, nb_vertices);
    defer massMatrix.deinit();
    var heat0: std.ArrayList(f32) = std.ArrayList(f32).initCapacity(allocator, nb_vertices);
    defer heat0.deinit();

    vertex_it.reset();
    while (vertex_it.next()) |v| {
        // rely on the fact that vertex iterator visits vertices in the same order as before
        try massMatrix.appendAssumeCapacity(vertex_areas.value(v));
        try heat0.appendAssumeCapacity(if (v == source_vertex) 1.0 else 0.0);
    }

    const mean_edge_length = geometry_utils.meanValue(f32, edge_length.data);
    const t = mean_edge_length * mean_edge_length;

    _ = t;
    _ = vertex_position;

    // Initialize distances
    vertex_distance.valuePtr(source_vertex).* = 0;
}
