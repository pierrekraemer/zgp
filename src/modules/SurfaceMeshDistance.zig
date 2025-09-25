const SurfaceMeshDistance = @This();

const std = @import("std");

const imgui_utils = @import("../utils/imgui.zig");

const zgp = @import("../main.zig");
const c = zgp.c;

const Module = @import("Module.zig");
const ModelsRegistry = @import("../models/ModelsRegistry.zig");
const SurfaceMesh = ModelsRegistry.SurfaceMesh;

const vec = @import("../geometry/vec.zig");
const Vec3 = vec.Vec3;

const distance = @import("../models/surface/distance.zig");

// TODO: useful to keep an allocator here rather than exposing & using zgp.allocator?
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !SurfaceMeshDistance {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(_: *SurfaceMeshDistance) void {}

/// Return a Module interface for the SurfaceMeshDistance.
pub fn module(smc: *SurfaceMeshDistance) Module {
    return Module.init(smc);
}

/// Part of the Module interface.
/// Return the name of the module.
pub fn name(_: *SurfaceMeshDistance) []const u8 {
    return "Surface Mesh Distance";
}

fn computeVertexGeodesicDistancesFromSource(
    smd: *SurfaceMeshDistance,
    sm: *SurfaceMesh,
    source_vertex: SurfaceMesh.Cell,
    diffusion_time: f32,
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    edge_length: SurfaceMesh.CellData(.edge, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
    vertex_distance: SurfaceMesh.CellData(.vertex, f32),
) !void {
    try distance.computeVertexGeodesicDistancesFromSource(
        smd.allocator,
        sm,
        source_vertex,
        diffusion_time,
        halfedge_cotan_weight,
        vertex_position,
        vertex_area,
        edge_length,
        face_area,
        face_normal,
        vertex_distance,
    );
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_distance);
}

pub fn uiPanel(smd: *SurfaceMeshDistance) void {
    const UiData = struct {
        var source_vertex: SurfaceMesh.Cell = .{ .vertex = 0 };
        var diffusion_time: f32 = 1.0;
        var vertex_distance: ?SurfaceMesh.CellData(.vertex, f32) = null;
    };
    const UiCB = struct {
        const DataSelectedContext = struct {};
        fn onDistanceDataSelected(
            comptime cell_type: SurfaceMesh.CellType,
            comptime T: type,
            data: ?SurfaceMesh.CellData(cell_type, T),
            _: DataSelectedContext,
        ) void {
            UiData.vertex_distance = data;
        }
    };

    const mr = &zgp.models_registry;

    const item_spacing = c.ImGui_GetStyle().*.ItemSpacing.x;
    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - item_spacing * 2);

    if (mr.selected_surface_mesh) |sm| {
        const info = mr.surfaceMeshInfo(sm);

        {
            c.ImGui_Text("Distance");
            c.ImGui_PushID("DistanceData");
            imgui_utils.surfaceMeshCellDataComboBox(
                sm,
                .vertex,
                f32,
                UiData.vertex_distance,
                UiCB.DataSelectedContext{},
                &UiCB.onDistanceDataSelected,
            );
            c.ImGui_PopID();
            c.ImGui_Text("Diffusion time");
            c.ImGui_PushID("Diffusion time");
            _ = c.ImGui_SliderFloatEx("", &UiData.diffusion_time, 1.0, 100.0, "%.1f", c.ImGuiSliderFlags_Logarithmic);
            c.ImGui_PopID();
            const disabled =
                info.std_data.halfedge_cotan_weight == null or
                info.std_data.vertex_position == null or
                info.std_data.vertex_area == null or
                info.std_data.edge_length == null or
                info.std_data.face_area == null or
                info.std_data.face_normal == null or
                UiData.vertex_distance == null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Compute geodesic distance", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                smd.computeVertexGeodesicDistancesFromSource(
                    sm,
                    UiData.source_vertex,
                    UiData.diffusion_time,
                    info.std_data.halfedge_cotan_weight.?,
                    info.std_data.vertex_position.?,
                    info.std_data.vertex_area.?,
                    info.std_data.edge_length.?,
                    info.std_data.face_area.?,
                    info.std_data.face_normal.?,
                    UiData.vertex_distance.?,
                ) catch |err| {
                    std.debug.print("Error computing geodesic distance: {}\n", .{err});
                };
            }
            imgui_utils.tooltip(
                \\ Read:
                \\ - halfedge_cotan_weight
                \\ - vertex_position
                \\ - vertex_area
                \\ - edge_length
                \\ - face_area
                \\ - face_normal
                \\ Write:
                \\ - vertex_distance
            );
            if (disabled) {
                c.ImGui_EndDisabled();
            }
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }

    c.ImGui_PopItemWidth();
}
