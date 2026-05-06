const SurfaceMeshDistance = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("c");

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const distance = @import("../models/surface/distance.zig");

const DistanceData = struct {
    vertex_distance: ?SurfaceMesh.CellData(.vertex, f32) = null,
    selected_vertex_set: ?*SurfaceMesh.CellSet = null,
};

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Distance",
    .supported_models = .{ .surface_mesh = true },
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .rightClickMenu = rightClickMenu,
    },
},
surface_meshes_data: std.AutoHashMapUnmanaged(*SurfaceMesh, DistanceData) = .empty,

pub fn init(app_ctx: *AppContext) SurfaceMeshDistance {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(smd: *SurfaceMeshDistance) void {
    smd.surface_meshes_data.deinit(smd.app_ctx.allocator);
}

/// Part of the Module interface.
/// Create and store a DistanceData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smd: *SurfaceMeshDistance = @alignCast(@fieldParentPtr("module", m));
    smd.surface_meshes_data.put(smd.app_ctx.allocator, surface_mesh, .{}) catch |err| {
        std.debug.print("Failed to store DistanceData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Remove the DistanceData associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smd: *SurfaceMeshDistance = @alignCast(@fieldParentPtr("module", m));
    _ = smd.surface_meshes_data.remove(surface_mesh);
}

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
    const t = std.Io.Timestamp.now(smd.app_ctx.io, .real);

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

    const elapsed: f64 = @floatFromInt(std.Io.Timestamp.untilNow(t, smd.app_ctx.io, .real).nanoseconds);
    zgp_log.info("Geodesic distance computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
}

/// Part of the Module interface.
/// Describe the right-click menu interface.
pub fn rightClickMenu(m: *Module) void {
    const smd: *SurfaceMeshDistance = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &smd.app_ctx.surface_mesh_store;

    assert(smd.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = smd.app_ctx.selected_model.surface_mesh;
    const dd = smd.surface_meshes_data.getPtr(sm).?;

    const UiData = struct {
        var diffusion_time: f32 = 1.0;
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (c.ImGui_BeginMenu(m.name.ptr)) {
        defer c.ImGui_EndMenu();

        const info = sm_store.surfaceMeshInfo(sm);

        if (c.ImGui_BeginMenu("Geodesic Distance")) {
            defer c.ImGui_EndMenu();
            c.ImGui_Text("Vertex set:");
            c.ImGui_PushID("vertex set");
            switch (imgui_utils.surfaceMeshCellSetComboBox(sm, .vertex, dd.selected_vertex_set)) {
                .unchanged => {},
                .cleared => dd.selected_vertex_set = null,
                .changed => |cell_set| dd.selected_vertex_set = cell_set,
            }
            c.ImGui_PopID();

            c.ImGui_Text("Distance data (to write)");
            c.ImGui_PushID("DistanceData");
            switch (imgui_utils.surfaceMeshCellDataComboBox(sm, .vertex, f32, dd.vertex_distance)) {
                .unchanged => {},
                .cleared => dd.vertex_distance = null,
                .changed => |data| dd.vertex_distance = data,
            }
            c.ImGui_PopID();

            if (c.ImGui_ButtonEx(c.ICON_FA_DATABASE ++ " Create distance data", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                if (dd.vertex_distance == null) {
                    const maybe_data = sm.addData(.vertex, f32, "distance");
                    if (maybe_data) |data| {
                        dd.vertex_distance = data;
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
                dd.selected_vertex_set == null or
                dd.selected_vertex_set.?.cells.items.len == 0 or
                info.std_datas.halfedge_cotan_weight == null or
                info.std_datas.vertex_position == null or
                info.std_datas.vertex_area == null or
                info.std_datas.edge_length == null or
                info.std_datas.face_area == null or
                info.std_datas.face_normal == null or
                dd.vertex_distance == null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Compute geodesic distance", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                smd.computeVertexGeodesicDistancesFromSource(
                    sm,
                    dd.selected_vertex_set.?.cells.items,
                    UiData.diffusion_time,
                    info.std_datas.halfedge_cotan_weight.?,
                    info.std_datas.vertex_position.?,
                    info.std_datas.vertex_area.?,
                    info.std_datas.edge_length.?,
                    info.std_datas.face_area.?,
                    info.std_datas.face_normal.?,
                    dd.vertex_distance.?,
                ) catch |err| {
                    std.debug.print("Error computing geodesic distance: {}\n", .{err});
                };
            }
            if (disabled) {
                imgui_utils.tooltip(
                    \\ Requires:
                    \\ - at least 1 vertex in the selected vertex set.
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
