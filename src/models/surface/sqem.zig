const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const SQEM = @import("../../geometry/SQEM.zig");

/// Compute and return the SQEM of the given vertex.
pub fn vertexSQEM(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Vertex,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    vertex_area: SurfaceMesh.VertexData(f32),
    vertex_tangent_basis: SurfaceMesh.VertexData([2]Vec3f),
    face_area: SurfaceMesh.FaceData(f32),
    face_normal: SurfaceMesh.FaceData(Vec3f),
    line_quadric_epsilon: f32,
) SQEM {
    var vsq = SQEM.zero;
    const p = vertex_position.value(vertex);
    var dart_it = sm.orbitDartIterator(sm.dart(vertex), .vertex);
    while (dart_it.next()) |d| {
        if (!sm.isBoundaryDart(d)) {
            const face = sm.face(d);
            const n = face_normal.value(face);
            var fsq: SQEM = .initSpherePlaneDistance(p, n, face_area.value(face) / 3.0); // TODO: should divide by sm.codegree(face) to avoid triangular hypothesis
            vsq.add(&fsq);
        }
    }
    const tb = vertex_tangent_basis.value(vertex);
    const reg1: SQEM = .initCenterPlaneDistance(p, tb[0], line_quadric_epsilon * vertex_area.value(vertex));
    const reg2: SQEM = .initCenterPlaneDistance(p, tb[1], line_quadric_epsilon * vertex_area.value(vertex));
    vsq.add(&reg1);
    vsq.add(&reg2);
    return vsq;
}

/// Compute the SQEMs of all vertices of the given SurfaceMesh
/// and store them in the given vertex_sqem data.
pub fn computeVertexSQEMs(
    io: std.Io,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    vertex_area: SurfaceMesh.VertexData(f32),
    vertex_tangent_basis: SurfaceMesh.VertexData([2]Vec3f),
    face_area: SurfaceMesh.FaceData(f32),
    face_normal: SurfaceMesh.FaceData(Vec3f),
    line_quadric_epsilon: f32,
    vertex_sqem: *SurfaceMesh.VertexData(SQEM),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        vertex_position: SurfaceMesh.VertexData(Vec3f),
        vertex_area: SurfaceMesh.VertexData(f32),
        vertex_tangent_basis: SurfaceMesh.VertexData([2]Vec3f),
        face_area: SurfaceMesh.FaceData(f32),
        face_normal: SurfaceMesh.FaceData(Vec3f),
        line_quadric_epsilon: f32,
        vertex_sqem: *SurfaceMesh.VertexData(SQEM),

        pub fn run(t: *const @This(), vertex: SurfaceMesh.Vertex) void {
            t.vertex_sqem.valuePtr(vertex).* = vertexSQEM(
                t.surface_mesh,
                vertex,
                t.vertex_position,
                t.vertex_area,
                t.vertex_tangent_basis,
                t.face_area,
                t.face_normal,
                t.line_quadric_epsilon,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelVertexTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .vertex_position = vertex_position,
        .vertex_area = vertex_area,
        .vertex_tangent_basis = vertex_tangent_basis,
        .face_area = face_area,
        .face_normal = face_normal,
        .line_quadric_epsilon = line_quadric_epsilon,
        .vertex_sqem = vertex_sqem,
    });
}
