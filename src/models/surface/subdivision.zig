const std = @import("std");
const assert = std.debug.assert;

const AppContext = @import("../../main.zig").AppContext;
const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

/// Triangulate the polygonal faces of the given SurfaceMesh.
/// TODO: should perform ear-triangulation on polygonal faces instead of just a triangle fan.
pub fn triangulateFaces(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
) !void {
    var face_buffer: std.ArrayList(SurfaceMesh.Cell) = try .initCapacity(app_ctx.allocator, 1024);
    defer face_buffer.deinit(app_ctx.allocator);
    var face_it = try SurfaceMesh.CellIterator(.face).init(sm);
    defer face_it.deinit();
    while (face_it.next()) |f| {
        if (sm.codegree(f) > 3) {
            try face_buffer.append(app_ctx.allocator, f);
        }
    }
    for (face_buffer.items) |f| {
        var d_start = f.dart();
        const d_end = sm.phi_1(d_start);
        var d_next = sm.phi1(d_start);
        if (d_next == d_start) continue; // 1-sided face
        d_next = sm.phi1(d_next);
        if (d_next == d_start) continue; // 2-sided face
        while (d_next != d_end) : (d_next = sm.phi1(d_next)) {
            _ = try sm.cutFace(d_start, d_next);
            d_start = sm.phi_1(d_next);
        }
    }
}

/// Cut all edges of the given SurfaceMesh.
/// The positions of the new vertices is the edge midpoints.
pub fn cutAllEdges(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
) !void {
    var edge_buffer: std.ArrayList(SurfaceMesh.Cell) = try .initCapacity(app_ctx.allocator, 1024);
    defer edge_buffer.deinit(app_ctx.allocator);
    var edge_it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer edge_it.deinit();
    while (edge_it.next()) |e| {
        try edge_buffer.append(app_ctx.allocator, e);
    }
    for (edge_buffer.items) |e| {
        const new_pos = vec.mulScalar3f(
            vec.add3f(
                vertex_position.value(.{ .vertex = e.dart() }),
                vertex_position.value(.{ .vertex = sm.phi1(e.dart()) }),
            ),
            0.5,
        );
        const v = try sm.cutEdge(e);
        vertex_position.valuePtr(v).* = new_pos;
    }
}
