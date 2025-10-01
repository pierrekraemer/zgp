const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

/// Triangulate the polygonal faces of the given SurfaceMesh.
/// TODO: should perform ear-triangulation on polygonal faces instead of just a triangle fan.
pub fn triangulateFaces(sm: *SurfaceMesh) !void {
    var face_it = try SurfaceMesh.CellIterator(.face).init(sm);
    defer face_it.deinit();
    while (face_it.next()) |f| {
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
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
) !void {
    var marker = try SurfaceMesh.CellMarker(.edge).init(sm);
    defer marker.deinit();
    var edge_it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer edge_it.deinit();
    while (edge_it.next()) |e| {
        if (!marker.value(e)) {
            const new_pos = vec.mulScalar3f(
                vec.add3f(
                    vertex_position.value(.{ .vertex = e.dart() }),
                    vertex_position.value(.{ .vertex = sm.phi1(e.dart()) }),
                ),
                0.5,
            );
            const v = try sm.cutEdge(e);
            vertex_position.valuePtr(v).* = new_pos;
            // the two resulting edges are marked so that they are not cut again
            marker.valuePtr(e).* = true;
            marker.valuePtr(.{ .edge = sm.phi1(e.dart()) }).* = true;
        }
    }
}
