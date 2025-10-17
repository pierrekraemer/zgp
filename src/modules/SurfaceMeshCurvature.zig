const SurfaceMeshCurvature = @This();

const std = @import("std");

const imgui_utils = @import("../utils/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const zgp = @import("../main.zig");
const c = zgp.c;

const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const curvature = @import("../models/surface/curvature.zig");

module: Module = .{
    .name = "Surface Mesh Curvature",
    .vtable = &.{
        .rightClickMenu = rightClickMenu,
    },
},

pub fn init() SurfaceMeshCurvature {
    return .{};
}

pub fn deinit(_: *SurfaceMeshCurvature) void {}

fn computeVertexCurvatures(
    _: *SurfaceMeshCurvature,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
    edge_length: SurfaceMesh.CellData(.edge, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
    vertex_kmin: SurfaceMesh.CellData(.vertex, f32),
    vertex_Kmin: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_kmax: SurfaceMesh.CellData(.vertex, f32),
    vertex_Kmax: SurfaceMesh.CellData(.vertex, Vec3f),
) !void {
    var timer = try std.time.Timer.start();

    try curvature.computeVertexCurvatures(
        sm,
        vertex_position,
        vertex_normal,
        edge_dihedral_angle,
        edge_length,
        face_area,
        vertex_kmin,
        vertex_Kmin,
        vertex_kmax,
        vertex_Kmax,
    );
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_kmin);
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, vertex_Kmin);
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_kmax);
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, vertex_Kmax);

    const elapsed: f64 = @floatFromInt(timer.read());
    zgp_log.info("Curvatures computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
}

/// Part of the Module interface.
/// Describe the right-click menu interface.
pub fn rightClickMenu(m: *Module) void {
    const smc: *SurfaceMeshCurvature = @alignCast(@fieldParentPtr("module", m));
    const sms = &zgp.surface_mesh_store;

    const UiData = struct {
        // TODO: these data should be associated to the selected SurfaceMesh
        var vertex_kmin: ?SurfaceMesh.CellData(.vertex, f32) = null;
        var vertex_Kmin: ?SurfaceMesh.CellData(.vertex, Vec3f) = null;
        var vertex_kmax: ?SurfaceMesh.CellData(.vertex, f32) = null;
        var vertex_Kmax: ?SurfaceMesh.CellData(.vertex, Vec3f) = null;
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (c.ImGui_BeginMenu(m.name.ptr)) {
        defer c.ImGui_EndMenu();

        if (sms.selected_surface_mesh) |sm| {
            const info = sms.surfaceMeshInfo(sm);

            if (c.ImGui_BeginMenu("Curvature")) {
                defer c.ImGui_EndMenu();
                c.ImGui_Text("Curvature min");
                c.ImGui_PushID("CurvatureMin");
                if (imgui_utils.surfaceMeshCellDataComboBox(
                    sm,
                    .vertex,
                    f32,
                    UiData.vertex_kmin,
                )) |data| {
                    UiData.vertex_kmin = data;
                }
                c.ImGui_PopID();
                c.ImGui_Text("Curvature min dir");
                c.ImGui_PushID("CurvatureMinDir");
                if (imgui_utils.surfaceMeshCellDataComboBox(
                    sm,
                    .vertex,
                    Vec3f,
                    UiData.vertex_Kmin,
                )) |data| {
                    UiData.vertex_Kmin = data;
                }
                c.ImGui_PopID();
                c.ImGui_Text("Curvature max");
                c.ImGui_PushID("CurvatureMax");
                if (imgui_utils.surfaceMeshCellDataComboBox(
                    sm,
                    .vertex,
                    f32,
                    UiData.vertex_kmax,
                )) |data| {
                    UiData.vertex_kmax = data;
                }
                c.ImGui_PopID();
                c.ImGui_Text("Curvature max dir");
                c.ImGui_PushID("CurvatureMaxDir");
                if (imgui_utils.surfaceMeshCellDataComboBox(
                    sm,
                    .vertex,
                    Vec3f,
                    UiData.vertex_Kmax,
                )) |data| {
                    UiData.vertex_Kmax = data;
                }
                c.ImGui_PopID();
                const disabled =
                    info.std_data.vertex_position == null or
                    info.std_data.vertex_normal == null or
                    info.std_data.edge_dihedral_angle == null or
                    info.std_data.edge_length == null or
                    info.std_data.face_area == null or
                    UiData.vertex_kmin == null or
                    UiData.vertex_Kmin == null or
                    UiData.vertex_kmax == null or
                    UiData.vertex_Kmax == null;
                if (disabled) {
                    c.ImGui_BeginDisabled(true);
                }
                if (c.ImGui_ButtonEx("Compute curvatures", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                    smc.computeVertexCurvatures(
                        sm,
                        info.std_data.vertex_position.?,
                        info.std_data.vertex_normal.?,
                        info.std_data.edge_dihedral_angle.?,
                        info.std_data.edge_length.?,
                        info.std_data.face_area.?,
                        UiData.vertex_kmin.?,
                        UiData.vertex_Kmin.?,
                        UiData.vertex_kmax.?,
                        UiData.vertex_Kmax.?,
                    ) catch |err| {
                        std.debug.print("Error computing curvatures: {}\n", .{err});
                    };
                }
                imgui_utils.tooltip(
                    \\ Read:
                    \\ - std vertex_position
                    \\ - std vertex_normal
                    \\ - std edge_dihedral_angle
                    \\ - std edge_length
                    \\ - std face_area
                    \\ Write:
                    \\ - given curvature data (kmin, Kmin, kmax, Kmax)
                );
                if (disabled) {
                    c.ImGui_EndDisabled();
                }
            }
        } else {
            c.ImGui_Text("No Surface Mesh selected");
        }
    }
}
