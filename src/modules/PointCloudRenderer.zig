const std = @import("std");
const gl = @import("gl");

const c = @cImport({
    @cInclude("dcimgui.h");
});
const imgui_utils = @import("../utils/imgui.zig");

const Self = @This();
const zgp = @import("../main.zig");

const Module = @import("Module.zig");

const ModelsRegistry = @import("../models/ModelsRegistry.zig");
const PointCloud = ModelsRegistry.PointCloud;
const PointCloudStandardData = ModelsRegistry.PointCloudStandardData;

const PointSphere = @import("../rendering/shaders/point_sphere/PointSphere.zig");
const VBO = @import("../rendering/VBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3 = vec.Vec3;

const mat = @import("../geometry/mat.zig");
const Mat4 = mat.Mat4;

const PointCloudRendererParameters = struct {
    point_sphere_shader_parameters: PointSphere.Parameters,
    draw_points: bool = true,

    pub fn init(point_cloud_renderer: *const Self) PointCloudRendererParameters {
        return .{
            .point_sphere_shader_parameters = point_cloud_renderer.point_sphere_shader.createParameters(),
        };
    }

    pub fn deinit(self: *PointCloudRendererParameters) void {
        self.point_sphere_shader_parameters.deinit();
    }
};

point_sphere_shader: PointSphere,

parameters: std.AutoHashMap(*const PointCloud, PointCloudRendererParameters),

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .point_sphere_shader = try PointSphere.init(),
        .parameters = std.AutoHashMap(*const PointCloud, PointCloudRendererParameters).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.point_sphere_shader.deinit();
    var p_it = self.parameters.iterator();
    while (p_it.next()) |entry| {
        var p = entry.value_ptr.*;
        p.deinit();
    }
    self.parameters.deinit();
}

pub fn module(self: *Self) Module {
    return Module.init(self);
}

pub fn name(_: *Self) []const u8 {
    return "Point Cloud Renderer";
}

pub fn pointCloudAdded(self: *Self, point_cloud: *PointCloud) !void {
    try self.parameters.put(point_cloud, PointCloudRendererParameters.init(self));
}

pub fn pointCloudStandardDataChanged(
    self: *Self,
    point_cloud: *PointCloud,
    std_data: PointCloudStandardData,
) !void {
    const p = self.parameters.getPtr(point_cloud) orelse return;
    const point_cloud_info = zgp.models_registry.getPointCloudInfo(point_cloud) orelse return;
    switch (std_data) {
        .position => {
            if (point_cloud_info.position) |position| {
                const position_vbo = try zgp.models_registry.getDataVBO(Vec3, position.data);
                p.point_sphere_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            } else {
                p.point_sphere_shader_parameters.unsetVertexAttribArray(.position);
            }
            zgp.need_redraw = true;
        },
        .color => {
            if (point_cloud_info.color) |color| {
                const color_vbo = try zgp.models_registry.getDataVBO(Vec3, color.data);
                p.point_sphere_shader_parameters.setVertexAttribArray(.color, color_vbo, 0, 0);
            } else {
                p.point_sphere_shader_parameters.unsetVertexAttribArray(.color);
            }
            zgp.need_redraw = true;
        },
        else => return, // Ignore other standard data changes
    }
}

pub fn draw(self: *Self, view_matrix: Mat4, projection_matrix: Mat4) void {
    var pc_it = zgp.models_registry.point_clouds.iterator();
    while (pc_it.next()) |entry| {
        const pc = entry.value_ptr.*;
        const info = zgp.models_registry.getPointCloudInfo(pc) orelse continue;
        const p = self.parameters.getPtr(pc) orelse continue;
        if (p.draw_points) {
            p.point_sphere_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            p.point_sphere_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            p.point_sphere_shader_parameters.draw(info.points_ibo);
        }
    }
}

pub fn uiPanel(self: *Self) void {
    const UiData = struct {
        var selected_point_cloud: ?*PointCloud = null;
    };

    const UiCB = struct {
        fn onPointCloudSelected(pc: ?*PointCloud) void {
            UiData.selected_point_cloud = pc;
        }
    };

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - c.ImGui_GetStyle().*.ItemSpacing.x * 2);

    c.ImGui_SeparatorText("Point Clouds");
    imgui_utils.pointCloudListBox(UiData.selected_point_cloud, &UiCB.onPointCloudSelected);

    if (UiData.selected_point_cloud) |pc| {
        const surface_mesh_renderer_parameters = self.parameters.getPtr(pc);
        if (surface_mesh_renderer_parameters) |p| {
            if (c.ImGui_Checkbox("draw points", &p.draw_points)) {
                zgp.need_redraw = true;
            }
            if (p.draw_points) {
                if (c.ImGui_SliderFloatEx("point size", &p.point_sphere_shader_parameters.point_size, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
                    zgp.need_redraw = true;
                }
            }
        } else {
            c.ImGui_Text("No parameters found for the selected Surface Mesh");
        }
    } else {
        c.ImGui_Text("No Point Cloud selected");
    }
}
