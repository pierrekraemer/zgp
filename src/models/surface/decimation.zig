const std = @import("std");
const assert = std.debug.assert;

const PriorityQueue = @import("../../utils/PriorityQueue.zig").PriorityQueue;

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const SimdVec4f = vec.SimdVec4f;
const mat = @import("../../geometry/mat.zig");
const SimdMat4f = mat.SimdMat4f;

const subdivision = @import("subdivision.zig");
const qem = @import("qem.zig");

const QEMDecimationContext = struct {
    surface_mesh: *SurfaceMesh,

    vertex_position_simd: SurfaceMesh.CellData(.vertex, SimdVec4f),
    vertex_qem_simd: SurfaceMesh.CellData(.vertex, SimdMat4f),

    pub fn init(
        sm: *SurfaceMesh,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_area: SurfaceMesh.CellData(.vertex, f32),
        vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
        face_area: SurfaceMesh.CellData(.face, f32),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),
    ) !QEMDecimationContext {
        const vertex_position_simd = try sm.addData(.vertex, SimdVec4f, "__position_simd");
        var it = vertex_position.data.constIterator();
        while (it.next()) |elem| {
            vertex_position_simd.data.data.items[elem.idx] = vec.simdFromVec3f(elem.value_ptr.*);
        }

        const vertex_qem_simd = try sm.addData(.vertex, SimdMat4f, "__qem_simd");
        try qem.computeVertexQEMsSimd(
            sm,
            vertex_position_simd,
            vertex_area,
            vertex_tangent_basis,
            face_area,
            face_normal,
            vertex_qem_simd,
        );

        return .{
            .surface_mesh = sm,
            .vertex_position_simd = vertex_position_simd,
            .vertex_qem_simd = vertex_qem_simd,
        };
    }

    pub fn deinit(qem_ctx: *QEMDecimationContext) void {
        qem_ctx.surface_mesh.removeData(.vertex, SimdVec4f, qem_ctx.vertex_position_simd);
        qem_ctx.surface_mesh.removeData(.vertex, SimdMat4f, qem_ctx.vertex_qem_simd);
    }

    pub fn writeBack(qem_ctx: *QEMDecimationContext, vertex_position: SurfaceMesh.CellData(.vertex, Vec3f)) !void {
        var it = qem_ctx.vertex_position_simd.data.constIterator();
        while (it.next()) |elem| {
            vertex_position.data.data.items[elem.idx] = vec.simdToVec3f(elem.value_ptr.*);
        }
    }

    fn edgeCollapsePositionAndQuadric(
        qem_ctx: *QEMDecimationContext,
        edge: SurfaceMesh.Cell,
    ) struct { SimdVec4f, SimdMat4f } {
        assert(edge.cellType() == .edge);
        const sm = qem_ctx.surface_mesh;
        const d = edge.dart();
        const d1 = sm.phi1(d);
        const v1: SurfaceMesh.Cell = .{ .vertex = d };
        const v2: SurfaceMesh.Cell = .{ .vertex = d1 };

        const q = mat.simdAdd4f(
            qem_ctx.vertex_qem_simd.value(v1),
            qem_ctx.vertex_qem_simd.value(v2),
        );

        var p: ?SimdVec4f = null;
        if (!sm.isIncidentToBoundary(edge)) {
            if (sm.isIncidentToBoundary(v1)) {
                p = qem_ctx.vertex_position_simd.value(v1); // put on v1 if v1 is on boundary and v2 is not
            } else if (sm.isIncidentToBoundary(v2)) {
                p = qem_ctx.vertex_position_simd.value(v2); // put on v2 if v2 is on boundary and v1 is not
            }
        }
        if (p == null) {
            p = qem.optimalPointSimd(q); // can still be null after this call if Q is not invertible
        }
        if (p == null) {
            // if Q is not invertible, we choose the midpoint of the edge
            p = (qem_ctx.vertex_position_simd.value(v1) + qem_ctx.vertex_position_simd.value(v2)) * @as(SimdVec4f, @splat(0.5));
        }
        return .{ p.?, q };
    }
};

/// Decimate the given SurfaceMesh using the QEM edge collapse approach.
/// (see qem.zig for details on the quadrics computation)
pub fn decimateQEM(
    allocator: std.mem.Allocator,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    nb_vertices_to_remove: u32,
) !void {
    try subdivision.triangulateFaces(allocator, sm);

    // Priority queue type for edge collapse, ordered by the ascending cost of collapsing the edge
    const EdgeQueueContext = struct {
        qem_ctx: *QEMDecimationContext,
        edge_queue_index: SurfaceMesh.CellData(.edge, ?usize),
    };
    const EdgeInfo = struct {
        const EdgeInfo = @This();
        edge: SurfaceMesh.Cell,
        cost: f32,
        pub fn cmp(qctx: EdgeQueueContext, a: EdgeInfo, b: EdgeInfo) std.math.Order {
            const cost_order = std.math.order(a.cost, b.cost);
            if (cost_order != .eq) return cost_order;
            // tie-breaker: use edge indices to have a deterministic order
            return std.math.order(qctx.qem_ctx.surface_mesh.cellIndex(a.edge), qctx.qem_ctx.surface_mesh.cellIndex(b.edge));
        }
        pub fn setEdgeIndexInQueue(qctx: EdgeQueueContext, a: EdgeInfo, index: usize) void {
            qctx.edge_queue_index.valuePtr(a.edge).* = index;
        }
    };
    const EdgeQueue = PriorityQueue(EdgeInfo, EdgeQueueContext, EdgeInfo.cmp, EdgeInfo.setEdgeIndexInQueue);
    const EdgeQueueUtil = struct {
        fn addEdgeToQueue(queue: *EdgeQueue, edge: SurfaceMesh.Cell, alloc: std.mem.Allocator) !void {
            assert(edge.cellType() == .edge);
            const p, const q = queue.context.qem_ctx.edgeCollapsePositionAndQuadric(edge);
            const p_hom: SimdVec4f = .{ p[0], p[1], p[2], 1.0 };
            // cost = p^T * Q * p  (in f32!)
            const qp = mat.simdMulVec4f(q, p_hom);
            const cost = vec.simdDot4f(p_hom, qp);

            try queue.push(alloc, .{ .edge = edge, .cost = cost });
        }
        fn removeEdgeFromQueue(queue: *EdgeQueue, edge: SurfaceMesh.Cell) void {
            assert(edge.cellType() == .edge);
            if (queue.context.edge_queue_index.value(edge)) |index| {
                _ = queue.popIndex(index);
            }
            queue.context.edge_queue_index.valuePtr(edge).* = null;
        }
        fn updateEdgeInQueue(queue: *EdgeQueue, edge: SurfaceMesh.Cell, alloc: std.mem.Allocator) !void {
            assert(edge.cellType() == .edge);
            removeEdgeFromQueue(queue, edge);
            if (queue.context.qem_ctx.surface_mesh.canCollapseEdge(edge)) {
                try addEdgeToQueue(queue, edge, alloc);
            }
        }
    };

    var edge_queue_index = try sm.addData(.edge, ?usize, "__edge_queue_index");
    defer sm.removeData(.edge, ?usize, edge_queue_index);
    edge_queue_index.data.fill(null);

    var qem_ctx: QEMDecimationContext = try .init(
        sm,
        vertex_position,
        vertex_area,
        vertex_tangent_basis,
        face_area,
        face_normal,
    );
    defer qem_ctx.deinit();

    var queue: EdgeQueue = .initContext(.{
        .qem_ctx = &qem_ctx,
        .edge_queue_index = edge_queue_index,
    });
    defer queue.deinit(allocator);

    // initialize the queue with all topologically collapsible edges
    var edge_it: SurfaceMesh.CellIterator = try .init(sm, .edge);
    defer edge_it.deinit();
    while (edge_it.next()) |edge| {
        if (sm.canCollapseEdge(edge)) {
            try EdgeQueueUtil.addEdgeToQueue(&queue, edge, allocator);
        }
    }

    var nb_removed_vertices: u32 = 0;
    while (queue.items.len > 0 and nb_removed_vertices < nb_vertices_to_remove) {
        const info = queue.popIndex(0);
        const edge = info.edge;

        const d = edge.dart();
        const dd = sm.phi2(d);
        const d1 = sm.phi1(d);
        const d_1 = sm.phi_1(d);
        const dd1 = sm.phi1(dd);
        const dd_1 = sm.phi_1(dd);
        const d_12 = sm.phi2(d_1);
        const dd_12 = sm.phi2(dd_1);

        EdgeQueueUtil.removeEdgeFromQueue(&queue, .{ .edge = d1 });
        EdgeQueueUtil.removeEdgeFromQueue(&queue, .{ .edge = d_1 });
        if (!sm.isBoundaryDart(dd)) { // if the edge is incident to a boundary face, the boundary dart is necessarily dd
            EdgeQueueUtil.removeEdgeFromQueue(&queue, .{ .edge = dd1 });
            EdgeQueueUtil.removeEdgeFromQueue(&queue, .{ .edge = dd_1 });
        }

        // TODO: check for potential face flips before collapsing
        const p, const q = qem_ctx.edgeCollapsePositionAndQuadric(edge);
        const v = sm.collapseEdge(edge);

        // Update the shadow context
        qem_ctx.vertex_position_simd.valuePtr(v).* = p;
        qem_ctx.vertex_qem_simd.valuePtr(v).* = q;

        var dart_it = sm.cellDartIterator(v); // v.dart() == d_12
        while (dart_it.next()) |dv| {
            try EdgeQueueUtil.updateEdgeInQueue(&queue, .{ .edge = dv }, allocator);
            try EdgeQueueUtil.updateEdgeInQueue(&queue, .{ .edge = sm.phi1(dv) }, allocator);
            if (dv == d_12 or dv == dd_12) {
                var d_it = sm.phi1(sm.phi2(sm.phi1(dv)));
                const d_stop = sm.phi2(dv);
                while (d_it != d_stop) : (d_it = sm.phi1(sm.phi2(d_it))) {
                    try EdgeQueueUtil.updateEdgeInQueue(&queue, .{ .edge = d_it }, allocator);
                    try EdgeQueueUtil.updateEdgeInQueue(&queue, .{ .edge = sm.phi1(d_it) }, allocator);
                }
            }
        }

        nb_removed_vertices += 1;
    }

    try qem_ctx.writeBack(vertex_position);
}
