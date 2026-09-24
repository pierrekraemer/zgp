const PointCloudMedialAxis = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("c");

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const PointCloud = @import("../models/point/PointCloud.zig");
const IncidenceGraph = @import("../models/incidenceGraph/IncidenceGraph.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const kdtree = @import("../geometry/kdtree.zig");

const medial_axis = @import("../models/point/medial_axis.zig");

const MedialAxisData = struct {
    app_ctx: *AppContext,
    point_cloud: *PointCloud,

    spheres: *PointCloud = undefined,
    skeleton: *IncidenceGraph = undefined,

    vmas_ctx: ?medial_axis.VMASContext = null, // optional VMAS context
    // maybe there will be other medial axis computation contexts in the future

    pub fn initVMASContext(
        mad: *MedialAxisData,
        point_cloud_kdtree: *kdtree.PointsKDTree,
        point_position: PointCloud.CellData(Vec3f),
        point_normal: PointCloud.CellData(Vec3f),
        line_quadric_epsilon: f32,
    ) !void {
        assert(mad.vmas_ctx == null);
        assert(point_cloud_kdtree.point_cloud == mad.point_cloud and point_cloud_kdtree.initialized);
        assert(point_position.point_cloud == mad.point_cloud);
        assert(point_normal.point_cloud == mad.point_cloud);

        var buf: [64]u8 = undefined;
        const spheres_name = std.fmt.bufPrintSentinel(&buf, "{s}_spheres", .{mad.app_ctx.point_cloud_store.pointCloudName(mad.point_cloud).?}, 0) catch "__spheres";
        mad.spheres = try mad.app_ctx.point_cloud_store.createPointCloud(spheres_name);
        const skeleton_name = std.fmt.bufPrintSentinel(&buf, "{s}_skeleton", .{mad.app_ctx.point_cloud_store.pointCloudName(mad.point_cloud).?}, 0) catch "__skeleton";
        mad.skeleton = try mad.app_ctx.incidence_graph_store.createIncidenceGraph(skeleton_name);

        mad.vmas_ctx = try .init(
            mad.app_ctx.allocator,
            mad.app_ctx.io,
            mad.point_cloud,
            point_cloud_kdtree,
            point_position,
            point_normal,
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
    .name = "Point Cloud Medial Axis",
    .supported_models = .{ .point_cloud = true },
    .vtable = &.{
        .pointCloudCreated = pointCloudCreated,
        .pointCloudDestroyed = pointCloudDestroyed,
        // TODO: should manage PointCloud connectivity & point_position updates
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
    var it = pcma.point_clouds_data.valueIterator();
    while (it.next()) |mad| {
        mad.deinit();
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
    if (pcma.point_clouds_data.getPtr(point_cloud)) |mad| {
        mad.deinit();
    }
    _ = pcma.point_clouds_data.remove(point_cloud);
}

/// Part of the Module interface.
/// Show a UI panel to control the medial axis data of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const pcma: *PointCloudMedialAxis = @alignCast(@fieldParentPtr("module", m));
    const pc_store = &pcma.app_ctx.point_cloud_store;

    assert(pcma.app_ctx.selected_model.modelType() == .point_cloud);
    const pc = pcma.app_ctx.selected_model.point_cloud;
    const mad = pcma.point_clouds_data.getPtr(pc).?;
    const info = pc_store.pointCloudInfo(pc);

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
            !info.kdtree.initialized or
            info.std_datas.position == null or
            info.std_datas.normal == null or
            mad.vmas_ctx != null;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx(if (mad.vmas_ctx != null) "VMAS initialized" else "Initialize VMAS", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            mad.initVMASContext(
                &info.kdtree,
                info.std_datas.position.?,
                info.std_datas.normal.?,
                UiData.line_quadric_epsilon,
            ) catch |err| {
                std.debug.print("Failed to initialize VMAS for PointCloud: {}\n", .{err});
            };
            if (mad.vmas_ctx) |*vmas_ctx| {
                vmas_ctx.createFirstSphere() catch |err| {
                    std.debug.print("Failed to create first medial sphere for PointCloud: {}\n", .{err});
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
                    \\ - kdtree
                    \\ Following data should be available:
                    \\ - std position
                    \\ - std normal
                );
            }
            c.ImGui_EndDisabled();
        }
    }

    if (mad.vmas_ctx) |*vmas_ctx| {
        if (c.ImGui_ButtonEx("Recompute SQEMs", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            vmas_ctx.updatePointSQEMs(UiData.line_quadric_epsilon) catch |err| {
                std.debug.print("Failed to recompute Medial Axis SQEMs for PointCloud: {}\n", .{err});
            };
            vmas_ctx.updateSpheres() catch |err| {
                std.debug.print("Failed to update Medial Axis spheres for PointCloud: {}\n", .{err});
            };
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
        }

        if (c.ImGui_ButtonEx("Update spheres", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            vmas_ctx.updateSpheres() catch |err| {
                std.debug.print("Failed to update Medial Axis spheres for PointCloud: {}\n", .{err});
            };
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
        }

        if (c.ImGui_ButtonEx("Split worst sphere", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            if (vmas_ctx.worstSphere()) |s| {
                vmas_ctx.splitSphere(s) catch |err| {
                    std.debug.print("Failed to split worst Medial Axis sphere for PointCloud: {}\n", .{err});
                };
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
            }
        }
        _ = c.ImGui_InputInt("Number of spheres", @ptrCast(&UiData.nb_spheres));
        if (c.ImGui_ButtonEx("Build skeleton from scratch", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            const t = std.Io.Timestamp.now(pcma.app_ctx.io, .real);

            vmas_ctx.clearRetainingCapacity();
            vmas_ctx.createFirstSphere() catch |err| {
                std.debug.print("Failed to create first medial sphere for PointCloud: {}\n", .{err});
            };
            for (0..UiData.nb_spheres) |_| {
                if (vmas_ctx.worstSphere()) |s| {
                    vmas_ctx.splitSphere(s) catch |err| {
                        std.debug.print("Failed to split worst Medial Axis sphere for PointCloud: {}\n", .{err});
                    };
                    vmas_ctx.updateSpheres() catch |err| {
                        std.debug.print("Failed to update Medial Axis spheres for PointCloud: {}\n", .{err});
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

            const elapsed: f64 = @floatFromInt(std.Io.Timestamp.untilNow(t, pcma.app_ctx.io, .real).nanoseconds);
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
