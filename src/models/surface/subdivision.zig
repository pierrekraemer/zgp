const std = @import("std");
const assert = std.debug.assert;

const zgp = @import("../../main.zig");

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

pub fn cutAllEdges(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
) !void {
    var marker = try SurfaceMesh.CellMarker(.edge).init(sm);
    defer marker.deinit();
    var edge_it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer edge_it.deinit();
    while (edge_it.next()) |edge| {
        if (!marker.value(edge)) {
            const new_pos = vec.mulScalar3(
                vec.add3(
                    vertex_position.value(.{ .vertex = edge.dart() }),
                    vertex_position.value(.{ .vertex = sm.phi1(edge.dart()) }),
                ),
                0.5,
            );
            const v = try sm.cutEdge(edge);
            vertex_position.valuePtr(v).* = new_pos;
            marker.valuePtr(edge).* = true;
            marker.valuePtr(.{ .edge = sm.phi1(edge.dart()) }).* = true;
        }
    }
}
