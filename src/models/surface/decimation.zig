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

    vertex_position_simd: SurfaceMesh.VertexData(SimdVec4f),
    vertex_qem_simd: SurfaceMesh.VertexData(SimdMat4f),

    pub fn init(
        sm: *SurfaceMesh,
        vertex_position: SurfaceMesh.VertexData(Vec3f),
        vertex_area: SurfaceMesh.VertexData(f32),
        vertex_tangent_basis: SurfaceMesh.VertexData([2]Vec3f),
        face_area: SurfaceMesh.FaceData(f32),
        face_normal: SurfaceMesh.FaceData(Vec3f),
    ) !QEMDecimationContext {
        const vertex_position_simd = try sm.addData(.vertex, SimdVec4f, "__position_simd");
        var it = vertex_position.data.constIterator();
        while (it.next()) |elem| {
            vertex_position_simd.data.valuePtr(elem.idx).* = vec.simdFromVec3f(elem.value_ptr.*);
        }

        var vertex_qem_simd = try sm.addData(.vertex, SimdMat4f, "__qem_simd");
        try qem.computeVertexQEMsSimd(
            sm,
            vertex_position_simd,
            vertex_area,
            vertex_tangent_basis,
            face_area,
            face_normal,
            &vertex_qem_simd,
        );

        return .{
            .surface_mesh = sm,
            .vertex_position_simd = vertex_position_simd,
            .vertex_qem_simd = vertex_qem_simd,
        };
    }

    pub fn deinit(qem_ctx: *QEMDecimationContext) void {
        qem_ctx.surface_mesh.removeData(qem_ctx.vertex_position_simd);
        qem_ctx.surface_mesh.removeData(qem_ctx.vertex_qem_simd);
    }

    pub fn writeBack(qem_ctx: *QEMDecimationContext, vertex_position: SurfaceMesh.VertexData(Vec3f)) !void {
        var it = qem_ctx.vertex_position_simd.data.constIterator();
        while (it.next()) |elem| {
            vertex_position.data.valuePtr(elem.idx).* = vec.simdToVec3f(elem.value_ptr.*);
        }
    }

    fn edgeCollapsePositionAndQuadric(qem_ctx: *QEMDecimationContext, edge: SurfaceMesh.Edge) struct { SimdVec4f, SimdMat4f } {
        const sm = qem_ctx.surface_mesh;
        const d = sm.dart(edge);
        const d1 = sm.phi1(d);
        const v1 = sm.vertex(d);
        const v2 = sm.vertex(d1);

        const q = mat.simdAdd4f(
            qem_ctx.vertex_qem_simd.value(v1),
            qem_ctx.vertex_qem_simd.value(v2),
        );

        var p: ?SimdVec4f = null;
        if (!sm.isOrbitIncidentToBoundary(d, .edge)) {
            if (sm.isOrbitIncidentToBoundary(d, .vertex)) {
                p = qem_ctx.vertex_position_simd.value(v1); // put on v1 if v1 is on boundary and v2 is not
            } else if (sm.isOrbitIncidentToBoundary(d1, .vertex)) {
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
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    vertex_area: SurfaceMesh.VertexData(f32),
    vertex_tangent_basis: SurfaceMesh.VertexData([2]Vec3f),
    face_area: SurfaceMesh.FaceData(f32),
    face_normal: SurfaceMesh.FaceData(Vec3f),
    nb_vertices_to_remove: u32,
) !void {
    try subdivision.triangulateFaces(allocator, sm);

    // Priority queue type for edge collapse, ordered by the ascending cost of collapsing the edge
    const EdgeQueueContext = struct {
        qem_ctx: *QEMDecimationContext,
        edge_queue_index: *SurfaceMesh.EdgeData(?usize),
    };
    const EdgeInfo = struct {
        const EdgeInfo = @This();
        edge: SurfaceMesh.Edge,
        cost: f32,
        pub fn cmp(_: EdgeQueueContext, a: EdgeInfo, b: EdgeInfo) std.math.Order {
            const cost_order = std.math.order(a.cost, b.cost);
            if (cost_order != .eq) return cost_order;
            // tie-breaker: use edge indices to have a deterministic order
            return std.math.order(a.edge.index, b.edge.index);
        }
        pub fn setEdgeIndexInQueue(qctx: EdgeQueueContext, a: EdgeInfo, index: usize) void {
            qctx.edge_queue_index.valuePtr(a.edge).* = index;
        }
    };
    const EdgeQueue = PriorityQueue(EdgeInfo, EdgeQueueContext, EdgeInfo.cmp, EdgeInfo.setEdgeIndexInQueue);
    const EdgeQueueUtil = struct {
        fn edgeCost(queue: *EdgeQueue, edge: SurfaceMesh.Edge) f32 {
            const p, const q = queue.context.qem_ctx.edgeCollapsePositionAndQuadric(edge);
            const p_hom: SimdVec4f = .{ p[0], p[1], p[2], 1.0 };
            // cost = p^T * Q * p  (in f32!)
            const qp = mat.simdMulVec4f(q, p_hom);
            return vec.simdDot4f(p_hom, qp);
        }
        fn addEdgeToQueue(queue: *EdgeQueue, edge: SurfaceMesh.Edge, alloc: std.mem.Allocator) !void {
            try queue.push(alloc, .{ .edge = edge, .cost = edgeCost(queue, edge) });
        }
        fn removeEdgeFromQueue(queue: *EdgeQueue, edge: SurfaceMesh.Edge) void {
            if (queue.context.edge_queue_index.value(edge)) |index| {
                _ = queue.popIndex(index);
            }
            queue.context.edge_queue_index.valuePtr(edge).* = null;
        }
        /// For edges whose collapse cost changed.
        /// If the edge is already in the queue, its cost is updated in place (its topological validity
        /// is checked when it is popped). Otherwise, it is added if it is collapsible.
        fn updateEdgeInQueue(queue: *EdgeQueue, edge: SurfaceMesh.Edge, alloc: std.mem.Allocator) !void {
            if (queue.context.edge_queue_index.value(edge)) |index| {
                _ = queue.updateIndex(index, .{ .edge = edge, .cost = edgeCost(queue, edge) });
            } else if (queue.context.qem_ctx.surface_mesh.canCollapseEdge(edge)) {
                try addEdgeToQueue(queue, edge, alloc);
            }
        }
        /// For edges whose collapse cost did not change but which may have become collapsible.
        /// If the edge is already in the queue, nothing is done: its cost is still valid and its
        /// topological validity is checked when it is popped.
        fn addEdgeToQueueIfNeeded(queue: *EdgeQueue, edge: SurfaceMesh.Edge, alloc: std.mem.Allocator) !void {
            if (queue.context.edge_queue_index.value(edge) != null) return;
            if (queue.context.qem_ctx.surface_mesh.canCollapseEdge(edge)) {
                try addEdgeToQueue(queue, edge, alloc);
            }
        }
    };

    var edge_queue_index = try sm.addData(.edge, ?usize, "__edge_queue_index");
    defer sm.removeData(edge_queue_index);
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
        .edge_queue_index = &edge_queue_index,
    });
    defer queue.deinit(allocator);

    // initialize the queue with all topologically collapsible edges
    var edge_it = sm.edgeIterator();
    while (edge_it.next()) |edge| {
        if (sm.canCollapseEdge(edge)) {
            try EdgeQueueUtil.addEdgeToQueue(&queue, edge, allocator);
        }
    }

    var nb_removed_vertices: u32 = 0;
    while (queue.items.len > 0 and nb_removed_vertices < nb_vertices_to_remove) {
        const info = queue.popIndex(0);
        const edge = info.edge;
        edge_queue_index.valuePtr(edge).* = null; // popIndex does not reset the queue index of the popped edge

        // the topological validity of the collapse may have changed since the edge was pushed in the queue
        // (e.g. condition 4 of canCollapseEdge depends on the 2-ring neighborhood of the edge,
        // which is not entirely covered by the update loop below)
        if (!sm.canCollapseEdge(edge)) {
            continue;
        }

        const d = sm.dart(edge);
        const dd = sm.phi2(d);
        const d_face_is_triangle = !sm.isBoundaryDart(d) and sm.phi1(sm.phi1(sm.phi1(d))) == d;
        const dd_face_is_triangle = !sm.isBoundaryDart(dd) and sm.phi1(sm.phi1(sm.phi1(dd))) == dd;

        // the incident triangle faces are removed by the collapse: their other edges are either removed or merged
        // (the merged edges are incident to the resulting vertex and are re-inserted below if collapsible)
        // the third vertices of these triangles lose an incident edge
        var v3: ?SurfaceMesh.Vertex = null;
        var v4: ?SurfaceMesh.Vertex = null;
        if (d_face_is_triangle) {
            EdgeQueueUtil.removeEdgeFromQueue(&queue, sm.edge(sm.phi1(d)));
            EdgeQueueUtil.removeEdgeFromQueue(&queue, sm.edge(sm.phi_1(d)));
            v3 = sm.vertex(sm.phi_1(d));
        }
        if (dd_face_is_triangle) {
            EdgeQueueUtil.removeEdgeFromQueue(&queue, sm.edge(sm.phi1(dd)));
            EdgeQueueUtil.removeEdgeFromQueue(&queue, sm.edge(sm.phi_1(dd)));
            v4 = sm.vertex(sm.phi_1(dd));
        }

        // TODO: check for potential face flips before collapsing
        const p, const q = qem_ctx.edgeCollapsePositionAndQuadric(edge);
        const v = sm.collapseEdge(edge);

        // Update the context data
        qem_ctx.vertex_position_simd.valuePtr(v).* = p;
        qem_ctx.vertex_qem_simd.valuePtr(v).* = q;

        // Update the queue
        // - edges incident to v: their cost changed (new position & quadric of v) -> cost update (or insertion if collapsible)
        // - link edges of v: cost unchanged, may have become collapsible (degree of v, their opposite vertex, increased)
        // - edges incident to the third vertices V3 / V4: cost unchanged, may have become collapsible (degree limit)
        // - link edges of V3 / V4: cost unchanged, can only have become non-collapsible (degree of V3 / V4,
        //   their opposite vertex, decreased) -> nothing to do, handled by the pop-time check
        var dart_it = sm.vertexDartIterator(sm.dart(v));
        while (dart_it.next()) |dv| {
            try EdgeQueueUtil.updateEdgeInQueue(&queue, sm.edge(dv), allocator);
            try EdgeQueueUtil.addEdgeToQueueIfNeeded(&queue, sm.edge(sm.phi1(dv)), allocator);
            const dv2 = sm.phi2(dv); // dart of the adjacent vertex
            const w = sm.vertex(dv2);
            if ((v3 != null and w.index == v3.?.index) or (v4 != null and w.index == v4.?.index)) {
                var w_it = sm.vertexDartIterator(dv2);
                while (w_it.next()) |dw| {
                    if (dw == dv2) continue; // edge incident to v: already updated
                    try EdgeQueueUtil.addEdgeToQueueIfNeeded(&queue, sm.edge(dw), allocator);
                }
            }
        }

        nb_removed_vertices += 1;
    }

    try qem_ctx.writeBack(vertex_position);
}
