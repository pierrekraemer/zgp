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

pub fn module(smp: *SurfaceMeshProcessing) Module {
    return Module.init(smp);
}

pub fn name(_: *SurfaceMeshProcessing) []const u8 {
    return "Surface Mesh Processing";
}

fn cutAllEdges(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
) !void {
    try subdivision.cutAllEdges(sm, vertex_position);
    try zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_position);
    try zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
    if (builtin.mode == .Debug) {
        try sm.checkIntegrity();
    }
}

fn triangulateFaces(sm: *SurfaceMesh) !void {
    try subdivision.triangulateFaces(sm);
    try zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
    if (builtin.mode == .Debug) {
        try sm.checkIntegrity();
    }
}

fn remesh(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    length_factor: f32,
) !void {
    try remeshing.pliantRemeshing(sm, vertex_position, length_factor);
    try zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_position);
    try zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
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
    // TODO: VBO.fillFrom does not currently support scalar data
    // try zgp.models_registry.surfaceMeshDataUpdated(sm, .corner, f32, corner_angle);
}

fn computeFaceAreas(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face_area: SurfaceMesh.CellData(.face, f32),
) !void {
    try area.computeFaceAreas(sm, vertex_position, face_area);
    // TODO: VBO.fillFrom does not currently support scalar data
    // try zgp.models_registry.surfaceMeshDataUpdated(sm, .face, f32, face_area);
}

fn computeFaceNormals(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
) !void {
    try normal.computeFaceNormals(sm, vertex_position, face_normal);
    try zgp.models_registry.surfaceMeshDataUpdated(sm, .face, Vec3, face_normal);
}

fn computeVertexAreas(
    sm: *SurfaceMesh,
    face_area: SurfaceMesh.CellData(.face, f32),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
) !void {
    try area.computeVertexAreas(sm, face_area, vertex_area);
    // TODO: VBO.fillFrom does not currently support scalar data
    // try zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_area);
}

fn computeVertexNormals(
    sm: *SurfaceMesh,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3),
) !void {
    try normal.computeVertexNormals(sm, corner_angle, face_normal, vertex_normal);
    try zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_normal);
}

pub fn uiPanel(_: *SurfaceMeshProcessing) void {
    const UiData = struct {
        var length_factor: f32 = 1.0;
    };

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - c.ImGui_GetStyle().*.ItemSpacing.x * 2);

    if (zgp.models_registry.selected_surface_mesh) |sm| {
        const info = zgp.models_registry.surfaceMeshInfo(sm);

        c.ImGui_SeparatorText("Mesh Operations");

        if (info.std_data.vertex_position) |vertex_position| {
            if (c.ImGui_Button("Cut all edges")) {
                cutAllEdges(sm, vertex_position) catch |err| {
                    std.debug.print("Error cutting all edges: {}\n", .{err});
                };
            }
        } else {
            imgui_utils.disabledButton("Cut all edges", "Missing vertex_position data");
        }

        if (c.ImGui_Button("Triangulate faces")) {
            triangulateFaces(sm) catch |err| {
                std.debug.print("Error triangulating faces: {}\n", .{err});
            };
        }

        _ = c.ImGui_SliderFloat("Length factor", &UiData.length_factor, 0.1, 10.0);
        if (info.std_data.vertex_position) |vertex_position| {
            if (c.ImGui_Button("Remesh")) {
                remesh(sm, vertex_position, UiData.length_factor) catch |err| {
                    std.debug.print("Error remeshing: {}\n", .{err});
                };
            }
        } else {
            imgui_utils.disabledButton("Remesh", "Missing vertex_position data");
        }

        c.ImGui_SeparatorText("Geometry Computations");

        if (info.std_data.vertex_position != null and info.std_data.corner_angle != null) {
            if (c.ImGui_Button("corner angles")) {
                computeCornerAngles(
                    sm,
                    info.std_data.vertex_position.?,
                    info.std_data.corner_angle.?,
                ) catch |err| {
                    std.debug.print("Error computing corner angles: {}\n", .{err});
                };
            }
        } else {
            imgui_utils.disabledButton("corner angles", "Missing one of (vertex_position, corner_angle) data");
        }

        if (info.std_data.vertex_position != null and info.std_data.face_area != null) {
            if (c.ImGui_Button("face areas")) {
                computeFaceAreas(
                    sm,
                    info.std_data.vertex_position.?,
                    info.std_data.face_area.?,
                ) catch |err| {
                    std.debug.print("Error computing face areas: {}\n", .{err});
                };
            }
        } else {
            imgui_utils.disabledButton("face areas", "Missing one of (vertex_position, face_area) data");
        }

        if (info.std_data.vertex_position != null and info.std_data.face_normal != null) {
            if (c.ImGui_Button("face normals")) {
                computeFaceNormals(
                    sm,
                    info.std_data.vertex_position.?,
                    info.std_data.face_normal.?,
                ) catch |err| {
                    std.debug.print("Error computing face normals: {}\n", .{err});
                };
            }
        } else {
            imgui_utils.disabledButton("face normals", "Missing one of (vertex_position, face_normal) data");
        }

        if (info.std_data.face_area != null and info.std_data.vertex_area != null) {
            if (c.ImGui_Button("vertex areas")) {
                computeVertexAreas(
                    sm,
                    info.std_data.face_area.?,
                    info.std_data.vertex_area.?,
                ) catch |err| {
                    std.debug.print("Error computing vertex areas: {}\n", .{err});
                };
            }
        } else {
            imgui_utils.disabledButton("vertex areas", "Missing one of (face_area, vertex_area) data");
        }

        if (info.std_data.corner_angle != null and info.std_data.face_normal != null and info.std_data.vertex_normal != null) {
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
        } else {
            imgui_utils.disabledButton("vertex normals", "Missing one of (corner_angle, face_normal, vertex_normal) data");
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }

    c.ImGui_PopItemWidth();
}
