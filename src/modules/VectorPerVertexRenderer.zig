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

const PointVector = @import("../rendering/shaders/point_vector/PointVector.zig");
const VBO = @import("../rendering/VBO.zig");

const Data = @import("../utils/Data.zig").Data;

const vec = @import("../geometry/vec.zig");
const Vec3 = vec.Vec3;

const mat = @import("../geometry/mat.zig");
const Mat4 = mat.Mat4;

const VectorPerVertexRendererParameters = struct {
    point_vector_shader_parameters: PointVector.Parameters,
    vector_data: ?*Data(Vec3) = null,

    pub fn init(vector_per_vertex_renderer: *const Self) VectorPerVertexRendererParameters {
        return .{
            .point_vector_shader_parameters = vector_per_vertex_renderer.vector_per_vertex_shader.createParameters(),
        };
    }

    pub fn deinit(self: *VectorPerVertexRendererParameters) void {
        self.point_vector_shader_parameters.deinit();
    }
};

vector_per_vertex_shader: PointVector,

parameters: std.AutoHashMap(*const SurfaceMesh, VectorPerVertexRendererParameters),

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .vector_per_vertex_shader = try PointVector.init(),
        .parameters = std.AutoHashMap(*const SurfaceMesh, VectorPerVertexRendererParameters).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.vector_per_vertex_shader.deinit();
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
    return "Vector Per Vertex Renderer";
}

pub fn surfaceMeshAdded(self: *Self, surface_mesh: *SurfaceMesh) !void {
    try self.parameters.put(surface_mesh, VectorPerVertexRendererParameters.init(self));
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
            const vertex_position = surface_mesh_info.vertex_position orelse return;
            const position_vbo = try zgp.models_registry.getDataVBO(Vec3, vertex_position);
            p.point_vector_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
        },
        else => return, // Ignore other data changes
    }
}

fn setSurfaceMeshVectorData(self: *Self, surface_mesh: *SurfaceMesh, vector: ?*Data(Vec3)) !void {
    const p = self.parameters.getPtr(surface_mesh) orelse return;
    p.vector_data = vector;
    if (p.vector_data) |v| {
        const vector_vbo = try zgp.models_registry.getDataVBO(Vec3, v);
        p.point_vector_shader_parameters.setVertexAttribArray(.vector, vector_vbo, 0, 0);
    }
}

pub fn draw(self: *Self, view_matrix: Mat4, projection_matrix: Mat4) void {
    var sm_it = zgp.models_registry.surface_meshes.iterator();
    while (sm_it.next()) |entry| {
        const surface_mesh = entry.value_ptr.*;
        const surface_mesh_info = zgp.models_registry.getSurfaceMeshInfo(surface_mesh) orelse continue;
        const vector_per_vertex_renderer_parameters = self.parameters.getPtr(surface_mesh) orelse continue;
        vector_per_vertex_renderer_parameters.point_vector_shader_parameters.model_view_matrix = @bitCast(view_matrix);
        vector_per_vertex_renderer_parameters.point_vector_shader_parameters.projection_matrix = @bitCast(projection_matrix);
        vector_per_vertex_renderer_parameters.point_vector_shader_parameters.useShader();
        defer gl.UseProgram(0);
        vector_per_vertex_renderer_parameters.point_vector_shader_parameters.drawElements(surface_mesh_info.points_ibo);
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
        const DataSelectedContext = struct {
            vector_per_vertex_renderer: *Self,
            surface_mesh: *SurfaceMesh,
        };
        fn onVectorDataSelected(comptime T: type, data: ?*Data(T), ctx: DataSelectedContext) void {
            ctx.vector_per_vertex_renderer.setSurfaceMeshVectorData(ctx.surface_mesh, data) catch |err| {
                zgp.imgui_log.err("Error setting vector data: {}", .{err});
            };
        }
    };

    // _ = c.ImGui_Begin("Vector Per Vertex Renderer", null, 0);
    // defer c.ImGui_End();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - c.ImGui_GetStyle().*.ItemSpacing.x * 2);

    c.ImGui_SeparatorText("Surface Meshes");
    imgui_utils.surfaceMeshListBox(UiData.selected_surface_mesh, &UiCB.onSurfaceMeshSelected);

    if (UiData.selected_surface_mesh) |sm| {
        const vector_per_vertex_renderer_parameters = self.parameters.getPtr(sm);
        if (vector_per_vertex_renderer_parameters) |p| {
            c.ImGui_Text("Vector");
            c.ImGui_PushID("Vector");
            imgui_utils.surfaceMeshCellDataComboBox(sm, .vertex, Vec3, p.vector_data, UiCB.DataSelectedContext{ .vector_per_vertex_renderer = self, .surface_mesh = sm }, &UiCB.onVectorDataSelected);
            c.ImGui_PopID();
            _ = c.ImGui_SliderFloatEx("scale", &p.point_vector_shader_parameters.vector_scale, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic);
            _ = c.ImGui_ColorEdit3("color", &p.point_vector_shader_parameters.vector_color, c.ImGuiColorEditFlags_NoInputs);
        } else {
            c.ImGui_Text("No parameters found for the selected Surface Mesh");
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }

    c.ImGui_PopItemWidth();
}
