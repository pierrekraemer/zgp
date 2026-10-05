const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const geometry_utils = @import("../../geometry/utils.zig");

/// Compute and return the tangent basis of the given vertex.
pub fn vertexTangentBasis(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Vertex,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    vertex_normal: SurfaceMesh.VertexData(Vec3f),
) [2]Vec3f {
    const d = sm.dart(vertex);
    const n = vertex_normal.value(vertex);
    var X = vec.sub3f(
        vertex_position.value(sm.vertex(sm.phi1(d))),
        vertex_position.value(vertex),
    );
    X = geometry_utils.removeComponent(X, n);
    X = vec.normalized3f(X);
    const Y = vec.cross3f(n, X);
    return .{ X, Y };
}

/// Compute the tangent bases of all vertices of the given SurfaceMesh
/// and store them in the given vertex_tangent_basis data.
pub fn computeVertexTangentBases(
    io: std.Io,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    vertex_normal: SurfaceMesh.VertexData(Vec3f),
    vertex_tangent_basis: *SurfaceMesh.VertexData([2]Vec3f),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        vertex_position: SurfaceMesh.VertexData(Vec3f),
        vertex_normal: SurfaceMesh.VertexData(Vec3f),
        vertex_tangent_basis: *SurfaceMesh.VertexData([2]Vec3f),

        pub fn run(t: *const @This(), vertex: SurfaceMesh.Vertex) void {
            t.vertex_tangent_basis.valuePtr(vertex).* = vertexTangentBasis(
                t.surface_mesh,
                vertex,
                t.vertex_position,
                t.vertex_normal,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelVertexTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .vertex_position = vertex_position,
        .vertex_normal = vertex_normal,
        .vertex_tangent_basis = vertex_tangent_basis,
    });
}
