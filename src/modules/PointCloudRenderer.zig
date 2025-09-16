const PointCloudRenderer = @This();

const std = @import("std");
const gl = @import("gl");

const zgp = @import("../main.zig");
const c = zgp.c;

const imgui_utils = @import("../utils/imgui.zig");

const Module = @import("Module.zig");

const ModelsRegistry = @import("../models/ModelsRegistry.zig");
const PointCloud = ModelsRegistry.PointCloud;
const PointCloudStdData = ModelsRegistry.PointCloudStdData;

const PointSphere = @import("../rendering/shaders/point_sphere/PointSphere.zig");
const VBO = @import("../rendering/VBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3 = vec.Vec3;

const mat = @import("../geometry/mat.zig");
const Mat4 = mat.Mat4;

const PointCloudRendererParameters = struct {
    point_sphere_shader_parameters: PointSphere.Parameters,

    draw_points: bool = true,

    pub fn init() PointCloudRendererParameters {
        return .{
            .point_sphere_shader_parameters = PointSphere.Parameters.init(),
        };
    }

    pub fn deinit(self: *PointCloudRendererParameters) void {
        self.point_sphere_shader_parameters.deinit();
    }
};

parameters: std.AutoHashMap(*const PointCloud, PointCloudRendererParameters),

pub fn init(allocator: std.mem.Allocator) !PointCloudRenderer {
    return .{
        .parameters = std.AutoHashMap(*const PointCloud, PointCloudRendererParameters).init(allocator),
    };
}

pub fn deinit(pcr: *PointCloudRenderer) void {
    var p_it = pcr.parameters.iterator();
    while (p_it.next()) |entry| {
        var p = entry.value_ptr.*;
        p.deinit();
    }
    pcr.parameters.deinit();
}

/// Return a Module interface for the PointCloudRenderer.
pub fn module(pcr: *PointCloudRenderer) Module {
    return Module.init(pcr);
}

/// Part of the Module interface.
/// Return the name of the module.
pub fn name(_: *PointCloudRenderer) []const u8 {
    return "Point Cloud Renderer";
}

/// Part of the Module interface.
/// Create and store a PointCloudRendererParameters for the new PointCloud.
pub fn pointCloudAdded(pcr: *PointCloudRenderer, point_cloud: *PointCloud) void {
    pcr.parameters.put(point_cloud, PointCloudRendererParameters.init()) catch {
        std.debug.print("Failed to create PointCloudRendererParameters for new PointCloud\n", .{});
        return;
    };
}

/// Part of the Module interface.
/// Update the PointCloudRendererParameters when a standard data of the PointCloud changes.
pub fn pointCloudStdDataChanged(
    pcr: *PointCloudRenderer,
    point_cloud: *PointCloud,
    std_data: PointCloudStdData,
) void {
    const p = pcr.parameters.getPtr(point_cloud) orelse return;
    switch (std_data) {
        .position => |maybe_position| {
            if (maybe_position) |position| {
                const position_vbo = zgp.models_registry.dataVBO(Vec3, position.data) catch {
                    std.debug.print("Failed to get VBO for vertex positions\n", .{});
                    return;
                };
                p.point_sphere_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            } else {
                p.point_sphere_shader_parameters.unsetVertexAttribArray(.position);
            }
        },
        .color => |maybe_color| {
            if (maybe_color) |color| {
                const color_vbo = zgp.models_registry.dataVBO(Vec3, color.data) catch {
                    std.debug.print("Failed to get VBO for vertex colors\n", .{});
                    return;
                };
                p.point_sphere_shader_parameters.setVertexAttribArray(.color, color_vbo, 0, 0);
            } else {
                p.point_sphere_shader_parameters.unsetVertexAttribArray(.color);
            }
        },
        else => return, // Ignore other standard data changes
    }
}

/// Part of the Module interface.
/// Render all PointClouds with their PointCloudRendererParameters and the given view and projection matrices.
pub fn draw(pcr: *PointCloudRenderer, view_matrix: Mat4, projection_matrix: Mat4) void {
    var pc_it = zgp.models_registry.point_clouds.iterator();
    while (pc_it.next()) |entry| {
        const pc = entry.value_ptr.*;
        const info = zgp.models_registry.pointCloudInfo(pc);
        const p = pcr.parameters.getPtr(pc) orelse continue;
        if (p.draw_points) {
            p.point_sphere_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            p.point_sphere_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            p.point_sphere_shader_parameters.draw(info.points_ibo);
        }
    }
}

/// Part of the Module interface.
/// Show a UI panel to control the PointCloudRendererParameters of the selected PointCloud.
pub fn uiPanel(pcr: *PointCloudRenderer) void {
    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - c.ImGui_GetStyle().*.ItemSpacing.x * 2);

    if (zgp.models_registry.selected_point_cloud) |pc| {
        const surface_mesh_renderer_parameters = pcr.parameters.getPtr(pc);
        if (surface_mesh_renderer_parameters) |p| {
            if (c.ImGui_Checkbox("draw points", &p.draw_points)) {
                zgp.requestRedraw();
            }
            if (p.draw_points) {
                if (c.ImGui_SliderFloatEx("point size", &p.point_sphere_shader_parameters.point_size, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
                    zgp.requestRedraw();
                }
            }
        } else {
            c.ImGui_Text("No parameters found for the selected Surface Mesh");
        }
    } else {
        c.ImGui_Text("No Point Cloud selected");
    }
}
