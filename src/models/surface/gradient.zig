const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;

/// Compute the gradient of a scalar field defined on the vertices of the given face.
/// The gradient is returned as a vector in the plane of the face,
/// pointing in the direction of maximum increase of the scalar field,
/// and with a magnitude equal to the rate of increase per unit length.
/// The face is assumed to be triangular.
pub fn vertexScalarFieldFaceGradient(
    sm: *const SurfaceMesh,
    face: SurfaceMesh.Face,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    face_area: SurfaceMesh.FaceData(f32),
    face_normal: SurfaceMesh.FaceData(Vec3f),
    comptime S: type,
    vertex_scalar_field: SurfaceMesh.VertexData(S),
) vec.Vec(3, S) {
    const V = vec.Vec(3, S);
    var g = vec.zero(V);
    var dart_it = sm.faceDartIterator(sm.dart(face));
    while (dart_it.next()) |d| {
        const v0 = vertex_position.value(sm.vertex(sm.phi1(d)));
        const v1 = vertex_position.value(sm.vertex(sm.phi_1(d)));
        const e = vec.sub(v1, v0);
        const ortho = vec.cross(face_normal.value(face), e);
        g = vec.add(
            g,
            vec.mulScalar(
                vec.cast(S, ortho),
                @floatCast(vertex_scalar_field.value(sm.vertex(d))),
            ),
        );
    }
    g = vec.divScalar(g, @floatCast(face_area.value(face)));
    return g;
}

/// Compute the gradient of a scalar field defined on the vertices of the given SurfaceMesh,
/// and store them in the given face_gradient data.
/// The faces of the SurfaceMesh are assumed to be triangular.
pub fn computeVertexScalarFieldFaceGradients(
    io: std.Io,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    face_area: SurfaceMesh.FaceData(f32),
    face_normal: SurfaceMesh.FaceData(Vec3f),
    comptime S: type,
    vertex_scalar_field: SurfaceMesh.VertexData(S),
    face_gradient: *SurfaceMesh.FaceData(vec.Vec(3, S)),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        vertex_position: SurfaceMesh.VertexData(Vec3f),
        face_area: SurfaceMesh.FaceData(f32),
        face_normal: SurfaceMesh.FaceData(Vec3f),
        vertex_scalar_field: SurfaceMesh.VertexData(S),
        face_gradient: *SurfaceMesh.FaceData(vec.Vec(3, S)),

        pub fn run(t: *const @This(), face: SurfaceMesh.Face) void {
            t.face_gradient.valuePtr(face).* = vertexScalarFieldFaceGradient(
                t.surface_mesh,
                face,
                t.vertex_position,
                t.face_area,
                t.face_normal,
                S,
                t.vertex_scalar_field,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelFaceTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .vertex_position = vertex_position,
        .vertex_scalar_field = vertex_scalar_field,
        .face_area = face_area,
        .face_normal = face_normal,
        .face_gradient = face_gradient,
    });
}

/// Compute the divergence of a vector field defined on the incident faces of the given vertex.
/// Incident faces are assumed to be triangular.
pub fn faceVectorFieldVertexDivergence(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Vertex,
    halfedge_cotan_weight: SurfaceMesh.HalfedgeData(f32),
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    comptime S: type,
    face_vector_field: SurfaceMesh.FaceData(vec.Vec(3, S)),
) S {
    var div: S = 0;
    var dart_it = sm.vertexDartIterator(sm.dart(vertex));
    while (dart_it.next()) |d| {
        if (sm.isBoundaryDart(d)) continue;
        const d1 = sm.phi1(d);
        const d_1 = sm.phi_1(d);
        const p1 = vertex_position.value(sm.vertex(d));
        const p2 = vertex_position.value(sm.vertex(d1));
        const p3 = vertex_position.value(sm.vertex(d_1));
        const X = face_vector_field.value(sm.face(d));
        div += halfedge_cotan_weight.data.value(d) * vec.dot(
            vec.cast(S, vec.sub(p2, p1)),
            X,
        );
        div += halfedge_cotan_weight.data.value(d_1) * vec.dot(
            vec.cast(S, vec.sub(p3, p1)),
            X,
        );
    }
    return div;
}

/// Compute the divergence of a vector field defined on the faces of the given SurfaceMesh,
/// and store them in the given vertex_divergence data.
/// The given vector field and its computed divergence are of type f64 for improved precision.
/// The faces of the SurfaceMesh are assumed to be triangular.
pub fn computeFaceVectorFieldVertexDivergences(
    io: std.Io,
    sm: *SurfaceMesh,
    halfedge_cotan_weight: SurfaceMesh.HalfedgeData(f32),
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    comptime S: type,
    face_vector_field: SurfaceMesh.FaceData(vec.Vec(3, S)),
    vertex_divergence: *SurfaceMesh.VertexData(S),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        halfedge_cotan_weight: SurfaceMesh.HalfedgeData(f32),
        vertex_position: SurfaceMesh.VertexData(Vec3f),
        face_vector_field: SurfaceMesh.FaceData(vec.Vec(3, S)),
        vertex_divergence: *SurfaceMesh.VertexData(S),

        pub fn run(t: *const @This(), vertex: SurfaceMesh.Vertex) void {
            t.vertex_divergence.valuePtr(vertex).* = faceVectorFieldVertexDivergence(
                t.surface_mesh,
                vertex,
                t.halfedge_cotan_weight,
                t.vertex_position,
                S,
                t.face_vector_field,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelVertexTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .halfedge_cotan_weight = halfedge_cotan_weight,
        .vertex_position = vertex_position,
        .face_vector_field = face_vector_field,
        .vertex_divergence = vertex_divergence,
    });
}
