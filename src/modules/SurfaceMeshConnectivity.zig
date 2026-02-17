const SurfaceMeshConnectivity = @This();

const std = @import("std");

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("../main.zig").c;

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfaceMeshCurvature = @import("./SurfaceMeshCurvature.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;
const bvh = @import("../geometry/bvh.zig");

const subdivision = @import("../models/surface/subdivision.zig");
const remeshing = @import("../models/surface/remeshing.zig");
const qem = @import("../models/surface/qem.zig");
const decimation = @import("../models/surface/decimation.zig");
const curvature = @import("../models/surface/curvature.zig");

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Connectivity",
    .vtable = &.{
        .rightClickMenu = rightClickMenu,
    },
},
// explicit dependency on curvature module to access curvature datas
surface_mesh_curvature: *SurfaceMeshCurvature,

pub fn init(app_ctx: *AppContext, surface_mesh_curvature: *SurfaceMeshCurvature) SurfaceMeshConnectivity {
    return .{
        .app_ctx = app_ctx,
        .surface_mesh_curvature = surface_mesh_curvature,
    };
}

pub fn deinit(_: *SurfaceMeshConnectivity) void {}

fn cutAllEdges(
    smc: *SurfaceMeshConnectivity,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
) !void {
    try subdivision.cutAllEdges(sm, vertex_position);
    smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, vertex_position);
    smc.app_ctx.surface_mesh_store.surfaceMeshConnectivityUpdated(sm);
    smc.app_ctx.requestRedraw();
}

fn triangulateFaces(
    smc: *SurfaceMeshConnectivity,
    sm: *SurfaceMesh,
) !void {
    try subdivision.triangulateFaces(sm);
    smc.app_ctx.surface_mesh_store.surfaceMeshConnectivityUpdated(sm);
    smc.app_ctx.requestRedraw();
}

fn remesh(
    smc: *SurfaceMeshConnectivity,
    sm: *SurfaceMesh,
    sm_bvh: bvh.TrianglesBVH,
    edge_length_factor: f32,
    adaptive: bool,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    edge_length: SurfaceMesh.CellData(.edge, f32),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_curvature: curvature.SurfaceMeshCurvatureDatas,
) !void {
    var timer = try std.time.Timer.start();

    try remeshing.pliantRemeshing(
        smc.app_ctx,
        sm,
        sm_bvh,
        edge_length_factor,
        adaptive,
        vertex_position,
        corner_angle,
        face_area,
        face_normal,
        edge_length,
        edge_dihedral_angle,
        vertex_area,
        vertex_normal,
        vertex_curvature,
    );
    smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, vertex_position);
    smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .corner, f32, corner_angle);
    smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .face, f32, face_area);
    smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .face, Vec3f, face_normal);
    smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .edge, f32, edge_length);
    smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .edge, f32, edge_dihedral_angle);
    smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_area);
    smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, vertex_normal);
    if (vertex_curvature.vertex_kmin) |kmin| {
        smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, f32, kmin);
    }
    if (vertex_curvature.vertex_Kmin) |Kmin| {
        smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, Kmin);
    }
    if (vertex_curvature.vertex_kmax) |kmax| {
        smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, f32, kmax);
    }
    if (vertex_curvature.vertex_Kmax) |Kmax| {
        smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, Kmax);
    }
    smc.app_ctx.surface_mesh_store.surfaceMeshConnectivityUpdated(sm);
    smc.app_ctx.requestRedraw();

    const elapsed: f64 = @floatFromInt(timer.read());
    zgp_log.info("Remeshing computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
}

fn decimate(
    smc: *SurfaceMeshConnectivity,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    nb_vertices_to_remove: u32,
) !void {
    var timer = try std.time.Timer.start();

    var vertex_qem = try sm.addData(.vertex, Mat4f, "__vertex_qem");
    defer sm.removeData(.vertex, vertex_qem.gen());
    try qem.computeVertexQEMs(
        smc.app_ctx,
        sm,
        vertex_position,
        vertex_area,
        vertex_tangent_basis,
        face_area,
        face_normal,
        vertex_qem,
    );
    try decimation.decimateQEM(
        sm,
        vertex_position,
        vertex_qem,
        nb_vertices_to_remove,
    );
    smc.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, vertex_position);
    smc.app_ctx.surface_mesh_store.surfaceMeshConnectivityUpdated(sm);
    smc.app_ctx.requestRedraw();

    const elapsed: f64 = @floatFromInt(timer.read());
    zgp_log.info("Decimation computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
}

/// Part of the Module interface.
/// Describe the right-click menu interface.
pub fn rightClickMenu(m: *Module) void {
    const smc: *SurfaceMeshConnectivity = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &smc.app_ctx.surface_mesh_store;

    const UiData = struct {
        var edge_length_factor: f32 = 1.0;
        var percent_vertices_to_keep: i32 = 75;
        var adaptive_remeshing: bool = false;
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (c.ImGui_BeginMenu(m.name.ptr)) {
        defer c.ImGui_EndMenu();

        if (sm_store.selected_surface_mesh) |sm| {
            const info = sm_store.surfaceMeshInfo(sm);

            if (c.ImGui_BeginMenu("Cut edges")) {
                defer c.ImGui_EndMenu();
                const disabled = info.std_datas.vertex_position == null;
                if (disabled) {
                    c.ImGui_BeginDisabled(true);
                }
                if (c.ImGui_ButtonEx("Cut all edges", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                    smc.cutAllEdges(sm, info.std_datas.vertex_position.?) catch |err| {
                        std.debug.print("Error cutting all edges: {}\n", .{err});
                    };
                }
                // imgui_utils.tooltip(
                //     \\ Read:
                //     \\ - std vertex_position
                //     \\ Update connectivity
                // );
                if (disabled) {
                    c.ImGui_EndDisabled();
                }
            }

            if (c.ImGui_BeginMenu("Triangulate faces")) {
                defer c.ImGui_EndMenu();
                if (c.ImGui_ButtonEx("Triangulate faces", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                    smc.triangulateFaces(sm) catch |err| {
                        std.debug.print("Error triangulating faces: {}\n", .{err});
                    };
                }
                imgui_utils.tooltip("Update connectivity");
            }

            if (c.ImGui_BeginMenu("Decimate (QEM)")) {
                defer c.ImGui_EndMenu();
                c.ImGui_Text("vertices to keep");
                c.ImGui_PushID("vertices to keep");
                _ = c.ImGui_SliderIntEx("", &UiData.percent_vertices_to_keep, 1, 100, "%d%%", c.ImGuiSliderFlags_AlwaysClamp);
                c.ImGui_PopID();
                const disabled = info.std_datas.vertex_position == null or
                    info.std_datas.vertex_area == null or
                    info.std_datas.vertex_tangent_basis == null or
                    info.std_datas.face_area == null or
                    info.std_datas.face_normal == null;
                if (disabled) {
                    c.ImGui_BeginDisabled(true);
                }
                if (c.ImGui_ButtonEx("Decimate (QEM)", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                    const nb_vertices_to_remove: u32 = @intFromFloat(@as(f32, @floatFromInt(sm.nbCells(.vertex))) * (1.0 - (@as(f32, @floatFromInt(UiData.percent_vertices_to_keep)) / 100.0)));
                    if (nb_vertices_to_remove > 0) {
                        smc.decimate(
                            sm,
                            info.std_datas.vertex_position.?,
                            info.std_datas.vertex_area.?,
                            info.std_datas.vertex_tangent_basis.?,
                            info.std_datas.face_area.?,
                            info.std_datas.face_normal.?,
                            nb_vertices_to_remove,
                        ) catch |err| {
                            std.debug.print("Error decimating: {}\n", .{err});
                        };
                    }
                }
                // imgui_utils.tooltip(
                //     \\ Read:
                //     \\ - std vertex_position
                //     \\ - std vertex_area
                //     \\ - std vertex_tangent_basis
                //     \\ - std face_area
                //     \\ - std face_normal
                //     \\ Write:
                //     \\ - std vertex_position
                //     \\ Update connectivity
                // );
                if (disabled) {
                    c.ImGui_EndDisabled();
                }
            }

            if (c.ImGui_BeginMenu("Remesh")) {
                defer c.ImGui_EndMenu();
                c.ImGui_Text("Edge length factor");
                c.ImGui_PushID("Edge length factor");
                _ = c.ImGui_SliderFloatEx("", &UiData.edge_length_factor, 0.1, 10.0, "%.2f", c.ImGuiSliderFlags_Logarithmic);
                c.ImGui_PopID();
                _ = c.ImGui_Checkbox("Curvature adaptive", &UiData.adaptive_remeshing);
                var disabled =
                    info.bvh.bvh_ptr == null or
                    info.std_datas.vertex_position == null or
                    info.std_datas.corner_angle == null or
                    info.std_datas.face_area == null or
                    info.std_datas.face_normal == null or
                    info.std_datas.edge_length == null or
                    info.std_datas.edge_dihedral_angle == null or
                    info.std_datas.vertex_area == null or
                    info.std_datas.vertex_normal == null;
                const curvature_datas = smc.surface_mesh_curvature.surfaceMeshCurvatureDatas(sm);
                if (UiData.adaptive_remeshing) {
                    if (curvature_datas.vertex_kmin == null or curvature_datas.vertex_Kmin == null or curvature_datas.vertex_kmax == null or curvature_datas.vertex_Kmax == null) {
                        disabled = true;
                    }
                }
                if (disabled) {
                    c.ImGui_BeginDisabled(true);
                }
                if (c.ImGui_ButtonEx("Remesh", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                    smc.remesh(
                        sm,
                        info.bvh,
                        UiData.edge_length_factor,
                        UiData.adaptive_remeshing,
                        info.std_datas.vertex_position.?,
                        info.std_datas.corner_angle.?,
                        info.std_datas.face_area.?,
                        info.std_datas.face_normal.?,
                        info.std_datas.edge_length.?,
                        info.std_datas.edge_dihedral_angle.?,
                        info.std_datas.vertex_area.?,
                        info.std_datas.vertex_normal.?,
                        curvature_datas,
                    ) catch |err| {
                        std.debug.print("Error remeshing: {}\n", .{err});
                    };
                }
                // imgui_utils.tooltip(
                //     \\ Read:
                //     \\ - std vertex_position
                //     \\ - std corner_angle
                //     \\ - std face_area
                //     \\ - std face_normal
                //     \\ - std edge_length
                //     \\ - std edge_dihedral_angle
                //     \\ - std vertex_area
                //     \\ - std vertex_normal
                //     \\ Write:
                //     \\ - std vertex_position
                //     \\ - std corner_angle
                //     \\ - std face_area
                //     \\ - std face_normal
                //     \\ - std edge_length
                //     \\ - std edge_dihedral_angle
                //     \\ - std vertex_area
                //     \\ - std vertex_normal
                //     \\ Update connectivity
                // );
                if (disabled) {
                    c.ImGui_EndDisabled();
                }
            }
        } else {
            c.ImGui_Text("No Surface Mesh selected");
        }
    }
}
