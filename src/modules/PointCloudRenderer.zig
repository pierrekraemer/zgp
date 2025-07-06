const std = @import("std");
const zm = @import("zmath");
const gl = @import("gl");

const c = @cImport({
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_sdl3.h");
    @cInclude("backends/dcimgui_impl_opengl3.h");
});

const ModelsRegistry = @import("../models/ModelsRegistry.zig");
const PointCloud = ModelsRegistry.PointCloud;

const PointSphere = @import("../rendering/shaders/point_sphere/PointSphere.zig");

const Self = @This();

const PointCloudRenderParameters = struct {
    point_sphere_shader_parameters: PointSphere.Parameters,
    draw_points: bool = true,
};

models_registry: *ModelsRegistry,

point_sphere_shader: PointSphere,

parameters: std.AutoHashMap(*PointCloud, PointCloudRenderParameters),

pub fn init(models_registry: *ModelsRegistry, allocator: std.mem.Allocator) !Self {
    var s: Self = .{
        .models_registry = models_registry,
        .point_sphere_shader = try PointSphere.init(),
        .parameters = std.AutoHashMap(*PointCloud, PointCloudRenderParameters).init(allocator),
    };

    var pc_it = models_registry.point_clouds.iterator();
    while (pc_it.next()) |entry| {
        const point_cloud = entry.value_ptr.*;
        try s.parameters.put(point_cloud, .{
            .point_sphere_shader_parameters = s.point_sphere_shader.createParameters(),
        });
    }

    return s;
}

pub fn deinit(self: *Self) void {
    self.point_sphere_shader.deinit();
    self.parameters.deinit();
}

pub fn draw(self: *Self, view_matrix: zm.Mat, projection_matrix: zm.Mat) void {
    var pc_it = self.models_registry.point_clouds.iterator();
    while (pc_it.next()) |entry| {
        const point_cloud = entry.value_ptr.*;
        const parameters = self.parameters.get(point_cloud);
        if (parameters) |p| {
            if (p.draw_points) {
                zm.storeMat(&p.point_sphere_shader_parameters.model_view_matrix, view_matrix);
                zm.storeMat(&p.point_sphere_shader_parameters.projection_matrix, projection_matrix);
                p.point_sphere_shader_parameters.ambiant_color = .{ 0.1, 0.1, 0.1, 1 };
                p.point_sphere_shader_parameters.light_position = .{ -100, 0, 100 };
                p.point_sphere_shader_parameters.point_size = 0.001;

                p.point_sphere_shader_parameters.useShader();
                defer gl.UseProgram(0);
                p.point_sphere_shader_parameters.drawElements(gl.POINTS, sm_points_ibo);
            }
        }
    }
}

pub fn uiPanel(self: *Self) void {
    const ui_data = struct {
        var selected_point_cloud: ?*PointCloud = null;
    };

    _ = c.ImGui_Begin("Point Cloud Renderer", null, c.ImGuiWindowFlags_NoSavedSettings);

    if (c.ImGui_BeginListBox("Point Cloud", c.ImVec2{ .x = 0, .y = 200 })) {
        var pc_it = self.models_registry.point_clouds.iterator();
        while (pc_it.next()) |entry| {
            const point_cloud = entry.value_ptr.*;
            const name = entry.key_ptr.*;
            var selected = if (ui_data.selected_point_cloud == point_cloud) true else false;
            if (c.ImGui_SelectableBoolPtr(name.ptr, &selected, 0)) {
                ui_data.selected_point_cloud = point_cloud;
            }
        }
        c.ImGui_EndListBox();
    }
    if (ui_data.selected_point_cloud) |point_cloud| {
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
