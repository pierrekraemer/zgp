const VectorPerVertexRenderer = @This();

const std = @import("std");
const gl = @import("gl");

const zgp = @import("../main.zig");
const c = zgp.c;

const imgui_utils = @import("../utils/imgui.zig");
const imgui_log = std.log.scoped(.imgui);

const Module = @import("Module.zig");

const ModelsRegistry = @import("../models/ModelsRegistry.zig");
const SurfaceMesh = ModelsRegistry.SurfaceMesh;
const SurfaceMeshStdData = ModelsRegistry.SurfaceMeshStdData;

const PointVector = @import("../rendering/shaders/point_vector/PointVector.zig");
const VBO = @import("../rendering/VBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3 = vec.Vec3;

const mat = @import("../geometry/mat.zig");
const Mat4 = mat.Mat4;

const VectorPerVertexRendererParameters = struct {
    point_vector_shader_parameters: PointVector.Parameters,
    vector_data: ?SurfaceMesh.CellData(.vertex, Vec3) = null,

    pub fn init() VectorPerVertexRendererParameters {
        return .{
            .point_vector_shader_parameters = PointVector.Parameters.init(),
        };
    }

    pub fn deinit(self: *VectorPerVertexRendererParameters) void {
        self.point_vector_shader_parameters.deinit();
    }
};

parameters: std.AutoHashMap(*const SurfaceMesh, VectorPerVertexRendererParameters),

pub fn init(allocator: std.mem.Allocator) !VectorPerVertexRenderer {
    return .{
        .parameters = std.AutoHashMap(*const SurfaceMesh, VectorPerVertexRendererParameters).init(allocator),
    };
}

pub fn deinit(vpvr: *VectorPerVertexRenderer) void {
    var p_it = vpvr.parameters.iterator();
    while (p_it.next()) |entry| {
        var p = entry.value_ptr.*;
        p.deinit();
    }
    vpvr.parameters.deinit();
}

/// Return a Module interface for the VectorPerVertexRenderer.
pub fn module(vpvr: *VectorPerVertexRenderer) Module {
    return Module.init(vpvr);
}

/// Part of the Module interface.
/// Return the name of the module.
pub fn name(_: *VectorPerVertexRenderer) []const u8 {
    return "Vector Per Vertex Renderer";
}

/// Part of the Module interface.
/// Create and store a VectorPerVertexRendererParameters for the new SurfaceMesh.
pub fn surfaceMeshAdded(vpvr: *VectorPerVertexRenderer, surface_mesh: *SurfaceMesh) void {
    vpvr.parameters.put(surface_mesh, VectorPerVertexRendererParameters.init()) catch {
        std.debug.print("Failed to create VectorPerVertexRendererParameters for new SurfaceMesh\n", .{});
    };
}

/// Part of the Module interface.
/// Update the VectorPerVertexRendererParameters when a standard data of the SurfaceMesh changes.
pub fn surfaceMeshStdDataChanged(
    vpvr: *VectorPerVertexRenderer,
    surface_mesh: *SurfaceMesh,
    std_data: SurfaceMeshStdData,
) void {
    const p = vpvr.parameters.getPtr(surface_mesh) orelse return;
    switch (std_data) {
        .vertex_position => |maybe_vertex_position| {
            if (maybe_vertex_position) |vertex_position| {
                const position_vbo = zgp.models_registry.dataVBO(Vec3, vertex_position.data) catch {
                    std.debug.print("Failed to get VBO for vertex positions\n", .{});
                    return;
                };
                p.point_vector_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            } else {
                p.point_vector_shader_parameters.unsetVertexAttribArray(.position);
            }
        },
        else => return, // Ignore other standard data changes
    }
}

fn setSurfaceMeshVectorData(vpvr: *VectorPerVertexRenderer, surface_mesh: *SurfaceMesh, vector: ?SurfaceMesh.CellData(.vertex, Vec3)) !void {
    const p = vpvr.parameters.getPtr(surface_mesh) orelse return;
    p.vector_data = vector;
    if (p.vector_data) |v| {
        const vector_vbo = try zgp.models_registry.dataVBO(Vec3, v.data);
        p.point_vector_shader_parameters.setVertexAttribArray(.vector, vector_vbo, 0, 0);
    } else {
        p.point_vector_shader_parameters.unsetVertexAttribArray(.vector);
    }
    zgp.requestRedraw();
}

/// Part of the Module interface.
/// Render all SurfaceMeshes with their VectorPerVertexRendererParameters and the given view and projection matrices.
pub fn draw(vpvr: *VectorPerVertexRenderer, view_matrix: Mat4, projection_matrix: Mat4) void {
    var sm_it = zgp.models_registry.surface_meshes.iterator();
    while (sm_it.next()) |entry| {
        const surface_mesh = entry.value_ptr.*;
        const surface_mesh_info = zgp.models_registry.surfaceMeshInfo(surface_mesh);
        const vector_per_vertex_renderer_parameters = vpvr.parameters.getPtr(surface_mesh) orelse continue;
        vector_per_vertex_renderer_parameters.point_vector_shader_parameters.model_view_matrix = @bitCast(view_matrix);
        vector_per_vertex_renderer_parameters.point_vector_shader_parameters.projection_matrix = @bitCast(projection_matrix);
        vector_per_vertex_renderer_parameters.point_vector_shader_parameters.draw(surface_mesh_info.points_ibo);
    }
}

/// Part of the Module interface.
/// Show a UI panel to control the VectorPerVertexRendererParameters of the selected SurfaceMesh.
pub fn uiPanel(vpvr: *VectorPerVertexRenderer) void {
    const UiCB = struct {
        const DataSelectedContext = struct {
            vector_per_vertex_renderer: *VectorPerVertexRenderer,
            surface_mesh: *SurfaceMesh,
        };
        fn onVectorDataSelected(comptime cell_type: SurfaceMesh.CellType, comptime T: type, data: ?SurfaceMesh.CellData(cell_type, T), ctx: DataSelectedContext) void {
            ctx.vector_per_vertex_renderer.setSurfaceMeshVectorData(ctx.surface_mesh, data) catch |err| {
                imgui_log.err("Error setting vector data: {}", .{err});
            };
        }
    };

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - c.ImGui_GetStyle().*.ItemSpacing.x * 2);

    if (zgp.models_registry.selected_surface_mesh) |sm| {
        const vector_per_vertex_renderer_parameters = vpvr.parameters.getPtr(sm);
        if (vector_per_vertex_renderer_parameters) |p| {
            c.ImGui_Text("Vector");
            c.ImGui_PushID("Vector");
            imgui_utils.surfaceMeshCellDataComboBox(
                sm,
                .vertex,
                Vec3,
                p.vector_data,
                UiCB.DataSelectedContext{ .vector_per_vertex_renderer = vpvr, .surface_mesh = sm },
                &UiCB.onVectorDataSelected,
            );
            c.ImGui_PopID();
            c.ImGui_Text("scale");
            c.ImGui_PushID("scale");
            if (c.ImGui_SliderFloatEx("", &p.point_vector_shader_parameters.vector_scale, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
                zgp.requestRedraw();
            }
            c.ImGui_PopID();
            c.ImGui_Text("color");
            c.ImGui_PushID("color");
            if (c.ImGui_ColorEdit3("", &p.point_vector_shader_parameters.vector_color, c.ImGuiColorEditFlags_NoInputs)) {
                zgp.requestRedraw();
            }
            c.ImGui_PopID();
        } else {
            c.ImGui_Text("No parameters found for the selected Surface Mesh");
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }

    c.ImGui_PopItemWidth();
}
