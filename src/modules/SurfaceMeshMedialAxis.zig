const SurfaceMeshMedialAxis = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("../main.zig").c;

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const PointCloud = @import("../models/point/PointCloud.zig");
const IncidenceGraph = @import("../models/incidenceGraph/IncidenceGraph.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const bvh = @import("../geometry/bvh.zig");
const SQEM = @import("../geometry/SQEM.zig");

const medialAxis = @import("../models/surface/medialAxis.zig");
const sqem = @import("../models/surface/sqem.zig");

const MedialAxisData = struct {
    app_ctx: *AppContext,

    surface_mesh: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f) = undefined,
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f) = undefined,
    vertex_sqem: SurfaceMesh.CellData(.vertex, SQEM) = undefined,
    vertex_shrinking_ball: SurfaceMesh.CellData(.vertex, ?Vec4f) = undefined,
    vertex_sphere: SurfaceMesh.CellData(.vertex, ?PointCloud.Point) = undefined,
    vertex_sphere_error: SurfaceMesh.CellData(.vertex, f32) = undefined,
    vertex_sphere_color: SurfaceMesh.CellData(.vertex, Vec3f) = undefined,

    spheres: *PointCloud = undefined,
    sphere_center: PointCloud.CellData(Vec3f) = undefined,
    sphere_radius: PointCloud.CellData(f32) = undefined,
    sphere_color: PointCloud.CellData(Vec3f) = undefined,
    sphere_cluster: PointCloud.CellData(std.ArrayList(SurfaceMesh.Cell)) = undefined,
    sphere_error: PointCloud.CellData(f32) = undefined,
    sphere_neighbor_spheres: PointCloud.CellData(std.AutoArrayHashMap(PointCloud.Point, void)) = undefined,

    shrinking_balls: *PointCloud = undefined,
    shrinking_ball_center: PointCloud.CellData(Vec3f) = undefined,
    shrinking_ball_radius: PointCloud.CellData(f32) = undefined,

    skeleton: *IncidenceGraph = undefined,
    skeleton_vertex_position: IncidenceGraph.CellData(.vertex, Vec3f) = undefined,

    initialized: bool = false,

    pub fn init(
        mad: *MedialAxisData,
        sm_bvh: bvh.TrianglesBVH,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_area: SurfaceMesh.CellData(.vertex, f32),
        vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
        face_area: SurfaceMesh.CellData(.face, f32),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),
        line_quadric_epsilon: f32,
    ) !void {
        mad.vertex_position = vertex_position;
        mad.vertex_normal = vertex_normal;

        if (!mad.initialized) {
            // create SurfaceMesh vertex data
            mad.vertex_sqem = try mad.surface_mesh.addData(.vertex, SQEM, "__vertex_sqem");
            mad.vertex_shrinking_ball = try mad.surface_mesh.addData(.vertex, ?Vec4f, "__vertex_shrinking_ball");
            mad.vertex_sphere = try mad.surface_mesh.addData(.vertex, ?PointCloud.Point, "__vertex_sphere");
            mad.vertex_sphere_error = try mad.surface_mesh.addData(.vertex, f32, "__vertex_sphere_error");
            mad.vertex_sphere_color = try mad.surface_mesh.addData(.vertex, Vec3f, "__vertex_sphere_color");

            var buf: [64]u8 = undefined;

            // create medial spheres PointCloud & data
            const pc_name = std.fmt.bufPrint(&buf, "{s}_ma_spheres", .{mad.app_ctx.surface_mesh_store.surfaceMeshName(mad.surface_mesh).?}) catch "__ma_spheres";
            mad.spheres = try mad.app_ctx.point_cloud_store.createPointCloud(pc_name);
            mad.sphere_center = try mad.spheres.addData(Vec3f, "center");
            mad.sphere_radius = try mad.spheres.addData(f32, "radius");
            mad.sphere_color = try mad.spheres.addData(Vec3f, "color");
            mad.sphere_cluster = try mad.spheres.addData(std.ArrayList(SurfaceMesh.Cell), "cluster");
            mad.sphere_error = try mad.spheres.addData(f32, "error");
            mad.sphere_neighbor_spheres = try mad.spheres.addData(std.AutoArrayHashMap(PointCloud.Point, void), "neighbor_spheres");
            mad.app_ctx.point_cloud_store.setPointCloudStdData(mad.spheres, .{ .position = mad.sphere_center });
            mad.app_ctx.point_cloud_store.setPointCloudStdData(mad.spheres, .{ .radius = mad.sphere_radius });

            // create shrinking balls PointCloud & data
            const sb_pc_name = std.fmt.bufPrint(&buf, "{s}_shrinking_balls", .{mad.app_ctx.surface_mesh_store.surfaceMeshName(mad.surface_mesh).?}) catch "__shrinking_balls";
            mad.shrinking_balls = try mad.app_ctx.point_cloud_store.createPointCloud(sb_pc_name);
            mad.shrinking_ball_center = try mad.shrinking_balls.addData(Vec3f, "center");
            mad.shrinking_ball_radius = try mad.shrinking_balls.addData(f32, "radius");
            mad.app_ctx.point_cloud_store.setPointCloudStdData(mad.shrinking_balls, .{ .position = mad.shrinking_ball_center });
            mad.app_ctx.point_cloud_store.setPointCloudStdData(mad.shrinking_balls, .{ .radius = mad.shrinking_ball_radius });

            // create skeleton IncidenceGraph & data
            const sk_name = std.fmt.bufPrint(&buf, "{s}_skeleton", .{mad.app_ctx.surface_mesh_store.surfaceMeshName(mad.surface_mesh).?}) catch "__skeleton";
            mad.skeleton = try mad.app_ctx.incidence_graph_store.createIncidenceGraph(sk_name);
            mad.skeleton_vertex_position = try mad.skeleton.addData(.vertex, Vec3f, "position");
            mad.app_ctx.incidence_graph_store.setIncidenceGraphStdData(mad.skeleton, .{ .vertex_position = mad.skeleton_vertex_position });

            mad.initialized = true;
        } else {
            // clear medial spheres
            // do not forget to deinit ArrayLists in sphere_cluster data & ArrayHashMaps in sphere_neighbor_spheres data
            var s_it = mad.spheres.pointIterator();
            while (s_it.next()) |s| {
                mad.sphere_cluster.valuePtr(s).deinit(mad.app_ctx.allocator);
                mad.sphere_neighbor_spheres.valuePtr(s).deinit();
            }
            mad.spheres.clearRetainingCapacity();
            // clear shrinking balls
            mad.shrinking_balls.clearRetainingCapacity();
            // clear skeleton
            mad.skeleton.clearRetainingCapacity();
        }

        try sqem.computeVertexSQEMs(
            mad.app_ctx,
            mad.surface_mesh,
            mad.vertex_position,
            vertex_area,
            vertex_tangent_basis,
            face_area,
            face_normal,
            line_quadric_epsilon,
            mad.vertex_sqem,
        );
        mad.vertex_shrinking_ball.data.fill(null);
        mad.vertex_sphere.data.fill(null);
        mad.vertex_sphere_error.data.fill(0.0);
        mad.vertex_sphere_color.data.fill(.{ 0.0, 0.0, 0.0 });

        // create the first medial sphere
        const s1 = try mad.spheres.addPoint();
        mad.sphere_center.valuePtr(s1).* = .{ 0.0, 0.0, 0.0 };
        mad.sphere_radius.valuePtr(s1).* = 0.01;
        var r = mad.app_ctx.rng.random();
        mad.sphere_color.valuePtr(s1).* = .{ 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32) };
        mad.sphere_cluster.valuePtr(s1).* = .empty;
        mad.sphere_error.valuePtr(s1).* = 0.0;
        mad.sphere_neighbor_spheres.valuePtr(s1).* = .init(mad.app_ctx.allocator);
        // and compute the cluster
        try mad.computeClusters();

        mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, mad.sphere_center);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, mad.sphere_radius);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, mad.sphere_color);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, mad.sphere_error);

        // compute vertex shrinking balls
        try medialAxis.computeVertexShrinkingBalls(
            mad.app_ctx,
            mad.surface_mesh,
            sm_bvh,
            mad.vertex_position,
            mad.vertex_normal,
            mad.vertex_shrinking_ball,
        );
        // and initialize the shrinking balls PointCloud
        for (mad.vertex_shrinking_ball.data.data.items) |ball| {
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

        mad.app_ctx.requestRedraw();
    }

    pub fn deinit(mad: *MedialAxisData) void {
        if (mad.initialized) {
            mad.surface_mesh.removeData(.vertex, SQEM, mad.vertex_sqem);
            mad.surface_mesh.removeData(.vertex, ?PointCloud.Point, mad.vertex_sphere);
            mad.surface_mesh.removeData(.vertex, f32, mad.vertex_sphere_error);
            mad.surface_mesh.removeData(.vertex, Vec3f, mad.vertex_sphere_color);
            // do not forget to deinit ArrayLists in sphere_cluster data & ArrayHashMaps in sphere_neighbor_spheres data
            var s_it = mad.spheres.pointIterator();
            while (s_it.next()) |s| {
                mad.sphere_cluster.valuePtr(s).deinit(mad.app_ctx.allocator);
                mad.sphere_neighbor_spheres.valuePtr(s).deinit();
            }
            // forget about the PointCloud and IncidenceGraph, but let them live on
            mad.spheres = undefined;
            mad.shrinking_balls = undefined;
            mad.skeleton = undefined;
            mad.initialized = false;
        }
    }

    fn recomputeSQEMs(
        mad: *MedialAxisData,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_area: SurfaceMesh.CellData(.vertex, f32),
        vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
        face_area: SurfaceMesh.CellData(.face, f32),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),
        line_quadric_epsilon: f32,
    ) !void {
        try sqem.computeVertexSQEMs(
            mad.app_ctx,
            mad.surface_mesh,
            vertex_position,
            vertex_area,
            vertex_tangent_basis,
            face_area,
            face_normal,
            line_quadric_epsilon,
            mad.vertex_sqem,
        );
        try mad.updateSpheres();
    }

    fn computeClusters(mad: *MedialAxisData) !void {
        assert(mad.initialized);
        // clean up previous clusters
        mad.vertex_sphere.data.fill(null);
        var p_it = mad.spheres.pointIterator();
        while (p_it.next()) |s| {
            mad.sphere_cluster.valuePtr(s).*.clearRetainingCapacity();
            mad.sphere_error.valuePtr(s).* = 0.0;
        }
        // compute new clusters
        var v_it: SurfaceMesh.CellIterator = try .init(mad.surface_mesh, .vertex);
        defer v_it.deinit();
        while (v_it.next()) |v| {
            var min_distance = std.math.floatMax(f32);
            var min_sphere: PointCloud.Point = undefined;
            var s_it = mad.spheres.pointIterator();
            while (s_it.next()) |s| {
                const sc = mad.sphere_center.value(s);
                const sr = mad.sphere_radius.value(s);
                const dist = mad.vertex_sqem.valuePtr(v).eval(.{ sc[0], sc[1], sc[2], sr });
                if (dist < min_distance) {
                    min_distance = dist;
                    min_sphere = s;
                }
            }
            try mad.sphere_cluster.valuePtr(min_sphere).append(mad.app_ctx.allocator, v);
            mad.vertex_sphere.valuePtr(v).* = min_sphere;
            mad.vertex_sphere_color.valuePtr(v).* = mad.sphere_color.value(min_sphere);
            mad.vertex_sphere_error.valuePtr(v).* = min_distance;
            mad.sphere_error.valuePtr(min_sphere).* += min_distance;
        }
        // check clusters sizes
        var s_it = mad.spheres.pointIterator();
        while (s_it.next()) |s| {
            if (mad.sphere_cluster.valuePtr(s).items.len < 4) {
                for (mad.sphere_cluster.valuePtr(s).items) |v| {
                    mad.vertex_sphere.valuePtr(v).* = null;
                }
                // do not forget to deinit ArrayList in sphere_cluster data & ArrayHashMap in sphere_neighbor_spheres data
                mad.sphere_cluster.valuePtr(s).deinit(mad.app_ctx.allocator);
                mad.sphere_neighbor_spheres.valuePtr(s).deinit();
                mad.spheres.removePoint(s); // it is safe to remove the point while iterating
            }
        }

        mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, mad.sphere_error);
        mad.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(mad.surface_mesh, .vertex, Vec3f, mad.vertex_sphere_color);
        mad.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(mad.surface_mesh, .vertex, f32, mad.vertex_sphere_error);
        mad.app_ctx.requestRedraw();
    }

    pub fn updateSpheres(mad: *MedialAxisData) !void {
        assert(mad.initialized);

        var previous_error: f32 = 0.0;
        var nb_iterations: usize = 0;
        const max_iterations: usize = 100;
        var s_it = mad.spheres.pointIterator();

        while (nb_iterations < max_iterations) {
            s_it.reset();
            while (s_it.next()) |s| {
                const cluster = mad.sphere_cluster.valuePtr(s);
                var cluster_sqem: SQEM = .zero;
                for (cluster.items) |v| {
                    cluster_sqem.add(mad.vertex_sqem.valuePtr(v));
                }
                const optimized_sphere = cluster_sqem.optimalSphere();
                if (optimized_sphere) |opt_s| {
                    mad.sphere_center.valuePtr(s).* = .{ opt_s[0], opt_s[1], opt_s[2] };
                    mad.sphere_radius.valuePtr(s).* = opt_s[3];
                }
            }

            try mad.computeClusters();

            nb_iterations += 1;

            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, mad.sphere_center);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, mad.sphere_radius);
            mad.app_ctx.requestRedraw();

            var current_error: f32 = 0.0;
            s_it.reset();
            while (s_it.next()) |s| {
                current_error += mad.sphere_error.value(s);
            }
            if (@abs(current_error - previous_error) < 1e-7) {
                break;
            }
            previous_error = current_error;
        }

        try mad.updateSkeleton();
    }

    pub fn splitWorseSphere(mad: *MedialAxisData) !void {
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
        var worst_vertex: SurfaceMesh.Cell = undefined;
        var worst_vertex_error: f32 = -1.0;
        for (mad.sphere_cluster.valuePtr(worst_sphere).items) |v| {
            const err = mad.vertex_sphere_error.value(v);
            if (err > worst_vertex_error) {
                worst_vertex_error = err;
                worst_vertex = v;
            }
        }
        const s = try mad.spheres.addPoint();
        const sb = mad.vertex_shrinking_ball.value(worst_vertex);
        if (sb) |ball| {
            mad.sphere_center.valuePtr(s).* = .{ ball[0], ball[1], ball[2] };
            mad.sphere_radius.valuePtr(s).* = ball[3];
        } else {
            const n = mad.vertex_normal.value(worst_vertex);
            mad.sphere_center.valuePtr(s).* = vec.add3f(
                mad.vertex_position.value(worst_vertex),
                vec.mulScalar3f(n, -0.01),
            );
            mad.sphere_radius.valuePtr(s).* = 0.01;
        }
        var r = mad.app_ctx.rng.random();
        mad.sphere_color.valuePtr(s).* = .{ 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32) };
        mad.sphere_cluster.valuePtr(s).* = .empty;
        mad.sphere_error.valuePtr(s).* = 0.0;
        mad.sphere_neighbor_spheres.valuePtr(s).* = .init(mad.app_ctx.allocator);

        try mad.computeClusters();
        try mad.updateSkeleton();

        mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, mad.sphere_center);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, mad.sphere_radius);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, mad.sphere_color);
        mad.app_ctx.requestRedraw();
    }

    pub fn updateSkeleton(mad: *MedialAxisData) !void {
        assert(mad.initialized);

        var s_it = mad.spheres.pointIterator();
        while (s_it.next()) |s| {
            mad.sphere_neighbor_spheres.valuePtr(s).clearRetainingCapacity();
        }

        var e_it: SurfaceMesh.CellIterator = try .init(mad.surface_mesh, .edge);
        defer e_it.deinit();
        while (e_it.next()) |e| {
            const s1 = mad.vertex_sphere.value(.{ .vertex = e.dart() });
            const s2 = mad.vertex_sphere.value(.{ .vertex = mad.surface_mesh.phi1(e.dart()) });
            if (s1 != null and s2 != null and s1.? != s2.?) {
                try mad.sphere_neighbor_spheres.valuePtr(s1.?).put(s2.?, {});
                try mad.sphere_neighbor_spheres.valuePtr(s2.?).put(s1.?, {});
            }
        }

        var sphere_skeleton_vertex = try mad.spheres.addData(IncidenceGraph.Cell, "__sphere_skeleton_vertex");
        defer mad.spheres.removeData(IncidenceGraph.Cell, sphere_skeleton_vertex);
        var skeleton_edges: std.AutoHashMap([2]IncidenceGraph.Cell, IncidenceGraph.Cell) = .init(mad.app_ctx.allocator);
        defer skeleton_edges.deinit();

        mad.skeleton.clearRetainingCapacity();
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
                    try skeleton_edges.put(.{ if (v.index() < sn_v.index()) v else sn_v, if (v.index() < sn_v.index()) sn_v else v }, e);
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

        mad.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(mad.skeleton);
        mad.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(mad.skeleton, .vertex, Vec3f, mad.skeleton_vertex_position);
        mad.app_ctx.requestRedraw();
    }
};

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Medial Axis",
    .supported_models = .{ .surface_mesh = true },
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        // TODO: should manage SurfaceMesh connectivity & vertex_position updates
        // TODO: should manage the destruction of the PointClouds and IncidenceGraph
        .rightPanel = rightPanel,
    },
},
surface_meshes_data: std.AutoHashMap(*SurfaceMesh, MedialAxisData),

pub fn init(app_ctx: *AppContext) SurfaceMeshMedialAxis {
    return .{
        .app_ctx = app_ctx,
        .surface_meshes_data = .init(app_ctx.allocator),
    };
}

pub fn deinit(smma: *SurfaceMeshMedialAxis) void {
    var it = smma.surface_meshes_data.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    smma.surface_meshes_data.deinit();
}

/// Part of the Module interface.
/// Create and store a MedialAxisData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smma: *SurfaceMeshMedialAxis = @alignCast(@fieldParentPtr("module", m));
    smma.surface_meshes_data.put(surface_mesh, .{
        .app_ctx = smma.app_ctx,
        .surface_mesh = surface_mesh,
    }) catch |err| {
        std.debug.print("Failed to store MedialAxisData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Remove the MedialAxisData associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smma: *SurfaceMeshMedialAxis = @alignCast(@fieldParentPtr("module", m));
    const mad = smma.surface_meshes_data.getPtr(surface_mesh) orelse return;
    mad.deinit();
    _ = smma.surface_meshes_data.remove(surface_mesh);
}

/// Part of the Module interface.
/// Show a UI panel to control the medial axis data of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const smma: *SurfaceMeshMedialAxis = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &smma.app_ctx.surface_mesh_store;

    assert(smma.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = smma.app_ctx.selected_model.surface_mesh;

    const UiData = struct {
        var line_quadric_epsilon: f32 = 0.1;
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const info = sm_store.surfaceMeshInfo(sm);
    const mad = smma.surface_meshes_data.getPtr(sm).?;
    c.ImGui_PushID("Line Quadric Epsilon");
    _ = c.ImGui_SliderFloatEx("", &UiData.line_quadric_epsilon, 0.0001, 1.0, "%.4f", c.ImGuiSliderFlags_Logarithmic);
    c.ImGui_PopID();
    const disabled =
        !info.bvh.initialized or
        info.std_datas.vertex_position == null or
        info.std_datas.vertex_normal == null or
        info.std_datas.vertex_area == null or
        info.std_datas.vertex_tangent_basis == null or
        info.std_datas.face_area == null or
        info.std_datas.face_normal == null;
    if (disabled) {
        c.ImGui_BeginDisabled(true);
    }
    if (c.ImGui_ButtonEx(if (mad.initialized) "Reinitialize all data" else "Initialize data", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
        _ = mad.init(
            info.bvh,
            info.std_datas.vertex_position.?,
            info.std_datas.vertex_normal.?,
            info.std_datas.vertex_area.?,
            info.std_datas.vertex_tangent_basis.?,
            info.std_datas.face_area.?,
            info.std_datas.face_normal.?,
            UiData.line_quadric_epsilon,
        ) catch |err| {
            std.debug.print("Failed to initialize Medial Axis data for SurfaceMesh: {}\n", .{err});
        };
    }
    if (mad.initialized) {
        if (c.ImGui_ButtonEx("Recompute SQEMs", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            mad.recomputeSQEMs(
                info.std_datas.vertex_position.?,
                info.std_datas.vertex_area.?,
                info.std_datas.vertex_tangent_basis.?,
                info.std_datas.face_area.?,
                info.std_datas.face_normal.?,
                UiData.line_quadric_epsilon,
            ) catch |err| {
                std.debug.print("Failed to recompute Medial Axis SQEMs for SurfaceMesh: {}\n", .{err});
            };
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
        }
        if (c.ImGui_ButtonEx("Split worse sphere", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            mad.splitWorseSphere() catch |err| {
                std.debug.print("Failed to split worse Medial Axis sphere for SurfaceMesh: {}\n", .{err});
            };
        }
    }
}
