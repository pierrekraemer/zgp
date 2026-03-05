const SurfaceMeshSampling = @This();

const std = @import("std");

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("../main.zig").c;

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");

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
    sampling_density: f32,
) !void {
    var timer = try std.time.Timer.start();

    const pc = try sms.app_ctx.point_cloud_store.createPointCloud(sms.app_ctx.surface_mesh_store.surfaceMeshName(sm).?);
    const point_position = try pc.addData(Vec3f, "position");
    sms.app_ctx.point_cloud_store.setPointCloudStdData(pc, .{ .position = point_position });

    try sampling.samplePointsOnSurface(sms.app_ctx, sm, vertex_position, face_area, pc, point_position, sampling_density);
    sms.app_ctx.point_cloud_store.pointCloudDataUpdated(pc, Vec3f, point_position);
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

    const UiData = struct {
        var sampling_density: f32 = 1.0;
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (c.ImGui_BeginMenu(m.name.ptr)) {
        defer c.ImGui_EndMenu();

        if (sm_store.selected_surface_mesh) |sm| {
            const info = sm_store.surfaceMeshInfo(sm);

            if (c.ImGui_BeginMenu("Uniform sampling")) {
                defer c.ImGui_EndMenu();
                c.ImGui_Text("Sampling density");
                c.ImGui_PushID("Sampling density");
                _ = c.ImGui_SliderFloatEx("", &UiData.sampling_density, 1.0, 100.0, "%.2f", c.ImGuiSliderFlags_Logarithmic);
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
                        UiData.sampling_density,
                    ) catch |err| {
                        std.debug.print("Error sampling: {}\n", .{err});
                    };
                }
                if (disabled) {
                    c.ImGui_EndDisabled();
                }
            }
        } else {
            c.ImGui_Text("No Surface Mesh selected");
        }
    }
}
