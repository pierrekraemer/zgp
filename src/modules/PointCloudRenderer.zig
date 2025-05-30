const ModelsRegistry = @import("../models/ModelsRegistry.zig");
const PointCloud = ModelsRegistry.PointCloud;

const Self = @This();

const c = @cImport({
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_sdl3.h");
    @cInclude("backends/dcimgui_impl_opengl3.h");
});

models_registry: *ModelsRegistry,
selected_point_cloud: ?*PointCloud = null,

pub fn ui_panel(self: *Self) void {
    _ = c.ImGui_Begin("Point Cloud Renderer", null, c.ImGuiWindowFlags_NoSavedSettings);

    if (c.ImGui_BeginListBox("Point Cloud", c.ImVec2{ .x = 0, .y = 200 })) {
        var pc_it = self.models_registry.point_clouds.iterator();
        while (pc_it.next()) |entry| {
            const point_cloud = entry.value_ptr.*;
            const name = entry.key_ptr.*;
            var selected = if (self.selected_point_cloud == point_cloud) true else false;
            if (c.ImGui_SelectableBoolPtr(name.ptr, &selected, 0)) {
                self.selected_point_cloud = point_cloud;
            }
        }
        c.ImGui_EndListBox();
    }
    if (self.selected_point_cloud) |point_cloud| {
        const nb_points = point_cloud.nbPoints();
        c.ImGui_Text("Number of points: %d", nb_points);
        if (c.ImGui_Button("Clear")) {
            point_cloud.clearRetainingCapacity();
        }
    } else {
        c.ImGui_Text("No Point Cloud selected");
    }

    c.ImGui_End();
}
