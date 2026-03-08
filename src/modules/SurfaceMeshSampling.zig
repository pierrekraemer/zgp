const SurfaceMeshSampling = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("../main.zig").c;

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfacePoint = @import("../models//surface/SurfacePoint.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const sampling = @import("../models/surface/sampling.zig");

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Sampling",
    .supported_models = .{ .surface_mesh = true },
    .vtable = &.{
        .rightClickMenu = rightClickMenu,
    },
},

pub fn init(app_ctx: *AppContext) SurfaceMeshSampling {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(_: *SurfaceMeshSampling) void {}

fn uniformSampling(
    sms: *SurfaceMeshSampling,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    nb_points: usize,
) !void {
    var timer = try std.time.Timer.start();

    const pc = try sms.app_ctx.point_cloud_store.createPointCloud(sms.app_ctx.surface_mesh_store.surfaceMeshName(sm).?);
    const point_position = try pc.addData(Vec3f, "position");
    const point_surface_point = try pc.addData(SurfacePoint, "surface_point");
    sms.app_ctx.point_cloud_store.setPointCloudStdData(pc, .{ .position = point_position });

    try sampling.samplePointsOnSurface(sms.app_ctx, sm, vertex_position, face_area, pc, point_position, point_surface_point, nb_points);
    sms.app_ctx.point_cloud_store.pointCloudDataUpdated(pc, Vec3f, point_position);
    sms.app_ctx.point_cloud_store.pointCloudDataUpdated(pc, SurfacePoint, point_surface_point);
    sms.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(pc);

    const elapsed: f64 = @floatFromInt(timer.read());
    zgp_log.info("Uniform sampling computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});

    sms.app_ctx.requestRedraw();
}

/// Part of the Module interface.
/// Describe the right-click menu interface.
pub fn rightClickMenu(m: *Module) void {
    const sms: *SurfaceMeshSampling = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &sms.app_ctx.surface_mesh_store;

    assert(sms.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = sms.app_ctx.selected_model.surface_mesh;

    const UiData = struct {
        var nb_points: usize = 1000;
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (c.ImGui_BeginMenu(m.name.ptr)) {
        defer c.ImGui_EndMenu();

        const info = sm_store.surfaceMeshInfo(sm);

        if (c.ImGui_BeginMenu("Uniform sampling")) {
            defer c.ImGui_EndMenu();
            c.ImGui_Text("Number of points");
            c.ImGui_PushID("Number of points");
            _ = c.ImGui_InputInt("", @ptrCast(&UiData.nb_points));
            c.ImGui_PopID();
            const disabled = info.std_datas.vertex_position == null or info.std_datas.face_area == null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Sample", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                sms.uniformSampling(
                    sm,
                    info.std_datas.vertex_position.?,
                    info.std_datas.face_area.?,
                    UiData.nb_points,
                ) catch |err| {
                    std.debug.print("Error sampling: {}\n", .{err});
                };
            }
            if (disabled) {
                c.ImGui_EndDisabled();
            }
        }
    }
}
