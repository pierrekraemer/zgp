const std = @import("std");
const zm = @import("zmath");
const gl = @import("gl");

const c = @cImport({
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_sdl3.h");
    @cInclude("backends/dcimgui_impl_opengl3.h");
});

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

const SurfaceMeshRenderParameters = struct {
    tri_flat_color_per_vertex_shader_parameters: TriFlatColorPerVertex.Parameters,
    line_bold_shader_parameters: LineBold.Parameters,
    point_sphere_shader_parameters: PointSphere.Parameters,

    draw_vertices: bool = true,
    draw_edges: bool = true,
    draw_faces: bool = true,

    pub fn init(surface_mesh_renderer: *const Self) SurfaceMeshRenderParameters {
        return .{
            .tri_flat_color_per_vertex_shader_parameters = surface_mesh_renderer.tri_flat_color_per_vertex_shader.createParameters(),
            .line_bold_shader_parameters = surface_mesh_renderer.line_bold_shader.createParameters(),
            .point_sphere_shader_parameters = surface_mesh_renderer.point_sphere_shader.createParameters(),
        };
    }

    pub fn deinit(self: *SurfaceMeshRenderParameters) void {
        self.tri_flat_color_per_vertex_shader_parameters.deinit();
        self.line_bold_shader_parameters.deinit();
        self.point_sphere_shader_parameters.deinit();
    }
};

tri_flat_color_per_vertex_shader: TriFlatColorPerVertex,
line_bold_shader: LineBold,
point_sphere_shader: PointSphere,

parameters: std.AutoHashMap(*const SurfaceMesh, SurfaceMeshRenderParameters),

pub fn init(allocator: std.mem.Allocator) !Self {
    const s: Self = .{
        .tri_flat_color_per_vertex_shader = try TriFlatColorPerVertex.init(),
        .line_bold_shader = try LineBold.init(),
        .point_sphere_shader = try PointSphere.init(),
        .parameters = std.AutoHashMap(*const SurfaceMesh, SurfaceMeshRenderParameters).init(allocator),
    };
    return s;
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

pub fn surfaceMeshAdded(self: *Self, surface_mesh: *SurfaceMesh) !void {
    try self.parameters.put(surface_mesh, SurfaceMeshRenderParameters.init(self));
}

pub fn surfaceMeshStandardDataChanged(
    self: *Self,
    surface_mesh: *SurfaceMesh,
    data: SurfaceMeshStandardData,
) void {
    const p = self.parameters.getPtr(surface_mesh) orelse return;
    const surface_mesh_info = zgp.models_registry.surface_meshes_info.getPtr(surface_mesh) orelse return;
    switch (data) {
        .vertex_position => {
            const vertex_position = surface_mesh_info.vertex_position orelse return;
            const position_vbo = zgp.models_registry.vbo_registry.get(&vertex_position.gen).?;
            p.tri_flat_color_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            p.line_bold_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            p.point_sphere_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
        },
        .vertex_color => {
            const vertex_color = surface_mesh_info.vertex_color orelse return;
            const color_vbo = zgp.models_registry.vbo_registry.get(&vertex_color.gen).?;
            p.tri_flat_color_per_vertex_shader_parameters.setVertexAttribArray(.color, color_vbo, 0, 0);
            p.point_sphere_shader_parameters.setVertexAttribArray(.color, color_vbo, 0, 0);
        },
        else => return, // Ignore other data changes
    }
}

pub fn draw(self: *Self, view_matrix: zm.Mat, projection_matrix: zm.Mat) void {
    var sm_it = zgp.models_registry.surface_meshes.iterator();
    while (sm_it.next()) |entry| {
        const surface_mesh = entry.value_ptr.*;
        const surface_mesh_info = zgp.models_registry.surface_meshes_info.getPtr(surface_mesh);
        if (surface_mesh_info) |info| {
            const surface_mesh_render_parameters = self.parameters.getPtr(surface_mesh);
            if (surface_mesh_render_parameters) |p| {
                if (p.draw_faces) {
                    zm.storeMat(&p.tri_flat_color_per_vertex_shader_parameters.model_view_matrix, view_matrix);
                    zm.storeMat(&p.tri_flat_color_per_vertex_shader_parameters.projection_matrix, projection_matrix);
                    p.tri_flat_color_per_vertex_shader_parameters.ambiant_color = .{ 0.1, 0.1, 0.1, 1 };
                    p.tri_flat_color_per_vertex_shader_parameters.light_position = .{ 10, 0, 100 };

                    p.tri_flat_color_per_vertex_shader_parameters.useShader();
                    defer gl.UseProgram(0);
                    p.tri_flat_color_per_vertex_shader_parameters.drawElements(gl.TRIANGLES, info.triangles_ibo);
                }
                if (p.draw_edges) {
                    zm.storeMat(&p.line_bold_shader_parameters.model_view_matrix, view_matrix);
                    zm.storeMat(&p.line_bold_shader_parameters.projection_matrix, projection_matrix);
                    p.line_bold_shader_parameters.line_color = .{ 0.0, 0.0, 0.1, 1 };
                    p.line_bold_shader_parameters.line_width = 1.0;

                    p.line_bold_shader_parameters.useShader();
                    defer gl.UseProgram(0);
                    p.line_bold_shader_parameters.drawElements(gl.LINES, info.lines_ibo);
                }
                if (p.draw_vertices) {
                    zm.storeMat(&p.point_sphere_shader_parameters.model_view_matrix, view_matrix);
                    zm.storeMat(&p.point_sphere_shader_parameters.projection_matrix, projection_matrix);
                    p.point_sphere_shader_parameters.ambiant_color = .{ 0.1, 0.1, 0.1, 1 };
                    p.point_sphere_shader_parameters.light_position = .{ -100, 0, 100 };
                    p.point_sphere_shader_parameters.point_size = 0.001;

                    p.point_sphere_shader_parameters.useShader();
                    defer gl.UseProgram(0);
                    p.point_sphere_shader_parameters.drawElements(gl.POINTS, info.points_ibo);
                }
            }
        }
    }
}

pub fn uiPanel(self: *Self) void {
    const UiData = struct {
        var selected_surface_mesh: ?*SurfaceMesh = null;
    };

    _ = c.ImGui_Begin("Surface Mesh Renderer", null, 0);
    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - c.ImGui_GetStyle().*.ItemSpacing.x * 2);

    c.ImGui_SeparatorText("Surface Meshes");
    if (c.ImGui_BeginListBox("##Surface Meshes", c.ImVec2{ .x = 0, .y = 0 })) {
        var sm_it = zgp.models_registry.surface_meshes.iterator();
        while (sm_it.next()) |entry| {
            const surface_mesh = entry.value_ptr.*;
            const name = entry.key_ptr.*;
            const selected = if (UiData.selected_surface_mesh == surface_mesh) true else false;
            if (c.ImGui_SelectableEx(name.ptr, selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                UiData.selected_surface_mesh = surface_mesh;
            }
        }
        c.ImGui_EndListBox();
    }

    if (UiData.selected_surface_mesh) |surface_mesh| {
        const surface_mesh_render_parameters = self.parameters.getPtr(surface_mesh);
        if (surface_mesh_render_parameters) |p| {
            _ = c.ImGui_Checkbox("draw vertices", &p.draw_vertices);
            _ = c.ImGui_Checkbox("draw edges", &p.draw_edges);
            _ = c.ImGui_Checkbox("draw faces", &p.draw_faces);
        } else {
            c.ImGui_Text("No parameters found for the selected Surface Mesh");
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }

    c.ImGui_PopItemWidth();
    c.ImGui_End();
}
