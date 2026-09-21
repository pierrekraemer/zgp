const std = @import("std");

const PointCloud = @import("PointCloud.zig");
const IncidenceGraph = @import("../incidenceGraph/IncidenceGraph.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const geometry_utils = @import("../../geometry/utils.zig");
const kdtree = @import("../../geometry/kdtree.zig");
const SQEM = @import("../../geometry/SQEM.zig");

const tangent_basis = @import("tangent_basis.zig");
const sqem = @import("sqem.zig");

pub fn shrinkingBall(
    pc_kdtree: *kdtree.PointsKDTree,
    p: Vec3f,
    n: Vec3f,
) ?Vec4f {
    var r: f32 = 0.5; // TODO: arbitrary value for the initial radius
    var c = vec.sub3f(p, vec.mulScalar3f(n, r));
    var q = vec.sub3f(p, vec.mulScalar3f(n, 2.0 * r));
    var j: u32 = 0;
    while (true) {
        const q_next = pc_kdtree.nearestNeighbor(c) orelse return null;
        const dist = vec.norm3f(vec.sub3f(q_next, c));
        if (@abs(dist - r) < 1e-4 or vec.norm3f(vec.sub3f(q_next, q)) < 1e-4 or vec.norm3f(vec.sub3f(p, q_next)) < 1e-4) { // TODO: use a better epsilon?
            break;
        }
        const r_next = blk: {
            const qp = vec.sub3f(p, q_next);
            const d = vec.norm3f(qp);
            const cos_theta = geometry_utils.cosAngle(n, qp);
            break :blk d / (2.0 * cos_theta);
        };
        const c_next = vec.sub3f(p, vec.mulScalar3f(n, r_next));
        const sep_angle = geometry_utils.angle(vec.sub3f(p, c_next), vec.sub3f(q_next, c_next));
        if (j > 0 and sep_angle < 35.0 * std.math.pi / 180.0) { // TODO: use a configurable angle threshold?
            break;
        }
        r = r_next;
        c = c_next;
        q = q_next;
        j += 1;
        if (j > 30) {
            std.debug.print("Shrinking ball: too many iterations\n", .{});
            break;
        }
    }
    if (vec.norm3f(vec.sub3f(p, q)) < 1e-4) {
        std.debug.print("Warning: shrinking ball center is too close to the point\n", .{});
    }
    return .{ c[0], c[1], c[2], r };
}

/// Compute the shrinking balls for all points of the given PointCloud
pub fn computePointShrinkingBalls(
    io: std.Io,
    pc: *PointCloud,
    pc_kdtree: *kdtree.PointsKDTree,
    point_position: PointCloud.CellData(Vec3f),
    point_normal: PointCloud.CellData(Vec3f),
    point_shrinking_ball: PointCloud.CellData(?Vec4f),
) !void {
    const Task = struct {
        const Task = @This();

        point_cloud: *const PointCloud,
        pc_kdtree: *kdtree.PointsKDTree,
        point_position: PointCloud.CellData(Vec3f),
        point_normal: PointCloud.CellData(Vec3f),
        point_shrinking_ball: PointCloud.CellData(?Vec4f),

        pub fn run(t: *const Task, point: PointCloud.Point) void {
            const n = t.point_normal.value(point);
            t.point_shrinking_ball.valuePtr(point).* = shrinkingBall(
                t.pc_kdtree,
                vec.add3f(t.point_position.value(point), vec.mulScalar3f(n, -1e-4)),
                n,
            );
        }
    };

    var pctr: PointCloud.ParallelPointTaskRunner = try .init(pc);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .point_cloud = pc,
        .pc_kdtree = pc_kdtree,
        .point_position = point_position,
        .point_normal = point_normal,
        .point_shrinking_ball = point_shrinking_ball,
    });
}

/// Context for computing medial axis of a PointCloud using the Variational Medial Axis Skeleton (VMAS) method.
pub const VMASContext = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    point_cloud: *PointCloud,
    // given data
    point_cloud_kdtree: *kdtree.PointsKDTree,
    point_position: PointCloud.CellData(Vec3f),
    point_normal: PointCloud.CellData(Vec3f),
    // created data
    point_knn: PointCloud.CellData(std.ArrayList(PointCloud.Point)),
    point_tangent_basis: PointCloud.CellData([2]Vec3f),
    // point_area: PointCloud.CellData(f32),
    point_sqem: PointCloud.CellData(SQEM),
    point_shrinking_ball: PointCloud.CellData(?Vec4f),
    point_sphere: PointCloud.CellData(?PointCloud.Point),
    point_sphere_error: PointCloud.CellData(f32),

    spheres: *PointCloud,
    // created data
    sphere_center: PointCloud.CellData(Vec3f),
    sphere_radius: PointCloud.CellData(f32),
    sphere_cluster: PointCloud.CellData(std.ArrayList(PointCloud.Point)),
    sphere_error: PointCloud.CellData(f32),
    sphere_neighbor_spheres: PointCloud.CellData(std.AutoArrayHashMapUnmanaged(PointCloud.Point, void)),

    skeleton: *IncidenceGraph,
    // created data
    skeleton_vertex_position: IncidenceGraph.CellData(.vertex, Vec3f),

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        point_cloud: *PointCloud,
        point_cloud_kdtree: *kdtree.PointsKDTree,
        point_position: PointCloud.CellData(Vec3f),
        point_normal: PointCloud.CellData(Vec3f),
        spheres: *PointCloud,
        skeleton: *IncidenceGraph,
        line_quadric_epsilon: f32,
    ) !VMASContext {
        // create point_cloud data
        const point_knn = try point_cloud.addData(std.ArrayList(PointCloud.Point), "knn");
        point_knn.data.fill(.empty);
        const point_tangent_basis = try point_cloud.addData([2]Vec3f, "tangent_basis");
        // const point_area = try point_cloud.addData(f32, "area");
        const point_sqem = try point_cloud.addData(SQEM, "sqem");
        const point_shrinking_ball = try point_cloud.addData(?Vec4f, "shrinking_ball");
        const point_sphere = try point_cloud.addData(?PointCloud.Point, "sphere");
        const point_sphere_error = try point_cloud.addData(f32, "sphere_error");

        spheres.clearRetainingCapacity();

        // create medial spheres PointCloud data
        const sphere_center = try spheres.addData(Vec3f, "center");
        const sphere_radius = try spheres.addData(f32, "radius");
        const sphere_cluster = try spheres.addData(std.ArrayList(PointCloud.Point), "cluster");
        const sphere_error = try spheres.addData(f32, "error");
        const sphere_neighbor_spheres = try spheres.addData(std.AutoArrayHashMapUnmanaged(PointCloud.Point, void), "neighbor_spheres");

        skeleton.clearRetainingCapacity();

        // create skeleton IncidenceGraph data
        const skeleton_vertex_position = try skeleton.addData(.vertex, Vec3f, "position");

        try tangent_basis.computePointTangentBases(
            io,
            point_cloud,
            point_normal,
            point_tangent_basis,
        );

        // compute knn graph of points
        var p_it = point_cloud.pointIterator();
        while (p_it.next()) |p| {
            point_knn.valuePtr(p).deinit(allocator);
            var nns = try point_cloud_kdtree.nearestNeighbors(allocator, point_position.value(p), 6);
            const p_idx = std.mem.findScalar(PointCloud.Point, nns.items, p);
            if (p_idx) |idx| {
                _ = nns.swapRemove(idx); // remove the point itself from its neighbors
            }
            point_knn.valuePtr(p).* = nns;
        }

        try sqem.computePointSQEMs(
            io,
            point_cloud,
            point_position,
            point_normal,
            // point_area,
            point_tangent_basis,
            line_quadric_epsilon,
            point_sqem,
        );

        // compute points shrinking balls
        try computePointShrinkingBalls(
            io,
            point_cloud,
            point_cloud_kdtree,
            point_position,
            point_normal,
            point_shrinking_ball,
        );

        // create the first medial sphere
        const center: Vec3f = .{ 0.0, 0.0, 0.0 };
        const radius: f32 = 0.01;
        const s1 = try spheres.addPoint();
        sphere_center.valuePtr(s1).* = center;
        sphere_radius.valuePtr(s1).* = radius;
        sphere_cluster.valuePtr(s1).* = .empty;
        sphere_error.valuePtr(s1).* = 0.0;
        sphere_neighbor_spheres.valuePtr(s1).* = .empty;

        // and initialize its cluster
        p_it.reset();
        while (p_it.next()) |p| {
            try sphere_cluster.valuePtr(s1).append(allocator, p);
            point_sphere.valuePtr(p).* = s1;
            const p_sqem = point_sqem.valuePtr(p);
            const dist = p_sqem.eval(.{ center[0], center[1], center[2], radius });
            point_sphere_error.valuePtr(p).* = dist;
            sphere_error.valuePtr(s1).* += dist;
        }

        return .{
            .allocator = allocator,
            .io = io,

            .point_cloud = point_cloud,
            .point_cloud_kdtree = point_cloud_kdtree,
            .point_position = point_position,
            .point_normal = point_normal,

            .point_knn = point_knn,
            .point_tangent_basis = point_tangent_basis,
            // .point_area = point_area,
            .point_sqem = point_sqem,
            .point_shrinking_ball = point_shrinking_ball,
            .point_sphere = point_sphere,
            .point_sphere_error = point_sphere_error,

            .spheres = spheres,
            .sphere_center = sphere_center,
            .sphere_radius = sphere_radius,
            .sphere_cluster = sphere_cluster,
            .sphere_error = sphere_error,
            .sphere_neighbor_spheres = sphere_neighbor_spheres,

            .skeleton = skeleton,
            .skeleton_vertex_position = skeleton_vertex_position,
        };
    }

    pub fn deinit(vmas_ctx: *VMASContext) void {
        // remove PointCloud data
        // first deinit ArrayLists in point_knn data
        var p_it = vmas_ctx.point_cloud.pointIterator();
        while (p_it.next()) |p| {
            vmas_ctx.point_knn.valuePtr(p).deinit(vmas_ctx.allocator);
        }
        vmas_ctx.point_cloud.removeData(std.ArrayList(PointCloud.Point), vmas_ctx.point_knn);
        vmas_ctx.point_cloud.removeData([2]Vec3f, vmas_ctx.point_tangent_basis);
        vmas_ctx.point_cloud.removeData(SQEM, vmas_ctx.point_sqem);
        vmas_ctx.point_cloud.removeData(?Vec4f, vmas_ctx.point_shrinking_ball);
        vmas_ctx.point_cloud.removeData(?PointCloud.Point, vmas_ctx.point_sphere);
        vmas_ctx.point_cloud.removeData(f32, vmas_ctx.point_sphere_error);

        // remove spheres PointCloud data
        // first deinit ArrayLists in sphere_cluster data & ArrayHashMaps in sphere_neighbor_spheres data
        var s_it = vmas_ctx.spheres.pointIterator();
        while (s_it.next()) |s| {
            vmas_ctx.sphere_cluster.valuePtr(s).deinit(vmas_ctx.allocator);
            vmas_ctx.sphere_neighbor_spheres.valuePtr(s).deinit(vmas_ctx.allocator);
        }
        vmas_ctx.spheres.removeData(std.ArrayList(PointCloud.Point), vmas_ctx.sphere_cluster);
        vmas_ctx.spheres.removeData(f32, vmas_ctx.sphere_error);
        vmas_ctx.spheres.removeData(std.AutoArrayHashMapUnmanaged(PointCloud.Point, void), vmas_ctx.sphere_neighbor_spheres);
        // do not destroy the spheres PointCloud itself and its position and radius data

        // do not destroy the skeleton IncidenceGraph itself and its vertex position and radius data
    }

    pub fn updatePointSQEMs(vmas_ctx: *VMASContext, line_quadric_epsilon: f32) !void {
        try sqem.computePointSQEMs(
            vmas_ctx.io,
            vmas_ctx.point_cloud,
            vmas_ctx.point_position,
            vmas_ctx.point_normal,
            // vmas_ctx.point_area,
            vmas_ctx.point_tangent_basis,
            line_quadric_epsilon,
            vmas_ctx.point_sqem,
        );
    }

    pub fn computeClusters(vmas_ctx: *VMASContext) !void {
        // clean up previous clusters
        var s_it = vmas_ctx.spheres.pointIterator();
        while (s_it.next()) |s| {
            vmas_ctx.sphere_cluster.valuePtr(s).*.clearRetainingCapacity();
            vmas_ctx.sphere_error.valuePtr(s).* = 0.0;
        }
        // compute new clusters
        var p_it = vmas_ctx.point_cloud.pointIterator();
        while (p_it.next()) |p| {
            const p_sqem = vmas_ctx.point_sqem.valuePtr(p);
            var min_distance = std.math.floatMax(f32);
            var min_sphere: PointCloud.Point = undefined;
            const old_sphere = vmas_ctx.point_sphere.value(p);
            // if there is a sphere assigned to this point, restrict the search to it and its neighbors
            if (old_sphere) |os| {
                {
                    const sc = vmas_ctx.sphere_center.value(os);
                    const sr = vmas_ctx.sphere_radius.value(os);
                    const dist = p_sqem.eval(.{ sc[0], sc[1], sc[2], sr });
                    if (dist < min_distance) {
                        min_distance = dist;
                        min_sphere = os;
                    }
                }
                const s_neighbors = vmas_ctx.sphere_neighbor_spheres.valuePtr(os);
                for (s_neighbors.keys()) |osn| {
                    const osc = vmas_ctx.sphere_center.value(osn);
                    const osr = vmas_ctx.sphere_radius.value(osn);
                    const dist = p_sqem.eval(.{ osc[0], osc[1], osc[2], osr });
                    if (dist < min_distance) {
                        min_distance = dist;
                        min_sphere = osn;
                    }
                }
            } else { // if there is no sphere assigned to this vertex, search all spheres
                s_it.reset();
                while (s_it.next()) |s| {
                    const sc = vmas_ctx.sphere_center.value(s);
                    const sr = vmas_ctx.sphere_radius.value(s);
                    const dist = p_sqem.eval(.{ sc[0], sc[1], sc[2], sr });
                    if (dist < min_distance) {
                        min_distance = dist;
                        min_sphere = s;
                    }
                }
            }
            try vmas_ctx.sphere_cluster.valuePtr(min_sphere).append(vmas_ctx.allocator, p);
            vmas_ctx.point_sphere.valuePtr(p).* = min_sphere;
            vmas_ctx.point_sphere_error.valuePtr(p).* = min_distance;
            vmas_ctx.sphere_error.valuePtr(min_sphere).* += min_distance;
        }
        // check clusters sizes & remove too small clusters
        s_it.reset();
        while (s_it.next()) |s| {
            if (vmas_ctx.sphere_cluster.valuePtr(s).items.len < 4) {
                for (vmas_ctx.sphere_cluster.valuePtr(s).items) |v| {
                    vmas_ctx.point_sphere.valuePtr(v).* = null;
                }
                // do not forget to deinit ArrayList in sphere_cluster data & ArrayHashMap in sphere_neighbor_spheres data
                vmas_ctx.sphere_cluster.valuePtr(s).deinit(vmas_ctx.allocator);
                vmas_ctx.sphere_neighbor_spheres.valuePtr(s).deinit(vmas_ctx.allocator);
                vmas_ctx.spheres.removePoint(s); // it is safe to remove the point while iterating
            }
        }
        // update clusters neighbors
        s_it.reset();
        while (s_it.next()) |s| {
            vmas_ctx.sphere_neighbor_spheres.valuePtr(s).clearRetainingCapacity();
        }
        p_it.reset();
        while (p_it.next()) |p| {
            const neighbors = vmas_ctx.point_knn.value(p);
            const s1 = vmas_ctx.point_sphere.value(p);
            for (neighbors.items) |n| {
                const s2 = vmas_ctx.point_sphere.value(n);
                if (s1 != null and s2 != null and s1.? != s2.?) {
                    try vmas_ctx.sphere_neighbor_spheres.valuePtr(s1.?).put(vmas_ctx.allocator, s2.?, {});
                    try vmas_ctx.sphere_neighbor_spheres.valuePtr(s2.?).put(vmas_ctx.allocator, s1.?, {});
                }
            }
        }
    }

    pub fn updateSpheres(vmas_ctx: *VMASContext) !void {
        var previous_error: f32 = 0.0;
        var nb_iterations: usize = 0;
        const max_iterations: usize = 50;

        var s_it = vmas_ctx.spheres.pointIterator();

        while (nb_iterations < max_iterations) {
            s_it.reset();

            // compute the optimal spheres for each cluster
            while (s_it.next()) |s| {
                // add the SQEM contributions of all vertices in the cluster
                const cluster = vmas_ctx.sphere_cluster.valuePtr(s);
                var cluster_sqem: SQEM = .zero;
                for (cluster.items) |v| {
                    cluster_sqem.add(vmas_ctx.point_sqem.valuePtr(v));
                }
                // compute the optimal sphere
                const optimized_sphere = cluster_sqem.optimalSphere();
                if (optimized_sphere) |opt_s| {
                    vmas_ctx.sphere_center.valuePtr(s).* = .{ opt_s[0], opt_s[1], opt_s[2] };
                    vmas_ctx.sphere_radius.valuePtr(s).* = opt_s[3];
                    // correct the optimal sphere on the medial axis
                    const s_center = .{ opt_s[0], opt_s[1], opt_s[2] };
                    const cp = vmas_ctx.point_cloud_kdtree.nearestNeighborIndex(s_center) orelse continue;
                    const cp_pos = vmas_ctx.point_position.value(cp);
                    var cp_dir = vec.normalized3f(vec.sub3f(cp_pos, s_center));
                    const cp_normal = vmas_ctx.point_normal.value(cp);
                    if (vec.dot3f(cp_dir, cp_normal) <= 0.0) {
                        cp_dir = vec.mulScalar3f(cp_dir, -1.0);
                    }
                    const corrected_sphere = shrinkingBall(
                        vmas_ctx.point_cloud_kdtree,
                        vec.add3f(cp_pos, vec.mulScalar3f(cp_dir, -1e-4)),
                        cp_dir,
                    );
                    if (corrected_sphere) |cs| {
                        vmas_ctx.sphere_center.valuePtr(s).* = .{ cs[0], cs[1], cs[2] };
                        vmas_ctx.sphere_radius.valuePtr(s).* = cs[3];
                    }
                }
            }

            // update the clusters
            try vmas_ctx.computeClusters();

            // check for convergence
            nb_iterations += 1;
            var current_error: f32 = 0.0;
            s_it.reset();
            while (s_it.next()) |s| {
                current_error += vmas_ctx.sphere_error.value(s);
            }
            if (@abs(current_error - previous_error) < 1e-6) {
                break;
            }
            previous_error = current_error;
        }
    }

    pub fn updateSkeleton(vmas_ctx: *VMASContext) !void {
        var sphere_skeleton_vertex = try vmas_ctx.spheres.addData(IncidenceGraph.Cell, "__sphere_skeleton_vertex");
        defer vmas_ctx.spheres.removeData(IncidenceGraph.Cell, sphere_skeleton_vertex);
        var skeleton_edges: std.AutoHashMapUnmanaged([2]IncidenceGraph.Cell, IncidenceGraph.Cell) = .empty;
        defer skeleton_edges.deinit(vmas_ctx.allocator);

        vmas_ctx.skeleton.clearRetainingCapacity();
        var s_it = vmas_ctx.spheres.pointIterator();
        s_it.reset();
        while (s_it.next()) |s| {
            const v = try vmas_ctx.skeleton.addVertex();
            sphere_skeleton_vertex.valuePtr(s).* = v;
            vmas_ctx.skeleton_vertex_position.valuePtr(v).* = vmas_ctx.sphere_center.value(s);
            const s_neighbors = vmas_ctx.sphere_neighbor_spheres.valuePtr(s);
            for (s_neighbors.keys()) |sn| {
                if (sn < s) {
                    const sn_v = sphere_skeleton_vertex.value(sn);
                    const e = try vmas_ctx.skeleton.addEdge(v, sn_v);
                    // store edge with canonical ordering of vertices (smaller index first)
                    try skeleton_edges.put(
                        vmas_ctx.allocator,
                        if (v.index() < sn_v.index()) .{ v, sn_v } else .{ sn_v, v },
                        e,
                    );
                }
            }
        }
        s_it.reset();
        while (s_it.next()) |s| {
            const s_neighbors = vmas_ctx.sphere_neighbor_spheres.valuePtr(s);
            for (s_neighbors.keys()) |sn| {
                if (s < sn) continue;
                const sn_neighbors = vmas_ctx.sphere_neighbor_spheres.valuePtr(sn);
                for (sn_neighbors.keys()) |snn| {
                    if (sn < s and snn < sn and s_neighbors.contains(snn)) {
                        const v1 = sphere_skeleton_vertex.value(s);
                        const v2 = sphere_skeleton_vertex.value(sn);
                        const v3 = sphere_skeleton_vertex.value(snn);
                        const edges: [3]IncidenceGraph.Cell = .{
                            skeleton_edges.get(if (v1.index() < v2.index()) .{ v1, v2 } else .{ v2, v1 }).?,
                            skeleton_edges.get(if (v2.index() < v3.index()) .{ v2, v3 } else .{ v3, v2 }).?,
                            skeleton_edges.get(if (v3.index() < v1.index()) .{ v3, v1 } else .{ v1, v3 }).?,
                        };
                        _ = try vmas_ctx.skeleton.addFace(&edges);
                    }
                }
            }
        }
    }

    pub fn worstSphere(vmas_ctx: *VMASContext) ?PointCloud.Point {
        var worst_sphere: ?PointCloud.Point = null;
        var worst_error: f32 = 0.0;
        var s_it = vmas_ctx.spheres.pointIterator();
        while (s_it.next()) |s| {
            const err = vmas_ctx.sphere_error.value(s);
            if (err > worst_error) {
                worst_error = err;
                worst_sphere = s;
            }
        }
        return worst_sphere;
    }

    pub fn splitSphere(vmas_ctx: *VMASContext, sphere: PointCloud.Point) !void {
        var worst_point: ?PointCloud.Point = null;
        var worst_point_error: f32 = 0.0;
        const cluster = vmas_ctx.sphere_cluster.valuePtr(sphere);
        for (cluster.items) |p| {
            const err = vmas_ctx.point_sphere_error.value(p);
            if (err > worst_point_error) {
                worst_point_error = err;
                worst_point = p;
            }
        }
        if (worst_point == null) {
            std.debug.print("Warning: no worst point found for sphere {}\n", .{sphere});
            return;
        }
        // create a new sphere
        const s = try vmas_ctx.spheres.addPoint();
        // assign this new sphere to the worst point
        vmas_ctx.point_sphere.valuePtr(worst_point.?).* = s;
        // compute the shrinking ball for the worst point
        const sb = vmas_ctx.point_shrinking_ball.value(worst_point.?);
        if (sb) |ball| {
            vmas_ctx.sphere_center.valuePtr(s).* = .{ ball[0], ball[1], ball[2] };
            vmas_ctx.sphere_radius.valuePtr(s).* = ball[3];
        } else {
            const n = vmas_ctx.point_normal.value(worst_point.?);
            vmas_ctx.sphere_center.valuePtr(s).* = vec.add3f(
                vmas_ctx.point_position.value(worst_point.?),
                vec.mulScalar3f(n, -0.01),
            );
            vmas_ctx.sphere_radius.valuePtr(s).* = 0.01;
        }
        vmas_ctx.sphere_cluster.valuePtr(s).* = .empty;
        vmas_ctx.sphere_error.valuePtr(s).* = 0.0;
        vmas_ctx.sphere_neighbor_spheres.valuePtr(s).* = .empty;

        try vmas_ctx.sphere_neighbor_spheres.valuePtr(sphere).put(vmas_ctx.allocator, s, {});
        try vmas_ctx.sphere_neighbor_spheres.valuePtr(s).put(vmas_ctx.allocator, sphere, {});

        try vmas_ctx.computeClusters();
    }
};
