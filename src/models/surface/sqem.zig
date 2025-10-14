const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const mat = @import("../../geometry/mat.zig");
const Mat4f = mat.Mat4f;
const Mat4d = mat.Mat4d;
const sqem = @import("../../geometry/sqem.zig");
const SQEM = sqem.SQEM;

const eigen = @import("../../geometry/eigen.zig");
const geometry_utils = @import("../../geometry/utils.zig");

/// Compute and return the SQEM of the given vertex.
pub fn vertexSQEM(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
) SQEM {
    assert(vertex.cellType() == .vertex);
    var vsq = sqem.zero;
    const p = vertex_position.value(vertex);
    const p4 = Vec4f{ p[0], p[1], p[2], 0.0 };
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (!sm.isBoundaryDart(d)) {
            const face: SurfaceMesh.Cell = .{ .face = d };
            const n = face_normal.value(face);
            const n4 = Vec4f{ n[0], n[1], n[2], 1.0 };
            const n4p4 = vec.dot4f(n4, p4);
            var fsq: SQEM = .{
                .A = mat.mulScalar4f(mat.outerProduct4f(n4, n4), 2.0),
                .b = vec.mulScalar4f(n4, n4p4),
                .c = n4p4 * n4p4,
            };
            fsq.mulScalar(face_area.value(face) / 3.0); // TODO: should divide by sm.codegree(face) to avoid triangular hypothesis
            vsq.add(&fsq);
        }
    }
    return vsq;
}

/// Compute the SQEMs of all vertices of the given SurfaceMesh
/// and store them in the given vertex_sqem data.
/// Face contributions to vertices SQEM are computed here in a face-centric manner for better performance.
pub fn computeVertexSQEMs(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    vertex_sqem: SurfaceMesh.CellData(.vertex, SQEM),
) !void {
    vertex_sqem.data.fill(sqem.zero);
    var face_it = try SurfaceMesh.CellIterator(.face).init(sm);
    defer face_it.deinit();
    while (face_it.next()) |face| {
        const n = face_normal.value(face);
        const n4 = Vec4f{ n[0], n[1], n[2], 1.0 };
        const p = vertex_position.value(.{ .vertex = face.dart() });
        const p4 = Vec4f{ p[0], p[1], p[2], 0.0 };
        const n4p4 = vec.dot4f(n4, p4);
        var fsq: SQEM = .{
            .A = mat.mulScalar4f(mat.outerProduct4f(n4, n4), 2.0),
            .b = vec.mulScalar4f(n4, n4p4),
            .c = n4p4 * n4p4,
        };
        fsq.mulScalar(face_area.value(face) / 3.0); // TODO: should divide by sm.codegree(face) to avoid triangular hypothesis
        var dart_it = sm.cellDartIterator(face);
        while (dart_it.next()) |d| {
            const v: SurfaceMesh.Cell = .{ .vertex = d };
            vertex_sqem.valuePtr(v).*.add(&fsq);
        }
    }
}
