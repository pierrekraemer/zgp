const SurfaceMeshDistance = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("../main.zig").c;

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const distance = @import("../models/surface/distance.zig");

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Distance",
    .supported_models = .{ .surface_mesh = true },
    .vtable = &.{
        .rightClickMenu = rightClickMenu,
    },
},

pub fn init(app_ctx: *AppContext) SurfaceMeshDistance {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(_: *SurfaceMeshDistance) void {}

fn computeVertexGeodesicDistancesFromSource(
    smd: *SurfaceMeshDistance,
    sm: *SurfaceMesh,
    source_vertices: []SurfaceMesh.Cell,
    diffusion_time: f32,
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    edge_length: SurfaceMesh.CellData(.edge, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    vertex_distance: SurfaceMesh.CellData(.vertex, f32),
) !void {
    var timer = try std.time.Timer.start();

    try distance.computeVertexGeodesicDistancesFromSource(
        smd.app_ctx,
        sm,
        source_vertices,
        diffusion_time,
        halfedge_cotan_weight,
        vertex_position,
        vertex_area,
        edge_length,
        face_area,
        face_normal,
        vertex_distance,
    );
    smd.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_distance);
    smd.app_ctx.requestRedraw();

    const elapsed: f64 = @floatFromInt(timer.read());
    zgp_log.info("Geodesic distance computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
}

/// Part of the Module interface.
/// Describe the right-click menu interface.
pub fn rightClickMenu(m: *Module) void {
    const smd: *SurfaceMeshDistance = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &smd.app_ctx.surface_mesh_store;

    assert(smd.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = smd.app_ctx.selected_model.surface_mesh;

    const UiData = struct {
        var diffusion_time: f32 = 1.0;
        var vertex_distance: ?SurfaceMesh.CellData(.vertex, f32) = null;
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (c.ImGui_BeginMenu(m.name.ptr)) {
        defer c.ImGui_EndMenu();

        const info = sm_store.surfaceMeshInfo(sm);

        if (c.ImGui_BeginMenu("Geodesic Distance")) {
            defer c.ImGui_EndMenu();
            c.ImGui_Text("Distance data (to write)");
            c.ImGui_PushID("DistanceData");
            switch (imgui_utils.surfaceMeshCellDataComboBox(sm, .vertex, f32, UiData.vertex_distance)) {
                .unchanged => {},
                .cleared => UiData.vertex_distance = null,
                .changed => |data| UiData.vertex_distance = data,
            }
            c.ImGui_PopID();

            if (c.ImGui_ButtonEx(c.ICON_FA_DATABASE ++ " Create distance data", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                if (UiData.vertex_distance == null) {
                    const maybe_data = sm.addData(.vertex, f32, "distance");
                    if (maybe_data) |data| {
                        UiData.vertex_distance = data;
                    } else |err| {
                        zgp_log.err("Error adding distance data: {}", .{err});
                    }
                }
            }

            c.ImGui_Text("Diffusion time");
            c.ImGui_PushID("Diffusion time");
            _ = c.ImGui_SliderFloatEx("", &UiData.diffusion_time, 1.0, 100.0, "%.1f", c.ImGuiSliderFlags_Logarithmic);
            c.ImGui_PopID();

            const disabled =
                info.vertex_set.cells.items.len == 0 or
                info.std_datas.halfedge_cotan_weight == null or
                info.std_datas.vertex_position == null or
                info.std_datas.vertex_area == null or
                info.std_datas.edge_length == null or
                info.std_datas.face_area == null or
                info.std_datas.face_normal == null or
                UiData.vertex_distance == null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Compute geodesic distance", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                smd.computeVertexGeodesicDistancesFromSource(
                    sm,
                    info.vertex_set.cells.items,
                    UiData.diffusion_time,
                    info.std_datas.halfedge_cotan_weight.?,
                    info.std_datas.vertex_position.?,
                    info.std_datas.vertex_area.?,
                    info.std_datas.edge_length.?,
                    info.std_datas.face_area.?,
                    info.std_datas.face_normal.?,
                    UiData.vertex_distance.?,
                ) catch |err| {
                    std.debug.print("Error computing geodesic distance: {}\n", .{err});
                };
            }
            if (disabled) {
                imgui_utils.tooltip(
                    \\ Requires:
                    \\ - at least 1 selected vertex.
                    \\ Following data should be available:
                    \\ - std halfedge_cotan_weight
                    \\ - std vertex_position
                    \\ - std vertex_area
                    \\ - std edge_length
                    \\ - std face_area
                    \\ - std face_normal
                    \\ - selected vertex distance data
                );
                c.ImGui_EndDisabled();
            }
        }
    }
}
