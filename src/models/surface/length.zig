const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

/// Compute and return the length of the given edge.
pub fn edgeLength(
    sm: *const SurfaceMesh,
    edge: SurfaceMesh.Edge,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
) f32 {
    const d = sm.dart(edge);
    return vec.norm3f(
        vec.sub3f(
            vertex_position.value(sm.vertex(sm.phi1(d))),
            vertex_position.value(sm.vertex(d)),
        ),
    );
}

/// Compute the lengths of all edges of the given SurfaceMesh
/// and store them in the given edge_length data.
/// Probably not worth parallelizing..
pub fn computeEdgeLengths(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    edge_length: *SurfaceMesh.EdgeData(f32),
) !void {
    var it = sm.edgeIterator();
    while (it.next()) |edge| {
        edge_length.valuePtr(edge).* = edgeLength(
            sm,
            edge,
            vertex_position,
        );
    }
}
