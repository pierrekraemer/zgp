const std = @import("std");
const assert = std.debug.assert;
const zgp_log = std.log.scoped(.zgp);

const PriorityQueue = @import("../../utils/PriorityQueue.zig").PriorityQueue;

const AppContext = @import("../../main.zig").AppContext;
const SurfaceMesh = @import("SurfaceMesh.zig");
const SurfacePoint = @import("SurfacePoint.zig");
const IncidenceGraph = @import("../incidenceGraph/IncidenceGraph.zig");

const vec = @import("../../geometry/vec.zig");
const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const geometry_utils = @import("../../geometry/utils.zig");

const angle = @import("angle.zig");
const area = @import("area.zig");
const laplacian = @import("laplacian.zig");
const distance = @import("distance.zig");
const geodesic = @import("geodesic.zig");

pub const ITContext = struct {
    app_ctx: *AppContext,

    // the extrinsic SurfaceMesh is the triangular mesh on which the intrinsic triangulation is built
    // it is considered as read-only, and its geometry is not modified by the intrinsic triangulation module

    // the intrinsic SurfaceMesh is initialized as a clone of the extrinsic SurfaceMesh
    // each vertex of the extrinsic SurfaceMesh is associated with a vertex of the intrinsic SurfaceMesh, as the operators of the intrinsic triangulation cannot remove any original vertex
    // each vertex of the intrinsic SurfaceMesh is associated with a SurfacePoint on the extrinsic SurfaceMesh which can be of vertex, edge or face type
    // directions of intrinsic halfedges are expressed as angles in the tangent space of the SurfacePoint of the intrinsic halfedge's vertex
    // tangent vectors at SurfacePoints are expressed by an angle w.r.t. the Dart that represents the Cell of the SurfacePoint
    // - for face SurfacePoints, the angle is measured CCW from the direction of the representative Dart of the face ; the value is in [0, 2π) (locally flat)
    // - for edge SurfacePoints, the angle is measured CCW from the direction of the representative Dart of the edge ; the value is in [0, 2π) (locally flat on the 2D layout of the incident faces)
    // - for vertex SurfacePoints, the angle is measured CCW from the direction of the representative Dart of the vertex ; the value is in [0, angle_sum_around_vertex)

    // TODO: manage boundary vertices (the representative Dart of a boundary vertex might not be on the boundary,
    // which causes issues if we want to use it as representative for the angles of the halfedges around the vertex)

    extrinsic_surface_mesh: *SurfaceMesh,
    extrinsic_edge_length: SurfaceMesh.CellData(.edge, f32) = undefined,
    extrinsic_corner_angle: SurfaceMesh.CellData(.corner, f32) = undefined,
    extrinsic_vertex_angle_sum: SurfaceMesh.CellData(.vertex, f32) = undefined,
    // maps each extrinsic vertex to the corresponding intrinsic vertex
    extrinsic_vertex_intrinsic_vertex: SurfaceMesh.CellData(.vertex, SurfaceMesh.Cell) = undefined,

    intrinsic_surface_mesh: *SurfaceMesh = undefined,
    intrinsic_edge_length: SurfaceMesh.CellData(.edge, f32) = undefined,
    intrinsic_corner_angle: SurfaceMesh.CellData(.corner, f32) = undefined,
    intrinsic_face_area: SurfaceMesh.CellData(.face, f32) = undefined,
    intrinsic_halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32) = undefined,
    // each intrinsic vertex is mapped to a SurfacePoint on the extrinsic mesh
    intrinsic_vertex_extrinsic_sp: SurfaceMesh.CellData(.vertex, SurfacePoint) = undefined,
    // each intrinsic halfedge is associated with an angle (tangent vector) that expresses the direction towards the intrinsic vertex on the other side of the edge
    // this angle is expressed in the tangent space of the SurfacePoint of the intrinsic vertex of the intrinsic halfedge
    intrinsic_halfedge_extrinsic_sp_angle: SurfaceMesh.CellData(.halfedge, f32) = undefined,
    // a boolean to mark the edges of the intrinsic triangulation that are also edges of the extrinsic mesh
    intrinsic_edge_is_original: SurfaceMesh.CellData(.edge, bool) = undefined,
    // for each intrinsic edge, we store the trace of the edge as a sequence of SurfacePoints on the extrinsic mesh
    intrinsic_edge_trace: SurfaceMesh.CellData(.edge, std.ArrayList(SurfacePoint)) = undefined,

    pub fn init(
        app_ctx: *AppContext,
        extrinsic_surface_mesh: *SurfaceMesh,
        extrinsic_edge_length: SurfaceMesh.CellData(.edge, f32),
        extrinsic_corner_angle: SurfaceMesh.CellData(.corner, f32),
    ) !ITContext {
        // the 2 following data are created on the extrinsic SurfaceMesh
        // as multiple ITContext can be created for the same extrinsic SurfaceMesh, unique names must be generated for each ITContext
        const extrinsic_vertex_angle_sum = try extrinsic_surface_mesh.addDataWithUniqueRandomName(&app_ctx.rng, .vertex, f32, "angle_sum");
        const extrinsic_vertex_intrinsic_vertex = try extrinsic_surface_mesh.addDataWithUniqueRandomName(&app_ctx.rng, .vertex, SurfaceMesh.Cell, "intrinsic_vertex");

        const intrinsic_surface_mesh = try extrinsic_surface_mesh.cloneWithoutCellData(app_ctx.allocator);
        const intrinsic_edge_length = try intrinsic_surface_mesh.addData(.edge, f32, "length");
        const intrinsic_corner_angle = try intrinsic_surface_mesh.addData(.corner, f32, "corner_angle");
        const intrinsic_face_area = try intrinsic_surface_mesh.addData(.face, f32, "area");
        const intrinsic_halfedge_cotan_weight = try intrinsic_surface_mesh.addData(.halfedge, f32, "cotan_weight");
        const intrinsic_vertex_extrinsic_sp = try intrinsic_surface_mesh.addData(.vertex, SurfacePoint, "extrinsic_sp");
        const intrinsic_halfedge_extrinsic_sp_angle = try intrinsic_surface_mesh.addData(.halfedge, f32, "extrinsic_sp_angle");
        const intrinsic_edge_is_original = try intrinsic_surface_mesh.addData(.edge, bool, "is_original");
        const intrinsic_edge_trace = try intrinsic_surface_mesh.addData(.edge, std.ArrayList(SurfacePoint), "trace");

        // initialize intrinsic edge lengths from extrinsic edge lengths
        // WARNING: direct raw data copy is only possible because the indices coincide after cloning
        intrinsic_edge_length.data.copyFrom(extrinsic_edge_length.data);
        // compute intrinsic corner angles (could be copied from extrinsic corner angles)
        try angle.computeCornerAnglesIntrinsic(app_ctx, intrinsic_surface_mesh, intrinsic_edge_length, intrinsic_corner_angle);
        // compute intrinsic face areas
        try area.computeFaceAreasIntrinsic(app_ctx, intrinsic_surface_mesh, intrinsic_edge_length, intrinsic_face_area);
        // compute intrinsic halfedge cotan weights
        try laplacian.computeHalfedgeCotanWeightsIntrinsic(app_ctx, intrinsic_surface_mesh, intrinsic_edge_length, intrinsic_face_area, intrinsic_halfedge_cotan_weight);

        // initialize extrinsic to intrinsic vertex mapping & intrinsic vertex extrinsic SurfacePoint (all are initially of vertex type, i.e. sit on extrinsic vertices)
        // initialize intrinsic halfedge extrinsic SurfacePoint angle (expressed in the underlying SurfacePoint tangent space)
        // initialize extrinsic vertex angle sums
        var int_vertex_it: SurfaceMesh.CellIterator = try .init(intrinsic_surface_mesh, .vertex);
        defer int_vertex_it.deinit();
        while (int_vertex_it.next()) |v| {
            // WARNING: the following code relies on the fact that after cloning, intrinsic vertex v.dart() is equal to extrinsic vertex v.dart()
            extrinsic_vertex_intrinsic_vertex.valuePtr(v).* = v; // WARNING: this mapping must be updated after intrinsic edge flips (the representative Dart of the intrinsic vertex might have moved to a different vertex)
            intrinsic_vertex_extrinsic_sp.valuePtr(v).* = .{
                .surface_mesh = extrinsic_surface_mesh,
                .type = .{ .vertex = v },
            };
            // v.dart() is the representative Dart of the vertex (its halfedge angle is 0 within the tangent space of the SurfacePoint)
            // the CellDartIterator iterates around the vertex in CCW order starting from this Dart
            var angle_sum: f32 = 0.0;
            var d_it = intrinsic_surface_mesh.cellDartIterator(v);
            while (d_it.next()) |d| {
                intrinsic_halfedge_extrinsic_sp_angle.valuePtr(.{ .halfedge = d }).* = angle_sum;
                angle_sum += extrinsic_corner_angle.value(.{ .corner = d });
            }
            extrinsic_vertex_angle_sum.valuePtr(v).* = angle_sum;
        }
        // initialize intrinsic edge data:
        // - original edge boolean
        // - edge traces (empty for now)
        var int_edge_it: SurfaceMesh.CellIterator = try .init(intrinsic_surface_mesh, .edge);
        defer int_edge_it.deinit();
        while (int_edge_it.next()) |e| {
            intrinsic_edge_is_original.valuePtr(e).* = true; // all edges are original after cloning
            intrinsic_edge_trace.valuePtr(e).* = .empty;
        }

        return .{
            .app_ctx = app_ctx,

            .extrinsic_surface_mesh = extrinsic_surface_mesh,
            .extrinsic_edge_length = extrinsic_edge_length,
            .extrinsic_corner_angle = extrinsic_corner_angle,
            .extrinsic_vertex_angle_sum = extrinsic_vertex_angle_sum,
            .extrinsic_vertex_intrinsic_vertex = extrinsic_vertex_intrinsic_vertex,

            .intrinsic_surface_mesh = intrinsic_surface_mesh,
            .intrinsic_edge_length = intrinsic_edge_length,
            .intrinsic_corner_angle = intrinsic_corner_angle,
            .intrinsic_face_area = intrinsic_face_area,
            .intrinsic_halfedge_cotan_weight = intrinsic_halfedge_cotan_weight,
            .intrinsic_vertex_extrinsic_sp = intrinsic_vertex_extrinsic_sp,
            .intrinsic_halfedge_extrinsic_sp_angle = intrinsic_halfedge_extrinsic_sp_angle,
            .intrinsic_edge_is_original = intrinsic_edge_is_original,
            .intrinsic_edge_trace = intrinsic_edge_trace,
        };
    }

    pub fn deinit(it_ctx: *ITContext) void {
        var edge_it = SurfaceMesh.CellIterator.init(it_ctx.intrinsic_surface_mesh, .edge) catch |err| {
            std.debug.print("Error creating edge iterator in ITData deinit: {}\n", .{err});
            return;
        };
        while (edge_it.next()) |e| {
            it_ctx.intrinsic_edge_trace.valuePtr(e).deinit(it_ctx.app_ctx.allocator);
        }
        edge_it.deinit(); // this deinit is not deferred because it must be called before the intrinsic_surface_mesh is deinit and destroyed

        it_ctx.intrinsic_surface_mesh.deinit();
        it_ctx.app_ctx.allocator.destroy(it_ctx.intrinsic_surface_mesh);

        it_ctx.extrinsic_surface_mesh.removeData(.vertex, f32, it_ctx.extrinsic_vertex_angle_sum);
        it_ctx.extrinsic_surface_mesh.removeData(.vertex, SurfaceMesh.Cell, it_ctx.extrinsic_vertex_intrinsic_vertex);
    }

    // flip the given edge and update the intrinsic geometry data accordingly
    fn flipEdge(it_ctx: *const ITContext, edge: SurfaceMesh.Cell) void {
        assert(edge.cellType() == .edge);
        assert(it_ctx.intrinsic_surface_mesh.canFlipEdge(edge));

        const dA0 = edge.dart();
        const dA1 = it_ctx.intrinsic_surface_mesh.phi1(dA0);
        const dA2 = it_ctx.intrinsic_surface_mesh.phi_1(dA0);
        const dB0 = it_ctx.intrinsic_surface_mesh.phi2(dA0);
        const dB1 = it_ctx.intrinsic_surface_mesh.phi1(dB0);
        const dB2 = it_ctx.intrinsic_surface_mesh.phi_1(dB0);
        const darts: [6]SurfaceMesh.Dart = .{ dA0, dA1, dA2, dB0, dB1, dB2 };

        // compute flipped edge length using intrinsic geometry (the flipped edge is p0-p2)
        //    p2---p1
        //   /  \  /
        // p3----p0
        const l01 = it_ctx.intrinsic_edge_length.value(.{ .edge = dA1 });
        const l12 = it_ctx.intrinsic_edge_length.value(.{ .edge = dA2 });
        const l23 = it_ctx.intrinsic_edge_length.value(.{ .edge = dB1 });
        const l30 = it_ctx.intrinsic_edge_length.value(.{ .edge = dB2 });
        const l02 = it_ctx.intrinsic_edge_length.value(.{ .edge = dA0 });
        const p3: Vec2f = .{ 0.0, 0.0 };
        const p0: Vec2f = .{ l30, 0.0 };
        const p2 = geometry_utils.layoutTriangleVertex(p3, p0, l02, l23);
        const p1 = geometry_utils.layoutTriangleVertex(p2, p0, l01, l12);
        const l13 = vec.norm2f(vec.sub2f(p3, p1));

        // flip the edge
        it_ctx.intrinsic_surface_mesh.flipEdge(edge);
        it_ctx.intrinsic_edge_is_original.valuePtr(edge).* = false; // the flipped edge is not original anymore

        // update intrinsic edge length
        it_ctx.intrinsic_edge_length.valuePtr(edge).* = l13;
        // update intrinsic face areas of the 2 faces incident to the flipped edge
        it_ctx.intrinsic_face_area.valuePtr(.{ .face = dA0 }).* = geometry_utils.triangleAreaIntrinsic(l12, l23, l13);
        it_ctx.intrinsic_face_area.valuePtr(.{ .face = dB0 }).* = geometry_utils.triangleAreaIntrinsic(l30, l01, l13);
        // update :
        // - intrinsic halfedge cotan weights of the 6 halfedges of the two incident faces
        // - intrinsic corner angles of the 6 corners of the two incident faces
        for (darts) |d| {
            const he: SurfaceMesh.Cell = .{ .halfedge = d };
            it_ctx.intrinsic_halfedge_cotan_weight.valuePtr(he).* = laplacian.halfedgeCotanWeightIntrinsic(
                it_ctx.intrinsic_surface_mesh,
                he,
                it_ctx.intrinsic_edge_length,
                it_ctx.intrinsic_face_area,
            );
            const corner: SurfaceMesh.Cell = .{ .corner = d };
            it_ctx.intrinsic_corner_angle.valuePtr(corner).* = angle.cornerAngleIntrinsic(
                it_ctx.intrinsic_surface_mesh,
                corner,
                it_ctx.intrinsic_edge_length,
            );
        }
        // update intrinsic halfedge SurfacePoint angles of the flipped halfedges
        it_ctx.intrinsic_halfedge_extrinsic_sp_angle.valuePtr(.{ .halfedge = dA0 }).* =
            it_ctx.intrinsic_halfedge_extrinsic_sp_angle.valuePtr(.{ .halfedge = dB2 }).* + it_ctx.intrinsic_corner_angle.value(.{ .corner = dB2 });
        it_ctx.intrinsic_halfedge_extrinsic_sp_angle.valuePtr(.{ .halfedge = dB0 }).* =
            it_ctx.intrinsic_halfedge_extrinsic_sp_angle.valuePtr(.{ .halfedge = dA2 }).* + it_ctx.intrinsic_corner_angle.value(.{ .corner = dA2 });

        // if the endpoints of the flipped edge are mapped to extrinsic vertices (SurfacePoints of vertex type), then the extrinsic to intrinsic vertex mapping must be updated
        // (the representative Dart of the intrinsic vertex might be the flipped edge's Dart, which has moved to a different vertex after the flip)
        const p0sp = it_ctx.intrinsic_vertex_extrinsic_sp.value(.{ .vertex = dA1 });
        if (p0sp.type == .vertex) {
            it_ctx.extrinsic_vertex_intrinsic_vertex.valuePtr(p0sp.type.vertex).* = .{ .vertex = dA1 };
        }
        const p2sp = it_ctx.intrinsic_vertex_extrinsic_sp.value(.{ .vertex = dB1 });
        if (p2sp.type == .vertex) {
            it_ctx.extrinsic_vertex_intrinsic_vertex.valuePtr(p2sp.type.vertex).* = .{ .vertex = dB1 };
        }
    }

    fn traceIntrinsicEdgesInIncidenceGraph(
        it_ctx: *ITContext,
        extrinsic_vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        ig: *IncidenceGraph,
        ig_vertex_position: IncidenceGraph.CellData(.vertex, Vec3f),
    ) !void {
        // clear the intrinsic edges incidence graph
        ig.clearRetainingCapacity();

        var edge_it: SurfaceMesh.CellIterator = try .init(it_ctx.intrinsic_surface_mesh, .edge);
        defer edge_it.deinit();
        while (edge_it.next()) |e| {
            const d = e.dart();

            const src_sp = it_ctx.intrinsic_vertex_extrinsic_sp.value(.{ .vertex = d });
            const dst_sp = it_ctx.intrinsic_vertex_extrinsic_sp.value(.{ .vertex = it_ctx.intrinsic_surface_mesh.phi2(d) });

            // original edges trace trivially
            if (it_ctx.intrinsic_edge_is_original.value(e)) {
                try it_ctx.intrinsic_edge_trace.valuePtr(e).append(it_ctx.app_ctx.allocator, src_sp);
                try it_ctx.intrinsic_edge_trace.valuePtr(e).append(it_ctx.app_ctx.allocator, dst_sp);

                // add the vertices and edge to the common subdivision incidence graph
                const p1 = src_sp.readData(Vec3f, .vertex, extrinsic_vertex_position);
                const p2 = dst_sp.readData(Vec3f, .vertex, extrinsic_vertex_position);
                const igv1 = try ig.addVertex();
                const igv2 = try ig.addVertex();
                ig_vertex_position.valuePtr(igv1).* = p1;
                ig_vertex_position.valuePtr(igv2).* = p2;
                _ = try ig.addEdge(igv1, igv2);

                continue;
            }

            // trace the intrinsic edge on the extrinsic mesh
            _ = try geodesic.traceGeodesic(
                it_ctx.app_ctx,
                it_ctx.extrinsic_surface_mesh,
                src_sp,
                it_ctx.intrinsic_halfedge_extrinsic_sp_angle.value(.{ .halfedge = d }),
                it_ctx.intrinsic_edge_length.value(e),
                it_ctx.extrinsic_corner_angle,
                it_ctx.extrinsic_edge_length,
                it_ctx.intrinsic_edge_trace.valuePtr(e),
            );

            // TODO: trim the trace to remove spurious SurfacePoints that are on the edges
            // incident to the destination vertex of the intrinsic edge
            // and snap the last SurfacePoint to the destination vertex of the intrinsic edge

            // add the vertices and edges of the trace to the common subdivision incidence graph
            var previous_sp: ?SurfacePoint = null;
            var previous_igv: ?IncidenceGraph.Cell = null;
            for (it_ctx.intrinsic_edge_trace.value(e).items) |sp| {
                const pos = sp.readData(Vec3f, .vertex, extrinsic_vertex_position);
                const igv = try ig.addVertex();
                ig_vertex_position.valuePtr(igv).* = pos;
                if (previous_sp) |_| {
                    _ = try ig.addEdge(igv, previous_igv.?);
                }
                previous_sp = sp;
                previous_igv = igv;
            }
        }
    }

    // ==================================
    // === FLIP-TO-DELAUNAY ALGORITHM ===
    // ==================================

    pub fn flipToDelaunay(it_ctx: *const ITContext) !void {
        var edges_queue: std.ArrayList(SurfaceMesh.Cell) = try .initCapacity(it_ctx.app_ctx.allocator, it_ctx.intrinsic_surface_mesh.nbCells(.edge));
        defer edges_queue.deinit(it_ctx.app_ctx.allocator);
        var edge_it: SurfaceMesh.CellIterator = try .init(it_ctx.intrinsic_surface_mesh, .edge);
        defer edge_it.deinit();
        while (edge_it.next()) |e| {
            try edges_queue.append(it_ctx.app_ctx.allocator, e); // all edges are initially added to the queue
        }
        try flipEdgesToDelaunay(it_ctx, &edges_queue, null);
    }

    pub fn flipEdgesToDelaunay(
        it_ctx: *const ITContext,
        edges_queue: *std.ArrayList(SurfaceMesh.Cell),
        callbacks: anytype, // can define `beforeEdgeFlip(edge: SurfaceMesh.Cell) void` and `afterEdgeFlip(edge: SurfaceMesh.Cell) void`
    ) !void {
        var edge_in_queue: SurfaceMesh.CellMarker = try .init(it_ctx.intrinsic_surface_mesh, .edge);
        defer edge_in_queue.deinit();
        for (edges_queue.items) |e| {
            edge_in_queue.mark(e);
        }

        var nb_flips: u32 = 0;

        while (edges_queue.pop()) |e| {
            edge_in_queue.unmark(e);
            // check if the edge can flip (i.e. not a boundary edge and incident vertices of degree > 2)
            if (!it_ctx.intrinsic_surface_mesh.canFlipEdge(e)) {
                continue;
            }

            const edge_cotan_weight = laplacian.edgeCotanWeight(it_ctx.intrinsic_surface_mesh, e, it_ctx.intrinsic_halfedge_cotan_weight);
            // TODO: all the isFinite checks in this file are a workaround for numerical issues, should be fixed properly by using more robust geometric predicates
            if (!std.math.isFinite(edge_cotan_weight)) {
                continue;
            }
            // do not flip already Delaunay edges
            // tolerate near-zero negatives to avoid numerical ping-pong flips on almost cocircular configurations
            if (edge_cotan_weight >= -geometry_utils.epsilon) {
                continue;
            }

            // non-Delaunay edges are contained in convex quadrilaterals, so there is no need to check for convexity before flipping

            if (comptime std.meta.hasFn(@TypeOf(callbacks), "beforeEdgeFlip")) {
                callbacks.beforeEdgeFlip(e);
            }

            // flip the edge (updates the intrinsic geometry data accordingly)
            it_ctx.flipEdge(e);
            nb_flips += 1;

            if (comptime std.meta.hasFn(@TypeOf(callbacks), "afterEdgeFlip")) {
                callbacks.afterEdgeFlip(e);
            }

            // the 4 incident edges of the flipped edge might not be Delaunay anymore, so we add them to the queue if they are not already
            const d = e.dart();
            const dd = it_ctx.intrinsic_surface_mesh.phi2(d);
            const edges: [4]SurfaceMesh.Cell = .{
                .{ .edge = it_ctx.intrinsic_surface_mesh.phi1(d) },
                .{ .edge = it_ctx.intrinsic_surface_mesh.phi_1(d) },
                .{ .edge = it_ctx.intrinsic_surface_mesh.phi1(dd) },
                .{ .edge = it_ctx.intrinsic_surface_mesh.phi_1(dd) },
            };
            for (edges) |edge| {
                if (!edge_in_queue.isMarked(edge)) {
                    try edges_queue.append(it_ctx.app_ctx.allocator, edge);
                    edge_in_queue.mark(edge);
                }
            }
        }

        zgp_log.info("Flipped {d} edges to intrinsic Delaunay", .{nb_flips});
    }

    // ============================================
    // === FLIP-OUT SHORTEST GEODESIC ALGORITHM ===
    // ============================================

    // Priority queue type for joints of the path, ordered by their ascending minimum wedge angle (to flip out the most "bent" joints first)
    const JointQueueContext = struct {
        joint_queue_index: SurfaceMesh.CellData(.halfedge, ?usize),
    };
    // a Joint is associated to a Dart of the path (except the first Dart)
    // the index of a Joint in the queue is stored in the joint_queue_index data of the halfedge of the Dart
    // - dart is the Dart of the path that belongs to the Joint vertex
    // - prev_dart is the Dart of the path that precedes the Dart of the Joint
    // - min_angle is the minimum angle formed by one of the two wedges between the incoming and outgoing halfedges of the joint
    // - min_angle_side is the side of the minimum angle wedge (left or right)
    // - flippable is a boolean that indicates whether the joint is flippable
    //   -> non-flippable joints include non-flexible joints (i.e. where an edge incident to the joint vertex in the smallest wedge is part of the path) and already straight joints
    //   -> these joints are nonetheless put in the queue so that they can be updated when the path changes and they could become flippable
    // the queue is ordered by ascending min_angle, so that the most "bent" joints are flipped first
    // execution finishes when the queue is empty or all remaining joints are non-flippable (i.e. the path is locally shortest)
    const JointInfo = struct {
        dart: SurfaceMesh.Dart,
        prev_dart: SurfaceMesh.Dart, // the first Dart of the path is not a joint, so prev_dart is always defined
        next_dart: ?SurfaceMesh.Dart, // the next Dart of the path after dart (null if dart is the last Dart of the path)
        min_angle: f32,
        min_angle_side: enum { left, right },
        flippable: bool,
        pub fn cmp(_: JointQueueContext, a: JointInfo, b: JointInfo) std.math.Order {
            const min_angle_order = std.math.order(a.min_angle, b.min_angle);
            if (min_angle_order != .eq) return min_angle_order;
            // tie-breaker: use dart indices to have a deterministic order
            return std.math.order(a.dart, b.dart);
        }
        pub fn setJointIndexInQueue(ctx: JointQueueContext, a: JointInfo, index: usize) void {
            ctx.joint_queue_index.valuePtr(.{ .halfedge = a.dart }).* = index;
        }
    };
    const JointQueue = PriorityQueue(JointInfo, JointQueueContext, JointInfo.cmp, JointInfo.setJointIndexInQueue);
    const JointQueueUtils = struct {
        fn addJointToQueue(it_ctx: *ITContext, queue: *JointQueue, d: SurfaceMesh.Dart, prev_d: SurfaceMesh.Dart, next_d: ?SurfaceMesh.Dart) !void {
            // assert that the joint is not already in the queue
            assert(queue.context.joint_queue_index.value(.{ .halfedge = d }) == null);
            // angles of the incoming and outgoing halfedges of the joint (expressed in the tangent space of the SurfacePoint of the vertex of the joint)
            const angle_in = it_ctx.intrinsic_halfedge_extrinsic_sp_angle.value(.{ .halfedge = it_ctx.intrinsic_surface_mesh.phi2(prev_d) });
            const angle_out = it_ctx.intrinsic_halfedge_extrinsic_sp_angle.value(.{ .halfedge = d });
            const angle_sum = switch (it_ctx.intrinsic_vertex_extrinsic_sp.value(.{ .vertex = d }).type) {
                .vertex => |v| it_ctx.extrinsic_vertex_angle_sum.value(v),
                else => std.math.tau, // for non-vertex SurfacePoints, the angle sum is 2π (locally flat)
            };
            const left_angle = if (angle_out < angle_in) angle_in - angle_out else angle_sum - angle_out + angle_in;
            const right_angle = if (angle_in < angle_out) angle_out - angle_in else angle_sum - angle_in + angle_out;
            if (left_angle < right_angle and left_angle < std.math.pi - geometry_utils.epsilon) {
                // the min angle wedge should contain at least one other edge between the incoming and outgoing halfedges of the joint (otherwise the joint is not flippable)
                // TODO: should also check that no edge in the min angle wedge is part of the path, otherwise the joint is not flippable
                const flippable = d != it_ctx.intrinsic_surface_mesh.phi1(prev_d);
                try queue.push(it_ctx.app_ctx.allocator, .{
                    .dart = d,
                    .prev_dart = prev_d,
                    .next_dart = next_d,
                    .min_angle = if (flippable) left_angle else std.math.tau, // greater than π, so that non-flippable joints are at the end of the queue
                    .min_angle_side = .left,
                    .flippable = flippable,
                });
            } else if (right_angle < left_angle and right_angle < std.math.pi - geometry_utils.epsilon) {
                const flippable = d != it_ctx.intrinsic_surface_mesh.phi2(it_ctx.intrinsic_surface_mesh.phi_1(it_ctx.intrinsic_surface_mesh.phi2(prev_d)));
                try queue.push(it_ctx.app_ctx.allocator, .{
                    .dart = d,
                    .prev_dart = prev_d,
                    .next_dart = next_d,
                    .min_angle = if (flippable) right_angle else std.math.tau, // greater than π, so that non-flippable joints are at the end of the queue
                    .min_angle_side = .right,
                    .flippable = flippable,
                });
            } else {
                try queue.push(it_ctx.app_ctx.allocator, .{
                    .dart = d,
                    .prev_dart = prev_d,
                    .next_dart = next_d,
                    .min_angle = std.math.tau, // greater than π, so that non-flippable joints are at the end of the queue
                    .min_angle_side = .left, // arbitrary
                    .flippable = false,
                });
            }
        }
    };

    const FlipOutShortestGeodesicContext = struct {
        it_ctx: *ITContext,
        sep_ctx: distance.ShortestEdgePathContext,
        joint_queue_index: SurfaceMesh.CellData(.halfedge, ?usize),
        joint_queue: JointQueue,

        pub fn init(it_ctx: *ITContext) FlipOutShortestGeodesicContext {
            const joint_queue_index = try it_ctx.intrinsic_surface_mesh.addData(.halfedge, ?usize, "__joint_queue_index");
            const joint_queue: JointQueue = .initContext(.{
                .joint_queue_index = joint_queue_index,
            });
            const sep_ctx: distance.ShortestEdgePathContext = .init(it_ctx.intrinsic_surface_mesh, it_ctx.intrinsic_edge_length);

            return .{
                .it_ctx = it_ctx,
                .sep_ctx = sep_ctx,
                .joint_queue_index = joint_queue_index,
                .joint_queue = joint_queue,
            };
        }

        pub fn deinit(flipout_ctx: *FlipOutShortestGeodesicContext) void {
            flipout_ctx.sep_ctx.deinit();
            flipout_ctx.joint_queue.deinit(flipout_ctx.it_ctx.app_ctx.allocator);
            flipout_ctx.it_ctx.intrinsic_surface_mesh.removeData(.halfedge, ?usize, flipout_ctx.joint_queue_index);
        }

        // performs intrinsic edge flips to shorten the path between the two given intrinsic vertices
        // TODO: manage boundary (for now, assumes that the path is not on the boundary)
        pub fn flipOutShortestGeodesic(
            flipout_ctx: *FlipOutShortestGeodesicContext,
            int_v_start: SurfaceMesh.Cell,
            int_v_end: SurfaceMesh.Cell,
            new_path: ?*std.ArrayList(SurfaceMesh.Dart), // if provided, filled with the new path after shortening
            performed_flips: ?*std.ArrayList(SurfaceMesh.Cell), // if provided, filled with the edges that were flipped during the shortening process)
        ) !void {
            flipout_ctx.joint_queue_index.data.fill(null);

            if (performed_flips) |p| {
                p.clearRetainingCapacity();
            }

            const it_ctx = flipout_ctx.it_ctx;

            // compute the shortest edge path between the two intrinsic vertices
            var path = try flipout_ctx.sep_ctx.shortestEdgePathBetweenVertices(
                flipout_ctx.it_ctx.app_ctx.allocator,
                int_v_start,
                int_v_end,
            );
            defer path.deinit(it_ctx.app_ctx.allocator);
            if (path.items.len == 0) {
                return error.NoPathFoundBetweenVertices;
            }
            if (path.items.len == 1) {
                // the two vertices are connected by a single edge, so the path cannot be shortened
                if (new_path) |p| {
                    p.clearRetainingCapacity();
                    try p.append(it_ctx.app_ctx.allocator, path.items[0]);
                }
                return;
            }

            // initialize the joint queue with the joints of the path
            for (path.items, 0..) |d, idx| {
                if (idx == 0) continue; // skip the first Dart of the path, as it is not a joint
                const prev_d = path.items[idx - 1];
                const next_d = if (idx + 1 < path.items.len) path.items[idx + 1] else null;
                // assert the consistency of the path (the vertex of d must be the same as the vertex of phi1(prev_d))
                assert(it_ctx.intrinsic_surface_mesh.cellIndex(.{ .vertex = d }) == it_ctx.intrinsic_surface_mesh.cellIndex(.{ .vertex = it_ctx.intrinsic_surface_mesh.phi1(prev_d) }));
                try JointQueueUtils.addJointToQueue(it_ctx, flipout_ctx.joint_queue, d, prev_d, next_d);
            }

            // maintenance of these variables is only useful for the final new_path construction
            var first_path_dart = path.items[0];
            var first_joint_dart: ?SurfaceMesh.Dart = path.items[1]; // the first Dart of the path is not a joint, so the first joint is the second Dart of the path

            while (flipout_ctx.joint_queue.items.len > 0) {
                // // check path global consistency (following the info found in the queue)
                // var nb_joints: u32 = 0;
                // var cur_dart: ?SurfaceMesh.Dart = first_joint_dart;
                // var prev_dart: SurfaceMesh.Dart = first_path_dart;
                // while (cur_dart) |d| {
                //     const cur_joint_index = joint_queue_index.value(.{ .halfedge = d });
                //     assert(cur_joint_index != null);
                //     const joint = queue.items[cur_joint_index.?];
                //     assert(joint.dart == d);
                //     assert(joint.prev_dart == prev_dart);
                //     assert(itc.intrinsic_surface_mesh.cellIndex(.{ .vertex = joint.dart }) == itc.intrinsic_surface_mesh.cellIndex(.{ .vertex = itc.intrinsic_surface_mesh.phi1(joint.prev_dart) }));
                //     nb_joints += 1;
                //     prev_dart = cur_dart.?;
                //     cur_dart = joint.next_dart;
                // }
                // assert(nb_joints == queue.items.len);

                // if all the joints left in the queue are non-flippable, then the path is locally shortest and we can stop
                const no_flippable_joint = for (flipout_ctx.joint_queue.items) |joint| {
                    if (joint.flippable) break false;
                } else true;
                if (no_flippable_joint) {
                    std.debug.print("No flippable joint left in the queue, path is locally shortest with {} joints left\n", .{flipout_ctx.joint_queue.items.len});
                    break;
                }

                const joint = flipout_ctx.joint_queue.pop().?;
                flipout_ctx.joint_queue_index.valuePtr(.{ .halfedge = joint.dart }).* = null; // the joint is no longer in the priority queue
                assert(joint.flippable); // if there is still at least one flippable joint in the queue, it must be the one with the smallest minimum angle

                // the flip out is performed CW in the min angle wedge, so consider the joint in the other orientation if the min angle wedge is on the right side of the path
                // (the new path will be reversed when inserting the new subpath after the flips)
                const cw_dart, const cw_prev_dart = if (joint.min_angle_side == .left)
                    .{ joint.dart, joint.prev_dart }
                else
                    .{ it_ctx.intrinsic_surface_mesh.phi2(joint.prev_dart), it_ctx.intrinsic_surface_mesh.phi2(joint.dart) };

                var cw_cur_dart = it_ctx.intrinsic_surface_mesh.phi1(cw_prev_dart);
                while (cw_cur_dart != cw_dart) {
                    // check if the edge can flip (i.e. not a boundary edge and incident vertices of degree > 2)
                    if (!it_ctx.intrinsic_surface_mesh.canFlipEdge(.{ .edge = cw_cur_dart })) {
                        cw_cur_dart = it_ctx.intrinsic_surface_mesh.phi1(it_ctx.intrinsic_surface_mesh.phi2(cw_cur_dart));
                        continue;
                    }
                    // do not flip if the edge is not in a convex quadrilateral (i.e. if the sum of the two corner angles opposite to the joint is greater than or equal to π)
                    if (it_ctx.intrinsic_corner_angle.value(.{ .corner = it_ctx.intrinsic_surface_mesh.phi1(cw_cur_dart) }) + it_ctx.intrinsic_corner_angle.value(.{ .corner = it_ctx.intrinsic_surface_mesh.phi2(cw_cur_dart) }) >= std.math.pi - geometry_utils.epsilon) {
                        cw_cur_dart = it_ctx.intrinsic_surface_mesh.phi1(it_ctx.intrinsic_surface_mesh.phi2(cw_cur_dart));
                        continue;
                    }
                    it_ctx.flipEdge(.{ .edge = cw_cur_dart });
                    if (performed_flips) |p| {
                        try p.append(it_ctx.app_ctx.allocator, .{ .edge = cw_cur_dart });
                    }
                    cw_cur_dart = it_ctx.intrinsic_surface_mesh.phi_1(cw_cur_dart);
                }

                // build the new subpath
                var new_subpath: std.ArrayList(SurfaceMesh.Dart) = .empty;
                defer new_subpath.deinit(it_ctx.app_ctx.allocator);
                cw_cur_dart = it_ctx.intrinsic_surface_mesh.phi1(cw_prev_dart);
                while (true) : ({
                    if (cw_cur_dart == cw_dart) break;
                    cw_cur_dart = it_ctx.intrinsic_surface_mesh.phi1(it_ctx.intrinsic_surface_mesh.phi2(cw_cur_dart));
                }) {
                    try new_subpath.append(it_ctx.app_ctx.allocator, it_ctx.intrinsic_surface_mesh.phi2(it_ctx.intrinsic_surface_mesh.phi1(cw_cur_dart)));
                }
                // reverse the new subpath if the min angle wedge was on the right side of the path (so that it can be inserted in the correct orientation)
                if (joint.min_angle_side == .right) {
                    std.mem.reverse(SurfaceMesh.Dart, new_subpath.items);
                    for (new_subpath.items) |*d| {
                        d.* = it_ctx.intrinsic_surface_mesh.phi2(d.*);
                    }
                }
                assert(new_subpath.items.len > 0); // the new subpath must contain at least one Dart

                if (first_joint_dart != null and first_joint_dart.? == joint.dart) {
                    first_path_dart = new_subpath.items[0];
                    first_joint_dart = if (new_subpath.items.len > 1) new_subpath.items[1] else joint.next_dart;
                } else if (first_joint_dart != null and first_joint_dart.? == joint.prev_dart) {
                    // the previous joint was the first joint and has been removed from the queue;
                    // the first dart of the new subpath takes its place as the new first joint
                    first_joint_dart = new_subpath.items[0];
                    // first_path_dart doesn't change: prev_prev_dart != null here, so new_subpath[0] is added as a joint
                }

                // update the joint queue (the current joint has already been removed from the queue)

                // the previous joint (if it exists) must be removed from the queue
                // it will be replaced by the first new joint of the new subpath (with updated min angle, side and flippable status)
                // we first need to get its previous Dart in the path (the Dart that precedes joint.prev_dart) to be able to add the first new joint to the queue
                var prev_prev_dart: ?SurfaceMesh.Dart = null;
                // if joint.prev_dart is the first Dart of the path (i.e. joint is the first joint), joint.prev_dart is not a joint and prev_prev_dart will remain null
                if (flipout_ctx.joint_queue_index.value(.{ .halfedge = joint.prev_dart })) |index| {
                    prev_prev_dart = flipout_ctx.joint_queue.items[index].prev_dart;
                    // the joint at prev_prev_dart (if it's in the queue) still has next_dart pointing to the to-be-removed joint.prev_dart;
                    // update it in-place to the first dart of the new subpath (next_dart is not part of the priority comparison so the heap is unaffected)
                    if (flipout_ctx.joint_queue_index.value(.{ .halfedge = prev_prev_dart.? })) |ppd_idx| {
                        flipout_ctx.joint_queue.items[ppd_idx].next_dart = new_subpath.items[0];
                    }
                    _ = flipout_ctx.joint_queue.popIndex(index);
                    flipout_ctx.joint_queue_index.valuePtr(.{ .halfedge = joint.prev_dart }).* = null;
                }
                for (new_subpath.items, 0..) |d, idx| {
                    if (idx == 0 and prev_prev_dart == null) continue; // the first Dart of the new subpath is the first Dart of the path, so it is not a joint
                    const prev_d: SurfaceMesh.Dart = if (idx == 0) prev_prev_dart.? else new_subpath.items[idx - 1];
                    const next_d = if (idx + 1 < new_subpath.items.len) new_subpath.items[idx + 1] else joint.next_dart;
                    // assert the consistency of the path (the vertex of d must be the same as the vertex of phi1(prev_d))
                    assert(it_ctx.intrinsic_surface_mesh.cellIndex(.{ .vertex = d }) == it_ctx.intrinsic_surface_mesh.cellIndex(.{ .vertex = it_ctx.intrinsic_surface_mesh.phi1(prev_d) }));
                    try JointQueueUtils.addJointToQueue(it_ctx, flipout_ctx.joint_queue, d, prev_d, next_d);
                }
                // the next joint (if it exists) must be removed from the queue and added again (with updated prev_dart, min angle, side and flippable status)
                if (joint.next_dart) |next_dart| {
                    const next_joint_index = flipout_ctx.joint_queue_index.value(.{ .halfedge = next_dart });
                    assert(next_joint_index != null); // if the current joint has a next dart, the corresponding next joint must be in the queue
                    const next_joint = flipout_ctx.joint_queue.items[next_joint_index.?];
                    _ = flipout_ctx.joint_queue.popIndex(next_joint_index.?);
                    flipout_ctx.joint_queue_index.valuePtr(.{ .halfedge = next_dart }).* = null;
                    const next_prev_d = new_subpath.items[new_subpath.items.len - 1]; // the previous Dart of the next joint is now the last Dart of the new subpath
                    const next_next_d = next_joint.next_dart; // the next Dart of the next joint is not affected by the flips, so it remains the same (potentially null if the next joint was the last joint of the path)
                    // assert the consistency of the path (the vertex of next_dart must be the same as the vertex of phi1(next_prev_d))
                    assert(it_ctx.intrinsic_surface_mesh.cellIndex(.{ .vertex = next_dart }) == it_ctx.intrinsic_surface_mesh.cellIndex(.{ .vertex = it_ctx.intrinsic_surface_mesh.phi1(next_prev_d) }));
                    try JointQueueUtils.addJointToQueue(it_ctx, flipout_ctx.joint_queue, next_dart, next_prev_d, next_next_d);
                }
            }

            if (new_path) |p| {
                p.clearRetainingCapacity();
                try p.append(it_ctx.app_ctx.allocator, first_path_dart);
                var cur_dart: ?SurfaceMesh.Dart = first_joint_dart;
                while (cur_dart) |d| {
                    try p.append(it_ctx.app_ctx.allocator, d);
                    const cur_joint_index = flipout_ctx.joint_queue_index.value(.{ .halfedge = d });
                    const joint = flipout_ctx.joint_queue.items[cur_joint_index.?];
                    cur_dart = joint.next_dart;
                }
            }
        }
    };

    // =====================================
    // === DELAUNAY REFINEMENT ALGORITHM ===
    // =====================================

    // computes the squared circumradius-to-shortest-edge ratio of a triangle
    // it is used as a cost in the priority queue of triangles in the Delaunay refinement algorithm
    pub fn triangleCircumradiusToShortestEdgeRatioSquared(
        it_ctx: *ITContext,
        tri: SurfaceMesh.Cell,
    ) f32 {
        const t_area = it_ctx.intrinsic_face_area.value(tri);
        const l_v0v1 = it_ctx.intrinsic_edge_length.value(.{ .edge = tri.dart() });
        const l_v1v2 = it_ctx.intrinsic_edge_length.value(.{ .edge = it_ctx.intrinsic_surface_mesh.phi1(tri.dart()) });
        const l_v2v0 = it_ctx.intrinsic_edge_length.value(.{ .edge = it_ctx.intrinsic_surface_mesh.phi_1(tri.dart()) });

        // Prevent division by zero for degenerate triangles (zero area)
        if (t_area < geometry_utils.epsilon) return std.math.inf(f32);

        const l_v0v1_sq = l_v0v1 * l_v0v1;
        const l_v1v2_sq = l_v1v2 * l_v1v2;
        const l_v2v0_sq = l_v2v0 * l_v2v0;
        const l_min_sq = @min(l_v0v1_sq, @min(l_v1v2_sq, l_v2v0_sq));
        return (l_v0v1_sq * l_v1v2_sq * l_v2v0_sq) / (16.0 * t_area * t_area * l_min_sq);
    }

    pub fn refineDelaunay(it_ctx: *ITContext, angle_threshold: f32) !void {
        var flip_edge_queue: std.ArrayList(SurfaceMesh.Cell) = try .initCapacity(it_ctx.app_ctx.allocator, it_ctx.intrinsic_surface_mesh.nbCells(.edge));
        defer flip_edge_queue.deinit(it_ctx.app_ctx.allocator);
        var edge_it: SurfaceMesh.CellIterator = try .init(it_ctx.intrinsic_surface_mesh, .edge);
        defer edge_it.deinit();
        while (edge_it.next()) |e| {
            try flip_edge_queue.append(it_ctx.app_ctx.allocator, e);
        }

        // check that no triangle has near zero area
        var face_it2: SurfaceMesh.CellIterator = try .init(it_ctx.intrinsic_surface_mesh, .face);
        defer face_it2.deinit();
        while (face_it2.next()) |f| {
            if (it_ctx.intrinsic_face_area.value(f) < geometry_utils.epsilon) {
                return error.TriangleHasNearZeroArea;
            }
        }
        // and that no edge has near zero length
        var edge_it2: SurfaceMesh.CellIterator = try .init(it_ctx.intrinsic_surface_mesh, .edge);
        defer edge_it2.deinit();
        while (edge_it2.next()) |e| {
            if (it_ctx.intrinsic_edge_length.value(e) < geometry_utils.epsilon) {
                return error.EdgeHasNearZeroLength;
            }
        }

        // start with a Delaunay triangulation (flip edges to Delaunay)
        try flipEdgesToDelaunay(it_ctx, &flip_edge_queue, null);

        // Priority queue type for triangles to refine, ordered by the circumradius-to-shortest-edge ratio (rho)
        const FacePriorityQueueContext = struct {
            surface_mesh: *SurfaceMesh,
            face_queue_index: SurfaceMesh.CellData(.face, ?usize),
        };
        const TriangleInfo = struct {
            const TriangleInfo = @This();
            face: SurfaceMesh.Cell,
            rho_sq: f32,
            pub fn cmpDesc(ctx: FacePriorityQueueContext, a: TriangleInfo, b: TriangleInfo) std.math.Order {
                const rho_order = std.math.order(b.rho_sq, a.rho_sq);
                if (rho_order != .eq) return rho_order;
                // tie-breaker: use face indices to order faces
                return std.math.order(ctx.surface_mesh.cellIndex(a.face), ctx.surface_mesh.cellIndex(b.face));
            }
            pub fn setFaceIndexInQueue(ctx: FacePriorityQueueContext, a: TriangleInfo, index: usize) void {
                ctx.face_queue_index.valuePtr(a.face).* = index;
            }
        };
        const FacePriorityQueueDesc = PriorityQueue(TriangleInfo, FacePriorityQueueContext, TriangleInfo.cmpDesc, TriangleInfo.setFaceIndexInQueue);

        var refine_triangle_pq_index = try it_ctx.intrinsic_surface_mesh.addData(.face, ?usize, "__refine_triangle_pq_index");
        refine_triangle_pq_index.data.fill(null);
        defer it_ctx.intrinsic_surface_mesh.removeData(.face, ?usize, refine_triangle_pq_index);
        var refine_triangle_pq: FacePriorityQueueDesc = .initContext(.{
            .surface_mesh = it_ctx.intrinsic_surface_mesh,
            .face_queue_index = refine_triangle_pq_index,
        });
        defer refine_triangle_pq.deinit(it_ctx.app_ctx.allocator);

        const rho_threshold = 1.0 / (2.0 * std.math.sin(angle_threshold));
        const rho_threshold_sq = rho_threshold * rho_threshold;

        var face_it: SurfaceMesh.CellIterator = try .init(it_ctx.intrinsic_surface_mesh, .face);
        defer face_it.deinit();
        while (face_it.next()) |f| {
            const rho_sq = it_ctx.triangleCircumradiusToShortestEdgeRatioSquared(f);
            if (std.math.isFinite(rho_sq) and rho_sq > rho_threshold_sq) {
                try refine_triangle_pq.push(it_ctx.app_ctx.allocator, .{ .face = f, .rho_sq = rho_sq });
            }
        }

        // define callbacks for the refinement process to update the triangle priority queue when triangles are split or edges are flipped
        const RefineCallbacks = struct {
            const RefineCallbacks = @This();
            it_ctx: *ITContext,
            pq: *FacePriorityQueueDesc,
            pq_index: SurfaceMesh.CellData(.face, ?usize),
            rho_threshold_sq: f32,
            pub fn beforeTriangleSplit(rc: *const RefineCallbacks, tri: SurfaceMesh.Cell) void {
                // remove the triangle from the priority queue if it is present
                if (rc.pq_index.value(tri)) |index| {
                    _ = rc.pq.popIndex(index);
                }
                rc.pq_index.valuePtr(tri).* = null;
            }
            pub fn beforeEdgeFlip(rc: *const RefineCallbacks, edge: SurfaceMesh.Cell) void {
                // remove the 2 incident triangles from the priority queue if they are present
                const d = edge.dart();
                const f1: SurfaceMesh.Cell = .{ .face = d };
                if (rc.pq_index.value(f1)) |index| {
                    _ = rc.pq.popIndex(index);
                }
                rc.pq_index.valuePtr(f1).* = null;
                const f2: SurfaceMesh.Cell = .{ .face = rc.it_ctx.intrinsic_surface_mesh.phi2(d) };
                if (rc.pq_index.value(f2)) |index| {
                    _ = rc.pq.popIndex(index);
                }
                rc.pq_index.valuePtr(f2).* = null;
            }
            pub fn afterEdgeFlip(rc: *const RefineCallbacks, edge: SurfaceMesh.Cell) void {
                // add the 2 incident triangles to the priority queue if they meet the refinement criterion
                const d = edge.dart();
                const f1: SurfaceMesh.Cell = .{ .face = d };
                assert(rc.pq_index.value(f1) == null);
                const rho_sq_f1 = rc.it_ctx.triangleCircumradiusToShortestEdgeRatioSquared(f1);
                if (std.math.isFinite(rho_sq_f1) and rho_sq_f1 > rc.rho_threshold_sq) {
                    rc.pq.push(rc.it_ctx.app_ctx.allocator, .{ .face = f1, .rho_sq = rho_sq_f1 }) catch {};
                }
                const f2: SurfaceMesh.Cell = .{ .face = rc.it_ctx.intrinsic_surface_mesh.phi2(d) };
                assert(rc.pq_index.value(f2) == null);
                const rho_sq_f2 = rc.it_ctx.triangleCircumradiusToShortestEdgeRatioSquared(f2);
                if (std.math.isFinite(rho_sq_f2) and rho_sq_f2 > rc.rho_threshold_sq) {
                    rc.pq.push(rc.it_ctx.app_ctx.allocator, .{ .face = f2, .rho_sq = rho_sq_f2 }) catch {};
                }
            }
        };

        // create an instance of the callbacks struct to pass to the refinement functions (insertIntrinsicTriangleCircumcenter and flipEdgesToDelaunay)
        const refine_callbacks = RefineCallbacks{
            .it_ctx = it_ctx,
            .pq = &refine_triangle_pq,
            .pq_index = refine_triangle_pq_index,
            .rho_threshold_sq = rho_threshold_sq,
        };

        while (refine_triangle_pq.pop()) |tri_info| {
            refine_triangle_pq_index.valuePtr(tri_info.face).* = null; // the triangle is no longer in the priority queue

            // The queue can contain stale entries after local updates; only refine if the
            // current quality is still valid and above threshold.
            const current_rho_sq = it_ctx.triangleCircumradiusToShortestEdgeRatioSquared(tri_info.face);
            if (!std.math.isFinite(current_rho_sq) or current_rho_sq <= rho_threshold_sq) {
                continue;
            }

            const central_vertex = try it_ctx.insertIntrinsicTriangleCircumcenter(
                tri_info.face,
                refine_callbacks,
            );

            // the queue containing edges to flip should be empty before refining a triangle
            assert(flip_edge_queue.items.len == 0);

            // add the 3 new triangles to the triangle priority queue if they meet the refinement criterion
            // add the 3 edges of the original triangle to the Delaunay edge flip queue
            var cv_dart_it = it_ctx.intrinsic_surface_mesh.cellDartIterator(central_vertex);
            while (cv_dart_it.next()) |cv_d| {
                const new_tri: SurfaceMesh.Cell = .{ .face = cv_d };
                // new triangles are not in the priority queue yet, so we can directly set their index to null
                refine_triangle_pq_index.valuePtr(new_tri).* = null;
                const rho_sq = it_ctx.triangleCircumradiusToShortestEdgeRatioSquared(new_tri);
                // add the new triangle to the priority queue if it meets the refinement criterion
                if (std.math.isFinite(rho_sq) and rho_sq > rho_threshold_sq) {
                    try refine_triangle_pq.push(it_ctx.app_ctx.allocator, .{ .face = new_tri, .rho_sq = rho_sq });
                }
                // add the edge of the new triangle opposite to the central vertex to the edge flip queue
                try flip_edge_queue.append(it_ctx.app_ctx.allocator, .{ .edge = it_ctx.intrinsic_surface_mesh.phi1(cv_d) });
            }

            // flip edges to Delaunay after refining the triangle
            try flipEdgesToDelaunay(
                it_ctx,
                &flip_edge_queue,
                refine_callbacks,
            );
        }
    }

    // returns the new central vertex of the intrinsic triangle split by inserting its circumcenter
    fn insertIntrinsicTriangleCircumcenter(
        it_ctx: *ITContext,
        triangle: SurfaceMesh.Cell,
        callbacks: anytype, // can define a method `beforeTriangleSplit(triangle: SurfaceMesh.Cell) void`
    ) !SurfaceMesh.Cell {
        // Dart of the source intrinsic triangle to split
        const src_d = triangle.dart();

        // layout the source intrinsic triangle in 2D
        const src_l_v0v1 = it_ctx.intrinsic_edge_length.value(.{ .edge = src_d });
        const src_l_v1v2 = it_ctx.intrinsic_edge_length.value(.{ .edge = it_ctx.intrinsic_surface_mesh.phi1(src_d) });
        const src_l_v2v0 = it_ctx.intrinsic_edge_length.value(.{ .edge = it_ctx.intrinsic_surface_mesh.phi_1(src_d) });
        const src_p2d: [3]Vec2f = .{
            .{ 0.0, 0.0 },
            .{ src_l_v0v1, 0.0 },
            geometry_utils.layoutTriangleVertex(
                .{ 0.0, 0.0 },
                .{ src_l_v0v1, 0.0 },
                src_l_v1v2,
                src_l_v2v0,
            ),
        };

        // compute the position of the circumcenter of the source intrinsic triangle
        const src_l_v0v1_sq = src_l_v0v1 * src_l_v0v1;
        const src_l_v2v0_sq = src_l_v2v0 * src_l_v2v0;
        const src_det = vec.cross2f(src_p2d[1], src_p2d[2]);
        const src_idet = 0.5 / src_det;
        const src_circumcenter: Vec2f = .{
            (src_l_v0v1_sq * src_p2d[2][1]) * src_idet,
            (src_l_v2v0_sq * src_l_v0v1 - src_l_v0v1_sq * src_p2d[2][0]) * src_idet,
        };

        // compute the position of the barycenter of the source intrinsic triangle
        const src_barycenter: Vec2f = .{
            (src_p2d[0][0] + src_p2d[1][0] + src_p2d[2][0]) / 3.0,
            (src_p2d[0][1] + src_p2d[1][1] + src_p2d[2][1]) / 3.0,
        };

        // compute the direction vector from the barycenter to the circumcenter
        const src_dir = vec.sub2f(src_circumcenter, src_barycenter);
        // compute the angle of the direction vector in the tangent space of the source triangle
        const dir_angle = std.math.atan2(
            vec.cross2f(src_p2d[1], src_dir),
            vec.dot2f(src_p2d[1], src_dir),
        );

        // trace on the intrinsic mesh from the barycenter of the triangle to the circumcenter
        const circumcenter_sp_int, _, _ = try geodesic.traceGeodesic(
            it_ctx.app_ctx,
            it_ctx.intrinsic_surface_mesh,
            .{
                .surface_mesh = it_ctx.intrinsic_surface_mesh,
                .type = .{
                    .face = .{
                        .cell = .{ .face = src_d },
                        .bcoords = .{ 1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0 },
                    },
                },
            },
            dir_angle,
            vec.norm2f(src_dir),
            it_ctx.intrinsic_corner_angle,
            it_ctx.intrinsic_edge_length,
            null,
        );

        // Dart of the destination intrinsic triangle
        assert(circumcenter_sp_int.type == .face);
        const dst_d = circumcenter_sp_int.type.face.cell.dart();

        // call the beforeTriangleSplit callback on the destination triangle
        if (comptime std.meta.hasFn(@TypeOf(callbacks), "beforeTriangleSplit")) {
            callbacks.beforeTriangleSplit(.{ .face = dst_d });
        }

        // layout the destination intrinsic triangle in 2D
        const dst_l_v0v1 = it_ctx.intrinsic_edge_length.value(.{ .edge = dst_d });
        const dst_l_v1v2 = it_ctx.intrinsic_edge_length.value(.{ .edge = it_ctx.intrinsic_surface_mesh.phi1(dst_d) });
        const dst_l_v2v0 = it_ctx.intrinsic_edge_length.value(.{ .edge = it_ctx.intrinsic_surface_mesh.phi_1(dst_d) });
        const dst_p2d: [3]Vec2f = .{
            .{ 0.0, 0.0 },
            .{ dst_l_v0v1, 0.0 },
            geometry_utils.layoutTriangleVertex(
                .{ 0.0, 0.0 },
                .{ dst_l_v0v1, 0.0 },
                dst_l_v1v2,
                dst_l_v2v0,
            ),
        };

        // compute the position of the point reached in the destination intrinsic triangle 2D layout
        const dst_circumcenter: Vec2f = .{
            circumcenter_sp_int.type.face.bcoords[0] * dst_p2d[0][0] + circumcenter_sp_int.type.face.bcoords[1] * dst_p2d[1][0] + circumcenter_sp_int.type.face.bcoords[2] * dst_p2d[2][0],
            circumcenter_sp_int.type.face.bcoords[0] * dst_p2d[0][1] + circumcenter_sp_int.type.face.bcoords[1] * dst_p2d[1][1] + circumcenter_sp_int.type.face.bcoords[2] * dst_p2d[2][1],
        };

        // compute the lengths of the three new edges created by splitting the destination intrinsic triangle at the circumcenter
        const dst_l_v0c = vec.norm2f(vec.sub2f(dst_circumcenter, dst_p2d[0]));
        const dst_l_v1c = vec.norm2f(vec.sub2f(dst_circumcenter, dst_p2d[1]));
        const dst_l_v2c = vec.norm2f(vec.sub2f(dst_circumcenter, dst_p2d[2]));

        // grab the Dart on the other side of the first edge of the destination triangle
        const dst_d2 = it_ctx.intrinsic_surface_mesh.phi2(dst_d);
        // save halfedge angles before removing the face (they will be restored on the new halfedges created by the umbrella triangulation)
        const dst_tri_he_angles: [3]f32 = .{
            it_ctx.intrinsic_halfedge_extrinsic_sp_angle.value(.{ .halfedge = dst_d }),
            it_ctx.intrinsic_halfedge_extrinsic_sp_angle.value(.{ .halfedge = it_ctx.intrinsic_surface_mesh.phi1(dst_d) }),
            it_ctx.intrinsic_halfedge_extrinsic_sp_angle.value(.{ .halfedge = it_ctx.intrinsic_surface_mesh.phi_1(dst_d) }),
        };

        // remove the triangle face
        it_ctx.intrinsic_surface_mesh.removeFace(.{ .face = dst_d });
        // and close the hole with an umbrella triangulation (the new central vertex is eventually returned)
        const central_vertex = try it_ctx.intrinsic_surface_mesh.closeHoleWithUmbrella(dst_d2);

        // get the Darts of the three halfedges incident to the central vertex
        const cvd0 = central_vertex.dart();
        const cvd1 = it_ctx.intrinsic_surface_mesh.phi2(it_ctx.intrinsic_surface_mesh.phi_1(cvd0));
        const cvd2 = it_ctx.intrinsic_surface_mesh.phi2(it_ctx.intrinsic_surface_mesh.phi_1(cvd1));

        // set the intrinsic edge lengths of the three new edges incident to the central vertex
        it_ctx.intrinsic_edge_length.valuePtr(.{ .edge = cvd0 }).* = dst_l_v0c;
        it_ctx.intrinsic_edge_length.valuePtr(.{ .edge = cvd1 }).* = dst_l_v1c;
        it_ctx.intrinsic_edge_length.valuePtr(.{ .edge = cvd2 }).* = dst_l_v2c;
        // restore the halfedge angles of the removed triangle
        it_ctx.intrinsic_halfedge_extrinsic_sp_angle.valuePtr(.{ .halfedge = it_ctx.intrinsic_surface_mesh.phi1(cvd0) }).* = dst_tri_he_angles[0];
        it_ctx.intrinsic_halfedge_extrinsic_sp_angle.valuePtr(.{ .halfedge = it_ctx.intrinsic_surface_mesh.phi1(cvd1) }).* = dst_tri_he_angles[1];
        it_ctx.intrinsic_halfedge_extrinsic_sp_angle.valuePtr(.{ .halfedge = it_ctx.intrinsic_surface_mesh.phi1(cvd2) }).* = dst_tri_he_angles[2];

        // update intrinsic mesh data (corner angles, face areas, halfedge cotan weights, halfedge SurfacePoint angles)
        var central_vertex_dart_it = it_ctx.intrinsic_surface_mesh.cellDartIterator(central_vertex);
        while (central_vertex_dart_it.next()) |cvdart| {
            // update intrinsic face areas
            const face: SurfaceMesh.Cell = .{ .face = cvdart };
            it_ctx.intrinsic_face_area.valuePtr(face).* = area.faceAreaIntrinsic(
                it_ctx.intrinsic_surface_mesh,
                face,
                it_ctx.intrinsic_edge_length,
            );
            // update :
            // - intrinsic halfedge cotan weights
            // - intrinsic corner angles
            var face_dart_it = it_ctx.intrinsic_surface_mesh.cellDartIterator(face);
            while (face_dart_it.next()) |fd| {
                const fdhe: SurfaceMesh.Cell = .{ .halfedge = fd };
                it_ctx.intrinsic_halfedge_cotan_weight.valuePtr(fdhe).* = laplacian.halfedgeCotanWeightIntrinsic(
                    it_ctx.intrinsic_surface_mesh,
                    fdhe,
                    it_ctx.intrinsic_edge_length,
                    it_ctx.intrinsic_face_area,
                );
                const fdcorner: SurfaceMesh.Cell = .{ .corner = fd };
                it_ctx.intrinsic_corner_angle.valuePtr(fdcorner).* = angle.cornerAngleIntrinsic(
                    it_ctx.intrinsic_surface_mesh,
                    fdcorner,
                    it_ctx.intrinsic_edge_length,
                );
            }
            // update incoming intrinsic halfedge SurfacePoint angle
            const cvdart1 = it_ctx.intrinsic_surface_mesh.phi1(cvdart);
            const cvdart2 = it_ctx.intrinsic_surface_mesh.phi2(cvdart);
            it_ctx.intrinsic_halfedge_extrinsic_sp_angle.valuePtr(.{ .halfedge = cvdart2 }).* =
                it_ctx.intrinsic_halfedge_extrinsic_sp_angle.valuePtr(.{ .halfedge = cvdart1 }).* + it_ctx.intrinsic_corner_angle.value(.{ .corner = cvdart1 });
            // initialize intrinsic edge data:
            // - original edge boolean
            // - edge traces (empty for now)
            const edge: SurfaceMesh.Cell = .{ .edge = cvdart };
            it_ctx.intrinsic_edge_is_original.valuePtr(edge).* = false;
            it_ctx.intrinsic_edge_trace.valuePtr(edge).* = .empty;
        }

        // get the SurfacePoint on the extrinsic mesh of the first vertex of the destination intrinsic triangle to trace from
        const dst_sp0 = it_ctx.intrinsic_vertex_extrinsic_sp.value(.{ .vertex = it_ctx.intrinsic_surface_mesh.phi2(cvd0) });
        const dst_dir_angle = it_ctx.intrinsic_halfedge_extrinsic_sp_angle.value(.{ .halfedge = it_ctx.intrinsic_surface_mesh.phi2(cvd0) });

        // trace the first new intrinsic edge on the extrinsic mesh
        const circumcenter_sp_ext, const last_entry_angle, _ = try geodesic.traceGeodesic(
            it_ctx.app_ctx,
            it_ctx.extrinsic_surface_mesh,
            dst_sp0,
            dst_dir_angle,
            dst_l_v0c,
            it_ctx.extrinsic_corner_angle,
            it_ctx.extrinsic_edge_length,
            null,
        );

        // set the reached extrinsic SurfacePoint to the new intrinsic central vertex
        it_ctx.intrinsic_vertex_extrinsic_sp.valuePtr(central_vertex).* = circumcenter_sp_ext;
        // set the intrinsic halfedge SurfacePoint angles of the three new outgoing intrinsic halfedges incident to the central vertex
        // (total angle around the central vertex, a face SurfacePoint, is 2π)
        const cvd0_angle = @mod(last_entry_angle + std.math.pi, std.math.tau); // modulo 2π should not be needed here because the entry angle is always < π
        const cvd1_angle = @mod(cvd0_angle + it_ctx.intrinsic_corner_angle.value(.{ .corner = cvd0 }), std.math.tau);
        const cvd2_angle = @mod(cvd1_angle + it_ctx.intrinsic_corner_angle.value(.{ .corner = cvd1 }), std.math.tau);
        it_ctx.intrinsic_halfedge_extrinsic_sp_angle.valuePtr(.{ .halfedge = cvd0 }).* = cvd0_angle;
        it_ctx.intrinsic_halfedge_extrinsic_sp_angle.valuePtr(.{ .halfedge = cvd1 }).* = cvd1_angle;
        it_ctx.intrinsic_halfedge_extrinsic_sp_angle.valuePtr(.{ .halfedge = cvd2 }).* = cvd2_angle;

        return central_vertex;
    }
};
