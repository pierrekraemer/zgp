const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const geometry_utils = @import("../../geometry/utils.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

/// Compute and return the tangent basis of the given vertex.
pub fn vertexTangentBasis(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
) [2]Vec3f {
    assert(vertex.cellType() == .vertex);
    const d = vertex.dart();
    const d1 = sm.phi1(d);
    const n = vertex_normal.value(vertex);
    var X = vec.sub3f(
        vertex_position.value(.{ .vertex = d1 }),
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
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
) !void {
    var it = try SurfaceMesh.CellIterator(.vertex).init(sm);
    defer it.deinit();
    while (it.next()) |vertex| {
        vertex_tangent_basis.valuePtr(vertex).* = vertexTangentBasis(
            sm,
            vertex,
            vertex_position,
            vertex_normal,
        );
    }
}
