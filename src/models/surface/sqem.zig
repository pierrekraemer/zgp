const std = @import("std");
const assert = std.debug.assert;

const AppContext = @import("../../main.zig").AppContext;
const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const mat = @import("../../geometry/mat.zig");
const Mat4f = mat.Mat4f;
const Mat4d = mat.Mat4d;

const eigen = @import("../../geometry/eigen.zig");
const geometry_utils = @import("../../geometry/utils.zig");

pub const SQEM = struct {
    A: Mat4f,
    b: Vec4f,
    c: f32,

    pub const zero: SQEM = .{
        .A = mat.zero4f,
        .b = vec.zero4f,
        .c = 0.0,
    };

    pub fn init(p: Vec4f, n: Vec4f) SQEM {
        const np = vec.dot4f(n, p);
        return .{
            .A = mat.mulScalar4f(mat.outerProduct4f(n, n), 2.0),
            .b = vec.mulScalar4f(n, 2.0 * np),
            .c = np * np,
        };
    }

    pub fn add(a: *SQEM, b: *const SQEM) void {
        a.A = mat.add4f(a.A, b.A);
        a.b = vec.add4f(a.b, b.b);
        a.c += b.c;
    }

    pub fn mulScalar(sq: *SQEM, s: f32) void {
        sq.A = mat.mulScalar4f(sq.A, s);
        sq.b = vec.mulScalar4f(sq.b, s);
        sq.c *= s;
    }

    pub fn gradient(sq: *const SQEM, s: Vec4f) Vec4f {
        return vec.sub4f(mat.mulVec4f(sq.A, s), sq.b);
    }

    pub fn eval(sq: *const SQEM, s: Vec4f) f32 {
        return 0.5 * vec.dot4f(s, mat.mulVec4f(sq.A, s)) - vec.dot4f(sq.b, s) + sq.c;
    }
};

/// Compute and return the SQEM of the given vertex.
pub fn vertexSQEM(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
) SQEM {
    assert(vertex.cellType() == .vertex);
    var vsq = SQEM.zero;
    const p = vertex_position.value(vertex);
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (!sm.isBoundaryDart(d)) {
            const face: SurfaceMesh.Cell = .{ .face = d };
            const n = face_normal.value(face);
            var fsq: SQEM = .init(
                Vec4f{ p[0], p[1], p[2], 0.0 },
                Vec4f{ n[0], n[1], n[2], 1.0 },
            );
            fsq.mulScalar(face_area.value(face) / 3.0); // TODO: should divide by sm.codegree(face) to avoid triangular hypothesis
            vsq.add(&fsq);
        }
    }
    return vsq;
}

/// Compute the SQEMs of all vertices of the given SurfaceMesh
/// and store them in the given vertex_sqem data.
/// Face contributions to vertices SQEM are computed here in a face-centric manner => nice but do not allow for parallelization (TODO: measure performance) pub fn computeVertexSQEMs( sm: *SurfaceMesh, vertex_position: SurfaceMesh.CellData(.vertex, Vec3f), face_area: SurfaceMesh.CellData(.face, f32), face_normal: SurfaceMesh.CellData(.face, Vec3f), vertex_sqem: SurfaceMesh.CellData(.vertex, SQEM), ) !void { vertex_sqem.data.fill(SQEM.zero); var face_it = try SurfaceMesh.CellIterator(.face).init(sm); defer face_it.deinit(); while (face_it.next()) |face| { const n = face_normal.value(face); const p = vertex_position.value(.{ .vertex = face.dart() }); var fsq: SQEM = .init( Vec4f{ p[0], p[1], p[2], 0.0 }, Vec4f{ n[0], n[1], n[2], 1.0 }, ); fsq.mulScalar(face_area.value(face) / 3.0); // TODO: should divide by sm.codegree(face) to avoid triangular hypothesis var dart_it = sm.cellDartIterator(face); while (dart_it.next()) |d| { vertex_sqem.valuePtr(.{ .vertex = d }).*.add(&fsq); } } } /// Compute the QEMs of all vertices of the given SurfaceMesh /// and store them in the given vertex_qem data. /// The QEM of a vertex is defined as the sum of the outer products of the planes of its incident faces. /// The plane of a face is defined by its normal n and a point p on the face as the 4D vector (n, -p.n). /// Face normals are assumed to be normalized. /// A regularization term is added to ensure QEM is well-conditioned by adding a small contribution of the vertices tangent basis planes. /// SGP2025: Controlling Quadric Error Simplification with Line Quadrics /// https://www.dgp.toronto.edu/~hsuehtil/pdf/lineQuadric.pdf /// Face contributions to vertices quadrics are computed here in a face-centric manner => nice but do not allow for parallelization (TODO: measure performance)
pub fn computeVertexSQEMs(
    _: *AppContext,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    vertex_sqem: SurfaceMesh.CellData(.vertex, SQEM),
) !void {
    vertex_sqem.data.fill(SQEM.zero);
    var face_it = try SurfaceMesh.CellIterator(.face).init(sm);
    defer face_it.deinit();
    while (face_it.next()) |face| {
        const n = face_normal.value(face);
        const p = vertex_position.value(.{ .vertex = face.dart() });
        var fsq: SQEM = .init(
            Vec4f{ p[0], p[1], p[2], 0.0 },
            Vec4f{ n[0], n[1], n[2], 1.0 },
        );
        fsq.mulScalar(face_area.value(face) / 3.0); // TODO: should divide by sm.codegree(face) to avoid triangular hypothesis
        var dart_it = sm.cellDartIterator(face);
        while (dart_it.next()) |d| {
            vertex_sqem.valuePtr(.{ .vertex = d }).*.add(&fsq);
        }
    }
}
