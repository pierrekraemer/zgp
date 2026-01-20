const std = @import("std");
const assert = std.debug.assert;
const PriorityQueue = @import("../../utils/PriorityQueue.zig").PriorityQueue;

const zgp_log = std.log.scoped(.zgp);

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const mat = @import("../../geometry/mat.zig");
const Mat4f = mat.Mat4f;

const subdivision = @import("subdivision.zig");
const qem = @import("qem.zig");

const EdgeInfo = struct {
    edge: SurfaceMesh.Cell,
    cost: f32,
    pub fn cmp(ctx: EdgeQueueContext, a: EdgeInfo, b: EdgeInfo) std.math.Order {
        const cost_order = std.math.order(a.cost, b.cost);
        if (cost_order != .eq) return cost_order;
        // tie-breaker: use edge indices to have a deterministic order
        return std.math.order(ctx.surface_mesh.cellIndex(a.edge), ctx.surface_mesh.cellIndex(b.edge));
    }
    pub fn setEdgeIndexInQueue(ctx: EdgeQueueContext, a: EdgeInfo, index: usize) void {
        ctx.edge_queue_index.valuePtr(a.edge).* = index;
    }
};
const EdgeQueueContext = struct {
    surface_mesh: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_qem: SurfaceMesh.CellData(.vertex, Mat4f),
    edge_queue_index: SurfaceMesh.CellData(.edge, ?usize),
};
const EdgeQueue = PriorityQueue(EdgeInfo, EdgeQueueContext, EdgeInfo.cmp, EdgeInfo.setEdgeIndexInQueue);

fn edgeCollapsePositionAndQuadric(queue: *EdgeQueue, edge: SurfaceMesh.Cell) struct { Vec3f, Mat4f } {
    assert(edge.cellType() == .edge);
    const ctx: EdgeQueueContext = queue.context;
    const d = edge.dart();
    const d1 = ctx.surface_mesh.phi1(d);
    const v1: SurfaceMesh.Cell = .{ .vertex = d };
    const v2: SurfaceMesh.Cell = .{ .vertex = d1 };
    const q = mat.add4f(
        ctx.vertex_qem.value(v1),
        ctx.vertex_qem.value(v2),
    );
    var p: ?Vec3f = null;
    if (!ctx.surface_mesh.isIncidentToBoundary(edge)) {
        if (ctx.surface_mesh.isIncidentToBoundary(v1)) {
            p = ctx.vertex_position.value(v1); // put on v1 if v1 is on boundary and v2 is not
        } else if (ctx.surface_mesh.isIncidentToBoundary(v2)) {
            p = ctx.vertex_position.value(v2); // put on v2 if v2 is on boundary and v1 is not
        }
    }
    if (p == null) {
        p = qem.optimalPoint(q); // can still be null after this call if Q is not invertible
    }
    if (p == null) {
        const mid_point = vec.mulScalar3f( // fallback to edge midpoint
            vec.add3f(
                ctx.vertex_position.value(v1),
                ctx.vertex_position.value(v2),
            ),
            0.5,
        );
        p = mid_point;
    }
    return .{ p.?, q };
}

fn addEdgeToQueue(queue: *EdgeQueue, edge: SurfaceMesh.Cell) !void {
    assert(edge.cellType() == .edge);
    const p, const q = edgeCollapsePositionAndQuadric(queue, edge);
    const p_hom: Vec4f = .{ p[0], p[1], p[2], 1.0 };
    // cost = p^T * Q * p
    try queue.add(.{
        .edge = edge,
        .cost = vec.dot4f(p_hom, mat.mulVec4f(q, p_hom)),
    });
}

fn removeEdgeFromQueue(queue: *EdgeQueue, edge: SurfaceMesh.Cell) void {
    assert(edge.cellType() == .edge);
    if (queue.context.edge_queue_index.value(edge)) |index| {
        _ = queue.removeIndex(index);
    }
    queue.context.edge_queue_index.valuePtr(edge).* = null;
}

fn updateEdgeInQueue(queue: *EdgeQueue, edge: SurfaceMesh.Cell) !void {
    assert(edge.cellType() == .edge);
    removeEdgeFromQueue(queue, edge);
    if (queue.context.surface_mesh.canCollapseEdge(edge)) {
        try addEdgeToQueue(queue, edge);
    }
}

/// Decimate the given SurfaceMesh using the QEM edge collapse approach.
/// (see qem.zig for details on the quadrics computation)
pub fn decimateQEM(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_qem: SurfaceMesh.CellData(.vertex, Mat4f),
    nb_vertices_to_remove: u32,
) !void {
    try subdivision.triangulateFaces(sm);

    var edge_queue_index = try sm.addData(.edge, ?usize, "__edge_queue_index");
    defer sm.removeData(.edge, edge_queue_index.gen());
    edge_queue_index.data.fill(null);

    var queue: EdgeQueue = EdgeQueue.init(sm.allocator, .{
        .surface_mesh = sm,
        .vertex_position = vertex_position,
        .vertex_qem = vertex_qem,
        .edge_queue_index = edge_queue_index,
    });
    defer queue.deinit();

    // init queue with collapsible edges
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
        const d1 = sm.phi1(d);
        const d_1 = sm.phi_1(d);
        const dd1 = sm.phi1(dd);
        const dd_1 = sm.phi_1(dd);
        const d_12 = sm.phi2(d_1);
        const dd_12 = sm.phi2(dd_1);

        removeEdgeFromQueue(&queue, .{ .edge = d1 });
        removeEdgeFromQueue(&queue, .{ .edge = d_1 });
        if (!sm.isBoundaryDart(dd)) { // if the edge is incident to a boundary face, the boundary dart is necessarily dd
            removeEdgeFromQueue(&queue, .{ .edge = dd1 });
            removeEdgeFromQueue(&queue, .{ .edge = dd_1 });
        }

        const p, const q = edgeCollapsePositionAndQuadric(&queue, info.edge);
        const v = sm.collapseEdge(info.edge);
        vertex_position.valuePtr(v).* = p;
        vertex_qem.valuePtr(v).* = q;

        var dit = sm.cellDartIterator(v); // v.dart() == d_12
        while (dit.next()) |dv| {
            try updateEdgeInQueue(&queue, .{ .edge = dv });
            try updateEdgeInQueue(&queue, .{ .edge = sm.phi1(dv) });
            if (dv == d_12 or dv == dd_12) {
                var d_it = sm.phi1(sm.phi2(sm.phi1(dv)));
                const d_stop = sm.phi2(dv);
                while (d_it != d_stop) : (d_it = sm.phi1(sm.phi2(d_it))) {
                    try updateEdgeInQueue(&queue, .{ .edge = d_it });
                    try updateEdgeInQueue(&queue, .{ .edge = sm.phi1(d_it) });
                }
            }
        }

        nb_removed_vertices += 1;
    }
}
