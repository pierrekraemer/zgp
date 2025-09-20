const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;
const Vec4 = vec.Vec4;
const mat = @import("../../geometry/mat.zig");
const Mat4 = mat.Mat4;

const zeigen = @import("zeigen");
const geometry_utils = @import("../../geometry/utils.zig");

/// Compute and return the QEM of the given vertex.
/// The QEM of a vertex is defined as the sum of the outer products of the planes of its incident faces.
/// The plane of a face is defined by its normal n and a point p on the face as the 4D vector (n, -p.n).
/// Face normals are assumed to be normalized.
pub fn vertexQEM(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
) Mat4 {
    assert(vertex.cellType() == .vertex);
    var vq = mat.zero4;
    const p = vertex_position.value(vertex);
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (!sm.isBoundaryDart(d)) {
            const face: SurfaceMesh.Cell = .{ .face = d };
            const n = face_normal.value(face);
            const plane: Vec4 = .{ n[0], n[1], n[2], -vec.dot3(p, n) };
            const fq = mat.mulScalar4(
                mat.outerProduct4(plane, plane),
                face_area.value(face),
            );
            vq = mat.add4(vq, fq);
        }
    }
    return vq;
}

/// Compute the QEMs of all vertices of the given SurfaceMesh
/// and store them in the given vertex_qem data.
/// Executed here in a face-centric manner for better performance.
pub fn computeVertexQEMs(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
    vertex_qem: SurfaceMesh.CellData(.vertex, Mat4),
) !void {
    vertex_qem.data.fill(mat.zero4);
    var face_it = try SurfaceMesh.CellIterator(.face).init(sm);
    defer face_it.deinit();
    while (face_it.next()) |face| {
        const n = face_normal.value(face);
        const p = vertex_position.value(.{ .vertex = face.dart() });
        const plane: Vec4 = .{ n[0], n[1], n[2], -vec.dot3(p, n) };
        const fq = mat.mulScalar4(
            mat.outerProduct4(plane, plane),
            face_area.value(face),
        );
        var dart_it = sm.cellDartIterator(face);
        while (dart_it.next()) |d| {
            const v: SurfaceMesh.Cell = .{ .vertex = d };
            vertex_qem.valuePtr(v).* = mat.add4(
                vertex_qem.value(v),
                fq,
            );
        }
    }
}

pub fn optimalPoint(q: Mat4) ?Vec3 {
    var m = q;
    m[0][3] = 0.0;
    m[1][3] = 0.0;
    m[2][3] = 0.0;
    m[3][3] = 1.0;
    var inv: Mat4 = undefined;
    const invertible = zeigen.computeInverseWithCheck(&m, &inv);
    return if (invertible) .{ inv[3][0], inv[3][1], inv[3][2] } else null;
}
