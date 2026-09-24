const SurfaceMeshMedialAxis = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("c");

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const PointCloud = @import("../models/point/PointCloud.zig");
const IncidenceGraph = @import("../models/incidenceGraph/IncidenceGraph.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const bvh = @import("../geometry/bvh.zig");

const medial_axis = @import("../models/surface/medial_axis.zig");

const MedialAxisData = struct {
    app_ctx: *AppContext,
    surface_mesh: *SurfaceMesh,

    spheres: *PointCloud = undefined,
    skeleton: *IncidenceGraph = undefined,

    vmas_ctx: ?medial_axis.VMASContext = null, // optional VMAS context
    // maybe there will be other medial axis computation contexts in the future

    pub fn initVMASContext(
        mad: *MedialAxisData,
        surface_mesh_bvh: *bvh.TrianglesBVH,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_area: SurfaceMesh.CellData(.vertex, f32),
        vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
        face_area: SurfaceMesh.CellData(.face, f32),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),
        line_quadric_epsilon: f32,
    ) !void {
        assert(mad.vmas_ctx == null);
        assert(surface_mesh_bvh.surface_mesh == mad.surface_mesh and surface_mesh_bvh.initialized);
        assert(vertex_position.surface_mesh == mad.surface_mesh);
        assert(vertex_normal.surface_mesh == mad.surface_mesh);
        assert(vertex_area.surface_mesh == mad.surface_mesh);
        assert(vertex_tangent_basis.surface_mesh == mad.surface_mesh);
        assert(face_area.surface_mesh == mad.surface_mesh);
        assert(face_normal.surface_mesh == mad.surface_mesh);

        var buf: [64]u8 = undefined;
        const spheres_name = std.fmt.bufPrintSentinel(&buf, "{s}_spheres", .{mad.app_ctx.surface_mesh_store.surfaceMeshName(mad.surface_mesh).?}, 0) catch "__spheres";
        mad.spheres = try mad.app_ctx.point_cloud_store.createPointCloud(spheres_name);
        const skeleton_name = std.fmt.bufPrintSentinel(&buf, "{s}_skeleton", .{mad.app_ctx.surface_mesh_store.surfaceMeshName(mad.surface_mesh).?}, 0) catch "__skeleton";
        mad.skeleton = try mad.app_ctx.incidence_graph_store.createIncidenceGraph(skeleton_name);

        mad.vmas_ctx = try .init(
            mad.app_ctx.allocator,
            mad.app_ctx.io,
            mad.surface_mesh,
            surface_mesh_bvh,
            vertex_position,
            vertex_normal,
            vertex_area,
            vertex_tangent_basis,
            face_area,
            face_normal,
            mad.spheres,
            mad.skeleton,
            line_quadric_epsilon,
        );

        mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres);
        mad.app_ctx.point_cloud_store.setPointCloudStdData(mad.spheres, .{ .position = mad.vmas_ctx.?.sphere_center });
        mad.app_ctx.point_cloud_store.setPointCloudStdData(mad.spheres, .{ .radius = mad.vmas_ctx.?.sphere_radius });

        mad.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(mad.skeleton);
        mad.app_ctx.incidence_graph_store.setIncidenceGraphStdData(mad.skeleton, .{ .vertex_position = mad.vmas_ctx.?.skeleton_vertex_position });
    }

    pub fn deinit(mad: *MedialAxisData) void {
        if (mad.vmas_ctx) |*vmas_ctx| {
            vmas_ctx.deinit();
            mad.vmas_ctx = null;
        }
        // the spheres PointCloud is owned by the PointCloudStore, it can outlive the MedialAxisData
        // the skeleton IncidenceGraph is owned by the IncidenceGraphStore, it can outlive the MedialAxisData
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
surface_meshes_data: std.AutoHashMapUnmanaged(*SurfaceMesh, MedialAxisData) = .empty,

pub fn init(app_ctx: *AppContext) SurfaceMeshMedialAxis {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(smma: *SurfaceMeshMedialAxis) void {
    var it = smma.surface_meshes_data.valueIterator();
    while (it.next()) |mad| {
        mad.deinit();
    }
    smma.surface_meshes_data.deinit(smma.app_ctx.allocator);
}

/// Part of the Module interface.
/// Create and store a MedialAxisData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smma: *SurfaceMeshMedialAxis = @alignCast(@fieldParentPtr("module", m));
    smma.surface_meshes_data.put(smma.app_ctx.allocator, surface_mesh, .{
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
    if (smma.surface_meshes_data.getPtr(surface_mesh)) |mad| {
        mad.deinit();
    }
    _ = smma.surface_meshes_data.remove(surface_mesh);
}

/// Part of the Module interface.
/// Show a UI panel to control the medial axis data of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const smma: *SurfaceMeshMedialAxis = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &smma.app_ctx.surface_mesh_store;

    assert(smma.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = smma.app_ctx.selected_model.surface_mesh;
    const mad = smma.surface_meshes_data.getPtr(sm).?;
    const info = sm_store.surfaceMeshInfo(sm);

    const UiData = struct {
        var line_quadric_epsilon: f32 = 0.2;
        var nb_spheres: usize = 100;
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    c.ImGui_PushID("Line Quadric Epsilon");
    _ = c.ImGui_SliderFloatEx("", &UiData.line_quadric_epsilon, 0.001, 1.0, "%.3f", c.ImGuiSliderFlags_Logarithmic);
    c.ImGui_PopID();

    // Initialize VMAS button
    {
        const disabled =
            !info.bvh.initialized or
            info.std_datas.vertex_position == null or
            info.std_datas.vertex_normal == null or
            info.std_datas.vertex_area == null or
            info.std_datas.vertex_tangent_basis == null or
            info.std_datas.face_area == null or
            info.std_datas.face_normal == null or
            mad.vmas_ctx != null;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx(if (mad.vmas_ctx != null) "VMAS initialized" else "Initialize VMAS", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            mad.initVMASContext(
                &info.bvh,
                info.std_datas.vertex_position.?,
                info.std_datas.vertex_normal.?,
                info.std_datas.vertex_area.?,
                info.std_datas.vertex_tangent_basis.?,
                info.std_datas.face_area.?,
                info.std_datas.face_normal.?,
                UiData.line_quadric_epsilon,
            ) catch |err| {
                std.debug.print("Failed to initialize VMAS for SurfaceMesh: {}\n", .{err});
            };
            if (mad.vmas_ctx) |*vmas_ctx| {
                vmas_ctx.createFirstSphere() catch |err| {
                    std.debug.print("Failed to create first medial sphere for SurfaceMesh: {}\n", .{err});
                };

                mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, vmas_ctx.sphere_center);
                mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, vmas_ctx.sphere_radius);
                mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, vmas_ctx.sphere_error);
                mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres);
                mad.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(mad.skeleton, .vertex, Vec3f, vmas_ctx.skeleton_vertex_position);
                mad.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(mad.skeleton);
                // mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, Vec3f, mad.point_sphere_color);
                // mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, f32, mad.point_sphere_error);
                mad.app_ctx.requestRedraw();
            }
        }
        if (disabled) {
            if (mad.vmas_ctx != null) {
                imgui_utils.tooltip("VMAS is already initialized. Reset first.");
            } else {
                imgui_utils.tooltip(
                    \\ Requires:
                    \\ - bvh
                    \\ Following data should be available:
                    \\ - std vertex_position
                    \\ - std vertex_normal
                    \\ - std vertex_area
                    \\ - std vertex_tangent_basis
                    \\ - std face_area
                    \\ - std face_normal
                );
            }
            c.ImGui_EndDisabled();
        }
    }

    if (mad.vmas_ctx) |*vmas_ctx| {
        if (c.ImGui_ButtonEx("Recompute SQEMs", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            vmas_ctx.updateVertexSQEMs(UiData.line_quadric_epsilon) catch |err| {
                std.debug.print("Failed to recompute Medial Axis SQEMs for SurfaceMesh: {}\n", .{err});
            };
            vmas_ctx.updateSpheres() catch |err| {
                std.debug.print("Failed to update Medial Axis spheres for SurfaceMesh: {}\n", .{err});
            };
            vmas_ctx.updateSkeleton() catch |err| {
                std.debug.print("Failed to update Medial Axis skeleton for SurfaceMesh: {}\n", .{err});
            };
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, vmas_ctx.sphere_center);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, vmas_ctx.sphere_radius);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, vmas_ctx.sphere_error);
            mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres);
            mad.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(mad.skeleton, .vertex, Vec3f, vmas_ctx.skeleton_vertex_position);
            mad.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(mad.skeleton);
            // mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, Vec3f, mad.point_sphere_color);
            // mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, f32, mad.point_sphere_error);
            mad.app_ctx.requestRedraw();
        }

        if (c.ImGui_ButtonEx("Update spheres", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            vmas_ctx.updateSpheres() catch |err| {
                std.debug.print("Failed to update Medial Axis spheres for SurfaceMesh: {}\n", .{err});
            };
            vmas_ctx.updateSkeleton() catch |err| {
                std.debug.print("Failed to update Medial Axis skeleton for SurfaceMesh: {}\n", .{err});
            };
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, vmas_ctx.sphere_center);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, vmas_ctx.sphere_radius);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, vmas_ctx.sphere_error);
            mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres);
            mad.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(mad.skeleton, .vertex, Vec3f, vmas_ctx.skeleton_vertex_position);
            mad.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(mad.skeleton);
            // mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, Vec3f, mad.point_sphere_color);
            // mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, f32, mad.point_sphere_error);
            mad.app_ctx.requestRedraw();
        }

        if (c.ImGui_ButtonEx("Split worst sphere", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            if (vmas_ctx.worstSphere()) |s| {
                vmas_ctx.splitSphere(s) catch |err| {
                    std.debug.print("Failed to split worst Medial Axis sphere for SurfaceMesh: {}\n", .{err});
                };
                vmas_ctx.updateSkeleton() catch |err| {
                    std.debug.print("Failed to update Medial Axis skeleton for SurfaceMesh: {}\n", .{err});
                };
                mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, vmas_ctx.sphere_center);
                mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, vmas_ctx.sphere_radius);
                mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, vmas_ctx.sphere_error);
                mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres);
                mad.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(mad.skeleton, .vertex, Vec3f, vmas_ctx.skeleton_vertex_position);
                mad.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(mad.skeleton);
                // mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, Vec3f, mad.point_sphere_color);
                // mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, f32, mad.point_sphere_error);
                mad.app_ctx.requestRedraw();
            }
        }
        _ = c.ImGui_InputInt("Number of spheres", @ptrCast(&UiData.nb_spheres));
        if (c.ImGui_ButtonEx("Build skeleton from scratch", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            const t = std.Io.Timestamp.now(smma.app_ctx.io, .real);

            vmas_ctx.clearRetainingCapacity();
            vmas_ctx.createFirstSphere() catch |err| {
                std.debug.print("Failed to create first medial sphere for SurfaceMesh: {}\n", .{err});
            };
            for (0..UiData.nb_spheres) |_| {
                if (vmas_ctx.worstSphere()) |s| {
                    vmas_ctx.splitSphere(s) catch |err| {
                        std.debug.print("Failed to split worst Medial Axis sphere for SurfaceMesh: {}\n", .{err});
                    };
                    vmas_ctx.updateSpheres() catch |err| {
                        std.debug.print("Failed to update Medial Axis spheres for SurfaceMesh: {}\n", .{err});
                    };
                }
            }
            vmas_ctx.updateSkeleton() catch |err| {
                std.debug.print("Failed to update Medial Axis skeleton for PointCloud: {}\n", .{err});
            };
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, Vec3f, vmas_ctx.sphere_center);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, vmas_ctx.sphere_radius);
            mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.spheres, f32, vmas_ctx.sphere_error);
            mad.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres);
            mad.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(mad.skeleton, .vertex, Vec3f, vmas_ctx.skeleton_vertex_position);
            mad.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(mad.skeleton);
            // mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, Vec3f, mad.point_sphere_color);
            // mad.app_ctx.point_cloud_store.pointCloudDataUpdated(mad.point_cloud, f32, mad.point_sphere_error);
            mad.app_ctx.requestRedraw();

            const elapsed: f64 = @floatFromInt(std.Io.Timestamp.untilNow(t, smma.app_ctx.io, .real).nanoseconds);
            zgp_log.info("Medial Axis skeleton computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
        }
    }

    c.ImGui_Separator();

    // Deinitialize VMAS button
    {
        const disabled = mad.vmas_ctx == null;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(255, 128, 128, 200));
        c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(255, 128, 128, 255));
        c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(255, 128, 128, 128));
        if (c.ImGui_ButtonEx("Deinitialize VMAS", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            if (mad.vmas_ctx) |*vmas_ctx| {
                vmas_ctx.deinit();
                mad.vmas_ctx = null;
            }
        }
        c.ImGui_PopStyleColorEx(3);
        if (disabled) {
            c.ImGui_EndDisabled();
        }
    }
}
