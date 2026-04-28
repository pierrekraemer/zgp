const std = @import("std");
const assert = std.debug.assert;

const AppContext = @import("../../main.zig").AppContext;
const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const SQEM = @import("../../geometry/SQEM.zig");

/// Compute and return the SQEM of the given vertex.
pub fn vertexSQEM(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    line_quadric_epsilon: f32,
) SQEM {
    assert(vertex.cellType() == .vertex);
    var vsq = SQEM.zero;
    const p = vertex_position.value(vertex);
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (!sm.isBoundaryDart(d)) {
            const face: SurfaceMesh.Cell = .{ .face = d };
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
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    line_quadric_epsilon: f32,
    vertex_sqem: SurfaceMesh.CellData(.vertex, SQEM),
) !void {
    const Task = struct {
        const Task = @This();

        surface_mesh: *const SurfaceMesh,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_area: SurfaceMesh.CellData(.vertex, f32),
        vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
        face_area: SurfaceMesh.CellData(.face, f32),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),
        line_quadric_epsilon: f32,
        vertex_sqem: SurfaceMesh.CellData(.vertex, SQEM),

        pub fn run(t: *const Task, vertex: SurfaceMesh.Cell) void {
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

    var pctr: SurfaceMesh.ParallelCellTaskRunner = try .init(sm, .vertex);
    defer pctr.deinit();
    try pctr.run(app_ctx, Task{
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
