const SurfaceMeshRenderer = @This();

const std = @import("std");
const gl = @import("gl");

const c = @cImport({
    @cInclude("dcimgui.h");
});
const imgui_utils = @import("../utils/imgui.zig");

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
    point_sphere_shader_parameters: PointSphere.Parameters,
    line_bold_shader_parameters: LineBold.Parameters,
    tri_flat_color_per_vertex_shader_parameters: TriFlatColorPerVertex.Parameters,

    draw_vertices: bool = true,
    draw_edges: bool = true,
    draw_faces: bool = true,
    draw_boundaries: bool = false,

    pub fn init() SurfaceMeshRendererParameters {
        return .{
            .point_sphere_shader_parameters = PointSphere.Parameters.init(),
            .line_bold_shader_parameters = LineBold.Parameters.init(),
            .tri_flat_color_per_vertex_shader_parameters = TriFlatColorPerVertex.Parameters.init(),
        };
    }

    pub fn deinit(self: *SurfaceMeshRendererParameters) void {
        self.point_sphere_shader_parameters.deinit();
        self.line_bold_shader_parameters.deinit();
        self.tri_flat_color_per_vertex_shader_parameters.deinit();
    }
};

parameters: std.AutoHashMap(*const SurfaceMesh, SurfaceMeshRendererParameters),

pub fn init(allocator: std.mem.Allocator) !SurfaceMeshRenderer {
    return .{
        .parameters = std.AutoHashMap(*const SurfaceMesh, SurfaceMeshRendererParameters).init(allocator),
    };
}

pub fn deinit(smr: *SurfaceMeshRenderer) void {
    var p_it = smr.parameters.iterator();
    while (p_it.next()) |entry| {
        var p = entry.value_ptr.*;
        p.deinit();
    }
    smr.parameters.deinit();
}

pub fn module(smr: *SurfaceMeshRenderer) Module {
    return Module.init(smr);
}

pub fn name(_: *SurfaceMeshRenderer) []const u8 {
    return "Surface Mesh Renderer";
}

pub fn surfaceMeshAdded(smr: *SurfaceMeshRenderer, surface_mesh: *SurfaceMesh) !void {
    try smr.parameters.put(surface_mesh, SurfaceMeshRendererParameters.init());
}

pub fn surfaceMeshStandardDataChanged(
    smr: *SurfaceMeshRenderer,
    surface_mesh: *SurfaceMesh,
    std_data: SurfaceMeshStandardData,
) !void {
    const p = smr.parameters.getPtr(surface_mesh) orelse return;
    switch (std_data) {
        .vertex_position => |maybe_vertex_position| {
            if (maybe_vertex_position) |vertex_position| {
                const position_vbo: VBO = try zgp.models_registry.getDataVBO(Vec3, vertex_position.data);
                p.tri_flat_color_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.line_bold_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.point_sphere_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            } else {
                p.tri_flat_color_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
                p.line_bold_shader_parameters.unsetVertexAttribArray(.position);
                p.point_sphere_shader_parameters.unsetVertexAttribArray(.position);
            }
        },
        .vertex_color => |maybe_vertex_color| {
            if (maybe_vertex_color) |vertex_color| {
                const color_vbo = try zgp.models_registry.getDataVBO(Vec3, vertex_color.data);
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

pub fn draw(smr: *SurfaceMeshRenderer, view_matrix: Mat4, projection_matrix: Mat4) void {
    var sm_it = zgp.models_registry.surface_meshes.iterator();
    while (sm_it.next()) |entry| {
        const sm = entry.value_ptr.*;
        const info = zgp.models_registry.getSurfaceMeshInfo(sm) orelse continue;
        const p = smr.parameters.getPtr(sm) orelse continue;
        if (p.draw_faces) {
            p.tri_flat_color_per_vertex_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            p.tri_flat_color_per_vertex_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            p.tri_flat_color_per_vertex_shader_parameters.draw(info.triangles_ibo);
        }
        if (p.draw_edges) {
            p.line_bold_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            p.line_bold_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            p.line_bold_shader_parameters.line_color = .{ 0.0, 0.0, 0.0, 1.0 }; // Black for edges
            p.line_bold_shader_parameters.draw(info.lines_ibo);
        }
        if (p.draw_vertices) {
            p.point_sphere_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            p.point_sphere_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            p.point_sphere_shader_parameters.draw(info.points_ibo);
        }
        if (p.draw_boundaries) {
            p.line_bold_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            p.line_bold_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            p.line_bold_shader_parameters.line_color = .{ 1.0, 0.0, 0.0, 1.0 }; // Red for boundaries
            p.line_bold_shader_parameters.draw(info.boundaries_ibo);
        }
    }
}

pub fn uiPanel(smr: *SurfaceMeshRenderer) void {
    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - c.ImGui_GetStyle().*.ItemSpacing.x * 2);

    if (zgp.models_registry.selected_surface_mesh) |sm| {
        const surface_mesh_renderer_parameters = smr.parameters.getPtr(sm);
        if (surface_mesh_renderer_parameters) |p| {
            if (c.ImGui_Checkbox("draw vertices", &p.draw_vertices)) {
                zgp.requestRedraw();
            }
            if (p.draw_vertices) {
                c.ImGui_Text("Point size");
                c.ImGui_PushID("Point size");
                if (c.ImGui_SliderFloatEx("", &p.point_sphere_shader_parameters.point_size, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
                    zgp.requestRedraw();
                }
                c.ImGui_PopID();
            }
            if (c.ImGui_Checkbox("draw edges", &p.draw_edges)) {
                zgp.requestRedraw();
            }
            if (c.ImGui_Checkbox("draw faces", &p.draw_faces)) {
                zgp.requestRedraw();
            }
            if (c.ImGui_Checkbox("draw boundaries", &p.draw_boundaries)) {
                zgp.requestRedraw();
            }
        } else {
            c.ImGui_Text("No parameters found for the selected Surface Mesh");
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }

    c.ImGui_PopItemWidth();
}
