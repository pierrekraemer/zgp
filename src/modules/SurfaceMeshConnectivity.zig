const SurfaceMeshConnectivity = @This();

const std = @import("std");

const imgui_utils = @import("../utils/imgui.zig");

const zgp = @import("../main.zig");
const c = zgp.c;

const Module = @import("Module.zig");
const ModelsRegistry = @import("../models/ModelsRegistry.zig");
const SurfaceMesh = ModelsRegistry.SurfaceMesh;

const vec = @import("../geometry/vec.zig");
const Vec3 = vec.Vec3;
const mat = @import("../geometry/mat.zig");
const Mat4 = mat.Mat4;

const subdivision = @import("../models/surface/subdivision.zig");
const remeshing = @import("../models/surface/remeshing.zig");
const qem = @import("../models/surface/qem.zig");
const decimation = @import("../models/surface/decimation.zig");

// TODO: useful to keep an allocator here rather than exposing & using zgp.allocator?
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !SurfaceMeshConnectivity {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(_: *SurfaceMeshConnectivity) void {}

/// Return a Module interface for the SurfaceMeshConnectivity.
pub fn module(smc: *SurfaceMeshConnectivity) Module {
    return Module.init(smc);
}

/// Part of the Module interface.
/// Return the name of the module.
pub fn name(_: *SurfaceMeshConnectivity) []const u8 {
    return "Surface Mesh Connectivity";
}

fn cutAllEdges(
    _: *SurfaceMeshConnectivity,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
) !void {
    try subdivision.cutAllEdges(sm, vertex_position);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_position);
    zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
}

fn triangulateFaces(
    _: *SurfaceMeshConnectivity,
    sm: *SurfaceMesh,
) !void {
    try subdivision.triangulateFaces(sm);
    zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
}

fn remesh(
    _: *SurfaceMeshConnectivity,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
    edge_length: SurfaceMesh.CellData(.edge, f32),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3),
    edge_length_factor: f32,
) !void {
    try remeshing.pliantRemeshing(
        sm,
        vertex_position,
        corner_angle,
        face_area,
        face_normal,
        edge_length,
        edge_dihedral_angle,
        vertex_area,
        vertex_normal,
        edge_length_factor,
    );
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_position);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .corner, f32, corner_angle);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .face, f32, face_area);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .face, Vec3, face_normal);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .edge, f32, edge_length);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .edge, f32, edge_dihedral_angle);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_area);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_normal);
    zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
}

fn decimate(
    smc: *SurfaceMeshConnectivity,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
    nb_vertices_to_remove: u32,
) !void {
    var vertex_qem = try sm.addData(.vertex, Mat4, "vertex_qem");
    defer sm.removeData(.vertex, vertex_qem.gen());
    try qem.computeVertexQEMs(sm, vertex_position, face_area, face_normal, vertex_qem);
    try decimation.decimateQEM(smc.allocator, sm, vertex_position, vertex_qem, nb_vertices_to_remove);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_position);
    zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
}

pub fn uiPanel(smc: *SurfaceMeshConnectivity) void {
    const UiData = struct {
        var edge_length_factor: f32 = 1.0;
        var percent_vertices_to_keep: i32 = 75;
        var button_text_buf: [64]u8 = undefined;
        var new_data_name: [32]u8 = undefined;
    };

    const mr = &zgp.models_registry;

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (mr.selected_surface_mesh) |sm| {
        const info = mr.surfaceMeshInfo(sm);

        {
            const disabled = info.std_data.vertex_position == null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Cut all edges", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                smc.cutAllEdges(sm, info.std_data.vertex_position.?) catch |err| {
                    std.debug.print("Error cutting all edges: {}\n", .{err});
                };
            }
            imgui_utils.tooltip(
                \\ Read:
                \\ - std vertex_position
                \\ Update connectivity
            );
            if (disabled) {
                c.ImGui_EndDisabled();
            }
        }

        {
            if (c.ImGui_ButtonEx("Triangulate faces", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                smc.triangulateFaces(sm) catch |err| {
                    std.debug.print("Error triangulating faces: {}\n", .{err});
                };
            }
            imgui_utils.tooltip("Update connectivity");
        }

        {
            c.ImGui_Text("vertices to keep");
            c.ImGui_PushID("vertices to keep");
            _ = c.ImGui_SliderIntEx("", &UiData.percent_vertices_to_keep, 1, 100, "%d%%", c.ImGuiSliderFlags_AlwaysClamp);
            c.ImGui_PopID();
            const disabled = info.std_data.vertex_position == null or
                info.std_data.face_area == null or
                info.std_data.face_normal == null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Decimate (QEM)", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                const nb_vertices_to_remove: u32 = @intFromFloat(@as(f32, @floatFromInt(sm.nbCells(.vertex))) * (1.0 - (@as(f32, @floatFromInt(UiData.percent_vertices_to_keep)) / 100.0)));
                if (nb_vertices_to_remove > 0) {
                    smc.decimate(
                        sm,
                        info.std_data.vertex_position.?,
                        info.std_data.face_area.?,
                        info.std_data.face_normal.?,
                        nb_vertices_to_remove,
                    ) catch |err| {
                        std.debug.print("Error decimating: {}\n", .{err});
                    };
                }
            }
            imgui_utils.tooltip(
                \\ Read:
                \\ - std vertex_position
                \\ - std face_area
                \\ - std face_normal
                \\ Write:
                \\ - std vertex_position
                \\ Update connectivity
            );
            if (disabled) {
                c.ImGui_EndDisabled();
            }
        }

        {
            c.ImGui_Text("Edge length factor");
            c.ImGui_PushID("Edge length factor");
            _ = c.ImGui_SliderFloatEx("", &UiData.edge_length_factor, 0.1, 10.0, "%.2f", c.ImGuiSliderFlags_Logarithmic);
            c.ImGui_PopID();
            const disabled = info.std_data.vertex_position == null or
                info.std_data.corner_angle == null or
                info.std_data.face_area == null or
                info.std_data.face_normal == null or
                info.std_data.edge_length == null or
                info.std_data.edge_dihedral_angle == null or
                info.std_data.vertex_area == null or
                info.std_data.vertex_normal == null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Remesh", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                smc.remesh(
                    sm,
                    info.std_data.vertex_position.?,
                    info.std_data.corner_angle.?,
                    info.std_data.face_area.?,
                    info.std_data.face_normal.?,
                    info.std_data.edge_length.?,
                    info.std_data.edge_dihedral_angle.?,
                    info.std_data.vertex_area.?,
                    info.std_data.vertex_normal.?,
                    UiData.edge_length_factor,
                ) catch |err| {
                    std.debug.print("Error remeshing: {}\n", .{err});
                };
            }
            imgui_utils.tooltip(
                \\ Read:
                \\ - std vertex_position
                \\ - std corner_angle
                \\ - std face_area
                \\ - std face_normal
                \\ - std edge_length
                \\ - std edge_dihedral_angle
                \\ - std vertex_area
                \\ - std vertex_normal
                \\ Write:
                \\ - std vertex_position
                \\ - std corner_angle
                \\ - std face_area
                \\ - std face_normal
                \\ - std edge_length
                \\ - std edge_dihedral_angle
                \\ - std vertex_area
                \\ - std vertex_normal
                \\ Update connectivity
            );
            if (disabled) {
                c.ImGui_EndDisabled();
            }
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }
}
