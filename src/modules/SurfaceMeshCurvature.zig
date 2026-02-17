const SurfaceMeshCurvature = @This();

const std = @import("std");

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("../main.zig").c;

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const curvature = @import("../models/surface/curvature.zig");

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Curvature",
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .rightClickMenu = rightClickMenu,
    },
},
surface_meshes_curvature_datas: std.AutoHashMap(*SurfaceMesh, curvature.SurfaceMeshCurvatureDatas),

pub fn init(app_ctx: *AppContext) SurfaceMeshCurvature {
    return .{
        .app_ctx = app_ctx,
        .surface_meshes_curvature_datas = .init(app_ctx.allocator),
    };
}

pub fn deinit(smc: *SurfaceMeshCurvature) void {
    smc.surface_meshes_curvature_datas.deinit();
}

fn computeVertexCurvatures(
    smc: *SurfaceMeshCurvature,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
    edge_length: SurfaceMesh.CellData(.edge, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
    vertex_curvature: curvature.SurfaceMeshCurvatureDatas,
) !void {
    var timer = try std.time.Timer.start();

    try curvature.computeVertexCurvatures(
        smc.app_ctx,
        sm,
        vertex_position,
        vertex_normal,
        edge_dihedral_angle,
        edge_length,
        face_area,
        vertex_curvature,
    );
    smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_curvature.vertex_kmin.?);
    smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, vertex_curvature.vertex_Kmin.?);
    smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_curvature.vertex_kmax.?);
    smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, vertex_curvature.vertex_Kmax.?);
    smc.app_ctx.requestRedraw();

    const elapsed: f64 = @floatFromInt(timer.read());
    zgp_log.info("Curvatures computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
}

pub fn surfaceMeshCurvatureDatas(smc: *SurfaceMeshCurvature, surface_mesh: *SurfaceMesh) curvature.SurfaceMeshCurvatureDatas {
    return smc.surface_meshes_curvature_datas.get(surface_mesh).?;
}

/// Part of the Module interface.
/// Create and store a CurvatureDatas for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smc: *SurfaceMeshCurvature = @alignCast(@fieldParentPtr("module", m));
    _ = smc.surface_meshes_curvature_datas.put(surface_mesh, .{}) catch {
        zgp_log.err("Error creating CurvatureDatas for new SurfaceMesh", .{});
    };
}

/// Part of the Module interface.
/// Remove the CurvatureDatas associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smc: *SurfaceMeshCurvature = @alignCast(@fieldParentPtr("module", m));
    _ = smc.surface_meshes_curvature_datas.remove(surface_mesh);
}

/// Part of the Module interface.
/// Describe the right-click menu interface.
pub fn rightClickMenu(m: *Module) void {
    const smc: *SurfaceMeshCurvature = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &smc.app_ctx.surface_mesh_store;

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (c.ImGui_BeginMenu(m.name.ptr)) {
        defer c.ImGui_EndMenu();

        if (sm_store.selected_surface_mesh) |sm| {
            const info = sm_store.surfaceMeshInfo(sm);
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
                    inline for (@typeInfo(curvature.SurfaceMeshCurvatureDatas).@"struct".fields) |*field| {
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
                    info.std_datas.vertex_position == null or
                    info.std_datas.vertex_normal == null or
                    info.std_datas.edge_dihedral_angle == null or
                    info.std_datas.edge_length == null or
                    info.std_datas.face_area == null or
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
                        info.std_datas.vertex_position.?,
                        info.std_datas.vertex_normal.?,
                        info.std_datas.edge_dihedral_angle.?,
                        info.std_datas.edge_length.?,
                        info.std_datas.face_area.?,
                        curvature_datas.*,
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
