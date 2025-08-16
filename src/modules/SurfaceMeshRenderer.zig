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
const SurfaceMesh = ModelsRegistry.SurfaceMesh;
const SurfaceMeshStandardData = ModelsRegistry.SurfaceMeshStandardData;

const TriFlatColorPerVertex = @import("../rendering/shaders/tri_flat_color_per_vertex/TriFlatColorPerVertex.zig");
const LineBold = @import("../rendering/shaders/line_bold/LineBold.zig");
const PointSphere = @import("../rendering/shaders/point_sphere/PointSphere.zig");
const VBO = @import("../rendering/VBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3 = vec.Vec3;

const mat = @import("../geometry/mat.zig");
const Mat4 = mat.Mat4;

const SurfaceMeshRendererParameters = struct {
    tri_flat_color_per_vertex_shader_parameters: TriFlatColorPerVertex.Parameters,
    line_bold_shader_parameters: LineBold.Parameters,
    point_sphere_shader_parameters: PointSphere.Parameters,

    draw_vertices: bool = true,
    draw_edges: bool = true,
    draw_faces: bool = true,

    pub fn init(surface_mesh_renderer: *const Self) SurfaceMeshRendererParameters {
        return .{
            .tri_flat_color_per_vertex_shader_parameters = surface_mesh_renderer.tri_flat_color_per_vertex_shader.createParameters(),
            .line_bold_shader_parameters = surface_mesh_renderer.line_bold_shader.createParameters(),
            .point_sphere_shader_parameters = surface_mesh_renderer.point_sphere_shader.createParameters(),
        };
    }

    pub fn deinit(self: *SurfaceMeshRendererParameters) void {
        self.tri_flat_color_per_vertex_shader_parameters.deinit();
        self.line_bold_shader_parameters.deinit();
        self.point_sphere_shader_parameters.deinit();
    }
};

tri_flat_color_per_vertex_shader: TriFlatColorPerVertex,
line_bold_shader: LineBold,
point_sphere_shader: PointSphere,

parameters: std.AutoHashMap(*const SurfaceMesh, SurfaceMeshRendererParameters),

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .tri_flat_color_per_vertex_shader = try TriFlatColorPerVertex.init(),
        .line_bold_shader = try LineBold.init(),
        .point_sphere_shader = try PointSphere.init(),
        .parameters = std.AutoHashMap(*const SurfaceMesh, SurfaceMeshRendererParameters).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.tri_flat_color_per_vertex_shader.deinit();
    self.line_bold_shader.deinit();
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
    return "Surface Mesh Renderer";
}

pub fn surfaceMeshAdded(self: *Self, surface_mesh: *SurfaceMesh) !void {
    try self.parameters.put(surface_mesh, SurfaceMeshRendererParameters.init(self));
}

pub fn surfaceMeshStandardDataChanged(
    self: *Self,
    surface_mesh: *SurfaceMesh,
    std_data: SurfaceMeshStandardData,
) !void {
    const p = self.parameters.getPtr(surface_mesh) orelse return;
    const surface_mesh_info = zgp.models_registry.getSurfaceMeshInfo(surface_mesh) orelse return;
    switch (std_data) {
        .vertex_position => {
            if (surface_mesh_info.vertex_position) |vertex_position| {
                const position_vbo: VBO = try zgp.models_registry.getDataVBO(Vec3, vertex_position);
                p.tri_flat_color_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.line_bold_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.point_sphere_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            } else {
                p.tri_flat_color_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
                p.line_bold_shader_parameters.unsetVertexAttribArray(.position);
                p.point_sphere_shader_parameters.unsetVertexAttribArray(.position);
            }
        },
        .vertex_color => {
            if (surface_mesh_info.vertex_color) |vertex_color| {
                const color_vbo = try zgp.models_registry.getDataVBO(Vec3, vertex_color);
                p.tri_flat_color_per_vertex_shader_parameters.setVertexAttribArray(.color, color_vbo, 0, 0);
                p.point_sphere_shader_parameters.setVertexAttribArray(.color, color_vbo, 0, 0);
            } else {
                p.tri_flat_color_per_vertex_shader_parameters.unsetVertexAttribArray(.color);
                p.point_sphere_shader_parameters.unsetVertexAttribArray(.color);
            }
        },
        else => return, // Ignore other standard data changes
    }
}

pub fn draw(self: *Self, view_matrix: Mat4, projection_matrix: Mat4) void {
    var sm_it = zgp.models_registry.surface_meshes.iterator();
    while (sm_it.next()) |entry| {
        const sm = entry.value_ptr.*;
        const info = zgp.models_registry.getSurfaceMeshInfo(sm) orelse continue;
        const p = self.parameters.getPtr(sm) orelse continue;
        if (p.draw_faces) {
            p.tri_flat_color_per_vertex_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            p.tri_flat_color_per_vertex_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            p.tri_flat_color_per_vertex_shader_parameters.useShader();
            defer gl.UseProgram(0);
            p.tri_flat_color_per_vertex_shader_parameters.drawElements(info.triangles_ibo);
        }
        if (p.draw_edges) {
            p.line_bold_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            p.line_bold_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            p.line_bold_shader_parameters.useShader();
            defer gl.UseProgram(0);
            p.line_bold_shader_parameters.drawElements(info.lines_ibo);
        }
        if (p.draw_vertices) {
            p.point_sphere_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            p.point_sphere_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            p.point_sphere_shader_parameters.useShader();
            defer gl.UseProgram(0);
            p.point_sphere_shader_parameters.drawElements(info.points_ibo);
        }
    }
}

pub fn uiPanel(self: *Self) void {
    const UiData = struct {
        var selected_surface_mesh: ?*SurfaceMesh = null;
    };

    const UiCB = struct {
        fn onSurfaceMeshSelected(sm: ?*SurfaceMesh) void {
            UiData.selected_surface_mesh = sm;
        }
    };

    // _ = c.ImGui_Begin("Surface Mesh Renderer", null, 0);
    // defer c.ImGui_End();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - c.ImGui_GetStyle().*.ItemSpacing.x * 2);

    c.ImGui_SeparatorText("Surface Meshes");
    imgui_utils.surfaceMeshListBox(UiData.selected_surface_mesh, &UiCB.onSurfaceMeshSelected);

    if (UiData.selected_surface_mesh) |sm| {
        const surface_mesh_renderer_parameters = self.parameters.getPtr(sm);
        if (surface_mesh_renderer_parameters) |p| {
            _ = c.ImGui_Checkbox("draw vertices", &p.draw_vertices);
            if (p.draw_vertices) {
                _ = c.ImGui_SliderFloatEx("point size", &p.point_sphere_shader_parameters.point_size, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic);
            }
            _ = c.ImGui_Checkbox("draw edges", &p.draw_edges);
            _ = c.ImGui_Checkbox("draw faces", &p.draw_faces);
        } else {
            c.ImGui_Text("No parameters found for the selected Surface Mesh");
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }

    c.ImGui_PopItemWidth();
}
