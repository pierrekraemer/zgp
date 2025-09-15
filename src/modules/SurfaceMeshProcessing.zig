const SurfaceMeshProcessing = @This();

const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("dcimgui.h");
});
const imgui_utils = @import("../utils/imgui.zig");

const zgp = @import("../main.zig");

const Module = @import("Module.zig");
const ModelsRegistry = @import("../models/ModelsRegistry.zig");
const SurfaceMesh = ModelsRegistry.SurfaceMesh;
const SurfaceMeshStdData = ModelsRegistry.SurfaceMeshStdData;

const vec = @import("../geometry/vec.zig");
const Vec3 = vec.Vec3;

const angle = @import("../models/surface/angle.zig");
const area = @import("../models/surface/area.zig");
const curvature = @import("../models/surface/curvature.zig");
const length = @import("../models/surface/length.zig");
const normal = @import("../models/surface/normal.zig");
const subdivision = @import("../models/surface/subdivision.zig");
const remeshing = @import("../models/surface/remeshing.zig");

/// Return a Module interface for the SurfaceMeshProcessing.
pub fn module(smp: *SurfaceMeshProcessing) Module {
    return Module.init(smp);
}

/// Part of the Module interface.
/// Return the name of the module.
pub fn name(_: *SurfaceMeshProcessing) []const u8 {
    return "Surface Mesh Processing";
}

fn cutAllEdges(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
) !void {
    try subdivision.cutAllEdges(sm, vertex_position);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_position);
    zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
    if (builtin.mode == .Debug) {
        try sm.checkIntegrity();
    }
}

fn triangulateFaces(sm: *SurfaceMesh) !void {
    try subdivision.triangulateFaces(sm);
    zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
    if (builtin.mode == .Debug) {
        try sm.checkIntegrity();
    }
}

fn remesh(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3),
    length_factor: f32,
) !void {
    try remeshing.pliantRemeshing(
        sm,
        vertex_position,
        corner_angle,
        face_area,
        face_normal,
        edge_dihedral_angle,
        vertex_area,
        vertex_normal,
        length_factor,
    );
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_position);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .corner, f32, corner_angle);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .face, f32, face_area);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .face, Vec3, face_normal);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .edge, f32, edge_dihedral_angle);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_area);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_normal);
    zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
    if (builtin.mode == .Debug) {
        try sm.checkIntegrity();
    }
}

fn computeCornerAngles(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    corner_angle: SurfaceMesh.CellData(.corner, f32),
) !void {
    try angle.computeCornerAngles(sm, vertex_position, corner_angle);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .corner, f32, corner_angle);
}

fn computeEdgeLengths(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    edge_length: SurfaceMesh.CellData(.edge, f32),
) !void {
    try length.computeEdgeLengths(sm, vertex_position, edge_length);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .edge, f32, edge_length);
}

fn computeEdgeDihedralAngles(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
) !void {
    try angle.computeEdgeDihedralAngles(sm, vertex_position, face_normal, edge_dihedral_angle);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .edge, f32, edge_dihedral_angle);
}

fn computeFaceAreas(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face_area: SurfaceMesh.CellData(.face, f32),
) !void {
    try area.computeFaceAreas(sm, vertex_position, face_area);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .face, f32, face_area);
}

fn computeFaceNormals(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
) !void {
    try normal.computeFaceNormals(sm, vertex_position, face_normal);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .face, Vec3, face_normal);
}

fn computeVertexAreas(
    sm: *SurfaceMesh,
    face_area: SurfaceMesh.CellData(.face, f32),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
) !void {
    try area.computeVertexAreas(sm, face_area, vertex_area);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_area);
}

fn computeVertexNormals(
    sm: *SurfaceMesh,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3),
) !void {
    try normal.computeVertexNormals(sm, corner_angle, face_normal, vertex_normal);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_normal);
}

pub fn uiPanel(_: *SurfaceMeshProcessing) void {
    const UiData = struct {
        var length_factor: f32 = 1.0;
        var button_text_buf: [64]u8 = undefined;
        var new_data_name: [32]u8 = undefined;
    };

    const mr = &zgp.models_registry;

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - c.ImGui_GetStyle().*.ItemSpacing.x * 2);

    if (mr.selected_surface_mesh) |sm| {
        const info = mr.surfaceMeshInfo(sm);

        c.ImGui_SeparatorText("Mesh Operations");

        if (info.std_data.vertex_position) |vertex_position| {
            if (c.ImGui_Button("Cut all edges")) {
                cutAllEdges(sm, vertex_position) catch |err| {
                    std.debug.print("Error cutting all edges: {}\n", .{err});
                };
            }
        } else {
            imgui_utils.disabledButton("Cut all edges", "Missing std vertex_position data");
        }

        if (c.ImGui_Button("Triangulate faces")) {
            triangulateFaces(sm) catch |err| {
                std.debug.print("Error triangulating faces: {}\n", .{err});
            };
        }

        c.ImGui_Text("Length factor");
        c.ImGui_PushID("Length factor");
        _ = c.ImGui_SliderFloatEx("", &UiData.length_factor, 0.1, 10.0, "%.2f", c.ImGuiSliderFlags_Logarithmic);
        c.ImGui_PopID();
        if (info.std_data.vertex_position != null and
            info.std_data.corner_angle != null and
            info.std_data.face_area != null and
            info.std_data.face_normal != null and
            info.std_data.edge_dihedral_angle != null and
            info.std_data.vertex_area != null and
            info.std_data.vertex_normal != null)
        {
            if (c.ImGui_Button("Remesh")) {
                remesh(
                    sm,
                    info.std_data.vertex_position.?,
                    info.std_data.corner_angle.?,
                    info.std_data.face_area.?,
                    info.std_data.face_normal.?,
                    info.std_data.edge_dihedral_angle.?,
                    info.std_data.vertex_area.?,
                    info.std_data.vertex_normal.?,
                    UiData.length_factor,
                ) catch |err| {
                    std.debug.print("Error remeshing: {}\n", .{err});
                };
            }
        } else {
            imgui_utils.disabledButton("Remesh", "Missing std data among:\n- vertex_position\n- corner_angle\n- face_area\n- face_normal\n- edge_dihedral_angle\n- vertex_area\n- vertex_normal");
        }

        c.ImGui_SeparatorText("Geometry Computations");

        // TODO: most of this code is very repetitive, could be factored out with comptime parameters and inline functions

        if (info.std_data.vertex_position != null and info.std_data.corner_angle != null) {
            const vertex_position_last_update = mr.dataLastUpdate(info.std_data.vertex_position.?.gen());
            const corner_angle_last_update = mr.dataLastUpdate(info.std_data.corner_angle.?.gen());
            const out_of_date =
                vertex_position_last_update == null or corner_angle_last_update == null or
                corner_angle_last_update.?.order(vertex_position_last_update.?) == .lt;
            if (out_of_date) {
                c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(255, 128, 128, 200));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(255, 128, 128, 255));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(255, 128, 128, 128));
            }
            if (c.ImGui_Button("corner angles")) {
                computeCornerAngles(
                    sm,
                    info.std_data.vertex_position.?,
                    info.std_data.corner_angle.?,
                ) catch |err| {
                    std.debug.print("Error computing corner angles: {}\n", .{err});
                };
            }
            if (out_of_date) {
                c.ImGui_PopStyleColorEx(3);
            }
            imgui_utils.tooltip("Read: vertex_position\nWrite: corner_angle");
        } else {
            imgui_utils.disabledButton("corner angles", "Missing std data among:\n-vertex_position\n-corner_angle");
        }
        c.ImGui_SameLine();
        c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + @max(0.0, c.ImGui_GetContentRegionAvail().x - 20.0));
        var button_text = std.fmt.bufPrintZ(&UiData.button_text_buf, "Add {s} data ({s})", .{ @tagName(.corner), @typeName(f32) }) catch "";
        _ = std.fmt.bufPrintZ(&UiData.new_data_name, "angle", .{}) catch "";
        if (imgui_utils.addDataButton("corner angles", button_text, &UiData.new_data_name)) {
            const maybe_data = sm.addData(.corner, f32, &UiData.new_data_name);
            if (maybe_data) |data| {
                if (info.std_data.corner_angle == null) {
                    mr.setSurfaceMeshStdData(sm, .{ .corner_angle = data });
                }
            } else |err| {
                std.debug.print("Error adding {s} {s} data: {}\n", .{ @tagName(.corner), @typeName(f32), err });
            }
            UiData.new_data_name[0] = 0;
        }

        if (info.std_data.vertex_position != null and info.std_data.face_area != null) {
            const vertex_position_last_update = mr.dataLastUpdate(info.std_data.vertex_position.?.gen());
            const face_area_last_update = mr.dataLastUpdate(info.std_data.face_area.?.gen());
            const out_of_date =
                vertex_position_last_update == null or face_area_last_update == null or
                face_area_last_update.?.order(vertex_position_last_update.?) == .lt;
            if (out_of_date) {
                c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(255, 128, 128, 200));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(255, 128, 128, 255));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(255, 128, 128, 128));
            }
            if (c.ImGui_Button("face areas")) {
                computeFaceAreas(
                    sm,
                    info.std_data.vertex_position.?,
                    info.std_data.face_area.?,
                ) catch |err| {
                    std.debug.print("Error computing face areas: {}\n", .{err});
                };
            }
            if (out_of_date) {
                c.ImGui_PopStyleColorEx(3);
            }
            imgui_utils.tooltip("Read: vertex_position\nWrite: face_area");
        } else {
            imgui_utils.disabledButton("face areas", "Missing std data among:\n-vertex_position\n-face_area");
        }
        c.ImGui_SameLine();
        c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + @max(0.0, c.ImGui_GetContentRegionAvail().x - 20.0));
        button_text = std.fmt.bufPrintZ(&UiData.button_text_buf, "Add {s} data ({s})", .{ @tagName(.face), @typeName(f32) }) catch "";
        _ = std.fmt.bufPrintZ(&UiData.new_data_name, "area", .{}) catch "";
        if (imgui_utils.addDataButton("face areas", button_text, &UiData.new_data_name)) {
            const maybe_data = sm.addData(.face, f32, &UiData.new_data_name);
            if (maybe_data) |data| {
                if (info.std_data.face_area == null) {
                    mr.setSurfaceMeshStdData(sm, .{ .face_area = data });
                }
            } else |err| {
                std.debug.print("Error adding {s} {s} data: {}\n", .{ @tagName(.face), @typeName(f32), err });
            }
            UiData.new_data_name[0] = 0;
        }

        if (info.std_data.vertex_position != null and info.std_data.face_normal != null) {
            const vertex_position_last_update = mr.dataLastUpdate(info.std_data.vertex_position.?.gen());
            const face_normal_last_update = mr.dataLastUpdate(info.std_data.face_normal.?.gen());
            const out_of_date =
                vertex_position_last_update == null or face_normal_last_update == null or
                face_normal_last_update.?.order(vertex_position_last_update.?) == .lt;
            if (out_of_date) {
                c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(255, 128, 128, 200));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(255, 128, 128, 255));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(255, 128, 128, 128));
            }
            if (c.ImGui_Button("face normals")) {
                computeFaceNormals(
                    sm,
                    info.std_data.vertex_position.?,
                    info.std_data.face_normal.?,
                ) catch |err| {
                    std.debug.print("Error computing face normals: {}\n", .{err});
                };
            }
            if (out_of_date) {
                c.ImGui_PopStyleColorEx(3);
            }
            imgui_utils.tooltip("Read: vertex_position\nWrite: face_normal");
        } else {
            imgui_utils.disabledButton("face normals", "Missing std data among:\n-vertex_position\n-face_normal");
        }
        c.ImGui_SameLine();
        c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + @max(0.0, c.ImGui_GetContentRegionAvail().x - 20.0));
        button_text = std.fmt.bufPrintZ(&UiData.button_text_buf, "Add {s} data ({s})", .{ @tagName(.face), @typeName(Vec3) }) catch "";
        _ = std.fmt.bufPrintZ(&UiData.new_data_name, "normal", .{}) catch "";
        if (imgui_utils.addDataButton("face normals", button_text, &UiData.new_data_name)) {
            const maybe_data = sm.addData(.face, Vec3, &UiData.new_data_name);
            if (maybe_data) |data| {
                if (info.std_data.face_normal == null) {
                    mr.setSurfaceMeshStdData(sm, .{ .face_normal = data });
                }
            } else |err| {
                std.debug.print("Error adding {s} {s} data: {}\n", .{ @tagName(.face), @typeName(f32), err });
            }
            UiData.new_data_name[0] = 0;
        }

        if (info.std_data.vertex_position != null and info.std_data.edge_length != null) {
            const vertex_position_last_update = mr.dataLastUpdate(info.std_data.vertex_position.?.gen());
            const edge_length_last_update = mr.dataLastUpdate(info.std_data.edge_length.?.gen());
            const out_of_date =
                vertex_position_last_update == null or edge_length_last_update == null or
                edge_length_last_update.?.order(vertex_position_last_update.?) == .lt;
            if (out_of_date) {
                c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(255, 128, 128, 200));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(255, 128, 128, 255));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(255, 128, 128, 128));
            }
            if (c.ImGui_Button("edge lengths")) {
                computeEdgeLengths(
                    sm,
                    info.std_data.vertex_position.?,
                    info.std_data.edge_length.?,
                ) catch |err| {
                    std.debug.print("Error computing edge lengths: {}\n", .{err});
                };
            }
            if (out_of_date) {
                c.ImGui_PopStyleColorEx(3);
            }
            imgui_utils.tooltip("Read: vertex_position\nWrite: edge_length");
        } else {
            imgui_utils.disabledButton("edge lengths", "Missing std data among:\n-vertex_position\n-edge_length");
        }
        c.ImGui_SameLine();
        c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + @max(0.0, c.ImGui_GetContentRegionAvail().x - 20.0));
        button_text = std.fmt.bufPrintZ(&UiData.button_text_buf, "Add {s} data ({s})", .{ @tagName(.edge), @typeName(f32) }) catch "";
        _ = std.fmt.bufPrintZ(&UiData.new_data_name, "length", .{}) catch "";
        if (imgui_utils.addDataButton("edge lengths", button_text, &UiData.new_data_name)) {
            const maybe_data = sm.addData(.edge, f32, &UiData.new_data_name);
            if (maybe_data) |data| {
                if (info.std_data.edge_length == null) {
                    mr.setSurfaceMeshStdData(sm, .{ .edge_length = data });
                }
            } else |err| {
                std.debug.print("Error adding {s} {s} data: {}\n", .{ @tagName(.edge), @typeName(f32), err });
            }
            UiData.new_data_name[0] = 0;
        }

        if (info.std_data.vertex_position != null and info.std_data.face_normal != null and info.std_data.edge_dihedral_angle != null) {
            const vertex_position_last_update = mr.dataLastUpdate(info.std_data.vertex_position.?.gen());
            const face_normal_last_update = mr.dataLastUpdate(info.std_data.face_normal.?.gen());
            const edge_dihedral_angle_last_update = mr.dataLastUpdate(info.std_data.edge_dihedral_angle.?.gen());
            const out_of_date =
                vertex_position_last_update == null or face_normal_last_update == null or edge_dihedral_angle_last_update == null or
                edge_dihedral_angle_last_update.?.order(vertex_position_last_update.?) == .lt or
                edge_dihedral_angle_last_update.?.order(face_normal_last_update.?) == .lt;
            if (out_of_date) {
                c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(255, 128, 128, 200));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(255, 128, 128, 255));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(255, 128, 128, 128));
            }
            if (c.ImGui_Button("edge dihedral angles")) {
                computeEdgeDihedralAngles(
                    sm,
                    info.std_data.vertex_position.?,
                    info.std_data.face_normal.?,
                    info.std_data.edge_dihedral_angle.?,
                ) catch |err| {
                    std.debug.print("Error computing edge dihedral angles: {}\n", .{err});
                };
            }
            if (out_of_date) {
                c.ImGui_PopStyleColorEx(3);
            }
            imgui_utils.tooltip("Read: vertex_position, face_normal\nWrite: edge_dihedral_angle");
        } else {
            imgui_utils.disabledButton("edge dihedral angles", "Missing std data among:\n-vertex_position\n-face_normal\n-edge_dihedral_angle");
        }
        c.ImGui_SameLine();
        c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + @max(0.0, c.ImGui_GetContentRegionAvail().x - 20.0));
        button_text = std.fmt.bufPrintZ(&UiData.button_text_buf, "Add {s} data ({s})", .{ @tagName(.edge), @typeName(f32) }) catch "";
        _ = std.fmt.bufPrintZ(&UiData.new_data_name, "dihedral angle", .{}) catch "";
        if (imgui_utils.addDataButton("edge dihedral angles", button_text, &UiData.new_data_name)) {
            const maybe_data = sm.addData(.edge, f32, &UiData.new_data_name);
            if (maybe_data) |data| {
                if (info.std_data.edge_dihedral_angle == null) {
                    mr.setSurfaceMeshStdData(sm, .{ .edge_dihedral_angle = data });
                }
            } else |err| {
                std.debug.print("Error adding {s} {s} data: {}\n", .{ @tagName(.edge), @typeName(f32), err });
            }
            UiData.new_data_name[0] = 0;
        }

        if (info.std_data.face_area != null and info.std_data.vertex_area != null) {
            const face_area_last_update = mr.dataLastUpdate(info.std_data.face_area.?.gen());
            const vertex_area_last_update = mr.dataLastUpdate(info.std_data.vertex_area.?.gen());
            const out_of_date =
                face_area_last_update == null or vertex_area_last_update == null or
                vertex_area_last_update.?.order(face_area_last_update.?) == .lt;
            if (out_of_date) {
                c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(255, 128, 128, 200));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(255, 128, 128, 255));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(255, 128, 128, 128));
            }
            if (c.ImGui_Button("vertex areas")) {
                computeVertexAreas(
                    sm,
                    info.std_data.face_area.?,
                    info.std_data.vertex_area.?,
                ) catch |err| {
                    std.debug.print("Error computing vertex areas: {}\n", .{err});
                };
            }
            if (out_of_date) {
                c.ImGui_PopStyleColorEx(3);
            }
            imgui_utils.tooltip("Read: face_area\nWrite: vertex_area");
        } else {
            imgui_utils.disabledButton("vertex areas", "Missing std data among:\n-face_area\n-vertex_area");
        }
        c.ImGui_SameLine();
        c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + @max(0.0, c.ImGui_GetContentRegionAvail().x - 20.0));
        button_text = std.fmt.bufPrintZ(&UiData.button_text_buf, "Add {s} data ({s})", .{ @tagName(.vertex), @typeName(f32) }) catch "";
        _ = std.fmt.bufPrintZ(&UiData.new_data_name, "area", .{}) catch "";
        if (imgui_utils.addDataButton("vertex areas", button_text, &UiData.new_data_name)) {
            const maybe_data = sm.addData(.vertex, f32, &UiData.new_data_name);
            if (maybe_data) |data| {
                if (info.std_data.vertex_area == null) {
                    mr.setSurfaceMeshStdData(sm, .{ .vertex_area = data });
                }
            } else |err| {
                std.debug.print("Error adding {s} {s} data: {}\n", .{ @tagName(.face), @typeName(f32), err });
            }
            UiData.new_data_name[0] = 0;
        }

        if (info.std_data.corner_angle != null and info.std_data.face_normal != null and info.std_data.vertex_normal != null) {
            const corner_angle_last_update = mr.dataLastUpdate(info.std_data.corner_angle.?.gen());
            const face_normal_last_update = mr.dataLastUpdate(info.std_data.face_normal.?.gen());
            const vertex_normal_last_update = mr.dataLastUpdate(info.std_data.vertex_normal.?.gen());
            const out_of_date =
                corner_angle_last_update == null or face_normal_last_update == null or vertex_normal_last_update == null or
                vertex_normal_last_update.?.order(corner_angle_last_update.?) == .lt or
                vertex_normal_last_update.?.order(face_normal_last_update.?) == .lt;
            if (out_of_date) {
                c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(255, 128, 128, 200));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(255, 128, 128, 255));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(255, 128, 128, 128));
            }
            if (c.ImGui_Button("vertex normals")) {
                computeVertexNormals(
                    sm,
                    info.std_data.corner_angle.?,
                    info.std_data.face_normal.?,
                    info.std_data.vertex_normal.?,
                ) catch |err| {
                    std.debug.print("Error computing vertex normals: {}\n", .{err});
                };
            }
            if (out_of_date) {
                c.ImGui_PopStyleColorEx(3);
            }
            imgui_utils.tooltip("Read: corner_angle, face_normal\nWrite: vertex_normal");
        } else {
            imgui_utils.disabledButton("vertex normals", "Missing std data among:\n-corner_angle\n-face_normal\n-vertex_normal");
        }
        c.ImGui_SameLine();
        c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + @max(0.0, c.ImGui_GetContentRegionAvail().x - 20.0));
        button_text = std.fmt.bufPrintZ(&UiData.button_text_buf, "Add {s} data ({s})", .{ @tagName(.vertex), @typeName(Vec3) }) catch "";
        _ = std.fmt.bufPrintZ(&UiData.new_data_name, "normal", .{}) catch "";
        if (imgui_utils.addDataButton("vertex normals", button_text, &UiData.new_data_name)) {
            const maybe_data = sm.addData(.vertex, Vec3, &UiData.new_data_name);
            if (maybe_data) |data| {
                if (info.std_data.vertex_normal == null) {
                    mr.setSurfaceMeshStdData(sm, .{ .vertex_normal = data });
                }
            } else |err| {
                std.debug.print("Error adding {s} {s} data: {}\n", .{ @tagName(.vertex), @typeName(Vec3), err });
            }
            UiData.new_data_name[0] = 0;
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }

    c.ImGui_PopItemWidth();
}
