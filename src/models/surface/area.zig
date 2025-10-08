const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const geometry_utils = @import("../../geometry/utils.zig");

/// Compute and return the area of the given face.
/// TODO: should perform ear-triangulation on polygonal faces instead of just a triangle fan.
pub fn faceArea(
    sm: *const SurfaceMesh,
    face: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
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

/// Compute the areas of all faces of the given SurfaceMesh
/// and store them in the given face_area data.
pub fn computeFaceAreas(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.face).init(sm);
    defer it.deinit();
    while (it.next()) |face| {
        face_area.valuePtr(face).* = faceArea(
            sm,
            face,
            vertex_position,
        );
    }
}

/// Compute and return the area of the given vertex.
/// The area of a vertex is defined as a sum of contributions from its incident faces.
/// Each incident face f contributes 1/codegree(f) of its area to the area of the vertex.
pub fn vertexArea(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    face_area: SurfaceMesh.CellData(.face, f32),
) f32 {
    assert(vertex.cellType() == .vertex);
    var area: f32 = 0.0;
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (sm.isBoundaryDart(d)) continue; // skip boundary faces
        const f: SurfaceMesh.Cell = .{ .face = d };
        const cd: f32 = @floatFromInt(sm.codegree(f));
        area += face_area.value(f) / cd;
    }
    return area;
}

/// Compute the areas of all vertices of the given SurfaceMesh
/// and store them in the given vertex_area data.
/// The area of a vertex is defined as a sum of contributions from its incident faces.
/// Each face f contributes 1/codegree(f) of its area to the area of its incident vertices.
/// Executed here in a face-centric manner for better performance.
pub fn computeVertexAreas(
    sm: *SurfaceMesh,
    face_area: SurfaceMesh.CellData(.face, f32),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
) !void {
    vertex_area.data.fill(0.0);
    var it = try SurfaceMesh.CellIterator(.face).init(sm);
    defer it.deinit();
    while (it.next()) |face| {
        const cd: f32 = @floatFromInt(sm.codegree(face));
        const a = face_area.value(face) / cd;
        var dart_it = sm.cellDartIterator(face);
        while (dart_it.next()) |d| {
            vertex_area.valuePtr(.{ .vertex = d }).* += a;
        }
    }
}
