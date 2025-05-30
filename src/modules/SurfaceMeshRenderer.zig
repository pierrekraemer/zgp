const ModelsRegistry = @import("../models/ModelsRegistry.zig");
const SurfaceMesh = ModelsRegistry.SurfaceMesh;

const Self = @This();

const c = @cImport({
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_sdl3.h");
    @cInclude("backends/dcimgui_impl_opengl3.h");
});

models_registry: *ModelsRegistry,
selected_surface_mesh: ?*SurfaceMesh = null,

pub fn ui_panel(self: *Self) void {
    _ = c.ImGui_Begin("Surface Mesh Renderer", null, c.ImGuiWindowFlags_NoSavedSettings);

    if (c.ImGui_BeginListBox("Surface Mesh", c.ImVec2{ .x = 0, .y = 200 })) {
        var sm_it = self.models_registry.surface_meshes.iterator();
        while (sm_it.next()) |entry| {
            const surface_mesh = entry.value_ptr.*;
            const name = entry.key_ptr.*;
            var selected = if (self.selected_surface_mesh == surface_mesh) true else false;
            if (c.ImGui_SelectableBoolPtr(name.ptr, &selected, 0)) {
                self.selected_surface_mesh = surface_mesh;
            }
        }
        c.ImGui_EndListBox();
    }
    if (self.selected_surface_mesh) |surface_mesh| {
        const nb_vertices = surface_mesh.nbCells(.vertex);
        const nb_edges = surface_mesh.nbCells(.edge);
        const nb_faces = surface_mesh.nbCells(.face);
        c.ImGui_Text("Number of vertices: %d", nb_vertices);
        c.ImGui_Text("Number of edges: %d", nb_edges);
        c.ImGui_Text("Number of faces: %d", nb_faces);
        if (c.ImGui_Button("Clear")) {
            surface_mesh.clearRetainingCapacity();
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }

    c.ImGui_End();
}
