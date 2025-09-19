const std = @import("std");
const assert = std.debug.assert;

const zgp_log = std.log.scoped(.zgp);

const SurfaceMesh = @import("SurfaceMesh.zig");
const subdivision = @import("subdivision.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

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
    nb_vertices_to_remove: u32,
) !void {
    _ = vertex_position;
    _ = nb_vertices_to_remove;

    try subdivision.triangulateFaces(sm);

    var queue: EdgeQueue = EdgeQueue.init(allocator, .{});
    defer queue.deinit();

    var edge_it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer edge_it.deinit();
    while (edge_it.next()) |edge| {
        // const cost = computeEdgeCollapseCost(sm, edge, vertex_position);
        const cost: f32 = 1.0;
        try queue.add(.{
            .edge_index = sm.cellIndex(edge),
            .cost = cost,
        });
    }
}
