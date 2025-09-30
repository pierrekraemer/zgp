const SurfaceMeshDistance = @This();

const std = @import("std");

const imgui_utils = @import("../utils/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const zgp = @import("../main.zig");
const c = zgp.c;

const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");

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

// TODO: allow selecting multiple source vertices
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
    var timer = try std.time.Timer.start();

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
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_distance);

    const elapsed: f64 = @floatFromInt(timer.read());
    zgp_log.info("Geodesic distance computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
}

pub fn uiPanel(smd: *SurfaceMeshDistance) void {
    const UiData = struct {
        var source_vertex: SurfaceMesh.Cell = .{ .vertex = 0 };
        var diffusion_time: f32 = 1.0;
        var vertex_distance: ?SurfaceMesh.CellData(.vertex, f32) = null;
    };

    const sms = &zgp.surface_mesh_store;

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (sms.selected_surface_mesh) |sm| {
        const info = sms.surfaceMeshInfo(sm);

        {
            c.ImGui_Text("Distance data (to write)");
            c.ImGui_PushID("DistanceData");
            if (imgui_utils.surfaceMeshCellDataComboBox(
                sm,
                .vertex,
                f32,
                UiData.vertex_distance,
            )) |data| {
                UiData.vertex_distance = data;
            }
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
                // TODO: select source vertex from a CellSet
                UiData.source_vertex = .{ .vertex = sm.vertex_data.firstIndex() };
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
                \\ - std halfedge_cotan_weight
                \\ - std vertex_position
                \\ - std vertex_area
                \\ - std edge_length
                \\ - std face_area
                \\ - std face_normal
                \\ Write:
                \\ - given distance data
            );
            if (disabled) {
                c.ImGui_EndDisabled();
            }
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }
}
