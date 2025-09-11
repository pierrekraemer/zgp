const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

const geometry_utils = @import("../../geometry/utils.zig");

/// Compute and return the area of the given face.
/// TODO: should perform ear-triangulation on polygonal faces instead of just a triangle fan.
pub fn faceArea(
    sm: *const SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face: SurfaceMesh.Cell,
) f32 {
    assert(face.cellType() == .face);
    var area: f32 = 0.0;
    const d_start = face.dart();
    const p1 = vertex_position.value(.{ .vertex = d_start });
    var d_next = sm.phi1(d_start);
    if (d_next == d_start) return 0.0; // 1-sided face
    var d_prev = d_next;
    d_next = sm.phi1(d_next);
    if (d_next == d_start) return 0.0; // 2-sided face
    var p2 = vertex_position.value(.{ .vertex = d_prev });
    while (d_next != d_start) : (d_next = sm.phi1(d_next)) {
        const p3 = vertex_position.value(.{ .vertex = d_next });
        area += geometry_utils.triangleArea(p1, p2, p3);
        d_prev = d_next;
        p2 = p3;
    }
    return area;
}

/// Compute and return the area of the given vertex.
/// The area of a vertex is defined as the sum of 1/3 of the areas of its incident faces.
pub fn vertexArea(
    sm: *const SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    vertex: SurfaceMesh.Cell,
) f32 {
    assert(vertex.cellType() == .vertex);
    var area: f32 = 0.0;
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (sm.isBoundaryDart(d)) continue; // skip boundary faces
        area += faceArea(sm, vertex_position, .{ .face = d }) / 3.0;
    }
    return area;
}

/// Compute the areas of all vertices of the given SurfaceMesh
/// and store them in the given vertex_area data.
pub fn computeVerticesArea(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.vertex).init(sm);
    defer it.deinit();
    while (it.next()) |vertex| {
        vertex_area.valuePtr(vertex).* = vertexArea(sm, vertex_position, vertex);
    }
}
