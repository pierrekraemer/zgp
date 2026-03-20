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

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const SQEM = @import("../geometry/SQEM.zig");

const sqem = @import("../models/surface/sqem.zig");

const MedialAxisData = struct {
    app_ctx: *AppContext,

    surface_mesh: *SurfaceMesh,
    vertex_position: ?SurfaceMesh.CellData(.vertex, Vec3f) = null,
    vertex_area: ?SurfaceMesh.CellData(.vertex, f32) = null,
    vertex_tangent_basis: ?SurfaceMesh.CellData(.vertex, [2]Vec3f) = null,
    vertex_sqem: ?SurfaceMesh.CellData(.vertex, SQEM) = null,
    vertex_sphere: ?SurfaceMesh.CellData(.vertex, ?PointCloud.Point) = null,
    vertex_sphere_error: ?SurfaceMesh.CellData(.vertex, f32) = null,
    vertex_sphere_color: ?SurfaceMesh.CellData(.vertex, Vec3f) = null,
    face_area: ?SurfaceMesh.CellData(.face, f32) = null,
    face_normal: ?SurfaceMesh.CellData(.face, Vec3f) = null,

    spheres: ?*PointCloud = null,
    sphere_center: ?PointCloud.CellData(Vec3f) = null,
    sphere_radius: ?PointCloud.CellData(f32) = null,
    sphere_color: ?PointCloud.CellData(Vec3f) = null,
    sphere_cluster: ?PointCloud.CellData(std.ArrayList(SurfaceMesh.Cell)) = null,
    sphere_error: ?PointCloud.CellData(f32) = null,
    initialized: bool = false,

    pub fn init(
        mad: *MedialAxisData,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_area: SurfaceMesh.CellData(.vertex, f32),
        vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
        face_area: SurfaceMesh.CellData(.face, f32),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),
    ) !void {
        mad.vertex_position = vertex_position;
        mad.vertex_area = vertex_area;
        mad.vertex_tangent_basis = vertex_tangent_basis;
        mad.face_area = face_area;
        mad.face_normal = face_normal;
        if (!mad.initialized) {
            mad.vertex_sqem = try mad.surface_mesh.addData(.vertex, SQEM, "__vertex_sqem");
            mad.vertex_sphere = try mad.surface_mesh.addData(.vertex, ?PointCloud.Point, "__vertex_sphere");
            mad.vertex_sphere_error = try mad.surface_mesh.addData(.vertex, f32, "__vertex_sphere_error");
            mad.vertex_sphere_color = try mad.surface_mesh.addData(.vertex, Vec3f, "__vertex_sphere_color");
        }
        try sqem.computeVertexSQEMs(
            mad.app_ctx,
            mad.surface_mesh,
            vertex_position,
            vertex_area,
            vertex_tangent_basis,
            face_area,
            face_normal,
            mad.vertex_sqem.?,
        );
        mad.vertex_sphere.?.data.fill(null);
        mad.vertex_sphere_error.?.data.fill(0.0);
        if (!mad.initialized) {
            var buf: [64]u8 = undefined;
            const pc_name = std.fmt.bufPrint(&buf, "{s}_ma_spheres", .{mad.app_ctx.surface_mesh_store.surfaceMeshName(mad.surface_mesh).?}) catch "__ma_spheres";
            mad.spheres = try mad.app_ctx.point_cloud_store.createPointCloud(pc_name);
            mad.sphere_center = try mad.spheres.?.addData(Vec3f, "center");
            mad.sphere_radius = try mad.spheres.?.addData(f32, "radius");
            mad.sphere_color = try mad.spheres.?.addData(Vec3f, "color");
            mad.sphere_cluster = try mad.spheres.?.addData(std.ArrayList(SurfaceMesh.Cell), "cluster");
            mad.sphere_error = try mad.spheres.?.addData(f32, "error");
            mad.app_ctx.point_cloud_store.setPointCloudStdData(mad.spheres.?, .{ .position = mad.sphere_center.? });
            mad.app_ctx.point_cloud_store.setPointCloudStdData(mad.spheres.?, .{ .radius = mad.sphere_radius.? });
        } else {
            var it = mad.sphere_cluster.?.data.iterator();
            while (it.next()) |*cluster| {
                cluster.*.deinit(mad.app_ctx.allocator); // do not forget to deinit ArrayLists in sphere_cluster data
            }
            mad.spheres.?.clearRetainingCapacity();
        }
        const s1 = try mad.spheres.?.addPoint(); // create the first sphere
        mad.sphere_center.?.valuePtr(s1).* = .{ 0.0, 0.0, 0.0 };
        mad.sphere_radius.?.valuePtr(s1).* = 0.01;
        var r = mad.app_ctx.rng.random();
        mad.sphere_color.?.valuePtr(s1).* = .{ 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32) };
        mad.sphere_cluster.?.valuePtr(s1).* = .empty;
        mad.sphere_error.?.valuePtr(s1).* = 0.0;
        mad.initialized = true;

        try mad.computeClusters();

        mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres.?);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres.?, Vec3f, mad.sphere_center.?);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres.?, f32, mad.sphere_radius.?);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres.?, Vec3f, mad.sphere_color.?);
        mad.app_ctx.requestRedraw();
    }

    pub fn deinit(mad: *MedialAxisData) void {
        if (mad.initialized) {
            mad.surface_mesh.removeData(.vertex, mad.vertex_sqem.?.gen());
            mad.surface_mesh.removeData(.vertex, mad.vertex_sphere.?.gen());
            mad.surface_mesh.removeData(.vertex, mad.vertex_sphere_error.?.gen());
            mad.surface_mesh.removeData(.vertex, mad.vertex_sphere_color.?.gen());
            var it = mad.sphere_cluster.?.data.iterator();
            while (it.next()) |*cluster| {
                cluster.*.deinit(mad.app_ctx.allocator); // do not forget to deinit ArrayLists in sphere_cluster data
            }
            mad.app_ctx.point_cloud_store.destroyPointCloud(mad.spheres.?); // PointCloud deinit manages its own CellData deinit
            mad.initialized = false;
        }
    }

    fn computeClusters(mad: *MedialAxisData) !void {
        assert(mad.initialized);
        // clean up previous clusters
        mad.vertex_sphere.?.data.fill(null);
        var p_it = mad.spheres.?.pointIterator();
        while (p_it.next()) |s| {
            mad.sphere_cluster.?.valuePtr(s).*.clearRetainingCapacity();
            mad.sphere_error.?.valuePtr(s).* = 0.0;
        }
        // compute new clusters
        var v_it = try SurfaceMesh.CellIterator(.vertex).init(mad.surface_mesh);
        defer v_it.deinit();
        while (v_it.next()) |v| {
            var min_distance = std.math.floatMax(f32);
            var min_sphere: PointCloud.Point = undefined;
            var s_it = mad.spheres.?.pointIterator();
            while (s_it.next()) |s| {
                const sc = mad.sphere_center.?.value(s);
                const sr = mad.sphere_radius.?.value(s);
                const dist = mad.vertex_sqem.?.valuePtr(v).eval(.{ sc[0], sc[1], sc[2], sr });
                if (dist < min_distance) {
                    min_distance = dist;
                    min_sphere = s;
                }
            }
            try mad.sphere_cluster.?.valuePtr(min_sphere).append(mad.app_ctx.allocator, v);
            mad.vertex_sphere.?.valuePtr(v).* = min_sphere;
            mad.vertex_sphere_color.?.valuePtr(v).* = mad.sphere_color.?.value(min_sphere);
            mad.vertex_sphere_error.?.valuePtr(v).* = min_distance;
            mad.sphere_error.?.valuePtr(min_sphere).* += min_distance;
        }
        // check clusters sizes
        var s_it = mad.spheres.?.pointIterator();
        while (s_it.next()) |s| {
            if (mad.sphere_cluster.?.valuePtr(s).items.len < 4) {
                for (mad.sphere_cluster.?.valuePtr(s).items) |v| {
                    mad.vertex_sphere.?.valuePtr(v).* = null;
                }
                mad.sphere_cluster.?.valuePtr(s).deinit(mad.app_ctx.allocator);
                mad.spheres.?.removePoint(s); // it is safe to remove the point while iterating
            }
        }

        mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres.?);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres.?, f32, mad.sphere_error.?);
        mad.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(mad.surface_mesh, .vertex, Vec3f, mad.vertex_sphere_color.?);
        mad.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(mad.surface_mesh, .vertex, f32, mad.vertex_sphere_error.?);
        mad.app_ctx.requestRedraw();
    }

    pub fn updateSpheres(mad: *MedialAxisData) !void {
        assert(mad.initialized);

        var previous_error: f32 = 0.0;
        var nb_iterations: usize = 0;
        const max_iterations: usize = 100;
        var s_it = mad.spheres.?.pointIterator();

        while (nb_iterations < max_iterations) {
            s_it.reset();
            while (s_it.next()) |s| {
                const cluster = mad.sphere_cluster.?.valuePtr(s);
                var cluster_sqem: SQEM = .zero;
                for (cluster.items) |v| {
                    cluster_sqem.add(mad.vertex_sqem.?.valuePtr(v));
                }
                const optimized_sphere = cluster_sqem.optimalSphere();
                if (optimized_sphere) |opt_s| {
                    mad.sphere_center.?.valuePtr(s).* = .{ opt_s[0], opt_s[1], opt_s[2] };
                    mad.sphere_radius.?.valuePtr(s).* = opt_s[3];
                }
            }

            try mad.computeClusters();

            nb_iterations += 1;

            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres.?, Vec3f, mad.sphere_center.?);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres.?, f32, mad.sphere_radius.?);
            mad.app_ctx.requestRedraw();

            var current_error: f32 = 0.0;
            s_it.reset();
            while (s_it.next()) |s| {
                current_error += mad.sphere_error.?.value(s);
            }
            if (@abs(current_error - previous_error) < 1e-7) {
                break;
            }
            previous_error = current_error;
        }
    }

    pub fn splitWorseSphere(mad: *MedialAxisData) !void {
        assert(mad.initialized);
        var worst_sphere: PointCloud.Point = undefined;
        var worst_error: f32 = -1.0;
        var s_it = mad.spheres.?.pointIterator();
        while (s_it.next()) |s| {
            const err = mad.sphere_error.?.value(s);
            if (err > worst_error) {
                worst_error = err;
                worst_sphere = s;
            }
        }
        var worst_vertex: SurfaceMesh.Cell = undefined;
        var worst_vertex_error: f32 = -1.0;
        for (mad.sphere_cluster.?.valuePtr(worst_sphere).items) |v| {
            const err = mad.vertex_sphere_error.?.value(v);
            if (err > worst_vertex_error) {
                worst_vertex_error = err;
                worst_vertex = v;
            }
        }
        const s = try mad.spheres.?.addPoint();
        var r = mad.app_ctx.rng.random();
        mad.sphere_center.?.valuePtr(s).* = vec.add3f(
            mad.vertex_position.?.value(worst_vertex),
            .{ 0.01 * r.float(f32), 0.01 * r.float(f32), 0.01 * r.float(f32) },
        );
        mad.sphere_radius.?.valuePtr(s).* = 0.01;
        mad.sphere_color.?.valuePtr(s).* = .{ 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32) };
        mad.sphere_cluster.?.valuePtr(s).* = .empty;
        mad.sphere_error.?.valuePtr(s).* = 0.0;

        try mad.computeClusters();

        mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres.?);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres.?, Vec3f, mad.sphere_center.?);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres.?, f32, mad.sphere_radius.?);
        mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres.?, Vec3f, mad.sphere_color.?);
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

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const info = sm_store.surfaceMeshInfo(sm);
    const mad = smma.surface_meshes_data.getPtr(sm).?;
    const disabled =
        info.std_datas.vertex_position == null or
        info.std_datas.vertex_area == null or
        info.std_datas.vertex_tangent_basis == null or
        info.std_datas.face_area == null or
        info.std_datas.face_normal == null;
    if (disabled) {
        c.ImGui_BeginDisabled(true);
    }
    if (c.ImGui_ButtonEx(if (mad.initialized) "Reinitialize data" else "Initialize data", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
        _ = mad.init(
            info.std_datas.vertex_position.?,
            info.std_datas.vertex_area.?,
            info.std_datas.vertex_tangent_basis.?,
            info.std_datas.face_area.?,
            info.std_datas.face_normal.?,
        ) catch |err| {
            std.debug.print("Failed to initialize Medial Axis data for SurfaceMesh: {}\n", .{err});
        };
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
