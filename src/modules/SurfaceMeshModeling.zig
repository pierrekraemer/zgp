const SurfaceMeshModeling = @This();

const std = @import("std");

const c = @cImport({
    @cInclude("dcimgui.h");
});

const zgp = @import("../main.zig");

const Module = @import("Module.zig");
const ModelsRegistry = @import("../models/ModelsRegistry.zig");
const SurfaceMesh = ModelsRegistry.SurfaceMesh;
const SurfaceMeshStandardData = ModelsRegistry.SurfaceMeshStandardData;
const vec = @import("../geometry/vec.zig");
const Vec3 = vec.Vec3;

const subdivision = @import("../models/surface/subdivision.zig");

pub fn module(smm: *SurfaceMeshModeling) Module {
    return Module.init(smm);
}

pub fn name(_: *SurfaceMeshModeling) []const u8 {
    return "Surface Mesh Modeling";
}

fn cutAllEdges() !void {
    const sm = zgp.models_registry.selected_surface_mesh orelse return;
    const surface_mesh_info = zgp.models_registry.getSurfaceMeshInfo(sm) orelse return;
    if (surface_mesh_info.vertex_position) |vertex_position| {
        try subdivision.cutAllEdges(sm, vertex_position);
        try zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_position);
        try zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
        zgp.need_redraw = true;
    }
}

fn flipEdge(dart: SurfaceMesh.Dart) !void {
    const sm = zgp.models_registry.selected_surface_mesh orelse return;
    try sm.flipEdge(.{ .edge = dart });
    try zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
    zgp.need_redraw = true;
}

fn collapseEdge(dart: SurfaceMesh.Dart) !void {
    const sm = zgp.models_registry.selected_surface_mesh orelse return;
    const surface_mesh_info = zgp.models_registry.getSurfaceMeshInfo(sm) orelse return;
    if (surface_mesh_info.vertex_position) |vertex_position| {
        const new_pos = vec.mulScalar3(
            vec.add3(
                vertex_position.value(.{ .vertex = dart }),
                vertex_position.value(.{ .vertex = sm.phi1(dart) }),
            ),
            0.5,
        );
        const v = try sm.collapseEdge(.{ .edge = dart });
        vertex_position.valuePtr(v).* = new_pos;
        try zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_position);
        try zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
        zgp.need_redraw = true;
    }
}

pub fn menuBar(_: *SurfaceMeshModeling) void {
    const UiData = struct {
        var dart: c_int = 0;
    };

    if (c.ImGui_BeginMenu("SurfaceMeshModeling")) {
        defer c.ImGui_EndMenu();
        if (zgp.models_registry.selected_surface_mesh) |sm| {
            if (c.ImGui_MenuItem("Cut All Edges")) {
                cutAllEdges() catch |err| {
                    std.debug.print("Error cutting all edges: {}\n", .{err});
                };
            }
            _ = c.ImGui_InputInt("Dart", &UiData.dart);
            if (sm.isValidDart(@intCast(UiData.dart))) {
                if (c.ImGui_MenuItem("Flip Edge")) {
                    flipEdge(@intCast(UiData.dart)) catch |err| {
                        std.debug.print("Error flipping edge: {}\n", .{err});
                    };
                }
                if (c.ImGui_MenuItem("Collapse Edge")) {
                    collapseEdge(@intCast(UiData.dart)) catch |err| {
                        std.debug.print("Error collapsing edge: {}\n", .{err});
                    };
                }
            } else {
                c.ImGui_TextDisabled("Invalid dart");
            }
        } else {
            c.ImGui_TextDisabled("No surface mesh selected");
        }
    }
}
