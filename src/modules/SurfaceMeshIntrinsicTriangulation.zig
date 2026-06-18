const SurfaceMeshIntrinsicTriangulation = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("c");

const PriorityQueue = @import("../utils/PriorityQueue.zig").PriorityQueue;

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfacePoint = @import("../models/surface/SurfacePoint.zig");
const IncidenceGraph = @import("../models/incidenceGraph/IncidenceGraph.zig");

const Data = @import("../utils/data.zig").Data;
const DataGen = @import("../utils/data.zig").DataGen;

const vec = @import("../geometry/vec.zig");
const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const geometry_utils = @import("../geometry/utils.zig");

const length = @import("../models/surface/length.zig");
const angle = @import("../models/surface/angle.zig");
const area = @import("../models/surface/area.zig");
const laplacian = @import("../models/surface/laplacian.zig");
const geodesic = @import("../models/surface/geodesic.zig");

const ITData = struct {
    app_ctx: *AppContext,

    // the reference Dart of a Cell (vertex, edge, face) is the first Dart of the Cell
    // (i.e. the one with the smallest index, which is also the one that represents a Cell given by a CellIterator)

    // a SurfacePoint on the extrinsic SurfaceMesh can be of vertex, edge or face type
    // tangent vectors at SurfacePoints are expressed by an angle w.r.t. the reference Dart of the Cell of the SurfacePoint
    // - for face SurfacePoints, the angle is measured CCW from the direction of the reference Dart of the face ; the value is in [0, 2π) (locally flat)
    // - for edge SurfacePoints, the angle is measured CCW from the direction of the reference Dart of the edge ; the value is in [0, 2π) (locally flat on the 2D layout of the incident faces)
    // - for vertex SurfacePoints, the angle is measured CCW from the direction of the reference Dart of the vertex ; the value is in [0, 2π) (normalized by the angle sum around the vertex)
    // Cells stored in intrinsic_vertex_sp data always represent their Cell with the reference Dart

    // TODO: manage boundary vertices (the reference Dart of a boundary vertex might not be on the boundary,
    // which causes issues if we want to use it as reference for the angles of the halfedges around the vertex)

    extrinsic_surface_mesh: *SurfaceMesh = undefined,
    extrinsic_vertex_position: SurfaceMesh.CellData(.vertex, Vec3f) = undefined,
    extrinsic_edge_length: SurfaceMesh.CellData(.edge, f32) = undefined,
    extrinsic_corner_angle: SurfaceMesh.CellData(.corner, f32) = undefined,
    extrinsic_vertex_angle_sum: SurfaceMesh.CellData(.vertex, f32) = undefined,

    intrinsic_surface_mesh: *SurfaceMesh = undefined,
    intrinsic_edge_length: SurfaceMesh.CellData(.edge, f32) = undefined,
    intrinsic_corner_angle: SurfaceMesh.CellData(.corner, f32) = undefined,
    intrinsic_face_area: SurfaceMesh.CellData(.face, f32) = undefined,
    intrinsic_halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32) = undefined,
    // each intrinsic vertex is mapped to a SurfacePoint on the extrinsic mesh
    intrinsic_vertex_sp: SurfaceMesh.CellData(.vertex, SurfacePoint) = undefined,
    // each intrinsic halfedge is associated with an angle (tangent vector) that expresses the direction towards the intrinsic vertex on the other side of the edge
    // this angle is expressed in the tangent space of the SurfacePoint of the intrinsic vertex of the intrinsic halfedge
    // (if this SurfacePoint is of vertex type, then the angle is normalized by the angle sum around the vertex)
    intrinsic_halfedge_sp_angle: SurfaceMesh.CellData(.halfedge, f32) = undefined,
    // a boolean to mark the edges of the intrinsic triangulation that are also edges of the extrinsic mesh
    intrinsic_edge_is_original: SurfaceMesh.CellData(.edge, bool) = undefined,
    // for each intrinsic edge, we store the trace of the edge as a sequence of SurfacePoints on the extrinsic mesh
    intrinsic_edge_trace: SurfaceMesh.CellData(.edge, std.ArrayList(SurfacePoint)) = undefined,

    // tmp
    // intrinsic_vertex_position: SurfaceMesh.CellData(.vertex, Vec3f) = undefined,

    common_subd_ig: *IncidenceGraph = undefined,
    ig_vertex_position: IncidenceGraph.CellData(.vertex, Vec3f) = undefined,

    initialized: bool = false,

    fn init(
        itd: *ITData,
        extrinsic_surface_mesh: *SurfaceMesh,
        extrinsic_vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        extrinsic_edge_length: SurfaceMesh.CellData(.edge, f32),
        extrinsic_corner_angle: SurfaceMesh.CellData(.corner, f32),
    ) !void {
        itd.extrinsic_surface_mesh = extrinsic_surface_mesh;
        itd.extrinsic_vertex_position = extrinsic_vertex_position;
        itd.extrinsic_edge_length = extrinsic_edge_length;
        itd.extrinsic_corner_angle = extrinsic_corner_angle;
        // create and compute extrinsic vertex angle sums
        itd.extrinsic_vertex_angle_sum = try itd.extrinsic_surface_mesh.addData(.vertex, f32, "angle_sum");
        var ext_vertex_it: SurfaceMesh.CellIterator = try .init(itd.extrinsic_surface_mesh, .vertex);
        defer ext_vertex_it.deinit();
        while (ext_vertex_it.next()) |v| {
            var angle_sum: f32 = 0.0;
            var d_it = itd.extrinsic_surface_mesh.cellDartIterator(v);
            while (d_it.next()) |d| {
                angle_sum += itd.extrinsic_corner_angle.value(.{ .corner = d });
            }
            itd.extrinsic_vertex_angle_sum.valuePtr(v).* = angle_sum;
        }

        if (itd.initialized) {
            itd.intrinsic_surface_mesh.deinit();
            itd.app_ctx.allocator.destroy(itd.intrinsic_surface_mesh);
        }
        itd.intrinsic_surface_mesh = try extrinsic_surface_mesh.cloneWithoutCellData(itd.app_ctx.allocator);
        itd.intrinsic_edge_length = try itd.intrinsic_surface_mesh.addData(.edge, f32, "length");
        itd.intrinsic_corner_angle = try itd.intrinsic_surface_mesh.addData(.corner, f32, "corner_angle");
        itd.intrinsic_face_area = try itd.intrinsic_surface_mesh.addData(.face, f32, "area");
        itd.intrinsic_halfedge_cotan_weight = try itd.intrinsic_surface_mesh.addData(.halfedge, f32, "cotan_weight");
        itd.intrinsic_vertex_sp = try itd.intrinsic_surface_mesh.addData(.vertex, SurfacePoint, "sp");
        itd.intrinsic_halfedge_sp_angle = try itd.intrinsic_surface_mesh.addData(.halfedge, f32, "sp_angle");
        itd.intrinsic_edge_is_original = try itd.intrinsic_surface_mesh.addData(.edge, bool, "is_original");
        itd.intrinsic_edge_trace = try itd.intrinsic_surface_mesh.addData(.edge, std.ArrayList(SurfacePoint), "trace");

        // initialize intrinsic edge lengths from extrinsic edge lengths
        // (indices coincide after cloning so we can directly copy the raw data)
        itd.intrinsic_edge_length.data.copyFrom(extrinsic_edge_length.data);
        // compute intrinsic corner angles
        try angle.computeCornerAnglesIntrinsic(itd.app_ctx, itd.intrinsic_surface_mesh, itd.intrinsic_edge_length, itd.intrinsic_corner_angle);
        // compute intrinsic face areas
        try area.computeFaceAreasIntrinsic(itd.app_ctx, itd.intrinsic_surface_mesh, itd.intrinsic_edge_length, itd.intrinsic_face_area);
        // compute intrinsic halfedge cotan weights
        try laplacian.computeHalfedgeCotanWeightsIntrinsic(itd.app_ctx, itd.intrinsic_surface_mesh, itd.intrinsic_edge_length, itd.intrinsic_face_area, itd.intrinsic_halfedge_cotan_weight);

        // initialize intrinsic vertex SurfacePoint (all are initially of vertex type, i.e. sit on extrinsic vertices)
        // initialize intrinsic halfedge SurfacePoint angle (expressed in the underlying SurfacePoint tangent space)
        var int_vertex_it: SurfaceMesh.CellIterator = try .init(itd.intrinsic_surface_mesh, .vertex);
        defer int_vertex_it.deinit();
        while (int_vertex_it.next()) |v| {
            itd.intrinsic_vertex_sp.valuePtr(v).* = .{
                .surface_mesh = itd.extrinsic_surface_mesh,
                .type = .{ .vertex = v }, // intrinsic vertex v.dart() corresponds to extrinsic vertex v.dart() after cloning
            };
            const angle_sum = itd.extrinsic_vertex_angle_sum.value(v); // get the angle sum of the corresponding extrinsic vertex
            // v.dart() is the reference Dart of the vertex
            // the CellDartIterator iterates around the vertex in CCW order starting from this Dart
            var normalized_angle_sum: f32 = 0.0;
            var d_it = itd.intrinsic_surface_mesh.cellDartIterator(v);
            while (d_it.next()) |d| {
                itd.intrinsic_halfedge_sp_angle.valuePtr(.{ .halfedge = d }).* = normalized_angle_sum;
                const corner_angle = itd.extrinsic_corner_angle.value(.{ .corner = d });
                normalized_angle_sum += corner_angle * (2.0 * std.math.pi) / angle_sum;
            }
            assert(@abs(normalized_angle_sum - (2.0 * std.math.pi)) < geometry_utils.epsilon); // should sum up to 2π
        }
        // initialize intrinsic edge data:
        // - original edge boolean
        // - edge traces (empty for now)
        var int_edge_it: SurfaceMesh.CellIterator = try .init(itd.intrinsic_surface_mesh, .edge);
        defer int_edge_it.deinit();
        while (int_edge_it.next()) |e| {
            itd.intrinsic_edge_is_original.valuePtr(e).* = true; // all edges are original after cloning
            itd.intrinsic_edge_trace.valuePtr(e).* = .empty;
        }

        itd.initialized = true;

        itd.common_subd_ig = try itd.app_ctx.incidence_graph_store.createIncidenceGraph("common_subd");
        itd.ig_vertex_position = try itd.common_subd_ig.addData(.vertex, Vec3f, "position");
        itd.app_ctx.incidence_graph_store.setIncidenceGraphStdData(itd.common_subd_ig, .{ .vertex_position = itd.ig_vertex_position });
        itd.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(itd.common_subd_ig);

        // // registers the cloned intrinsic SurfaceMesh in the SurfaceMeshStore to make it available in the UI and for other modules
        // var buf: [64]u8 = undefined;
        // const intrinsic_sm_name = std.fmt.bufPrint(&buf, "{s}_intrinsic", .{itd.app_ctx.surface_mesh_store.surfaceMeshName(itd.extrinsic_surface_mesh).?}) catch "__intrinsic";
        // itd.intrinsic_vertex_position = try itd.intrinsic_surface_mesh.addData(.vertex, Vec3f, "position");
        // itd.intrinsic_vertex_position.data.copyFrom(extrinsic_vertex_position.data);
        // try itd.app_ctx.surface_mesh_store.registerSurfaceMesh(intrinsic_sm_name, itd.intrinsic_surface_mesh);
        // itd.app_ctx.surface_mesh_store.setSurfaceMeshStdData(itd.intrinsic_surface_mesh, .{ .vertex_position = itd.intrinsic_vertex_position });
        // itd.app_ctx.surface_mesh_store.surfaceMeshConnectivityUpdated(itd.intrinsic_surface_mesh);

        itd.app_ctx.requestRedraw();
    }

    fn deinit(itd: *ITData) void {
        if (itd.initialized) {
            var edge_it = SurfaceMesh.CellIterator.init(itd.intrinsic_surface_mesh, .edge) catch |err| {
                std.debug.print("Error creating edge iterator in ITData deinit: {}\n", .{err});
                return;
            };
            while (edge_it.next()) |e| {
                itd.intrinsic_edge_trace.valuePtr(e).deinit(itd.app_ctx.allocator);
            }
            edge_it.deinit(); // this deinit is not deferred because it must not be called after the intrinsic_surface_mesh is deinit and destroyed

            // // unregister the intrinsic SurfaceMesh from the SurfaceMeshStore, deinit and destroy it
            // itd.app_ctx.surface_mesh_store.unregisterSurfaceMesh(itd.intrinsic_surface_mesh);
            itd.intrinsic_surface_mesh.deinit();
            itd.app_ctx.allocator.destroy(itd.intrinsic_surface_mesh);
        }
        itd.initialized = false;
    }

    // Returns .{t_ray, t_seg} such that p + t_ray*dir = a + t_seg*(b-a), or null if parallel.
    fn raySegmentIntersect(p: Vec2f, dir: Vec2f, a: Vec2f, b: Vec2f) ?struct { f32, f32 } {
        const seg = vec.sub2f(b, a);
        const det = vec.cross2f(dir, seg);
        if (@abs(det) < geometry_utils.epsilon) return null;
        const ap = vec.sub2f(a, p);
        const t_ray = vec.cross2f(ap, seg) / det;
        const t_seg = vec.cross2f(ap, dir) / det;
        return .{ t_ray, t_seg };
    }

    fn traceIntrinsicEdges(itd: *ITData) !void {
        // clear the common subdivision incidence graph
        itd.common_subd_ig.clearRetainingCapacity();

        var edge_it: SurfaceMesh.CellIterator = try .init(itd.intrinsic_surface_mesh, .edge);
        defer edge_it.deinit();
        while (edge_it.next()) |e| {
            const d = e.dart();

            const src_sp = itd.intrinsic_vertex_sp.value(.{ .vertex = d });
            const dst_sp = itd.intrinsic_vertex_sp.value(.{ .vertex = itd.intrinsic_surface_mesh.phi2(d) });

            // original edges trace trivially
            if (itd.intrinsic_edge_is_original.value(e)) {
                try itd.intrinsic_edge_trace.valuePtr(e).append(itd.app_ctx.allocator, src_sp);
                try itd.intrinsic_edge_trace.valuePtr(e).append(itd.app_ctx.allocator, dst_sp);

                // add the vertices and edge to the common subdivision incidence graph
                const p1 = src_sp.readData(Vec3f, .vertex, itd.extrinsic_vertex_position);
                const p2 = dst_sp.readData(Vec3f, .vertex, itd.extrinsic_vertex_position);
                const igv1 = try itd.common_subd_ig.addVertex();
                const igv2 = try itd.common_subd_ig.addVertex();
                itd.ig_vertex_position.valuePtr(igv1).* = p1;
                itd.ig_vertex_position.valuePtr(igv2).* = p2;
                _ = try itd.common_subd_ig.addEdge(igv1, igv2);

                continue;
            }

            var dir_angle = itd.intrinsic_halfedge_sp_angle.value(.{ .halfedge = d });
            // for vertex SurfacePoints, the angle passed to traceGeodesic is first denormalized
            if (src_sp.type == .vertex) {
                dir_angle = dir_angle * itd.extrinsic_vertex_angle_sum.value(src_sp.type.vertex) / (2.0 * std.math.pi);
            }

            // trace the intrinsic edge on the extrinsic mesh
            _ = try geodesic.traceGeodesic(
                itd.app_ctx,
                itd.extrinsic_surface_mesh,
                src_sp,
                dir_angle,
                itd.intrinsic_edge_length.value(e),
                itd.extrinsic_corner_angle,
                itd.extrinsic_edge_length,
                itd.intrinsic_edge_trace.valuePtr(e),
            );

            // TODO: trim the trace to remove spurious SurfacePoints that are on the edges
            // incident to the destination vertex of the intrinsic edge

            // add the vertices and edges of the trace to the common subdivision incidence graph
            var previous_sp: ?SurfacePoint = null;
            var previous_igv: ?IncidenceGraph.Cell = null;
            for (itd.intrinsic_edge_trace.value(e).items) |sp| {
                const pos = sp.readData(Vec3f, .vertex, itd.extrinsic_vertex_position);
                const igv = try itd.common_subd_ig.addVertex();
                itd.ig_vertex_position.valuePtr(igv).* = pos;
                if (previous_sp) |_| {
                    _ = try itd.common_subd_ig.addEdge(igv, previous_igv.?);
                }
                previous_sp = sp;
                previous_igv = igv;
            }
        }

        itd.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(itd.common_subd_ig, .vertex, Vec3f, itd.ig_vertex_position);
        itd.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(itd.common_subd_ig);
        itd.app_ctx.requestRedraw();
    }

    fn flipToDelaunay(itd: *ITData) !void {
        var edges_queue: std.ArrayList(SurfaceMesh.Cell) = try .initCapacity(itd.app_ctx.allocator, itd.intrinsic_surface_mesh.nbCells(.edge));
        defer edges_queue.deinit(itd.app_ctx.allocator);
        var edge_it: SurfaceMesh.CellIterator = try .init(itd.intrinsic_surface_mesh, .edge);
        defer edge_it.deinit();
        while (edge_it.next()) |e| {
            try edges_queue.append(itd.app_ctx.allocator, e);
        }
        try flipEdgesToDelaunay(itd, &edges_queue);
    }

    fn flipEdgesToDelaunay(itd: *ITData, edges_queue: *std.ArrayList(SurfaceMesh.Cell)) !void {
        var edge_in_queue: SurfaceMesh.CellMarker = try .init(itd.intrinsic_surface_mesh, .edge);
        defer edge_in_queue.deinit();
        edge_in_queue.marker.fill(true); // all edges are initially in the queue
        // var nb_flips: usize = 0;
        while (edges_queue.pop()) |e| {
            edge_in_queue.unmark(e);
            // check if the edge can flip (i.e. not a boundary edge and incident vertices of degree > 2)
            if (!itd.intrinsic_surface_mesh.canFlipEdge(e)) {
                continue;
            }
            // do not flip already Delaunay edges
            if (laplacian.edgeCotanWeight(itd.intrinsic_surface_mesh, e, itd.intrinsic_halfedge_cotan_weight) >= 0.0) {
                continue;
            }

            // TODO: check if the flip would create negative area faces (maybe test this in flipEdge once the triangles are laid out in 2D?)

            // flip the edge (updates the intrinsic geometry data accordingly)
            itd.flipEdge(e);

            // the 4 incident edges of the flipped edge might not be Delaunay anymore, so we add them to the queue if they are not already in
            const d = e.dart();
            const dd = itd.intrinsic_surface_mesh.phi2(d);
            const edges: [4]SurfaceMesh.Cell = .{
                .{ .edge = itd.intrinsic_surface_mesh.phi1(d) },
                .{ .edge = itd.intrinsic_surface_mesh.phi_1(d) },
                .{ .edge = itd.intrinsic_surface_mesh.phi1(dd) },
                .{ .edge = itd.intrinsic_surface_mesh.phi_1(dd) },
            };
            for (edges) |edge| {
                if (!edge_in_queue.isMarked(edge)) {
                    try edges_queue.append(itd.app_ctx.allocator, edge);
                    edge_in_queue.mark(edge);
                }
            }
            // nb_flips += 1;
        }

        // zgp_log.info("Flipped {} edges to get a Delaunay intrinsic triangulation", .{nb_flips});
        // itd.app_ctx.surface_mesh_store.surfaceMeshConnectivityUpdated(itd.intrinsic_surface_mesh);
        // itd.app_ctx.requestRedraw();
    }

    // flip the given edge and update the intrinsic geometry data accordingly
    fn flipEdge(itd: *ITData, edge: SurfaceMesh.Cell) void {
        assert(edge.cellType() == .edge);
        assert(itd.intrinsic_surface_mesh.canFlipEdge(edge));

        const dA0 = edge.dart();
        const dA1 = itd.intrinsic_surface_mesh.phi1(dA0);
        const dA2 = itd.intrinsic_surface_mesh.phi_1(dA0);
        const dB0 = itd.intrinsic_surface_mesh.phi2(dA0);
        const dB1 = itd.intrinsic_surface_mesh.phi1(dB0);
        const dB2 = itd.intrinsic_surface_mesh.phi_1(dB0);
        const darts: [6]SurfaceMesh.Dart = .{ dA0, dA1, dA2, dB0, dB1, dB2 };

        // compute flipped edge length using intrinsic geometry (the flipped edge is p0-p2)
        //    p2---p1
        //   /  \  /
        // p3----p0
        const l01 = itd.intrinsic_edge_length.value(.{ .edge = dA1 });
        const l12 = itd.intrinsic_edge_length.value(.{ .edge = dA2 });
        const l23 = itd.intrinsic_edge_length.value(.{ .edge = dB1 });
        const l30 = itd.intrinsic_edge_length.value(.{ .edge = dB2 });
        const l02 = itd.intrinsic_edge_length.value(.{ .edge = dA0 });
        const p3: Vec2f = .{ 0.0, 0.0 };
        const p0: Vec2f = .{ l30, 0.0 };
        const p2 = geometry_utils.layoutTriangleVertex(p3, p0, l02, l23);
        const p1 = geometry_utils.layoutTriangleVertex(p2, p0, l01, l12);
        const l13 = vec.norm2f(vec.sub2f(p3, p1));

        // flip the edge
        itd.intrinsic_surface_mesh.flipEdge(edge);
        itd.intrinsic_edge_is_original.valuePtr(edge).* = false; // the flipped edge is not original anymore

        // update intrinsic edge length
        itd.intrinsic_edge_length.valuePtr(edge).* = l13;
        // update intrinsic face areas of the 2 faces incident to the flipped edge
        itd.intrinsic_face_area.valuePtr(.{ .face = dA0 }).* = geometry_utils.triangleAreaIntrinsic(l12, l23, l13);
        itd.intrinsic_face_area.valuePtr(.{ .face = dB0 }).* = geometry_utils.triangleAreaIntrinsic(l30, l01, l13);
        // update :
        // - intrinsic halfedge cotan weights of the 6 halfedges of the two incident faces
        // - intrinsic corner angles of the 6 corners of the two incident faces
        for (darts) |d| {
            const he: SurfaceMesh.Cell = .{ .halfedge = d };
            itd.intrinsic_halfedge_cotan_weight.valuePtr(he).* = laplacian.halfedgeCotanWeightIntrinsic(
                itd.intrinsic_surface_mesh,
                he,
                itd.intrinsic_edge_length,
                itd.intrinsic_face_area,
            );
            const corner: SurfaceMesh.Cell = .{ .corner = d };
            itd.intrinsic_corner_angle.valuePtr(corner).* = angle.cornerAngleIntrinsic(
                itd.intrinsic_surface_mesh,
                corner,
                itd.intrinsic_edge_length,
            );
        }
        // update intrinsic halfedge SurfacePoint angles of the flipped halfedges
        const dB2angle = itd.intrinsic_corner_angle.value(.{ .corner = dB2 });
        itd.intrinsic_halfedge_sp_angle.valuePtr(.{ .halfedge = dA0 }).* = itd.intrinsic_halfedge_sp_angle.valuePtr(.{ .halfedge = dB2 }).* +
            switch (itd.intrinsic_vertex_sp.value(.{ .vertex = dA0 }).type) {
                .vertex => |v| dB2angle * (2.0 * std.math.pi) / itd.extrinsic_vertex_angle_sum.value(v), // normalize angle on vertex SurfacePoint
                else => dB2angle,
            };
        // TODO: check if it is needed to recompute the corner angle or if it can just be fetched from the intrinsic_corner_angle data
        const dA2angle = itd.intrinsic_corner_angle.value(.{ .corner = dA2 });
        itd.intrinsic_halfedge_sp_angle.valuePtr(.{ .halfedge = dB0 }).* = itd.intrinsic_halfedge_sp_angle.valuePtr(.{ .halfedge = dA2 }).* +
            switch (itd.intrinsic_vertex_sp.value(.{ .vertex = dB0 }).type) {
                .vertex => |v| dA2angle * (2.0 * std.math.pi) / itd.extrinsic_vertex_angle_sum.value(v), // normalize angle on vertex SurfacePoint
                else => dA2angle,
            };
    }

    const TriangleInfo = struct {
        face: SurfaceMesh.Cell,
        area: f32,
        pub fn cmpDesc(ctx: FaceQueueContext, a: TriangleInfo, b: TriangleInfo) std.math.Order {
            const area_order = std.math.order(b.area, a.area);
            if (area_order != .eq) return area_order;
            // tie-breaker: use face indices to order faces
            return std.math.order(ctx.surface_mesh.cellIndex(a.face), ctx.surface_mesh.cellIndex(b.face));
        }
        pub fn setFaceIndexInQueue(ctx: FaceQueueContext, a: TriangleInfo, index: usize) void {
            ctx.face_queue_index.valuePtr(a.face).* = index;
        }
    };
    const FaceQueueContext = struct {
        surface_mesh: *SurfaceMesh,
        face_queue_index: SurfaceMesh.CellData(.face, ?usize),
    };
    const FaceQueueDesc = PriorityQueue(TriangleInfo, FaceQueueContext, TriangleInfo.cmpDesc, TriangleInfo.setFaceIndexInQueue);

    fn refineDelaunay(itd: *ITData, angle_threshold: f32) !void {
        var edges_queue: std.ArrayList(SurfaceMesh.Cell) = try .initCapacity(itd.app_ctx.allocator, itd.intrinsic_surface_mesh.nbCells(.edge));
        defer edges_queue.deinit(itd.app_ctx.allocator);
        var edge_it: SurfaceMesh.CellIterator = try .init(itd.intrinsic_surface_mesh, .edge);
        defer edge_it.deinit();
        while (edge_it.next()) |e| {
            try edges_queue.append(itd.app_ctx.allocator, e);
        }

        try flipEdgesToDelaunay(itd, &edges_queue);

        var refine_triangle_queue_index = try itd.intrinsic_surface_mesh.addData(.face, ?usize, "__refine_triangle_queue_index");
        defer itd.intrinsic_surface_mesh.removeData(.face, ?usize, refine_triangle_queue_index);
        var refine_triangle_queue: FaceQueueDesc = .initContext(.{
            .surface_mesh = itd.intrinsic_surface_mesh,
            .face_queue_index = refine_triangle_queue_index,
        });
        defer refine_triangle_queue.deinit(itd.app_ctx.allocator);

        var face_it: SurfaceMesh.CellIterator = try .init(itd.intrinsic_surface_mesh, .face);
        defer face_it.deinit();
        refine_triangle_queue_index.data.fill(null);

        _ = angle_threshold;
    }

    fn insertIntrinsicTriangleCircumcenter(itd: *ITData, triangle: SurfaceMesh.Cell) !void {
        // // find an intrinsic corner with an angle lower than 30°
        // var int_corner_it: SurfaceMesh.CellIterator = try .init(itd.intrinsic_surface_mesh, .corner);
        // defer int_corner_it.deinit();
        // const corner_to_split: ?SurfaceMesh.Cell = while (int_corner_it.next()) |corner| {
        //     const a = itd.intrinsic_corner_angle.value(corner);
        //     if (a < std.math.pi / 6.0) { // 30 degrees in radians
        //         break corner;
        //     }
        // } else null;

        // Dart of the source intrinsic triangle to split
        const src_d = triangle.dart();

        // layout the source intrinsic triangle in 2D
        const src_l_v0v1 = itd.intrinsic_edge_length.value(.{ .edge = src_d });
        const src_l_v1v2 = itd.intrinsic_edge_length.value(.{ .edge = itd.intrinsic_surface_mesh.phi1(src_d) });
        const src_l_v2v0 = itd.intrinsic_edge_length.value(.{ .edge = itd.intrinsic_surface_mesh.phi_1(src_d) });
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
            itd.app_ctx,
            itd.intrinsic_surface_mesh,
            .{
                .surface_mesh = itd.intrinsic_surface_mesh,
                .type = .{
                    .face = .{
                        .cell = .{ .face = src_d },
                        .bcoords = .{ 1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0 },
                    },
                },
            },
            dir_angle,
            vec.norm2f(src_dir),
            itd.intrinsic_corner_angle,
            itd.intrinsic_edge_length,
            null,
        );

        // Dart of the destination intrinsic triangle
        assert(circumcenter_sp_int.type == .face);
        const dst_d = circumcenter_sp_int.type.face.cell.dart();

        // layout the destination intrinsic triangle in 2D
        const dst_l_v0v1 = itd.intrinsic_edge_length.value(.{ .edge = dst_d });
        const dst_l_v1v2 = itd.intrinsic_edge_length.value(.{ .edge = itd.intrinsic_surface_mesh.phi1(dst_d) });
        const dst_l_v2v0 = itd.intrinsic_edge_length.value(.{ .edge = itd.intrinsic_surface_mesh.phi_1(dst_d) });
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

        // insert the central vertex
        const dst_d2 = itd.intrinsic_surface_mesh.phi2(dst_d);
        // save halfedge angles before removing the face (they will be used to update the halfedge SurfacePoint angles after closing the hole)
        const dst_tri_he_angles: [3]f32 = .{
            itd.intrinsic_halfedge_sp_angle.value(.{ .halfedge = dst_d }),
            itd.intrinsic_halfedge_sp_angle.value(.{ .halfedge = itd.intrinsic_surface_mesh.phi1(dst_d) }),
            itd.intrinsic_halfedge_sp_angle.value(.{ .halfedge = itd.intrinsic_surface_mesh.phi_1(dst_d) }),
        };
        // remove the triangle face
        itd.intrinsic_surface_mesh.removeFace(.{ .face = dst_d });
        // and close the hole with an umbrella triangulation (the new central vertex is returned)
        const central_vertex = try itd.intrinsic_surface_mesh.closeHoleWithUmbrella(dst_d2);

        // get the Darts of the three halfedges incident to the central vertex
        const cvd0 = central_vertex.dart();
        const cvd1 = itd.intrinsic_surface_mesh.phi2(itd.intrinsic_surface_mesh.phi_1(cvd0));
        const cvd2 = itd.intrinsic_surface_mesh.phi2(itd.intrinsic_surface_mesh.phi_1(cvd1));

        // set the intrinsic edge lengths of the three new edges incident to the central vertex
        itd.intrinsic_edge_length.valuePtr(.{ .edge = cvd0 }).* = dst_l_v0c;
        itd.intrinsic_edge_length.valuePtr(.{ .edge = cvd1 }).* = dst_l_v1c;
        itd.intrinsic_edge_length.valuePtr(.{ .edge = cvd2 }).* = dst_l_v2c;
        // restore the halfedge angles of the removed triangle
        itd.intrinsic_halfedge_sp_angle.valuePtr(.{ .halfedge = itd.intrinsic_surface_mesh.phi1(cvd0) }).* = dst_tri_he_angles[0];
        itd.intrinsic_halfedge_sp_angle.valuePtr(.{ .halfedge = itd.intrinsic_surface_mesh.phi1(cvd1) }).* = dst_tri_he_angles[1];
        itd.intrinsic_halfedge_sp_angle.valuePtr(.{ .halfedge = itd.intrinsic_surface_mesh.phi1(cvd2) }).* = dst_tri_he_angles[2];

        // update intrinsic mesh data (corner angles, face areas, halfedge cotan weights, halfedge SurfacePoint angles)
        var central_vertex_dart_it = itd.intrinsic_surface_mesh.cellDartIterator(central_vertex);
        while (central_vertex_dart_it.next()) |cvdart| {
            // update intrinsic face areas
            const face: SurfaceMesh.Cell = .{ .face = cvdart };
            itd.intrinsic_face_area.valuePtr(face).* = area.faceAreaIntrinsic(
                itd.intrinsic_surface_mesh,
                face,
                itd.intrinsic_edge_length,
            );
            // update :
            // - intrinsic halfedge cotan weights
            // - intrinsic corner angles
            var face_dart_it = itd.intrinsic_surface_mesh.cellDartIterator(face);
            while (face_dart_it.next()) |fd| {
                const fdhe: SurfaceMesh.Cell = .{ .halfedge = fd };
                itd.intrinsic_halfedge_cotan_weight.valuePtr(fdhe).* = laplacian.halfedgeCotanWeightIntrinsic(
                    itd.intrinsic_surface_mesh,
                    fdhe,
                    itd.intrinsic_edge_length,
                    itd.intrinsic_face_area,
                );
                const fdcorner: SurfaceMesh.Cell = .{ .corner = fd };
                itd.intrinsic_corner_angle.valuePtr(fdcorner).* = angle.cornerAngleIntrinsic(
                    itd.intrinsic_surface_mesh,
                    fdcorner,
                    itd.intrinsic_edge_length,
                );
            }
            // update incoming intrinsic halfedge SurfacePoint angle
            const cvdart1 = itd.intrinsic_surface_mesh.phi1(cvdart);
            const cvdart2 = itd.intrinsic_surface_mesh.phi2(cvdart);
            const cvdart1angle = itd.intrinsic_corner_angle.value(.{ .corner = cvdart1 });
            itd.intrinsic_halfedge_sp_angle.valuePtr(.{ .halfedge = cvdart2 }).* = itd.intrinsic_halfedge_sp_angle.valuePtr(.{ .halfedge = cvdart1 }).* +
                switch (itd.intrinsic_vertex_sp.value(.{ .vertex = cvdart2 }).type) {
                    .vertex => |v| cvdart1angle * (2.0 * std.math.pi) / itd.extrinsic_vertex_angle_sum.value(v), // normalize angle on vertex SurfacePoint
                    else => cvdart1angle,
                };
            // initialize intrinsic edge data:
            // - original edge boolean
            // - edge traces (empty for now)
            const edge: SurfaceMesh.Cell = .{ .edge = cvdart };
            itd.intrinsic_edge_is_original.valuePtr(edge).* = false;
            itd.intrinsic_edge_trace.valuePtr(edge).* = .empty;
        }

        // get the SurfacePoint on the extrinsic mesh of the first vertex of the destination intrinsic triangle to trace from
        const dst_sp0 = itd.intrinsic_vertex_sp.value(.{ .vertex = itd.intrinsic_surface_mesh.phi2(cvd0) });

        var dst_dir_angle = itd.intrinsic_halfedge_sp_angle.value(.{ .halfedge = itd.intrinsic_surface_mesh.phi2(cvd0) });
        // for vertex SurfacePoints, the angle passed to traceGeodesic is first denormalized
        if (dst_sp0.type == .vertex) {
            dst_dir_angle = dst_dir_angle * itd.extrinsic_vertex_angle_sum.value(dst_sp0.type.vertex) / (2.0 * std.math.pi);
        }

        // trace the first new intrinsic edge on the extrinsic mesh
        const circumcenter_sp_ext, const last_entry_angle, _ = try geodesic.traceGeodesic(
            itd.app_ctx,
            itd.extrinsic_surface_mesh,
            dst_sp0,
            dst_dir_angle,
            dst_l_v0c,
            itd.extrinsic_corner_angle,
            itd.extrinsic_edge_length,
            null,
        );

        // set the reached extrinsic SurfacePoint to the new intrinsic central vertex
        itd.intrinsic_vertex_sp.valuePtr(central_vertex).* = circumcenter_sp_ext;
        // set the intrinsic halfedge SurfacePoint angles of the three new outgoing intrinsic halfedges incident to the central vertex
        const cvd0_angle = last_entry_angle + std.math.pi; // modulo 2π is not needed here because the entry angle is always < π
        const cvd1_angle = @mod(cvd0_angle + itd.intrinsic_corner_angle.value(.{ .corner = cvd0 }), 2.0 * std.math.pi);
        const cvd2_angle = @mod(cvd1_angle + itd.intrinsic_corner_angle.value(.{ .corner = cvd1 }), 2.0 * std.math.pi);
        itd.intrinsic_halfedge_sp_angle.valuePtr(.{ .halfedge = cvd0 }).* = cvd0_angle;
        itd.intrinsic_halfedge_sp_angle.valuePtr(.{ .halfedge = cvd1 }).* = cvd1_angle;
        itd.intrinsic_halfedge_sp_angle.valuePtr(.{ .halfedge = cvd2 }).* = cvd2_angle;

        // trigger Delaunay flip on the three edges of the original triangle
        var edges_queue: std.ArrayList(SurfaceMesh.Cell) = try .initCapacity(itd.app_ctx.allocator, 32);
        defer edges_queue.deinit(itd.app_ctx.allocator);
        try edges_queue.append(itd.app_ctx.allocator, .{ .edge = cvd0 });
        try edges_queue.append(itd.app_ctx.allocator, .{ .edge = cvd1 });
        try edges_queue.append(itd.app_ctx.allocator, .{ .edge = cvd2 });
        try flipToDelaunay(itd, &edges_queue);
    }
};

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Intrinsic Triangulation",
    .supported_models = .{ .surface_mesh = true },
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .rightPanel = rightPanel,
    },
},
surface_meshes_data: std.AutoHashMapUnmanaged(*SurfaceMesh, ITData) = .empty,

pub fn init(app_ctx: *AppContext) SurfaceMeshIntrinsicTriangulation {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(smit: *SurfaceMeshIntrinsicTriangulation) void {
    var it = smit.surface_meshes_data.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    smit.surface_meshes_data.deinit(smit.app_ctx.allocator);
}

/// Part of the Module interface.
/// Create and store a ITData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smit: *SurfaceMeshIntrinsicTriangulation = @alignCast(@fieldParentPtr("module", m));
    smit.surface_meshes_data.put(smit.app_ctx.allocator, surface_mesh, .{ .app_ctx = smit.app_ctx }) catch |err| {
        std.debug.print("Failed to store ITData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Deinit & remove the ITData associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smit: *SurfaceMeshIntrinsicTriangulation = @alignCast(@fieldParentPtr("module", m));
    smit.surface_meshes_data.getPtr(surface_mesh).?.deinit();
    _ = smit.surface_meshes_data.remove(surface_mesh);
}

/// Part of the Module interface.
/// Show a UI panel to control the sampling of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const smit: *SurfaceMeshIntrinsicTriangulation = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &smit.app_ctx.surface_mesh_store;

    assert(smit.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = smit.app_ctx.selected_model.surface_mesh;

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const info = sm_store.surfaceMeshInfo(sm);
    const itd = smit.surface_meshes_data.getPtr(sm).?;

    if (!itd.initialized) {
        const disabled =
            info.std_datas.vertex_position == null or
            info.std_datas.edge_length == null or
            info.std_datas.corner_angle == null;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx("Initialize intrinsic triangulation", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            itd.init(
                sm,
                info.std_datas.vertex_position.?,
                info.std_datas.edge_length.?,
                info.std_datas.corner_angle.?,
            ) catch |err| {
                std.debug.print("Error initializing intrinsic triangulation: {}\n", .{err});
            };
        }
        if (disabled) {
            imgui_utils.tooltip(
                \\ Following data should be available:
                \\ - std vertex_position
                \\ - std edge_length
                \\ - std corner_angle
            );
            c.ImGui_EndDisabled();
        }
    }

    if (itd.initialized) {
        if (c.ImGui_ButtonEx("Deinitialize intrinsic triangulation", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            itd.deinit();
        }
        c.ImGui_Separator();
        if (c.ImGui_ButtonEx("Flip to Delaunay triangulation", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            itd.flipToDelaunay() catch |err| {
                std.debug.print("Error flipping to Delaunay: {}\n", .{err});
            };
        }
        if (c.ImGui_ButtonEx("Refine Delaunay triangulation", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            itd.refineDelaunay(std.math.pi / 10.0) catch |err| {
                std.debug.print("Error refining Delaunay: {}\n", .{err});
            };
        }
        if (c.ImGui_ButtonEx("Trace intrinsic edges", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            itd.traceIntrinsicEdges() catch |err| {
                std.debug.print("Error tracing intrinsic edges: {}\n", .{err});
            };
        }
    }
}
