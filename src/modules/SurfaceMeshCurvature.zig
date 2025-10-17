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

const CurvatureDatas = struct {
    vertex_kmin: ?SurfaceMesh.CellData(.vertex, f32) = null,
    vertex_Kmin: ?SurfaceMesh.CellData(.vertex, Vec3f) = null,
    vertex_kmax: ?SurfaceMesh.CellData(.vertex, f32) = null,
    vertex_Kmax: ?SurfaceMesh.CellData(.vertex, Vec3f) = null,
};

module: Module = .{
    .name = "Surface Mesh Curvature",
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .rightClickMenu = rightClickMenu,
    },
},
allocator: std.mem.Allocator,
surface_meshes_curvature_datas: std.AutoHashMap(*SurfaceMesh, CurvatureDatas),

pub fn init(allocator: std.mem.Allocator) SurfaceMeshCurvature {
    return .{
        .allocator = allocator,
        .surface_meshes_curvature_datas = .init(allocator),
    };
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
/// Create and store a CurvatureDatas for the new SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smc: *SurfaceMeshCurvature = @alignCast(@fieldParentPtr("module", m));
    _ = smc.surface_meshes_curvature_datas.put(surface_mesh, .{}) catch {
        zgp_log.err("Error creating CurvatureDatas for new SurfaceMesh", .{});
    };
}

/// Part of the Module interface.
/// Describe the right-click menu interface.
pub fn rightClickMenu(m: *Module) void {
    const smc: *SurfaceMeshCurvature = @alignCast(@fieldParentPtr("module", m));
    const sms = &zgp.surface_mesh_store;

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (c.ImGui_BeginMenu(m.name.ptr)) {
        defer c.ImGui_EndMenu();

        if (sms.selected_surface_mesh) |sm| {
            const info = sms.surfaceMeshInfo(sm);
            var curvature_datas = smc.surface_meshes_curvature_datas.getPtr(sm).?;

            if (c.ImGui_BeginMenu("Curvature")) {
                defer c.ImGui_EndMenu();
                c.ImGui_Text("Min curvature");
                c.ImGui_PushID("MinCurvature");
                if (imgui_utils.surfaceMeshCellDataComboBox(
                    sm,
                    .vertex,
                    f32,
                    curvature_datas.vertex_kmin,
                )) |data| {
                    curvature_datas.vertex_kmin = data;
                }
                c.ImGui_PopID();
                c.ImGui_Text("Min curvature dir");
                c.ImGui_PushID("MinCurvatureDir");
                if (imgui_utils.surfaceMeshCellDataComboBox(
                    sm,
                    .vertex,
                    Vec3f,
                    curvature_datas.vertex_Kmin,
                )) |data| {
                    curvature_datas.vertex_Kmin = data;
                }
                c.ImGui_PopID();
                c.ImGui_Text("Max curvature");
                c.ImGui_PushID("MaxCurvature");
                if (imgui_utils.surfaceMeshCellDataComboBox(
                    sm,
                    .vertex,
                    f32,
                    curvature_datas.vertex_kmax,
                )) |data| {
                    curvature_datas.vertex_kmax = data;
                }
                c.ImGui_PopID();
                c.ImGui_Text("Max curvature dir");
                c.ImGui_PushID("MaxCurvatureDir");
                if (imgui_utils.surfaceMeshCellDataComboBox(
                    sm,
                    .vertex,
                    Vec3f,
                    curvature_datas.vertex_Kmax,
                )) |data| {
                    curvature_datas.vertex_Kmax = data;
                }
                c.ImGui_PopID();

                if (c.ImGui_ButtonEx(c.ICON_FA_DATABASE ++ " Create missing datas", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                    inline for (@typeInfo(CurvatureDatas).@"struct".fields) |*field| {
                        if (@field(curvature_datas, field.name) == null) {
                            const maybe_data = sm.addData(@typeInfo(field.type).optional.child.CellType, @typeInfo(field.type).optional.child.DataType, field.name);
                            if (maybe_data) |data| {
                                @field(curvature_datas, field.name) = data;
                            } else |err| {
                                zgp_log.err("Error adding {s} ({s}: {s}) data: {}", .{ field.name, @tagName(@typeInfo(field.type).optional.child.CellType), @typeName(@typeInfo(field.type).optional.child.DataType), err });
                            }
                        }
                    }
                }

                const disabled =
                    info.std_data.vertex_position == null or
                    info.std_data.vertex_normal == null or
                    info.std_data.edge_dihedral_angle == null or
                    info.std_data.edge_length == null or
                    info.std_data.face_area == null or
                    curvature_datas.vertex_kmin == null or
                    curvature_datas.vertex_Kmin == null or
                    curvature_datas.vertex_kmax == null or
                    curvature_datas.vertex_Kmax == null;
                if (disabled) {
                    c.ImGui_BeginDisabled(true);
                }
                if (c.ImGui_ButtonEx(c.ICON_FA_GEAR ++ " Compute curvatures", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                    smc.computeVertexCurvatures(
                        sm,
                        info.std_data.vertex_position.?,
                        info.std_data.vertex_normal.?,
                        info.std_data.edge_dihedral_angle.?,
                        info.std_data.edge_length.?,
                        info.std_data.face_area.?,
                        curvature_datas.vertex_kmin.?,
                        curvature_datas.vertex_Kmin.?,
                        curvature_datas.vertex_kmax.?,
                        curvature_datas.vertex_Kmax.?,
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
