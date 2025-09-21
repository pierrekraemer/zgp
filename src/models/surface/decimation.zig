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
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    vertex_qem: SurfaceMesh.CellData(.vertex, Mat4),
};
const EdgeQueue = std.PriorityQueue(EdgeInfo, EdgeQueueContext, EdgeInfo.cmp);

fn edgeOptimalPosition(queue: *EdgeQueue, edge: SurfaceMesh.Cell) Vec3 {
    assert(edge.cellType() == .edge);
    const ctx: EdgeQueueContext = queue.context;
    const d = edge.dart();
    const dd = ctx.surface_mesh.phi2(d);
    const v1: SurfaceMesh.Cell = .{ .vertex = d };
    const v2: SurfaceMesh.Cell = .{ .vertex = dd };
    const q = mat.add4(
        ctx.vertex_qem.value(v1),
        ctx.vertex_qem.value(v2),
    );
    var p: ?Vec3 = null;
    if (!ctx.surface_mesh.isIncidentToBoundary(edge)) {
        if (ctx.surface_mesh.isIncidentToBoundary(v1)) {
            p = ctx.vertex_position.value(v1);
        } else if (ctx.surface_mesh.isIncidentToBoundary(v2)) {
            p = ctx.vertex_position.value(v2);
        }
    }
    if (p == null) {
        p = qem.optimalPoint(q);
    }
    if (p == null) {
        const mid_point = vec.mulScalar3(
            vec.add3(
                ctx.vertex_position.value(v1),
                ctx.vertex_position.value(v2),
            ),
            0.5,
        );
        p = mid_point;
    }
    return p.?;
}

fn addEdgeToQueue(queue: *EdgeQueue, edge: SurfaceMesh.Cell) !void {
    assert(edge.cellType() == .edge);
    const ctx: EdgeQueueContext = queue.context;
    const d = edge.dart();
    const dd = ctx.surface_mesh.phi2(d);
    const v1: SurfaceMesh.Cell = .{ .vertex = d };
    const v2: SurfaceMesh.Cell = .{ .vertex = dd };
    const q = mat.add4(
        ctx.vertex_qem.value(v1),
        ctx.vertex_qem.value(v2),
    );
    const p = edgeOptimalPosition(queue, edge);
    const p_hom: Vec4 = .{ p[0], p[1], p[2], 1.0 };
    // cost = p^T * Q * p
    try queue.add(.{
        .edge = edge,
        .edge_index = ctx.surface_mesh.cellIndex(edge),
        .cost = vec.dot4(p_hom, mat.mulVec4(q, p_hom)),
    });
}

fn removeEdgeFromQueue(queue: *EdgeQueue, edge_index: u32) void {
    for (queue.items, 0..) |e, i| {
        if (e.edge_index == edge_index) {
            _ = queue.removeIndex(i);
            return;
        }
    }
}

fn updateEdgeInQueue(queue: *EdgeQueue, edge_info: EdgeInfo) !void {
    assert(edge_info.edge.cellType() == .edge);
    const ctx: EdgeQueueContext = queue.context;
    const d = edge_info.edge.dart();
    const dd = ctx.surface_mesh.phi2(d);
    const v1: SurfaceMesh.Cell = .{ .vertex = d };
    const v2: SurfaceMesh.Cell = .{ .vertex = dd };
    const q = mat.add4(
        ctx.vertex_qem.value(v1),
        ctx.vertex_qem.value(v2),
    );
    const p = edgeOptimalPosition(queue, edge_info.edge);
    const p_hom: Vec4 = .{ p[0], p[1], p[2], 1.0 };
    // cost = p^T * Q * p
    try queue.update(edge_info, .{
        .edge = edge_info.edge,
        .edge_index = ctx.surface_mesh.cellIndex(edge_info.edge),
        .cost = vec.dot4(p_hom, mat.mulVec4(q, p_hom)),
    });
}

/// Decimate the given SurfaceMesh using the QEM method.
pub fn decimateQEM(
    allocator: std.mem.Allocator,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    vertex_qem: SurfaceMesh.CellData(.vertex, Mat4),
    nb_vertices_to_remove: u32,
) !void {
    var queue: EdgeQueue = EdgeQueue.init(allocator, .{
        .surface_mesh = sm,
        .vertex_position = vertex_position,
        .vertex_qem = vertex_qem,
    });
    defer queue.deinit();

    var edge_it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer edge_it.deinit();
    while (edge_it.next()) |edge| {
        try addEdgeToQueue(&queue, edge);
    }

    var nb_removed_vertices: u32 = 0;
    while (queue.items.len > 0 and nb_removed_vertices < nb_vertices_to_remove) {
        const info = queue.remove();
        if (!sm.canCollapseEdge(info.edge)) {
            continue;
        }
        const d = info.edge.dart();
        const dd = sm.phi2(d);
        const v1: SurfaceMesh.Cell = .{ .vertex = d };
        const v2: SurfaceMesh.Cell = .{ .vertex = dd };
        var dit1 = sm.cellDartIterator(v1);
        _ = dit1.next(); // skip d (info.edge)
        while (dit1.next()) |dv1| {
            removeEdgeFromQueue(&queue, sm.cellIndex(.{ .edge = dv1 }));
        }
        var dit2 = sm.cellDartIterator(v2);
        _ = dit2.next(); // skip dd (info.edge)
        while (dit2.next()) |dv2| {
            removeEdgeFromQueue(&queue, sm.cellIndex(.{ .edge = dv2 }));
        }
        const q = mat.add4(vertex_qem.value(v1), vertex_qem.value(v2));
        const p = edgeOptimalPosition(&queue, info.edge);
        const v = sm.collapseEdge(info.edge);
        vertex_position.valuePtr(v).* = p;
        vertex_qem.valuePtr(v).* = q;
        var dit = sm.cellDartIterator(v);
        while (dit.next()) |dv| {
            const e: SurfaceMesh.Cell = .{ .edge = dv };
            const edge_index = sm.cellIndex(e);
            var existing_edge_info: ?EdgeInfo = null;
            for (queue.items) |einfo| {
                if (einfo.edge_index == edge_index) {
                    existing_edge_info = einfo;
                    break;
                }
            }
            if (existing_edge_info) |einfo| { // TODO: should not happen
                try updateEdgeInQueue(&queue, einfo);
            } else {
                try addEdgeToQueue(&queue, e);
            }
        }
        nb_removed_vertices += 1;
        // try sm.checkIntegrity();
    }
}
