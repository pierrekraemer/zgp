const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const SimdVec4f = vec.SimdVec4f;

const mat = @import("../../geometry/mat.zig");
const Mat4f = mat.Mat4f;
const Mat4d = mat.Mat4d;
const SimdMat4f = mat.SimdMat4f;

const geometry_utils = @import("../../geometry/utils.zig");
const eigen = @import("../../geometry/eigen.zig");

const line_quadric_epsilon = 1e-4;

/// Compute and return the QEM of the given vertex.
/// The QEM of a vertex is defined as the weighted sum of the outer products of the planes of its incident faces.
/// The plane of a face is defined by its normal n and a point p on the face as the 4D vector (n, -p.n).
/// Face normals are assumed to be normalized.
/// A regularization term is added to ensure QEM is well-conditioned by adding a small contribution of the vertices normal line quadric.
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
    const tb = vertex_tangent_basis.value(vertex);
    const plane_tb1 = Vec4f{ tb[0][0], tb[0][1], tb[0][2], -vec.dot3f(p, tb[0]) };
    const plane_tb2 = Vec4f{ tb[1][0], tb[1][1], tb[1][2], -vec.dot3f(p, tb[1]) };
    const reg = mat.mulScalar4f(
        mat.add4f(
            mat.outerProduct4f(plane_tb1, plane_tb1),
            mat.outerProduct4f(plane_tb2, plane_tb2),
        ),
        line_quadric_epsilon * vertex_area.value(vertex),
    );

    vq = mat.add4f(vq, reg);
    return vq;
}

/// Compute the QEMs of all vertices of the given SurfaceMesh
/// and store them in the given vertex_qem data.
/// The QEM of a vertex is defined as the weighted sum of the outer products of the planes of its incident faces.
/// The plane of a face is defined by its normal n and a point p on the face as the 4D vector (n, -p.n).
/// Face normals are assumed to be normalized.
/// A regularization term is added to ensure QEM is well-conditioned by adding a small contribution of the vertices normal line quadrics.
/// SGP2025: Controlling Quadric Error Simplification with Line Quadrics
/// https://www.dgp.toronto.edu/~hsuehtil/pdf/lineQuadric.pdf
/// Face contributions to vertices quadrics are computed here in a face-centric manner => nice but do not allow for parallelization (TODO: measure performance)
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
    var face_it: SurfaceMesh.CellIterator = try .init(sm, .face);
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
    var vertex_it: SurfaceMesh.CellIterator = try .init(sm, .vertex);
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
            line_quadric_epsilon * vertex_area.value(vertex),
        );
        vertex_qem.valuePtr(vertex).* = mat.add4f(
            vertex_qem.value(vertex),
            reg,
        );
    }
}

pub fn computeVertexQEMsSimd(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, SimdVec4f),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    vertex_qem: SurfaceMesh.CellData(.vertex, SimdMat4f),
) !void {
    vertex_qem.data.fill(@splat(vec.zero4f));

    var face_it: SurfaceMesh.CellIterator = try .init(sm, .face);
    defer face_it.deinit();
    while (face_it.next()) |face| {
        const n = vec.simdFromVec3f(face_normal.value(face));
        const p = vertex_position.value(.{ .vertex = face.dart() });
        const plane: SimdVec4f = .{ n[0], n[1], n[2], -vec.simdDot4f(p, n) };
        const fq = mat.simdMulScalar4f(
            mat.simdOuterProduct4f(plane, plane),
            face_area.value(face) / 3.0,
        );
        var dart_it = sm.cellDartIterator(face);
        while (dart_it.next()) |d| {
            const v: SurfaceMesh.Cell = .{ .vertex = d };
            vertex_qem.valuePtr(v).* = mat.simdAdd4f(vertex_qem.value(v), fq);
        }
    }
    var vertex_it: SurfaceMesh.CellIterator = try .init(sm, .vertex);
    defer vertex_it.deinit();
    while (vertex_it.next()) |vertex| {
        const p = vertex_position.value(vertex);
        const tb = vertex_tangent_basis.value(vertex);
        const tb1 = vec.simdFromVec3f(tb[0]);
        const tb2 = vec.simdFromVec3f(tb[1]);
        const plane_tb1: SimdVec4f = .{ tb1[0], tb1[1], tb1[2], -vec.simdDot4f(p, tb1) };
        const plane_tb2: SimdVec4f = .{ tb2[0], tb2[1], tb2[2], -vec.simdDot4f(p, tb2) };
        const reg = mat.simdMulScalar4f(
            mat.simdAdd4f(
                mat.simdOuterProduct4f(plane_tb1, plane_tb1),
                mat.simdOuterProduct4f(plane_tb2, plane_tb2),
            ),
            line_quadric_epsilon * vertex_area.value(vertex),
        );
        vertex_qem.valuePtr(vertex).* = mat.simdAdd4f(vertex_qem.value(vertex), reg);
    }
}

/// Given a QEM matrix, compute the optimal point minimizing the quadric error.
/// Return null if the QEM is not invertible.
pub fn optimalPoint(q: Mat4f) ?Vec3f {
    if (optimalPointSimd(mat.loadMat4f(q))) |p_simd| {
        return vec.storeVec3f(p_simd);
    }
    return null;
}

pub fn optimalPointSimd(q: mat.SimdMat4f) ?vec.SimdVec4f {
    // The QEM matrix is symmetric. We want to find the point p = [x, y, z]
    // that minimizes the error. This is equivalent to solving the linear system:
    // A * p = -b, where A is the top-left 3x3 block and b is the top-right 3x1 block.
    // Instead of computing scalars, we can compute Cramer's rule using pure SIMD vector cross products.
    // Let C0, C1, C2 be the columns of A.
    // The rows of adj(A) are exactly (C1 x C2), (C2 x C0), and (C0 x C1).
    // The determinant is dot(C0, C1 x C2).

    // Compute the adjugate matrix rows
    const r0 = vec.simdCross4f(q[1], q[2]);
    const r1 = vec.simdCross4f(q[2], q[0]);
    const r2 = vec.simdCross4f(q[0], q[1]);
    // Compute determinant
    const det = vec.simdDot4f(q[0], r0);
    if (@abs(det) < 1e-6) {
        return null; // Matrix is singular or poorly conditioned
    }
    const b = q[3]; // The translation column
    // p = -(adj(A) * b) / det
    const inv_det: SimdVec4f = @splat(-1.0 / det);
    return SimdVec4f{ vec.simdDot4f(r0, b), vec.simdDot4f(r1, b), vec.simdDot4f(r2, b), 0.0 } * inv_det;
}
