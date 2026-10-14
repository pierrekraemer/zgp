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
    vertex: SurfaceMesh.Vertex,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    vertex_area: SurfaceMesh.VertexData(f32),
    vertex_tangent_basis: SurfaceMesh.VertexData([2]Vec3f),
    face_area: SurfaceMesh.FaceData(f32),
    face_normal: SurfaceMesh.FaceData(Vec3f),
) Mat4f {
    var vq = mat.zero4;
    const p = vertex_position.value(vertex);
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (!sm.isBoundaryDart(d)) {
            const face = sm.face(d);
            const n = face_normal.value(face);
            const plane: Vec4f = .{ n[0], n[1], n[2], -vec.dot(p, n) };
            const fq = mat.mulScalar4f(
                mat.outerProduct4f(plane, plane),
                face_area.value(face) / 3.0, // TODO: should divide by sm.codegree(face) to avoid triangular hypothesis
            );
            vq = mat.add4f(vq, fq);
        }
    }
    const tb = vertex_tangent_basis.value(vertex);
    const plane_tb1 = Vec4f{ tb[0][0], tb[0][1], tb[0][2], -vec.dot(p, tb[0]) };
    const plane_tb2 = Vec4f{ tb[1][0], tb[1][1], tb[1][2], -vec.dot(p, tb[1]) };
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
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    vertex_area: SurfaceMesh.VertexData(f32),
    vertex_tangent_basis: SurfaceMesh.VertexData([2]Vec3f),
    face_area: SurfaceMesh.FaceData(f32),
    face_normal: SurfaceMesh.FaceData(Vec3f),
    vertex_qem: *SurfaceMesh.VertexData(Mat4f),
) !void {
    vertex_qem.data.fill(mat.zero(Mat4f));
    var face_it = sm.faceIterator();
    while (face_it.next()) |face| {
        const fd = sm.dart(face);
        const n = face_normal.value(face);
        const p = vertex_position.value(sm.vertex(fd));
        const plane: Vec4f = .{ n[0], n[1], n[2], -vec.dot(p, n) };
        const fq = mat.mulScalar(
            mat.outerProduct(plane, plane),
            face_area.value(face) / 3.0, // TODO: should divide by sm.codegree(face) to avoid triangular hypothesis
        );
        var dart_it = sm.faceDartIterator(sm.dart(face));
        while (dart_it.next()) |d| {
            const v = sm.vertex(d);
            vertex_qem.valuePtr(v).* = mat.add(
                vertex_qem.value(v),
                fq,
            );
        }
    }
    var vertex_it = sm.vertexIterator();
    while (vertex_it.next()) |vertex| {
        const p = vertex_position.value(vertex);
        const tb = vertex_tangent_basis.value(vertex);
        const plane_tb1: Vec4f = .{ tb[0][0], tb[0][1], tb[0][2], -vec.dot(p, tb[0]) };
        const plane_tb2: Vec4f = .{ tb[1][0], tb[1][1], tb[1][2], -vec.dot(p, tb[1]) };
        const reg = mat.mulScalar(
            mat.add(
                mat.outerProduct(plane_tb1, plane_tb1),
                mat.outerProduct(plane_tb2, plane_tb2),
            ),
            line_quadric_epsilon * vertex_area.value(vertex),
        );
        vertex_qem.valuePtr(vertex).* = mat.add(
            vertex_qem.value(vertex),
            reg,
        );
    }
}

/// Given a QEM matrix, compute the optimal point minimizing the quadric error.
/// Return null if the QEM is not invertible.
pub fn optimalPoint(q: Mat4f) ?Vec3f {
    // The QEM matrix is symmetric. We want to find the point p = [x, y, z]
    // that minimizes the error. This is equivalent to solving the linear system:
    // A * p = -b, where A is the top-left 3x3 block and b is the top-right 3x1 block.
    // Instead of computing scalars, we can compute Cramer's rule using pure SIMD vector cross products.
    // Let C0, C1, C2 be the columns of A.
    // The rows of adj(A) are exactly (C1 x C2), (C2 x C0), and (C0 x C1).
    // The determinant is dot(C0, C1 x C2).

    // Compute the adjugate matrix rows
    const r0 = vec.cross(vec.truncate(3, q[1]), vec.truncate(3, q[2]));
    const r1 = vec.cross(vec.truncate(3, q[2]), vec.truncate(3, q[0]));
    const r2 = vec.cross(vec.truncate(3, q[0]), vec.truncate(3, q[1]));
    // Compute determinant
    const det = vec.dot(vec.truncate(3, q[0]), r0);
    if (@abs(det) < 1e-6) {
        return null; // matrix is singular or poorly conditioned
    }
    const b = vec.truncate(3, q[3]); // translation column
    // p = -(adj(A) * b) / det
    return vec.mulScalar(Vec3f{
        vec.dot(r0, b),
        vec.dot(r1, b),
        vec.dot(r2, b),
    }, -1.0 / det);
}
