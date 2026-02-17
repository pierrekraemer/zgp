const std = @import("std");
const assert = std.debug.assert;

const AppContext = @import("../../main.zig").AppContext;
const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;

/// Compute the gradient of a scalar field defined on the vertices of the given face.
/// The gradient is returned as a vector in the plane of the face,
/// pointing in the direction of maximum increase of the scalar field,
/// and with a magnitude equal to the rate of increase per unit length.
/// The given scalar field and its computed gradient are of type f64 for improved precision.
/// The face is assumed to be triangular.
pub fn scalarFieldFaceGradient(
    sm: *const SurfaceMesh,
    face: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_scalar_field: SurfaceMesh.CellData(.vertex, f64),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
) Vec3d {
    assert(face.cellType() == .face);
    var g = vec.zero3d;
    var dart_it = sm.cellDartIterator(face);
    while (dart_it.next()) |d| {
        const v0 = vertex_position.value(.{ .vertex = sm.phi1(d) });
        const v1 = vertex_position.value(.{ .vertex = sm.phi_1(d) });
        const e = vec.sub3f(v1, v0);
        const ortho = vec.cross3f(face_normal.value(face), e);
        g = vec.add3d(
            g,
            vec.mulScalar3d(
                vec.vec3dFromVec3f(ortho),
                vertex_scalar_field.value(.{ .vertex = d }),
            ),
        );
    }
    g = vec.divScalar3d(g, @floatCast(face_area.value(face)));
    return g;
}

/// Compute the gradient of a scalar field defined on the vertices of the given SurfaceMesh,
/// and store them in the given face_gradient data.
/// The given scalar field and its computed gradients are of type f64 for improved precision.
/// The faces of the SurfaceMesh are assumed to be triangular.
pub fn computeScalarFieldFaceGradients(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_scalar_field: SurfaceMesh.CellData(.vertex, f64),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    face_gradient: SurfaceMesh.CellData(.face, Vec3d),
) !void {
    const Task = struct {
        const Task = @This();

        surface_mesh: *const SurfaceMesh,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_scalar_field: SurfaceMesh.CellData(.vertex, f64),
        face_area: SurfaceMesh.CellData(.face, f32),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),
        face_gradient: SurfaceMesh.CellData(.face, Vec3d),

        pub inline fn run(t: *const Task, face: SurfaceMesh.Cell) void {
            t.face_gradient.valuePtr(face).* = scalarFieldFaceGradient(
                t.surface_mesh,
                face,
                t.vertex_position,
                t.vertex_scalar_field,
                t.face_area,
                t.face_normal,
            );
        }
    };

    var pctr = try SurfaceMesh.ParallelCellTaskRunner(.face).init(sm);
    defer pctr.deinit();
    try pctr.run(app_ctx, Task{
        .surface_mesh = sm,
        .vertex_position = vertex_position,
        .vertex_scalar_field = vertex_scalar_field,
        .face_area = face_area,
        .face_normal = face_normal,
        .face_gradient = face_gradient,
    });
}

/// Compute the divergence of a vector field defined on the incident faces of the given vertex.
/// The given vector field and its computed divergence are of type f64 for improved precision.
/// Incident faces are assumed to be triangular.
pub fn vectorFieldVertexDivergence(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_vector_field: SurfaceMesh.CellData(.face, Vec3d),
) f64 {
    assert(vertex.cellType() == .vertex);
    var div: f64 = 0.0;
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (sm.isBoundaryDart(d)) continue;
        const d1 = sm.phi1(d);
        const d_1 = sm.phi_1(d);
        const p1 = vertex_position.value(.{ .vertex = d });
        const p2 = vertex_position.value(.{ .vertex = d1 });
        const p3 = vertex_position.value(.{ .vertex = d_1 });
        const X = face_vector_field.value(.{ .face = d });
        div += halfedge_cotan_weight.value(.{ .halfedge = d }) * vec.dot3d(
            vec.vec3dFromVec3f(vec.sub3f(p2, p1)),
            X,
        );
        div += halfedge_cotan_weight.value(.{ .halfedge = d_1 }) * vec.dot3d(
            vec.vec3dFromVec3f(vec.sub3f(p3, p1)),
            X,
        );
    }
    return div;
}

/// Compute the divergence of a vector field defined on the faces of the given SurfaceMesh,
/// and store them in the given vertex_divergence data.
/// The given vector field and its computed divergence are of type f64 for improved precision.
/// The faces of the SurfaceMesh are assumed to be triangular.
pub fn computeVectorFieldVertexDivergences(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_vector_field: SurfaceMesh.CellData(.face, Vec3d),
    vertex_divergence: SurfaceMesh.CellData(.vertex, f64),
) !void {
    const Task = struct {
        const Task = @This();

        surface_mesh: *const SurfaceMesh,
        halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        face_vector_field: SurfaceMesh.CellData(.face, Vec3d),
        vertex_divergence: SurfaceMesh.CellData(.vertex, f64),

        pub inline fn run(t: *const Task, vertex: SurfaceMesh.Cell) void {
            t.vertex_divergence.valuePtr(vertex).* = vectorFieldVertexDivergence(
                t.surface_mesh,
                vertex,
                t.halfedge_cotan_weight,
                t.vertex_position,
                t.face_vector_field,
            );
        }
    };

    var pctr = try SurfaceMesh.ParallelCellTaskRunner(.vertex).init(sm);
    defer pctr.deinit();
    try pctr.run(app_ctx, Task{
        .surface_mesh = sm,
        .halfedge_cotan_weight = halfedge_cotan_weight,
        .vertex_position = vertex_position,
        .face_vector_field = face_vector_field,
        .vertex_divergence = vertex_divergence,
    });
}
