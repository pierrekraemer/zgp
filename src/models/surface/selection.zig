const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

fn includeVertex(
    sm: *const SurfaceMesh,
    dm: SurfaceMesh.DartMarker,
    v: SurfaceMesh.Cell,
    vertices: *std.ArrayList(SurfaceMesh.Cell),
    edges: *std.ArrayList(SurfaceMesh.Cell),
    faces: *std.ArrayList(SurfaceMesh.Cell),
) !void {
    try vertices.append(sm.allocator, v);
    var dart_it = sm.cellDartIterator(v);
    while (dart_it.next()) |d| {
        dm.valuePtr(d).* = true;
        // if all darts of the edge are now marked, include edge in result
        if (dm.value(d) and dm.value(sm.phi2(d))) {
            try edges.append(sm.allocator, .{ .edge = d });
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
            try faces.append(sm.allocator, face);
        }
    }
}

pub fn cellsWithinSphereAroundVertex(
    sm: *SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    radius: f32,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
) !struct {
    std.ArrayList(SurfaceMesh.Cell),
    std.ArrayList(SurfaceMesh.Cell),
    std.ArrayList(SurfaceMesh.Cell),
} {
    assert(vertex.cellType() == .vertex);
    const vp = vertex_position.value(vertex);

    var vertices = try std.ArrayList(SurfaceMesh.Cell).initCapacity(sm.allocator, 32);
    var edges = try std.ArrayList(SurfaceMesh.Cell).initCapacity(sm.allocator, 32);
    var faces = try std.ArrayList(SurfaceMesh.Cell).initCapacity(sm.allocator, 32);

    var dm = try SurfaceMesh.DartMarker.init(sm);
    defer dm.deinit();

    try includeVertex(sm, dm, vertex, &vertices, &edges, &faces);

    var i: u32 = 0;
    while (i < vertices.items.len) : (i += 1) {
        const v = vertices.items[i];
        var dart_it = sm.cellDartIterator(v);
        while (dart_it.next()) |d| {
            const d2 = sm.phi2(d);
            if (dm.value(d2)) {
                continue;
            }
            const nv: SurfaceMesh.Cell = .{ .vertex = d2 };
            const nvp = vertex_position.value(nv);
            if (vec.squaredNorm3f(vec.sub3f(nvp, vp)) < radius * radius) {
                try includeVertex(sm, dm, nv, &vertices, &edges, &faces);
            }
        }
    }

    return .{ vertices, edges, faces };
}
