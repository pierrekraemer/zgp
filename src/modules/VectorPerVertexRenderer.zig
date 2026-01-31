const VectorPerVertexRenderer = @This();

const std = @import("std");
const gl = @import("gl");

const zgp = @import("../main.zig");
const c = zgp.c;

const imgui_utils = @import("../utils/imgui.zig");
const imgui_log = std.log.scoped(.imgui);

// TODO: this module should also work with PointClouds

const Module = @import("Module.zig");
const SurfaceMeshStore = @import("../models/SurfaceMeshStore.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfaceMeshStdData = @import("../models/surface/SurfaceMeshStdDatas.zig").SurfaceMeshStdData;

const PointVector = @import("../rendering/shaders/point_vector/PointVector.zig");
const VBO = @import("../rendering/VBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;

const VectorPerVertexRendererParameters = struct {
    point_vector_shader_parameters: PointVector.Parameters,

    vertex_vector: ?SurfaceMesh.CellData(.vertex, Vec3f) = null,

    pub fn init() VectorPerVertexRendererParameters {
        return .{
            .point_vector_shader_parameters = PointVector.Parameters.init(),
        };
    }

    pub fn deinit(self: *VectorPerVertexRendererParameters) void {
        self.point_vector_shader_parameters.deinit();
    }
};

module: Module = .{
    .name = "Vector Per Vertex Renderer",
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .surfaceMeshStdDataChanged = surfaceMeshStdDataChanged,
        .draw = draw,
        .uiPanel = uiPanel,
    },
},
parameters: std.AutoHashMap(*SurfaceMesh, VectorPerVertexRendererParameters),

pub fn init(allocator: std.mem.Allocator) VectorPerVertexRenderer {
    return .{
        .parameters = .init(allocator),
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

/// Part of the Module interface.
/// Create and store a VectorPerVertexRendererParameters for the new SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const vpvr: *VectorPerVertexRenderer = @alignCast(@fieldParentPtr("module", m));
    vpvr.parameters.put(surface_mesh, VectorPerVertexRendererParameters.init()) catch |err| {
        std.debug.print("Failed to create VectorPerVertexRendererParameters for new SurfaceMesh: {}\n", .{err});
    };
}

/// Part of the Module interface.
/// Destroy the VectorPerVertexRendererParameters associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const vpvr: *VectorPerVertexRenderer = @alignCast(@fieldParentPtr("module", m));
    const p = vpvr.parameters.getPtr(surface_mesh) orelse return;
    p.deinit();
    _ = vpvr.parameters.remove(surface_mesh);
}

/// Part of the Module interface.
/// Update the VectorPerVertexRendererParameters when a standard data of the SurfaceMesh changes.
pub fn surfaceMeshStdDataChanged(
    m: *Module,
    surface_mesh: *SurfaceMesh,
    std_data: SurfaceMeshStdData,
) void {
    const vpvr: *VectorPerVertexRenderer = @alignCast(@fieldParentPtr("module", m));
    const p = vpvr.parameters.getPtr(surface_mesh) orelse return;
    switch (std_data) {
        .vertex_position => |maybe_vertex_position| {
            if (maybe_vertex_position) |vertex_position| {
                const position_vbo = zgp.surface_mesh_store.dataVBO(.vertex, Vec3f, vertex_position);
                p.point_vector_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            } else {
                p.point_vector_shader_parameters.unsetVertexAttribArray(.position);
            }
        },
        else => return, // Ignore other standard data changes
    }
}

fn setSurfaceMeshVectorData(
    vpvr: *VectorPerVertexRenderer,
    surface_mesh: *SurfaceMesh,
    vertex_vector: ?SurfaceMesh.CellData(.vertex, Vec3f),
) void {
    const p = vpvr.parameters.getPtr(surface_mesh) orelse return;
    p.vertex_vector = vertex_vector;
    if (p.vertex_vector) |v| {
        const vector_vbo = zgp.surface_mesh_store.dataVBO(.vertex, Vec3f, v);
        p.point_vector_shader_parameters.setVertexAttribArray(.vector, vector_vbo, 0, 0);
    } else {
        p.point_vector_shader_parameters.unsetVertexAttribArray(.vector);
    }
    zgp.requestRedraw();
}

/// Part of the Module interface.
/// Render all SurfaceMeshes with their VectorPerVertexRendererParameters and the given view and projection matrices.
pub fn draw(m: *Module, view_matrix: Mat4f, projection_matrix: Mat4f) void {
    const vpvr: *VectorPerVertexRenderer = @alignCast(@fieldParentPtr("module", m));
    var sm_it = zgp.surface_mesh_store.surface_meshes.iterator();
    while (sm_it.next()) |entry| {
        const surface_mesh = entry.value_ptr.*;
        const surface_mesh_info = zgp.surface_mesh_store.surfaceMeshInfo(surface_mesh);
        const vector_per_vertex_renderer_parameters = vpvr.parameters.getPtr(surface_mesh).?;

        vector_per_vertex_renderer_parameters.point_vector_shader_parameters.model_view_matrix = @bitCast(view_matrix);
        vector_per_vertex_renderer_parameters.point_vector_shader_parameters.projection_matrix = @bitCast(projection_matrix);
        vector_per_vertex_renderer_parameters.point_vector_shader_parameters.draw(surface_mesh_info.points_ibo);
    }
}

/// Part of the Module interface.
/// Show a UI panel to control the VectorPerVertexRendererParameters of the selected SurfaceMesh.
pub fn uiPanel(m: *Module) void {
    const vpvr: *VectorPerVertexRenderer = @alignCast(@fieldParentPtr("module", m));

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (zgp.surface_mesh_store.selected_surface_mesh) |sm| {
        const p = vpvr.parameters.getPtr(sm).?;
        c.ImGui_Text("Vector");
        c.ImGui_PushID("VectorData");
        if (imgui_utils.surfaceMeshCellDataComboBox(
            sm,
            .vertex,
            Vec3f,
            p.vertex_vector,
        )) |data| {
            vpvr.setSurfaceMeshVectorData(sm, data);
        }
        c.ImGui_PopID();
        c.ImGui_Text("Vector scale");
        c.ImGui_PushID("VectorScale");
        if (c.ImGui_SliderFloatEx("", &p.point_vector_shader_parameters.vector_scale, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
            zgp.requestRedraw();
        }
        c.ImGui_PopID();
        if (c.ImGui_ColorEdit3("Vector color", &p.point_vector_shader_parameters.vector_color, c.ImGuiColorEditFlags_NoInputs)) {
            zgp.requestRedraw();
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }
}
