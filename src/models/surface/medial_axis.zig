const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const PointCloud = @import("../point/PointCloud.zig");
const IncidenceGraph = @import("../incidenceGraph/IncidenceGraph.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const geometry_utils = @import("../../geometry/utils.zig");
const bvh = @import("../../geometry/bvh.zig");
const SQEM = @import("../../geometry/SQEM.zig");

const sqem = @import("sqem.zig");

pub fn shrinkingBall(
    sm_bvh: *bvh.TrianglesBVH,
    p: Vec3f,
    n: Vec3f,
) ?Vec4f {
    var r = if (sm_bvh.intersectedSurfacePoint(.{ .origin = p, .direction = vec.mulScalar3f(n, -1.0) })) |sp| blk: {
        const ip = sp.readData(Vec3f, .vertex, sm_bvh.vertex_position);
        break :blk vec.norm3f(vec.sub3f(p, ip)) * 0.75;
    } else {
        return null;
    };
    var c = vec.sub3f(p, vec.mulScalar3f(n, r));
    var q = vec.sub3f(p, vec.mulScalar3f(n, 2.0 * r));
    var j: u32 = 0;
    while (true) {
        const q_next = sm_bvh.closestPoint(c);
        const dist = vec.norm3f(vec.sub3f(q_next, c));
        if (@abs(dist - r) < 1e-4 or vec.norm3f(vec.sub3f(q_next, q)) < 1e-4) { // TODO: use a better epsilon?
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
        if (j > 0 and sep_angle < 45.0 * std.math.pi / 180.0) { // TODO: use a configurable angle threshold?
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
    return .{ c[0], c[1], c[2], r };
}

/// Compute the shrinking balls for all vertices of the given SurfaceMesh
pub fn computeVertexShrinkingBalls(
    io: std.Io,
    sm: *SurfaceMesh,
    sm_bvh: *bvh.TrianglesBVH,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_shrinking_ball: SurfaceMesh.CellData(.vertex, ?Vec4f),
) !void {
    const Task = struct {
        const Task = @This();

        surface_mesh: *const SurfaceMesh,
        sm_bvh: *bvh.TrianglesBVH,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_shrinking_ball: SurfaceMesh.CellData(.vertex, ?Vec4f),

        pub fn run(t: *const Task, vertex: SurfaceMesh.Cell) void {
            const n = t.vertex_normal.value(vertex);
            t.vertex_shrinking_ball.valuePtr(vertex).* = shrinkingBall(
                t.sm_bvh,
                vec.add3f(t.vertex_position.value(vertex), vec.mulScalar3f(n, -1e-4)),
                n,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelCellTaskRunner = try .init(sm, .vertex);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .sm_bvh = sm_bvh,
        .vertex_position = vertex_position,
        .vertex_normal = vertex_normal,
        .vertex_shrinking_ball = vertex_shrinking_ball,
    });
}

/// Context for computing medial axis of a SurfaceMesh using the Variational Medial Axis Skeleton (VMAS) method.
pub const VMASContext = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    surface_mesh: *SurfaceMesh,
    // given data
    surface_mesh_bvh: *bvh.TrianglesBVH,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    // created data
    vertex_sqem: SurfaceMesh.CellData(.vertex, SQEM),
    vertex_shrinking_ball: SurfaceMesh.CellData(.vertex, ?Vec4f),
    vertex_sphere: SurfaceMesh.CellData(.vertex, ?PointCloud.Point),
    vertex_sphere_error: SurfaceMesh.CellData(.vertex, f32),

    spheres: *PointCloud,
    // created data
    sphere_center: PointCloud.CellData(Vec3f),
    sphere_radius: PointCloud.CellData(f32),
    sphere_cluster: PointCloud.CellData(std.ArrayList(SurfaceMesh.Cell)),
    sphere_error: PointCloud.CellData(f32),
    sphere_neighbor_spheres: PointCloud.CellData(std.AutoArrayHashMapUnmanaged(PointCloud.Point, void)),

    skeleton: *IncidenceGraph,
    // created data
    skeleton_vertex_position: IncidenceGraph.CellData(.vertex, Vec3f),

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        surface_mesh: *SurfaceMesh,
        surface_mesh_bvh: *bvh.TrianglesBVH,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_area: SurfaceMesh.CellData(.vertex, f32),
        vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
        face_area: SurfaceMesh.CellData(.face, f32),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),
        spheres: *PointCloud,
        skeleton: *IncidenceGraph,
        line_quadric_epsilon: f32,
    ) !VMASContext {
        // create surface_mesh vertex data
        const vertex_sqem = try surface_mesh.addData(.vertex, SQEM, "sqem");
        const vertex_shrinking_ball = try surface_mesh.addData(.vertex, ?Vec4f, "shrinking_ball");
        const vertex_sphere = try surface_mesh.addData(.vertex, ?PointCloud.Point, "sphere");
        const vertex_sphere_error = try surface_mesh.addData(.vertex, f32, "sphere_error");

        spheres.clearRetainingCapacity();

        // create medial spheres PointCloud data
        const sphere_center = try spheres.addData(Vec3f, "center");
        const sphere_radius = try spheres.addData(f32, "radius");
        const sphere_cluster = try spheres.addData(std.ArrayList(SurfaceMesh.Cell), "cluster");
        const sphere_error = try spheres.addData(f32, "error");
        const sphere_neighbor_spheres = try spheres.addData(std.AutoArrayHashMapUnmanaged(PointCloud.Point, void), "neighbor_spheres");

        skeleton.clearRetainingCapacity();

        // create skeleton IncidenceGraph data
        const skeleton_vertex_position = try skeleton.addData(.vertex, Vec3f, "position");

        try sqem.computeVertexSQEMs(
            io,
            surface_mesh,
            vertex_position,
            vertex_area,
            vertex_tangent_basis,
            face_area,
            face_normal,
            line_quadric_epsilon,
            vertex_sqem,
        );

        try computeVertexShrinkingBalls(
            io,
            surface_mesh,
            surface_mesh_bvh,
            vertex_position,
            vertex_normal,
            vertex_shrinking_ball,
        );

        return .{
            .allocator = allocator,
            .io = io,

            .surface_mesh = surface_mesh,
            .surface_mesh_bvh = surface_mesh_bvh,
            .vertex_position = vertex_position,
            .vertex_normal = vertex_normal,
            .vertex_area = vertex_area,
            .vertex_tangent_basis = vertex_tangent_basis,
            .face_area = face_area,
            .face_normal = face_normal,

            .vertex_sqem = vertex_sqem,
            .vertex_shrinking_ball = vertex_shrinking_ball,
            .vertex_sphere = vertex_sphere,
            .vertex_sphere_error = vertex_sphere_error,

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

    // deinitialize the VMASContext
    // the position & radius data of the spheres PointCloud and the vertex position data of the skeleton IncidenceGraph are not destroyed
    // TODO: maybe take a boolean argument to decide whether to destroy them or not?
    pub fn deinit(vmas_ctx: *VMASContext) void {
        // remove SurfaceMesh data
        vmas_ctx.surface_mesh.removeData(.vertex, SQEM, vmas_ctx.vertex_sqem);
        vmas_ctx.surface_mesh.removeData(.vertex, ?Vec4f, vmas_ctx.vertex_shrinking_ball);
        vmas_ctx.surface_mesh.removeData(.vertex, ?PointCloud.Point, vmas_ctx.vertex_sphere);
        vmas_ctx.surface_mesh.removeData(.vertex, f32, vmas_ctx.vertex_sphere_error);

        // remove spheres PointCloud data
        // first deinit ArrayLists in sphere_cluster data & ArrayHashMaps in sphere_neighbor_spheres data
        var s_it = vmas_ctx.spheres.pointIterator();
        while (s_it.next()) |s| {
            vmas_ctx.sphere_cluster.valuePtr(s).deinit(vmas_ctx.allocator);
            vmas_ctx.sphere_neighbor_spheres.valuePtr(s).deinit(vmas_ctx.allocator);
        }
        vmas_ctx.spheres.removeData(std.ArrayList(SurfaceMesh.Cell), vmas_ctx.sphere_cluster);
        vmas_ctx.spheres.removeData(f32, vmas_ctx.sphere_error);
        vmas_ctx.spheres.removeData(std.AutoArrayHashMapUnmanaged(PointCloud.Point, void), vmas_ctx.sphere_neighbor_spheres);
        // do not destroy the position and radius data of the spheres PointCloud

        // do not destroy the vertex position data of the skeleton IncidenceGraph
    }

    pub fn createFirstSphere(vmas_ctx: *VMASContext) !void {
        assert(vmas_ctx.spheres.nbPoints() == 0);

        // create the first medial sphere
        const center: Vec3f = .{ 0.0, 0.0, 0.0 };
        const radius: f32 = 0.01;
        const s1 = try vmas_ctx.spheres.addPoint();
        vmas_ctx.sphere_center.valuePtr(s1).* = center;
        vmas_ctx.sphere_radius.valuePtr(s1).* = radius;
        vmas_ctx.sphere_cluster.valuePtr(s1).* = .empty;
        vmas_ctx.sphere_error.valuePtr(s1).* = 0.0;
        vmas_ctx.sphere_neighbor_spheres.valuePtr(s1).* = .empty;

        // and initialize its cluster
        var v_it = try SurfaceMesh.CellIterator.init(vmas_ctx.surface_mesh, .vertex);
        defer v_it.deinit();
        while (v_it.next()) |v| {
            try vmas_ctx.sphere_cluster.valuePtr(s1).append(vmas_ctx.allocator, v);
            vmas_ctx.vertex_sphere.valuePtr(v).* = s1;
            const v_sqem = vmas_ctx.vertex_sqem.valuePtr(v);
            const dist = v_sqem.eval(.{ center[0], center[1], center[2], radius });
            vmas_ctx.vertex_sphere_error.valuePtr(v).* = dist;
            vmas_ctx.sphere_error.valuePtr(s1).* += dist;
        }
    }

    pub fn clearRetainingCapacity(vmas_ctx: *VMASContext) void {
        var s_it = vmas_ctx.spheres.pointIterator();
        while (s_it.next()) |s| {
            vmas_ctx.sphere_cluster.valuePtr(s).deinit(vmas_ctx.allocator);
            vmas_ctx.sphere_neighbor_spheres.valuePtr(s).deinit(vmas_ctx.allocator);
        }
        vmas_ctx.spheres.clearRetainingCapacity();
        vmas_ctx.skeleton.clearRetainingCapacity();
    }

    pub fn updateVertexSQEMs(vmas_ctx: *VMASContext, line_quadric_epsilon: f32) !void {
        try sqem.computeVertexSQEMs(
            vmas_ctx.io,
            vmas_ctx.surface_mesh,
            vmas_ctx.vertex_position,
            vmas_ctx.vertex_area,
            vmas_ctx.vertex_tangent_basis,
            vmas_ctx.face_area,
            vmas_ctx.face_normal,
            line_quadric_epsilon,
            vmas_ctx.vertex_sqem,
        );
    }

    fn computeClusters(vmas_ctx: *VMASContext) !void {
        // clean up previous clusters
        var p_it = vmas_ctx.spheres.pointIterator();
        while (p_it.next()) |s| {
            vmas_ctx.sphere_cluster.valuePtr(s).*.clearRetainingCapacity();
            vmas_ctx.sphere_error.valuePtr(s).* = 0.0;
        }
        // compute new clusters
        var v_it: SurfaceMesh.CellIterator = try .init(vmas_ctx.surface_mesh, .vertex);
        defer v_it.deinit();
        while (v_it.next()) |v| {
            const v_sqem = vmas_ctx.vertex_sqem.valuePtr(v);
            var min_distance = std.math.floatMax(f32);
            var min_sphere: PointCloud.Point = undefined;
            const old_sphere = vmas_ctx.vertex_sphere.value(v);
            // if there is a sphere assigned to this vertex, restrict the search to it and its neighbors
            if (old_sphere) |os| {
                {
                    const sc = vmas_ctx.sphere_center.value(os);
                    const sr = vmas_ctx.sphere_radius.value(os);
                    const dist = v_sqem.eval(.{ sc[0], sc[1], sc[2], sr });
                    if (dist < min_distance) {
                        min_distance = dist;
                        min_sphere = os;
                    }
                }
                const s_neighbors = vmas_ctx.sphere_neighbor_spheres.valuePtr(os);
                for (s_neighbors.keys()) |osn| {
                    const osc = vmas_ctx.sphere_center.value(osn);
                    const osr = vmas_ctx.sphere_radius.value(osn);
                    const dist = v_sqem.eval(.{ osc[0], osc[1], osc[2], osr });
                    if (dist < min_distance) {
                        min_distance = dist;
                        min_sphere = osn;
                    }
                }
            } else { // if there is no sphere assigned to this vertex, search all spheres
                var s_it = vmas_ctx.spheres.pointIterator();
                while (s_it.next()) |s| {
                    const sc = vmas_ctx.sphere_center.value(s);
                    const sr = vmas_ctx.sphere_radius.value(s);
                    const dist = v_sqem.eval(.{ sc[0], sc[1], sc[2], sr });
                    if (dist < min_distance) {
                        min_distance = dist;
                        min_sphere = s;
                    }
                }
            }
            try vmas_ctx.sphere_cluster.valuePtr(min_sphere).append(vmas_ctx.allocator, v);
            vmas_ctx.vertex_sphere.valuePtr(v).* = min_sphere;
            vmas_ctx.vertex_sphere_error.valuePtr(v).* = min_distance;
            vmas_ctx.sphere_error.valuePtr(min_sphere).* += min_distance;
        }
        // check clusters sizes & remove too small clusters
        var s_it = vmas_ctx.spheres.pointIterator();
        while (s_it.next()) |s| {
            if (vmas_ctx.sphere_cluster.valuePtr(s).items.len < 4) {
                for (vmas_ctx.sphere_cluster.valuePtr(s).items) |v| {
                    vmas_ctx.vertex_sphere.valuePtr(v).* = null;
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
        var e_it: SurfaceMesh.CellIterator = try .init(vmas_ctx.surface_mesh, .edge);
        defer e_it.deinit();
        while (e_it.next()) |e| {
            const s1 = vmas_ctx.vertex_sphere.value(.{ .vertex = e.dart() });
            const s2 = vmas_ctx.vertex_sphere.value(.{ .vertex = vmas_ctx.surface_mesh.phi1(e.dart()) });
            if (s1 != null and s2 != null and s1.? != s2.?) {
                try vmas_ctx.sphere_neighbor_spheres.valuePtr(s1.?).put(vmas_ctx.allocator, s2.?, {});
                try vmas_ctx.sphere_neighbor_spheres.valuePtr(s2.?).put(vmas_ctx.allocator, s1.?, {});
            }
        }
    }

    pub fn updateSpheres(vmas_ctx: *VMASContext) !void {
        var previous_error: f32 = 0.0;
        var nb_iterations: usize = 0;
        const max_iterations: usize = 50;

        var s_it = vmas_ctx.spheres.pointIterator();

        while (nb_iterations < max_iterations) {
            // compute the optimal spheres for each cluster
            s_it.reset();
            while (s_it.next()) |s| {
                // add the SQEM contributions of all vertices in the cluster
                const cluster = vmas_ctx.sphere_cluster.valuePtr(s);
                var cluster_sqem: SQEM = .zero;
                for (cluster.items) |v| {
                    cluster_sqem.add(vmas_ctx.vertex_sqem.valuePtr(v));
                }
                // compute the optimal sphere
                const optimized_sphere = cluster_sqem.optimalSphere();
                if (optimized_sphere) |opt_s| {
                    // correct the optimal sphere on the medial axis
                    const s_center = .{ opt_s[0], opt_s[1], opt_s[2] };
                    const cp, const sp = vmas_ctx.surface_mesh_bvh.closestPointWithSurfacePoint(s_center);
                    var cp_dir = vec.normalized3f(vec.sub3f(cp, s_center));
                    const cp_normal = sp.readData(Vec3f, .face, vmas_ctx.face_normal);
                    if (vec.dot3f(cp_dir, cp_normal) <= 0.0) {
                        cp_dir = vec.mulScalar3f(cp_dir, -1.0);
                    }
                    const corrected_sphere = shrinkingBall(
                        vmas_ctx.surface_mesh_bvh,
                        vec.add3f(cp, vec.mulScalar3f(cp_dir, -1e-4)),
                        cp_dir,
                    );
                    if (corrected_sphere) |cs| {
                        vmas_ctx.sphere_center.valuePtr(s).* = .{ cs[0], cs[1], cs[2] };
                        vmas_ctx.sphere_radius.valuePtr(s).* = cs[3];
                    } else {
                        vmas_ctx.sphere_center.valuePtr(s).* = .{ opt_s[0], opt_s[1], opt_s[2] };
                        vmas_ctx.sphere_radius.valuePtr(s).* = opt_s[3];
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
        var worst_vertex: ?SurfaceMesh.Cell = null;
        var worst_vertex_error: f32 = 0.0;
        const cluster = vmas_ctx.sphere_cluster.valuePtr(sphere);
        for (cluster.items) |v| {
            const err = vmas_ctx.vertex_sphere_error.value(v);
            if (err > worst_vertex_error) {
                worst_vertex_error = err;
                worst_vertex = v;
            }
        }
        if (worst_vertex == null) {
            std.debug.print("Warning: no worst vertex found for sphere {}\n", .{sphere});
            return;
        }
        // create a new sphere
        const s = try vmas_ctx.spheres.addPoint();
        // assign this new sphere to the worst vertex
        vmas_ctx.vertex_sphere.valuePtr(worst_vertex.?).* = s;
        // compute the shrinking ball for the worst point
        const sb = vmas_ctx.vertex_shrinking_ball.value(worst_vertex.?);
        if (sb) |ball| {
            vmas_ctx.sphere_center.valuePtr(s).* = .{ ball[0], ball[1], ball[2] };
            vmas_ctx.sphere_radius.valuePtr(s).* = ball[3];
        } else {
            const n = vmas_ctx.vertex_normal.value(worst_vertex.?);
            vmas_ctx.sphere_center.valuePtr(s).* = vec.add3f(
                vmas_ctx.vertex_position.value(worst_vertex.?),
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
