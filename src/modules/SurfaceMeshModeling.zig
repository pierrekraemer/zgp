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
const Vec3 = @import("../geometry/vec.zig").Vec3;

const subdivision = @import("../models/surface/subdivision.zig");

pub fn menuBar(_: *SurfaceMeshModeling) void {
    if (c.ImGui_BeginMenu("SurfaceMeshModeling")) {
        defer c.ImGui_EndMenu();
        const sm = ModelsRegistry.selected_surface_mesh orelse return;
        const surface_mesh_info = zgp.models_registry.getSurfaceMeshInfo(sm) orelse return;
        if (surface_mesh_info.vertex_position) |vertex_position| {
            if (c.ImGui_MenuItem("Cut All Edges")) {
                subdivision.cutAllEdges(sm, vertex_position) catch |err| {
                    std.debug.print("Error cutting edges: {}\n", .{err});
                };
                zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_position) catch |err| {
                    std.debug.print("Error updating surface mesh data: {}\n", .{err});
                };
                zgp.models_registry.surfaceMeshConnectivityUpdated(sm) catch |err| {
                    std.debug.print("Error updating surface mesh connectivity: {}\n", .{err});
                };
                zgp.need_redraw = true;
            }
        }
    }
}

pub fn module(smm: *SurfaceMeshModeling) Module {
    return Module.init(smm);
}
