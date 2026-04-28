const PointCloudMedialAxis = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("../main.zig").c;

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const PointCloud = @import("../models/point/PointCloud.zig");
const IncidenceGraph = @import("../models/incidenceGraph/IncidenceGraph.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const kdtree = @import("../geometry//kdtree.zig");
const SQEM = @import("../geometry/SQEM.zig");

const tangent_basis = @import("../models/point/tangentBasis.zig");
const medialAxis = @import("../models/point/medialAxis.zig");
const sqem = @import("../models/point/sqem.zig");

const MedialAxisData = struct {
    app_ctx: *AppContext,

    point_cloud: *PointCloud,
    point_cloud_kdtree: *kdtree.PointsKDTree = undefined,
    point_position: PointCloud.CellData(Vec3f) = undefined,
    point_normal: PointCloud.CellData(Vec3f) = undefined,
    // point_area: PointCloud.CellData(f32) = undefined,
    point_knn: PointCloud.CellData(std.ArrayList(PointCloud.Point)) = undefined,
    point_tangent_basis: PointCloud.CellData([2]Vec3f) = undefined,
    point_sqem: PointCloud.CellData(SQEM) = undefined,
    point_shrinking_ball: PointCloud.CellData(?Vec4f) = undefined,
    point_sphere: PointCloud.CellData(?PointCloud.Point) = undefined,
    point_sphere_error: PointCloud.CellData(f32) = undefined,
    point_sphere_color: PointCloud.CellData(Vec3f) = undefined,

    // point_cloud_knn_ig: *IncidenceGraph = undefined,
    // point_cloud_knn_ig_vertex_position: IncidenceGraph.CellData(.vertex, Vec3f) = undefined,

    spheres: *PointCloud = undefined,
    sphere_center: PointCloud.CellData(Vec3f) = undefined,
    sphere_radius: PointCloud.CellData(f32) = undefined,
    sphere_color: PointCloud.CellData(Vec3f) = undefined,
    sphere_cluster: PointCloud.CellData(std.ArrayList(PointCloud.Point)) = undefined,
    sphere_error: PointCloud.CellData(f32) = undefined,
    sphere_neighbor_spheres: PointCloud.CellData(std.AutoArrayHashMapUnmanaged(PointCloud.Point, void)) = undefined,

    shrinking_balls: *PointCloud = undefined,
    shrinking_ball_center: PointCloud.CellData(Vec3f) = undefined,
    shrinking_ball_radius: PointCloud.CellData(f32) = undefined,

    skeleton: *IncidenceGraph = undefined,
    skeleton_vertex_position: IncidenceGraph.CellData(.vertex, Vec3f) = undefined,

    initialized: bool = false,

    pub fn init(
        mad: *MedialAxisData,
        point_cloud_kdtree: *kdtree.PointsKDTree,
        point_position: PointCloud.CellData(Vec3f),
        point_normal: PointCloud.CellData(Vec3f),
        line_quadric_epsilon: f32,
    ) !void {
        mad.point_cloud_kdtree = point_cloud_kdtree;
        mad.point_position = point_position;
        mad.point_normal = point_normal;

        if (!mad.initialized) {
            // create PointCloud data
            // mad.point_area = try mad.point_cloud.addData(f32, "area");
            mad.point_knn = try mad.point_cloud.addData(std.ArrayList(PointCloud.Point), "knn");
            mad.point_knn.data.fill(.empty);
            mad.point_tangent_basis = try mad.point_cloud.addData([2]Vec3f, "tangent_basis");
            mad.point_sqem = try mad.point_cloud.addData(SQEM, "sqem");
            mad.point_shrinking_ball = try mad.point_cloud.addData(?Vec4f, "shrinking_ball");
            mad.point_sphere = try mad.point_cloud.addData(?PointCloud.Point, "sphere");
            mad.point_sphere_error = try mad.point_cloud.addData(f32, "sphere_error");
            mad.point_sphere_color = try mad.point_cloud.addData(Vec3f, "sphere_color");

            var buf: [64]u8 = undefined;

            // create medial spheres PointCloud & data
            const ms_pc_name = std.fmt.bufPrintZ(&buf, "{s}_ma_spheres", .{mad.app_ctx.point_cloud_store.pointCloudName(mad.point_cloud).?}) catch "__ma_spheres";
            mad.spheres = try mad.app_ctx.point_cloud_store.createPointCloud(ms_pc_name);
            mad.sphere_center = try mad.spheres.addData(Vec3f, "center");
            mad.sphere_radius = try mad.spheres.addData(f32, "radius");
            mad.sphere_color = try mad.spheres.addData(Vec3f, "color");
            mad.sphere_cluster = try mad.spheres.addData(std.ArrayList(PointCloud.Point), "cluster");
            mad.sphere_error = try mad.spheres.addData(f32, "error");
            mad.sphere_neighbor_spheres = try mad.spheres.addData(std.AutoArrayHashMapUnmanaged(PointCloud.Point, void), "neighbor_spheres");
            mad.app_ctx.point_cloud_store.setPointCloudStdData(mad.spheres, .{ .position = mad.sphere_center });
            mad.app_ctx.point_cloud_store.setPointCloudStdData(mad.spheres, .{ .radius = mad.sphere_radius });

            // create shrinking balls PointCloud & data
            const sb_pc_name = std.fmt.bufPrintZ(&buf, "{s}_shrinking_balls", .{mad.app_ctx.point_cloud_store.pointCloudName(mad.point_cloud).?}) catch "__shrinking_balls";
            mad.shrinking_balls = try mad.app_ctx.point_cloud_store.createPointCloud(sb_pc_name);
            mad.shrinking_ball_center = try mad.shrinking_balls.addData(Vec3f, "center");
            mad.shrinking_ball_radius = try mad.shrinking_balls.addData(f32, "radius");
            mad.app_ctx.point_cloud_store.setPointCloudStdData(mad.shrinking_balls, .{ .position = mad.shrinking_ball_center });
            mad.app_ctx.point_cloud_store.setPointCloudStdData(mad.shrinking_balls, .{ .radius = mad.shrinking_ball_radius });

            // create skeleton IncidenceGraph & data
            const sk_name = std.fmt.bufPrintZ(&buf, "{s}_skeleton", .{mad.app_ctx.point_cloud_store.pointCloudName(mad.point_cloud).?}) catch "__skeleton";
            mad.skeleton = try mad.app_ctx.incidence_graph_store.createIncidenceGraph(sk_name);
            mad.skeleton_vertex_position = try mad.skeleton.addData(.vertex, Vec3f, "position");
            mad.app_ctx.incidence_graph_store.setIncidenceGraphStdData(mad.skeleton, .{ .vertex_position = mad.skeleton_vertex_position });

            // knn IncidenceGraph & data (only here to check the knn)
            // const knn_name = std.fmt.bufPrintZ(&buf, "{s}_knn", .{mad.app_ctx.point_cloud_store.pointCloudName(mad.point_cloud).?}) catch "__knn";
            // mad.point_cloud_knn_ig = try mad.app_ctx.incidence_graph_store.createIncidenceGraph(knn_name);
            // mad.point_cloud_knn_ig_vertex_position = try mad.point_cloud_knn_ig.addData(.vertex, Vec3f, "position");
            // mad.app_ctx.incidence_graph_store.setIncidenceGraphStdData(mad.point_cloud_knn_ig, .{ .vertex_position = mad.point_cloud_knn_ig_vertex_position });

            mad.initialized = true;
        } else {
            // clear medial spheres
            // do not forget to deinit ArrayLists in sphere_cluster data & ArrayHashMaps in sphere_neighbor_spheres data
            var s_it = mad.spheres.pointIterator();
            while (s_it.next()) |s| {
                mad.sphere_cluster.valuePtr(s).deinit(mad.app_ctx.allocator);
                mad.sphere_neighbor_spheres.valuePtr(s).deinit(mad.app_ctx.allocator);
            }
            mad.spheres.clearRetainingCapacity();
            // clear shrinking balls
            mad.shrinking_balls.clearRetainingCapacity();
            // clear skeleton
            mad.skeleton.clearRetainingCapacity();
            // // clear knn
            // mad.point_cloud_knn_ig.clearRetainingCapacity();
        }

        try tangent_basis.computePointTangentBases(
            mad.app_ctx,
            mad.point_cloud,
            mad.point_normal,
            mad.point_tangent_basis,
        );

        // compute knn graph of points
        // var point_knn_ig_vertex = try mad.point_cloud.addData(IncidenceGraph.Cell, "__point_knn_ig_vertex");
        // defer mad.point_cloud.removeData(IncidenceGraph.Cell, point_knn_ig_vertex);
        var p_it = mad.point_cloud.pointIterator();
        while (p_it.next()) |p| {
            mad.point_knn.valuePtr(p).deinit(mad.app_ctx.allocator);
            var nns = try mad.point_cloud_kdtree.nearestNeighbors(mad.app_ctx.allocator, mad.point_position.value(p), 6);
            const p_idx = std.mem.findScalar(PointCloud.Point, nns.items, p);
            if (p_idx) |idx| {
                _ = nns.swapRemove(idx);
            }
            mad.point_knn.valuePtr(p).* = nns;

            // const v = try mad.point_cloud_knn_ig.addVertex();
            // point_knn_ig_vertex.valuePtr(p).* = v;
            // mad.point_cloud_knn_ig_vertex_position.valuePtr(v).* = mad.point_position.value(p);
        }
        // p_it.reset();
        // while (p_it.next()) |p| {
        //     for (mad.point_knn.value(p).items) |np| {
        //         _ = try mad.point_cloud_knn_ig.addEdge(point_knn_ig_vertex.value(p), point_knn_ig_vertex.value(np));
        //     }
        // }
        // mad.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(mad.point_cloud_knn_ig, .vertex, Vec3f, mad.point_cloud_knn_ig_vertex_position);
        // mad.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(mad.point_cloud_knn_ig);

        // compute point areas
        // TODO?

        try sqem.computePointSQEMs(
            mad.app_ctx,
            mad.point_cloud,
            mad.point_position,
            mad.point_normal,
            // mad.point_area,
            mad.point_tangent_basis,
            line_quadric_epsilon,
            mad.point_sqem,
        );
        mad.point_shrinking_ball.data.fill(null);
        mad.point_sphere.data.fill(null);
        mad.point_sphere_error.data.fill(0.0);
        mad.point_sphere_color.data.fill(.{ 0.0, 0.0, 0.0 });

        // create the first medial sphere
        const s1 = try mad.spheres.addPoint();
        mad.sphere_center.valuePtr(s1).* = .{ 0.0, 0.0, 0.0 };
        mad.sphere_radius.valuePtr(s1).* = 0.01;
        var r = mad.app_ctx.rng.random();
        mad.sphere_color.valuePtr(s1).* = .{ 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32) };
        mad.sphere_cluster.valuePtr(s1).* = .empty;
        mad.sphere_error.valuePtr(s1).* = 0.0;
        mad.sphere_neighbor_spheres.valuePtr(s1).* = .empty;
        // and compute the cluster
        try mad.computeClusters();

        mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, mad.sphere_center);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, mad.sphere_radius);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, mad.sphere_color);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, mad.sphere_error);

        // compute points shrinking balls
        try medialAxis.computePointShrinkingBalls(
            mad.app_ctx,
            mad.point_cloud,
            mad.point_cloud_kdtree,
            mad.point_position,
            mad.point_normal,
            mad.point_shrinking_ball,
        );
        // and initialize the shrinking balls PointCloud
        for (mad.point_shrinking_ball.data.data.items) |ball| { // raw data iteration is ok because the data was filled with null
            if (ball) |b| {
                const sb = try mad.shrinking_balls.addPoint();
                mad.shrinking_ball_center.valuePtr(sb).* = .{ b[0], b[1], b[2] };
                mad.shrinking_ball_radius.valuePtr(sb).* = b[3];
            }
        }

        mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.shrinking_balls);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.shrinking_balls, Vec3f, mad.shrinking_ball_center);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.shrinking_balls, f32, mad.shrinking_ball_radius);

        try mad.updateSkeleton();

        mad.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(mad.skeleton, .vertex, Vec3f, mad.skeleton_vertex_position);
        mad.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(mad.skeleton);

        mad.app_ctx.requestRedraw();
    }

    pub fn deinit(mad: *MedialAxisData) void {
        if (mad.initialized) {
            var p_it = mad.point_cloud.pointIterator();
            while (p_it.next()) |p| {
                mad.point_knn.valuePtr(p).deinit(mad.app_ctx.allocator);
            }
            mad.point_cloud.removeData(std.ArrayList(PointCloud.Point), mad.point_knn);
            mad.point_cloud.removeData([2]Vec3f, mad.point_tangent_basis);
            mad.point_cloud.removeData(SQEM, mad.point_sqem);
            mad.point_cloud.removeData(?Vec4f, mad.point_shrinking_ball);
            mad.point_cloud.removeData(?PointCloud.Point, mad.point_sphere);
            mad.point_cloud.removeData(f32, mad.point_sphere_error);
            mad.point_cloud.removeData(Vec3f, mad.point_sphere_color);
            // do not forget to deinit ArrayLists in sphere_cluster data & ArrayHashMaps in sphere_neighbor_spheres data
            var s_it = mad.spheres.pointIterator();
            while (s_it.next()) |s| {
                mad.sphere_cluster.valuePtr(s).deinit(mad.app_ctx.allocator);
                mad.sphere_neighbor_spheres.valuePtr(s).deinit(mad.app_ctx.allocator);
            }
            // forget about the medial spheres & shrinking ball PointClouds and skeleton IncidenceGraph, but let them live on
            mad.spheres = undefined;
            mad.shrinking_balls = undefined;
            mad.skeleton = undefined;
            // mad.point_cloud_knn_ig = undefined;
            mad.initialized = false;
        }
    }

    fn recomputeSQEMs(
        mad: *MedialAxisData,
        line_quadric_epsilon: f32,
    ) !void {
        try sqem.computePointSQEMs(
            mad.app_ctx,
            mad.point_cloud,
            mad.point_position,
            mad.point_normal,
            // mad.point_area,
            mad.point_tangent_basis,
            line_quadric_epsilon,
            mad.point_sqem,
        );
    }

    fn computeClusters(mad: *MedialAxisData) !void {
        assert(mad.initialized);
        // clean up previous clusters
        var s_it = mad.spheres.pointIterator();
        while (s_it.next()) |s| {
            mad.sphere_cluster.valuePtr(s).*.clearRetainingCapacity();
            mad.sphere_error.valuePtr(s).* = 0.0;
        }
        // mad.point_sphere.data.fill(null);
        // compute new clusters
        var p_it = mad.point_cloud.pointIterator();
        while (p_it.next()) |p| {
            const p_sqem = mad.point_sqem.valuePtr(p);
            var min_distance = std.math.floatMax(f32);
            var min_sphere: PointCloud.Point = undefined;
            const old_sphere = mad.point_sphere.value(p);
            // if there is a sphere assigned to this point, restrict the search to it and its neighbors
            if (old_sphere) |os| {
                {
                    const sc = mad.sphere_center.value(os);
                    const sr = mad.sphere_radius.value(os);
                    const dist = p_sqem.eval(.{ sc[0], sc[1], sc[2], sr });
                    if (dist < min_distance) {
                        min_distance = dist;
                        min_sphere = os;
                    }
                }
                const s_neighbors = mad.sphere_neighbor_spheres.valuePtr(os);
                for (s_neighbors.keys()) |osn| {
                    const osc = mad.sphere_center.value(osn);
                    const osr = mad.sphere_radius.value(osn);
                    const dist = p_sqem.eval(.{ osc[0], osc[1], osc[2], osr });
                    if (dist < min_distance) {
                        min_distance = dist;
                        min_sphere = osn;
                    }
                }
            } else { // if there is no sphere assigned to this vertex, search all spheres
                s_it.reset();
                while (s_it.next()) |s| {
                    const sc = mad.sphere_center.value(s);
                    const sr = mad.sphere_radius.value(s);
                    const dist = p_sqem.eval(.{ sc[0], sc[1], sc[2], sr });
                    if (dist < min_distance) {
                        min_distance = dist;
                        min_sphere = s;
                    }
                }
            }
            try mad.sphere_cluster.valuePtr(min_sphere).append(mad.app_ctx.allocator, p);
            mad.point_sphere.valuePtr(p).* = min_sphere;
            mad.point_sphere_color.valuePtr(p).* = mad.sphere_color.value(min_sphere);
            mad.point_sphere_error.valuePtr(p).* = min_distance;
            mad.sphere_error.valuePtr(min_sphere).* += min_distance;
        }
        // check clusters sizes & remove too small clusters
        s_it.reset();
        while (s_it.next()) |s| {
            if (mad.sphere_cluster.valuePtr(s).items.len < 4) {
                for (mad.sphere_cluster.valuePtr(s).items) |v| {
                    mad.point_sphere.valuePtr(v).* = null;
                }
                // do not forget to deinit ArrayList in sphere_cluster data & ArrayHashMap in sphere_neighbor_spheres data
                mad.sphere_cluster.valuePtr(s).deinit(mad.app_ctx.allocator);
                mad.sphere_neighbor_spheres.valuePtr(s).deinit(mad.app_ctx.allocator);
                mad.spheres.removePoint(s); // it is safe to remove the point while iterating
            }
        }
        // update clusters neighbors
        s_it.reset();
        while (s_it.next()) |s| {
            mad.sphere_neighbor_spheres.valuePtr(s).clearRetainingCapacity();
        }
        p_it.reset();
        while (p_it.next()) |p| {
            const neighbors = mad.point_knn.value(p);
            const s1 = mad.point_sphere.value(p);
            for (neighbors.items) |n| {
                const s2 = mad.point_sphere.value(n);
                if (s1 != null and s2 != null and s1.? != s2.?) {
                    try mad.sphere_neighbor_spheres.valuePtr(s1.?).put(mad.app_ctx.allocator, s2.?, {});
                    try mad.sphere_neighbor_spheres.valuePtr(s2.?).put(mad.app_ctx.allocator, s1.?, {});
                }
            }
        }
    }

    pub fn updateSpheres(mad: *MedialAxisData) !void {
        assert(mad.initialized);

        var previous_error: f32 = 0.0;
        var nb_iterations: usize = 0;
        const max_iterations: usize = 50;

        var s_it = mad.spheres.pointIterator();

        while (nb_iterations < max_iterations) {
            s_it.reset();
            while (s_it.next()) |s| {
                // add the SQEM contributions of all vertices in the cluster
                const cluster = mad.sphere_cluster.valuePtr(s);
                var cluster_sqem: SQEM = .zero;
                for (cluster.items) |v| {
                    cluster_sqem.add(mad.point_sqem.valuePtr(v));
                }
                // compute the optimal sphere
                const optimized_sphere = cluster_sqem.optimalSphere();
                if (optimized_sphere) |opt_s| {
                    mad.sphere_center.valuePtr(s).* = .{ opt_s[0], opt_s[1], opt_s[2] };
                    mad.sphere_radius.valuePtr(s).* = opt_s[3];
                    // correct the optimal sphere on the medial axis
                    const s_center = .{ opt_s[0], opt_s[1], opt_s[2] };
                    const cp = mad.point_cloud_kdtree.nearestNeighborIndex(s_center) orelse continue;
                    const cp_pos = mad.point_position.value(cp);
                    var cp_dir = vec.normalized3f(vec.sub3f(cp_pos, s_center));
                    const cp_normal = mad.point_normal.value(cp);
                    if (vec.dot3f(cp_dir, cp_normal) <= 0.0) {
                        cp_dir = vec.mulScalar3f(cp_dir, -1.0);
                    }
                    const corrected_sphere = medialAxis.shrinkingBall(
                        mad.point_cloud_kdtree,
                        vec.add3f(cp_pos, vec.mulScalar3f(cp_dir, -1e-4)),
                        cp_dir,
                    );
                    if (corrected_sphere) |cs| {
                        mad.sphere_center.valuePtr(s).* = .{ cs[0], cs[1], cs[2] };
                        mad.sphere_radius.valuePtr(s).* = cs[3];
                    }
                    // else {
                    //     mad.sphere_center.valuePtr(s).* = .{ opt_s[0], opt_s[1], opt_s[2] };
                    //     mad.sphere_radius.valuePtr(s).* = opt_s[3];
                    // }
                }
            }

            try mad.computeClusters();

            nb_iterations += 1;

            var current_error: f32 = 0.0;
            s_it.reset();
            while (s_it.next()) |s| {
                current_error += mad.sphere_error.value(s);
            }
            if (@abs(current_error - previous_error) < 1e-6) {
                break;
            }
            previous_error = current_error;
        }
    }

    pub fn splitWorstSphere(mad: *MedialAxisData) !void {
        assert(mad.initialized);
        var worst_sphere: PointCloud.Point = undefined;
        var worst_error: f32 = -1.0;
        var s_it = mad.spheres.pointIterator();
        while (s_it.next()) |s| {
            const err = mad.sphere_error.value(s);
            if (err > worst_error) {
                worst_error = err;
                worst_sphere = s;
            }
        }
        var worst_point: PointCloud.Point = undefined;
        var worst_point_error: f32 = -1.0;
        for (mad.sphere_cluster.valuePtr(worst_sphere).items) |p| {
            const err = mad.point_sphere_error.value(p);
            if (err > worst_point_error) {
                worst_point_error = err;
                worst_point = p;
            }
        }
        const s = try mad.spheres.addPoint();
        const sb = mad.point_shrinking_ball.value(worst_point);
        if (sb) |ball| {
            mad.sphere_center.valuePtr(s).* = .{ ball[0], ball[1], ball[2] };
            mad.sphere_radius.valuePtr(s).* = ball[3];
        } else {
            const n = mad.point_normal.value(worst_point);
            mad.sphere_center.valuePtr(s).* = vec.add3f(
                mad.point_position.value(worst_point),
                vec.mulScalar3f(n, -0.01),
            );
            mad.sphere_radius.valuePtr(s).* = 0.01;
        }
        var r = mad.app_ctx.rng.random();
        mad.sphere_color.valuePtr(s).* = .{ 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32) };
        mad.sphere_cluster.valuePtr(s).* = .empty;
        mad.sphere_error.valuePtr(s).* = 0.0;
        mad.sphere_neighbor_spheres.valuePtr(s).* = .empty;

        try mad.sphere_neighbor_spheres.valuePtr(worst_sphere).put(mad.app_ctx.allocator, s, {});
        try mad.sphere_neighbor_spheres.valuePtr(s).put(mad.app_ctx.allocator, worst_sphere, {});
        mad.point_sphere.valuePtr(worst_point).* = s;

        try mad.computeClusters();
    }

    pub fn updateSkeleton(mad: *MedialAxisData) !void {
        assert(mad.initialized);

        var sphere_skeleton_vertex = try mad.spheres.addData(IncidenceGraph.Cell, "__sphere_skeleton_vertex");
        defer mad.spheres.removeData(IncidenceGraph.Cell, sphere_skeleton_vertex);
        var skeleton_edges: std.AutoHashMapUnmanaged([2]IncidenceGraph.Cell, IncidenceGraph.Cell) = .empty;
        defer skeleton_edges.deinit(mad.app_ctx.allocator);

        mad.skeleton.clearRetainingCapacity();
        var s_it = mad.spheres.pointIterator();
        s_it.reset();
        while (s_it.next()) |s| {
            const v = try mad.skeleton.addVertex();
            sphere_skeleton_vertex.valuePtr(s).* = v;
            mad.skeleton_vertex_position.valuePtr(v).* = mad.sphere_center.value(s);
            const s_neighbors = mad.sphere_neighbor_spheres.valuePtr(s);
            for (s_neighbors.keys()) |sn| {
                if (sn < s) {
                    const sn_v = sphere_skeleton_vertex.value(sn);
                    const e = try mad.skeleton.addEdge(v, sn_v);
                    // store edge with canonical ordering of vertices (smaller index first)
                    try skeleton_edges.put(mad.app_ctx.allocator, .{ if (v.index() < sn_v.index()) v else sn_v, if (v.index() < sn_v.index()) sn_v else v }, e);
                }
            }
        }
        s_it.reset();
        while (s_it.next()) |s| {
            const s_neighbors = mad.sphere_neighbor_spheres.valuePtr(s);
            for (s_neighbors.keys()) |sn| {
                if (s < sn) continue;
                const sn_neighbors = mad.sphere_neighbor_spheres.valuePtr(sn);
                for (sn_neighbors.keys()) |snn| {
                    if (sn < s and snn < sn and s_neighbors.contains(snn)) {
                        const v1 = sphere_skeleton_vertex.value(s);
                        const v2 = sphere_skeleton_vertex.value(sn);
                        const v3 = sphere_skeleton_vertex.value(snn);
                        const edges: [3]IncidenceGraph.Cell = .{
                            skeleton_edges.get(.{ if (v1.index() < v2.index()) v1 else v2, if (v1.index() < v2.index()) v2 else v1 }).?,
                            skeleton_edges.get(.{ if (v2.index() < v3.index()) v2 else v3, if (v2.index() < v3.index()) v3 else v2 }).?,
                            skeleton_edges.get(.{ if (v3.index() < v1.index()) v3 else v1, if (v3.index() < v1.index()) v1 else v3 }).?,
                        };
                        _ = try mad.skeleton.addFace(&edges);
                    }
                }
            }
        }
    }
};

app_ctx: *AppContext,
module: Module = .{
    .name = "Point Cloud Medial Axis",
    .supported_models = .{ .point_cloud = true },
    .vtable = &.{
        .pointCloudCreated = pointCloudCreated,
        .pointCloudDestroyed = pointCloudDestroyed,
        // TODO: should manage PointCloud connectivity & vertex_position updates
        // TODO: should manage the destruction of the PointClouds and IncidenceGraph
        .rightPanel = rightPanel,
    },
},
point_clouds_data: std.AutoHashMapUnmanaged(*PointCloud, MedialAxisData) = .empty,

pub fn init(app_ctx: *AppContext) PointCloudMedialAxis {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(pcma: *PointCloudMedialAxis) void {
    var it = pcma.point_clouds_data.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    pcma.point_clouds_data.deinit(pcma.app_ctx.allocator);
}

/// Part of the Module interface.
/// Create and store a MedialAxisData for the created PointCloud.
pub fn pointCloudCreated(m: *Module, point_cloud: *PointCloud) void {
    const pcma: *PointCloudMedialAxis = @alignCast(@fieldParentPtr("module", m));
    pcma.point_clouds_data.put(pcma.app_ctx.allocator, point_cloud, .{
        .app_ctx = pcma.app_ctx,
        .point_cloud = point_cloud,
    }) catch |err| {
        std.debug.print("Failed to store MedialAxisData for new PointCloud: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Remove the MedialAxisData associated to the destroyed PointCloud.
pub fn pointCloudDestroyed(m: *Module, point_cloud: *PointCloud) void {
    const pcma: *PointCloudMedialAxis = @alignCast(@fieldParentPtr("module", m));
    const mad = pcma.point_clouds_data.getPtr(point_cloud) orelse return;
    mad.deinit();
    _ = pcma.point_clouds_data.remove(point_cloud);
}

/// Part of the Module interface.
/// Show a UI panel to control the medial axis data of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const pcma: *PointCloudMedialAxis = @alignCast(@fieldParentPtr("module", m));
    const pc_store = &pcma.app_ctx.point_cloud_store;

    assert(pcma.app_ctx.selected_model.modelType() == .point_cloud);
    const pc = pcma.app_ctx.selected_model.point_cloud;

    const UiData = struct {
        var line_quadric_epsilon: f32 = 0.2;
        var nb_spheres: usize = 100;
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const info = pc_store.pointCloudInfo(pc);
    const mad = pcma.point_clouds_data.getPtr(pc).?;
    c.ImGui_PushID("Line Quadric Epsilon");
    _ = c.ImGui_SliderFloatEx("", &UiData.line_quadric_epsilon, 0.001, 1.0, "%.3f", c.ImGuiSliderFlags_Logarithmic);
    c.ImGui_PopID();
    const disabled =
        !info.kdtree.initialized or
        info.std_datas.position == null or
        info.std_datas.normal == null;
    if (disabled) {
        c.ImGui_BeginDisabled(true);
    }
    if (c.ImGui_ButtonEx(if (mad.initialized) "Reinitialize all data" else "Initialize data", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
        mad.init(
            &info.kdtree,
            info.std_datas.position.?,
            info.std_datas.normal.?,
            UiData.line_quadric_epsilon,
        ) catch |err| {
            std.debug.print("Failed to initialize Medial Axis data for PointCloud: {}\n", .{err});
        };
    }
    if (mad.initialized) {
        if (c.ImGui_ButtonEx("Recompute SQEMs", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            mad.recomputeSQEMs(UiData.line_quadric_epsilon) catch |err| {
                std.debug.print("Failed to recompute Medial Axis SQEMs for PointCloud: {}\n", .{err});
            };
            mad.updateSpheres() catch |err| {
                std.debug.print("Failed to update Medial Axis spheres for PointCloud: {}\n", .{err});
            };
            mad.updateSkeleton() catch |err| {
                std.debug.print("Failed to update Medial Axis skeleton for SurfaceMesh: {}\n", .{err});
            };
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, mad.sphere_center);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, mad.sphere_radius);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, mad.sphere_error);
            mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres);
            mad.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(mad.skeleton, .vertex, Vec3f, mad.skeleton_vertex_position);
            mad.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(mad.skeleton);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, Vec3f, mad.point_sphere_color);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, f32, mad.point_sphere_error);
            mad.app_ctx.requestRedraw();
        }
    }
    if (disabled) {
        c.ImGui_EndDisabled();
    }
    if (mad.initialized) {
        if (c.ImGui_ButtonEx("Update spheres", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            mad.updateSpheres() catch |err| {
                std.debug.print("Failed to update Medial Axis spheres for SurfaceMesh: {}\n", .{err});
            };
            mad.updateSkeleton() catch |err| {
                std.debug.print("Failed to update Medial Axis skeleton for SurfaceMesh: {}\n", .{err});
            };
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, mad.sphere_center);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, mad.sphere_radius);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, mad.sphere_error);
            mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres);
            mad.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(mad.skeleton, .vertex, Vec3f, mad.skeleton_vertex_position);
            mad.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(mad.skeleton);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, Vec3f, mad.point_sphere_color);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, f32, mad.point_sphere_error);
            mad.app_ctx.requestRedraw();
        }
        if (c.ImGui_ButtonEx("Split worst sphere", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            mad.splitWorstSphere() catch |err| {
                std.debug.print("Failed to split worst Medial Axis sphere for SurfaceMesh: {}\n", .{err});
            };
            mad.updateSkeleton() catch |err| {
                std.debug.print("Failed to update Medial Axis skeleton for SurfaceMesh: {}\n", .{err});
            };
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, mad.sphere_center);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, mad.sphere_radius);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, mad.sphere_error);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, mad.sphere_color);
            mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres);
            mad.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(mad.skeleton, .vertex, Vec3f, mad.skeleton_vertex_position);
            mad.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(mad.skeleton);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, Vec3f, mad.point_sphere_color);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, f32, mad.point_sphere_error);
            mad.app_ctx.requestRedraw();
        }
        _ = c.ImGui_InputInt("Number of spheres", @ptrCast(&UiData.nb_spheres));
        if (c.ImGui_ButtonEx("Build skeleton from scratch", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            const t = std.Io.Timestamp.now(pcma.app_ctx.io, .real);

            mad.init(
                &info.kdtree,
                info.std_datas.position.?,
                info.std_datas.normal.?,
                UiData.line_quadric_epsilon,
            ) catch |err| {
                std.debug.print("Failed to initialize Medial Axis data for PointCloud: {}\n", .{err});
                return;
            };
            for (1..UiData.nb_spheres) |_| {
                mad.splitWorstSphere() catch |err| {
                    std.debug.print("Failed to split worse Medial Axis sphere for PointCloud: {}\n", .{err});
                    break;
                };
                mad.updateSpheres() catch |err| {
                    std.debug.print("Failed to update Medial Axis spheres for PointCloud: {}\n", .{err});
                    break;
                };
            }
            mad.updateSkeleton() catch |err| {
                std.debug.print("Failed to update Medial Axis skeleton for SurfaceMesh: {}\n", .{err});
            };
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, mad.sphere_center);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, mad.sphere_radius);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, mad.sphere_error);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, mad.sphere_color);
            mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres);
            mad.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(mad.skeleton, .vertex, Vec3f, mad.skeleton_vertex_position);
            mad.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(mad.skeleton);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, Vec3f, mad.point_sphere_color);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, f32, mad.point_sphere_error);
            mad.app_ctx.requestRedraw();

            const elapsed: f64 = @floatFromInt(std.Io.Timestamp.untilNow(t, pcma.app_ctx.io, .real).nanoseconds);
            zgp_log.info("Medial Axis skeleton computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
        }
    }
}
