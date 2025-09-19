const std = @import("std");
const assert = std.debug.assert;

const zgp_log = std.log.scoped(.zgp);

const SurfaceMesh = @import("SurfaceMesh.zig");
const subdivision = @import("subdivision.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;
const Vec4 = vec.Vec4;
const mat = @import("../../geometry/mat.zig");
const Mat4 = mat.Mat4;

const EdgeCollapseCost = struct {
    edge_index: u32,
    cost: f32,

    pub fn cmp(ctx: EdgeQueueContext, a: EdgeCollapseCost, b: EdgeCollapseCost) std.math.Order {
        _ = ctx;
        return std.math.order(a.cost, b.cost);
    }
};
const EdgeQueueContext = struct {};
const EdgeQueue = std.PriorityQueue(EdgeCollapseCost, EdgeQueueContext, EdgeCollapseCost.cmp);

/// Decimate the given SurfaceMesh.
/// The obtained mesh will be triangular.
pub fn decimateQEM(
    allocator: std.mem.Allocator,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    vertex_qem: SurfaceMesh.CellData(.vertex, Mat4),
    nb_vertices_to_remove: u32,
) !void {
    _ = nb_vertices_to_remove;

    try subdivision.triangulateFaces(sm);

    var queue: EdgeQueue = EdgeQueue.init(allocator, .{});
    defer queue.deinit();

    var edge_it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer edge_it.deinit();
    while (edge_it.next()) |edge| {
        const d = edge.dart();
        const dd = sm.phi2(d);
        const v1 = SurfaceMesh.Cell{ .vertex = d };
        const v2 = SurfaceMesh.Cell{ .vertex = dd };
        const mid_point = vec.mulScalar3(
            vec.add3(
                vertex_position.value(v1),
                vertex_position.value(v2),
            ),
            0.5,
        );
        const q = mat.add4(
            vertex_qem.value(v1),
            vertex_qem.value(v2),
        );
        const mid_point_4: Vec4 = .{ mid_point[0], mid_point[1], mid_point[2], 1.0 };
        // cost = v^T * Q * v
        const cost = vec.dot4(mid_point_4, mat.mulVec4(q, mid_point_4));
        try queue.add(.{
            .edge_index = sm.cellIndex(edge),
            .cost = cost,
        });
    }
}
