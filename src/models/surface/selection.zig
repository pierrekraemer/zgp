const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

fn includeVertex(
    sm: *const SurfaceMesh,
    dm: SurfaceMesh.DartMarker,
    v: SurfaceMesh.Cell,
    vertex_buffer: *std.ArrayList(SurfaceMesh.Cell),
    edge_buffer: *std.ArrayList(SurfaceMesh.Cell),
    face_buffer: *std.ArrayList(SurfaceMesh.Cell),
) !void {
    try vertex_buffer.append(sm.allocator, v);
    var dart_it = sm.cellDartIterator(v);
    while (dart_it.next()) |d| {
        dm.valuePtr(d).* = true;
        // if all darts of the edge are now marked, include edge in result
        if (dm.value(d) and dm.value(sm.phi2(d))) {
            try edge_buffer.append(sm.allocator, .{ .edge = d });
        }
        // if all darts of the face are now marked, include face in result
        var face_in = true;
        const face: SurfaceMesh.Cell = .{ .face = d };
        var face_dart_it = sm.cellDartIterator(face);
        while (face_dart_it.next()) |fd| {
            if (!dm.value(fd)) {
                face_in = false;
                break;
            }
        }
        if (face_in) {
            try face_buffer.append(sm.allocator, face);
        }
    }
}

/// Collect all cells within a sphere of given radius around the given vertex
/// and store them in the given buffers.
pub fn cellsWithinSphereAroundVertex(
    sm: *SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    radius: f32,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_buffer: *std.ArrayList(SurfaceMesh.Cell),
    edge_buffer: *std.ArrayList(SurfaceMesh.Cell),
    face_buffer: *std.ArrayList(SurfaceMesh.Cell),
) !void {
    assert(vertex.cellType() == .vertex);
    vertex_buffer.clearRetainingCapacity();
    edge_buffer.clearRetainingCapacity();
    face_buffer.clearRetainingCapacity();

    const vp = vertex_position.value(vertex);

    var dm = try SurfaceMesh.DartMarker.init(sm);
    defer dm.deinit();

    try includeVertex(sm, dm, vertex, vertex_buffer, edge_buffer, face_buffer);

    var i: u32 = 0;
    while (i < vertex_buffer.items.len) : (i += 1) {
        const v = vertex_buffer.items[i];
        var dart_it = sm.cellDartIterator(v);
        while (dart_it.next()) |d| {
            const d2 = sm.phi2(d);
            if (dm.value(d2)) {
                continue;
            }
            const nv: SurfaceMesh.Cell = .{ .vertex = d2 };
            const nvp = vertex_position.value(nv);
            if (vec.squaredNorm3f(vec.sub3f(nvp, vp)) < radius * radius) {
                try includeVertex(sm, dm, nv, vertex_buffer, edge_buffer, face_buffer);
            }
        }
    }
}
