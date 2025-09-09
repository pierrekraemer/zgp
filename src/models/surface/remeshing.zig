const std = @import("std");
const assert = std.debug.assert;

const zgp = @import("../../main.zig");

const SurfaceMesh = @import("SurfaceMesh.zig");
const length = @import("length.zig");
const subdivision = @import("subdivision.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

pub fn pliantRemeshing(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
) !void {
    try subdivision.triangulateFaces(sm);
    const mean_edge_length = try length.meanEdgeLength(sm, vertex_position);
    const threshold_squared = mean_edge_length * mean_edge_length * 1.5625;
    for (0..5) |_| {
        // cut long edges
        var marker = try SurfaceMesh.CellMarker(.edge).init(sm);
        defer marker.deinit();
        var edge_it = try SurfaceMesh.CellIterator(.edge).init(sm);
        defer edge_it.deinit();
        while (edge_it.next()) |edge| {
            if (!marker.value(edge)) {
                const d = edge.dart();
                const v1: SurfaceMesh.Cell = .{ .vertex = d };
                const v2: SurfaceMesh.Cell = .{ .vertex = sm.phi1(d) };
                const length_squared = vec.squaredNorm3(vec.sub3(vertex_position.value(v2), vertex_position.value(v1)));
                if (length_squared > threshold_squared) {
                    const new_pos = vec.mulScalar3(
                        vec.add3(vertex_position.value(v1), vertex_position.value(v2)),
                        0.5,
                    );
                    const v = try sm.cutEdge(edge);
                    vertex_position.valuePtr(v).* = new_pos;
                    const d1 = v.dart();
                    const dd1 = sm.phi1(sm.phi2(d1));
                    if (!sm.isBoundaryDart(d1)) {
                        _ = try sm.cutFace(d1, sm.phi1(sm.phi1(d1)));
                    }
                    if (!sm.isBoundaryDart(dd1)) {
                        _ = try sm.cutFace(dd1, sm.phi1(sm.phi1(dd1)));
                    }
                }
                marker.valuePtr(edge).* = true;
                marker.valuePtr(.{ .edge = sm.phi1(edge.dart()) }).* = true;
            }
        }
    }
}
