const std = @import("std");
const assert = std.debug.assert;

const zgp_log = std.log.scoped(.zgp);

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;
const Vec4 = vec.Vec4;
const mat = @import("../../geometry/mat.zig");
const Mat4 = mat.Mat4;

const qem = @import("qem.zig");

const EdgeInfo = struct {
    edge: SurfaceMesh.Cell,
    edge_index: u32,
    cost: f32,

    pub fn cmp(_: EdgeQueueContext, a: EdgeInfo, b: EdgeInfo) std.math.Order {
        const cost_order = std.math.order(a.cost, b.cost);
        if (cost_order != .eq) return cost_order;
        return std.math.order(a.edge_index, b.edge_index);
    }
};
const EdgeQueueContext = struct {
    surface_mesh: *SurfaceMesh,
    edge_in_queue: SurfaceMesh.CellData(.edge, bool),
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    vertex_qem: SurfaceMesh.CellData(.vertex, Mat4),
};
const EdgeQueue = std.PriorityQueue(EdgeInfo, EdgeQueueContext, EdgeInfo.cmp);

fn addEdgeToQueue(queue: *EdgeQueue, edge: SurfaceMesh.Cell) !void {
    assert(edge.cellType() == .edge);
    const ctx: EdgeQueueContext = queue.context;
    const d = edge.dart();
    const dd = ctx.surface_mesh.phi2(d);
    const v1 = SurfaceMesh.Cell{ .vertex = d };
    const v2 = SurfaceMesh.Cell{ .vertex = dd };
    const q = mat.add4(
        ctx.vertex_qem.value(v1),
        ctx.vertex_qem.value(v2),
    );
    var p: Vec4 = undefined;
    const opt = qem.optimalPoint(q);
    if (opt) |opt_point| {
        p = .{ opt_point[0], opt_point[1], opt_point[2], 1.0 };
    } else {
        const mid_point = vec.mulScalar3(
            vec.add3(
                ctx.vertex_position.value(v1),
                ctx.vertex_position.value(v2),
            ),
            0.5,
        );
        p = .{ mid_point[0], mid_point[1], mid_point[2], 1.0 };
    }
    // cost = p^T * Q * p
    try queue.add(.{
        .edge = edge,
        .edge_index = ctx.surface_mesh.cellIndex(edge),
        .cost = vec.dot4(p, mat.mulVec4(q, p)),
    });
    ctx.edge_in_queue.valuePtr(edge).* = true;
}

fn removeEdgeFromQueue(queue: *EdgeQueue, edge_index: u32) void {
    for (queue.items, 0..) |e, i| {
        if (e.edge_index == edge_index) {
            _ = queue.removeIndex(i);
            queue.context.edge_in_queue.valuePtr(e.edge).* = false;
            return;
        }
    }
}

/// Decimate the given SurfaceMesh using the QEM method.
pub fn decimateQEM(
    allocator: std.mem.Allocator,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    vertex_qem: SurfaceMesh.CellData(.vertex, Mat4),
    nb_vertices_to_remove: u32,
) !void {
    var edge_in_queue = try sm.addData(.edge, bool, "in_queue");
    defer sm.removeData(.edge, edge_in_queue.gen());
    edge_in_queue.data.fill(false);

    var queue: EdgeQueue = EdgeQueue.init(allocator, .{
        .surface_mesh = sm,
        .edge_in_queue = edge_in_queue,
        .vertex_position = vertex_position,
        .vertex_qem = vertex_qem,
    });
    defer queue.deinit();

    var edge_it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer edge_it.deinit();
    while (edge_it.next()) |edge| {
        if (sm.canCollapseEdge(edge)) {
            try addEdgeToQueue(&queue, edge);
        }
    }

    var nb_removed_vertices: u32 = 0;
    while (queue.items.len > 0 and nb_removed_vertices < nb_vertices_to_remove) {
        const info = queue.remove();
        const d = info.edge.dart();
        const dd = sm.phi2(d);
        const v1 = SurfaceMesh.Cell{ .vertex = d };
        const v2 = SurfaceMesh.Cell{ .vertex = dd };
        const q = mat.add4(vertex_qem.value(v1), vertex_qem.value(v2));
        const opt = qem.optimalPoint(q);
        const pos = if (opt) |opt_point| opt_point else vec.mulScalar3(
            vec.add3(
                vertex_position.value(v1),
                vertex_position.value(v2),
            ),
            0.5,
        );
        var dit1 = sm.cellDartIterator(.{ .vertex = d });
        _ = dit1.next(); // skip d
        while (dit1.next()) |dv1| {
            const e = SurfaceMesh.Cell{ .edge = dv1 };
            if (edge_in_queue.value(e)) {
                removeEdgeFromQueue(&queue, sm.cellIndex(e));
            }
        }
        var dit2 = sm.cellDartIterator(.{ .vertex = dd });
        _ = dit2.next(); // skip dd
        while (dit2.next()) |dv2| {
            const e = SurfaceMesh.Cell{ .edge = dv2 };
            if (edge_in_queue.value(e)) {
                removeEdgeFromQueue(&queue, sm.cellIndex(e));
            }
        }
        if (!sm.canCollapseEdge(info.edge)) {
            removeEdgeFromQueue(&queue, info.edge_index);
            continue;
        }
        const v = sm.collapseEdge(info.edge);
        vertex_position.valuePtr(v).* = pos;
        vertex_qem.valuePtr(v).* = q;
        var dit = sm.cellDartIterator(v);
        while (dit.next()) |de| {
            const e = SurfaceMesh.Cell{ .edge = de };
            if (sm.canCollapseEdge(e)) {
                try addEdgeToQueue(&queue, e);
            }
        }
        // try sm.checkIntegrity();
        nb_removed_vertices += 1;
    }
}
