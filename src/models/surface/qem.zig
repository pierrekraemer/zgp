const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const mat = @import("../../geometry/mat.zig");
const Mat4f = mat.Mat4f;
const Mat4d = mat.Mat4d;

const zeigen = @import("zeigen");
const geometry_utils = @import("../../geometry/utils.zig");

/// Compute and return the QEM of the given vertex.
/// The QEM of a vertex is defined as the sum of the outer products of the planes of its incident faces.
/// The plane of a face is defined by its normal n and a point p on the face as the 4D vector (n, -p.n).
/// Face normals are assumed to be normalized.
/// A regularization term is added to ensure QEM is well-conditioned by adding a small contribution of the vertices tangent basis planes.
/// SGP2025: Controlling Quadric Error Simplification with Line Quadrics
/// https://www.dgp.toronto.edu/~hsuehtil/pdf/lineQuadric.pdf
pub fn vertexQEM(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
) Mat4f {
    assert(vertex.cellType() == .vertex);
    var vq = mat.zero4;
    const p = vertex_position.value(vertex);
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (!sm.isBoundaryDart(d)) {
            const face: SurfaceMesh.Cell = .{ .face = d };
            const n = face_normal.value(face);
            const plane: Vec4f = .{ n[0], n[1], n[2], -vec.dot3f(p, n) };
            const fq = mat.mulScalar4f(
                mat.outerProduct4f(plane, plane),
                face_area.value(face) / 3.0, // TODO: should divide by sm.codegree(face) to avoid triangular hypothesis
            );
            vq = mat.add4f(vq, fq);
        }
    }
    const epsilon = 1e-4;
    const tb = vertex_tangent_basis.value(vertex);
    const plane_tb1 = Vec4f{ tb[0][0], tb[0][1], tb[0][2], -vec.dot3f(p, tb[0]) };
    const plane_tb2 = Vec4f{ tb[1][0], tb[1][1], tb[1][2], -vec.dot3f(p, tb[1]) };
    const reg = mat.mulScalar4f(
        mat.add4f(
            mat.outerProduct4f(plane_tb1, plane_tb1),
            mat.outerProduct4f(plane_tb2, plane_tb2),
        ),
        epsilon * vertex_area.value(vertex),
    );
    vq = mat.add4f(vq, reg);
    return vq;
}

/// Compute the QEMs of all vertices of the given SurfaceMesh
/// and store them in the given vertex_qem data.
/// Face contributions to vertices quadrics is executed here in a face-centric manner for better performance.
pub fn computeVertexQEMs(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    vertex_qem: SurfaceMesh.CellData(.vertex, Mat4f),
) !void {
    vertex_qem.data.fill(mat.zero4f);
    var face_it = try SurfaceMesh.CellIterator(.face).init(sm);
    defer face_it.deinit();
    while (face_it.next()) |face| {
        const n = face_normal.value(face);
        const p = vertex_position.value(.{ .vertex = face.dart() });
        const plane: Vec4f = .{ n[0], n[1], n[2], -vec.dot3f(p, n) };
        const fq = mat.mulScalar4f(
            mat.outerProduct4f(plane, plane),
            face_area.value(face) / 3.0, // TODO: should divide by sm.codegree(face) to avoid triangular hypothesis
        );
        var dart_it = sm.cellDartIterator(face);
        while (dart_it.next()) |d| {
            const v: SurfaceMesh.Cell = .{ .vertex = d };
            vertex_qem.valuePtr(v).* = mat.add4f(
                vertex_qem.value(v),
                fq,
            );
        }
    }
    const epsilon = 1e-4;
    var vertex_it = try SurfaceMesh.CellIterator(.vertex).init(sm);
    defer vertex_it.deinit();
    while (vertex_it.next()) |vertex| {
        const p = vertex_position.value(vertex);
        const tb = vertex_tangent_basis.value(vertex);
        const plane_tb1 = Vec4f{ tb[0][0], tb[0][1], tb[0][2], -vec.dot3f(p, tb[0]) };
        const plane_tb2 = Vec4f{ tb[1][0], tb[1][1], tb[1][2], -vec.dot3f(p, tb[1]) };
        const reg = mat.mulScalar4f(
            mat.add4f(
                mat.outerProduct4f(plane_tb1, plane_tb1),
                mat.outerProduct4f(plane_tb2, plane_tb2),
            ),
            epsilon * vertex_area.value(vertex),
        );
        vertex_qem.valuePtr(vertex).* = mat.add4f(
            vertex_qem.value(vertex),
            reg,
        );
    }
}

pub fn optimalPoint(q: Mat4f) ?Vec3f {
    // warning: Eigen (via zeigen) uses double precision
    var m = mat.fromMat4f(q);
    m[0][3] = 0.0;
    m[1][3] = 0.0;
    m[2][3] = 0.0;
    m[3][3] = 1.0;
    var inv: Mat4d = undefined;
    const invertible = zeigen.computeInverseWithCheck(&m, &inv);
    return if (invertible) .{ @floatCast(inv[3][0]), @floatCast(inv[3][1]), @floatCast(inv[3][2]) } else null;
}
