const VectorPerVertexRenderer = @This();

const std = @import("std");
const assert = std.debug.assert;
const gl = @import("gl");

const c = @import("../main.zig").c;

const imgui_utils = @import("../ui/imgui.zig");
const imgui_log = std.log.scoped(.imgui);

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const PointCloud = @import("../models/point/PointCloud.zig");
const PointCloudStdData = @import("../models/PointCloudStore.zig").PointCloudStdData;
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfaceMeshStdData = @import("../models/SurfaceMeshStore.zig").SurfaceMeshStdData;

const PointVector = @import("../rendering/shaders/point_vector/PointVector.zig");
const VBO = @import("../rendering/VBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;

// TODO: implement IncidenceGraph support

const VertexVectorData = union(enum) {
    surface_mesh: ?SurfaceMesh.CellData(.vertex, Vec3f),
    point_cloud: ?PointCloud.CellData(Vec3f),
};

const VectorPerVertexRendererParameters = struct {
    point_vector_shader_parameters: PointVector.Parameters,

    vertex_vector: VertexVectorData,

    pub fn init(t: std.meta.Tag(VertexVectorData)) VectorPerVertexRendererParameters {
        return .{
            .point_vector_shader_parameters = PointVector.Parameters.init(),
            .vertex_vector = switch (t) {
                .surface_mesh => .{ .surface_mesh = null },
                .point_cloud => .{ .point_cloud = null },
            },
        };
    }

    pub fn deinit(self: *VectorPerVertexRendererParameters) void {
        self.point_vector_shader_parameters.deinit();
    }
};

app_ctx: *AppContext,
module: Module = .{
    .name = "Vector Per Vertex Renderer",
    .supported_models = .{
        .point_cloud = true,
        .surface_mesh = true,
    },
    .vtable = &.{
        .pointCloudCreated = pointCloudCreated,
        .pointCloudDestroyed = pointCloudDestroyed,
        .pointCloudStdDataChanged = pointCloudStdDataChanged,
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .surfaceMeshStdDataChanged = surfaceMeshStdDataChanged,
        .draw = draw,
        .rightPanel = rightPanel,
    },
},
point_cloud_parameters: std.AutoHashMap(*PointCloud, VectorPerVertexRendererParameters),
surface_mesh_parameters: std.AutoHashMap(*SurfaceMesh, VectorPerVertexRendererParameters),

pub fn init(app_ctx: *AppContext) VectorPerVertexRenderer {
    return .{
        .app_ctx = app_ctx,
        .point_cloud_parameters = .init(app_ctx.allocator),
        .surface_mesh_parameters = .init(app_ctx.allocator),
    };
}

pub fn deinit(vpvr: *VectorPerVertexRenderer) void {
    var pc_it = vpvr.point_cloud_parameters.iterator();
    while (pc_it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    var sm_it = vpvr.surface_mesh_parameters.iterator();
    while (sm_it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    vpvr.point_cloud_parameters.deinit();
    vpvr.surface_mesh_parameters.deinit();
}

/// Part of the Module interface.
/// Create and store a VectorPerVertexRendererParameters for the new PointCloud.
pub fn pointCloudCreated(m: *Module, point_cloud: *PointCloud) void {
    const vpvr: *VectorPerVertexRenderer = @alignCast(@fieldParentPtr("module", m));
    vpvr.point_cloud_parameters.put(point_cloud, VectorPerVertexRendererParameters.init(.point_cloud)) catch |err| {
        std.debug.print("Failed to create VectorPerVertexRendererParameters for new PointCloud: {}\n", .{err});
    };
}

/// Part of the Module interface.
/// Destroy the VectorPerVertexRendererParameters associated to the destroyed PointCloud.
pub fn pointCloudDestroyed(m: *Module, point_cloud: *PointCloud) void {
    const vpvr: *VectorPerVertexRenderer = @alignCast(@fieldParentPtr("module", m));
    const p = vpvr.point_cloud_parameters.getPtr(point_cloud) orelse return;
    p.deinit();
    _ = vpvr.point_cloud_parameters.remove(point_cloud);
}

/// Part of the Module interface.
/// Update the VectorPerVertexRendererParameters when a standard data of the PointCloud changes.
pub fn pointCloudStdDataChanged(m: *Module, point_cloud: *PointCloud, std_data: PointCloudStdData) void {
    const vpvr: *VectorPerVertexRenderer = @alignCast(@fieldParentPtr("module", m));
    const p = vpvr.point_cloud_parameters.getPtr(point_cloud) orelse return;
    switch (std_data) {
        .position => |maybe_position| {
            if (maybe_position) |position| {
                const position_vbo = vpvr.app_ctx.point_cloud_store.dataVBO(Vec3f, position);
                p.point_vector_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            } else {
                p.point_vector_shader_parameters.unsetVertexAttribArray(.position);
            }
        },
        else => return, // Ignore other standard data changes
    }
}

/// Part of the Module interface.
/// Create and store a VectorPerVertexRendererParameters for the new SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const vpvr: *VectorPerVertexRenderer = @alignCast(@fieldParentPtr("module", m));
    vpvr.surface_mesh_parameters.put(surface_mesh, VectorPerVertexRendererParameters.init(.surface_mesh)) catch |err| {
        std.debug.print("Failed to create VectorPerVertexRendererParameters for new SurfaceMesh: {}\n", .{err});
    };
}

/// Part of the Module interface.
/// Destroy the VectorPerVertexRendererParameters associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const vpvr: *VectorPerVertexRenderer = @alignCast(@fieldParentPtr("module", m));
    const p = vpvr.surface_mesh_parameters.getPtr(surface_mesh) orelse return;
    p.deinit();
    _ = vpvr.surface_mesh_parameters.remove(surface_mesh);
}

/// Part of the Module interface.
/// Update the VectorPerVertexRendererParameters when a standard data of the SurfaceMesh changes.
pub fn surfaceMeshStdDataChanged(
    m: *Module,
    surface_mesh: *SurfaceMesh,
    std_data: SurfaceMeshStdData,
) void {
    const vpvr: *VectorPerVertexRenderer = @alignCast(@fieldParentPtr("module", m));
    const p = vpvr.surface_mesh_parameters.getPtr(surface_mesh) orelse return;
    switch (std_data) {
        .vertex_position => |maybe_vertex_position| {
            if (maybe_vertex_position) |vertex_position| {
                const position_vbo = vpvr.app_ctx.surface_mesh_store.dataVBO(.vertex, Vec3f, vertex_position);
                p.point_vector_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            } else {
                p.point_vector_shader_parameters.unsetVertexAttribArray(.position);
            }
        },
        else => return, // Ignore other standard data changes
    }
}

fn setPointCloudVectorData(
    vpvr: *VectorPerVertexRenderer,
    point_cloud: *PointCloud,
    vertex_vector: ?PointCloud.CellData(Vec3f),
) void {
    const p = vpvr.point_cloud_parameters.getPtr(point_cloud) orelse return;
    p.vertex_vector.point_cloud = vertex_vector;
    if (p.vertex_vector.point_cloud) |v| {
        const vector_vbo = vpvr.app_ctx.point_cloud_store.dataVBO(Vec3f, v);
        p.point_vector_shader_parameters.setVertexAttribArray(.vector, vector_vbo, 0, 0);
    } else {
        p.point_vector_shader_parameters.unsetVertexAttribArray(.vector);
    }
    vpvr.app_ctx.requestRedraw();
}

fn setSurfaceMeshVectorData(
    vpvr: *VectorPerVertexRenderer,
    surface_mesh: *SurfaceMesh,
    vertex_vector: ?SurfaceMesh.CellData(.vertex, Vec3f),
) void {
    const p = vpvr.surface_mesh_parameters.getPtr(surface_mesh) orelse return;
    p.vertex_vector.surface_mesh = vertex_vector;
    if (p.vertex_vector.surface_mesh) |v| {
        const vector_vbo = vpvr.app_ctx.surface_mesh_store.dataVBO(.vertex, Vec3f, v);
        p.point_vector_shader_parameters.setVertexAttribArray(.vector, vector_vbo, 0, 0);
    } else {
        p.point_vector_shader_parameters.unsetVertexAttribArray(.vector);
    }
    vpvr.app_ctx.requestRedraw();
}

/// Part of the Module interface.
/// Render all PointClouds & SurfaceMeshes with their VectorPerVertexRendererParameters and the given view and projection matrices.
pub fn draw(m: *Module, view_matrix: Mat4f, projection_matrix: Mat4f) void {
    const vpvr: *VectorPerVertexRenderer = @alignCast(@fieldParentPtr("module", m));

    var pc_it = vpvr.app_ctx.point_cloud_store.point_clouds.iterator();
    while (pc_it.next()) |entry| {
        const pc = entry.value_ptr.*;
        const info = vpvr.app_ctx.point_cloud_store.pointCloudInfo(pc);
        const p = vpvr.point_cloud_parameters.getPtr(pc).?;

        gl.Enable(gl.CULL_FACE);
        gl.CullFace(gl.BACK);
        p.point_vector_shader_parameters.model_view_matrix = @bitCast(view_matrix);
        p.point_vector_shader_parameters.projection_matrix = @bitCast(projection_matrix);
        p.point_vector_shader_parameters.draw(info.points_ibo);
        gl.Disable(gl.CULL_FACE);
    }

    var sm_it = vpvr.app_ctx.surface_mesh_store.surface_meshes.iterator();
    while (sm_it.next()) |entry| {
        const sm = entry.value_ptr.*;
        const info = vpvr.app_ctx.surface_mesh_store.surfaceMeshInfo(sm);
        const p = vpvr.surface_mesh_parameters.getPtr(sm).?;

        gl.Enable(gl.CULL_FACE);
        gl.CullFace(gl.BACK);
        p.point_vector_shader_parameters.model_view_matrix = @bitCast(view_matrix);
        p.point_vector_shader_parameters.projection_matrix = @bitCast(projection_matrix);
        p.point_vector_shader_parameters.draw(info.points_ibo);
        gl.Disable(gl.CULL_FACE);
    }
}

/// Part of the Module interface.
/// Show a UI panel to control the VectorPerVertexRendererParameters of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const vpvr: *VectorPerVertexRenderer = @alignCast(@fieldParentPtr("module", m));

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    c.ImGui_Text("Vector");
    c.ImGui_PushID("VectorData");
    switch (vpvr.app_ctx.selected_model) {
        .surface_mesh => |sm| {
            const p = vpvr.surface_mesh_parameters.getPtr(sm).?;
            switch (imgui_utils.surfaceMeshCellDataComboBox(sm, .vertex, Vec3f, p.vertex_vector.surface_mesh)) {
                .unchanged => {},
                .cleared => vpvr.setSurfaceMeshVectorData(sm, null),
                .changed => |data| vpvr.setSurfaceMeshVectorData(sm, data),
            }
        },
        .point_cloud => |pc| {
            const p = vpvr.point_cloud_parameters.getPtr(pc).?;
            switch (imgui_utils.pointCloudDataComboBox(pc, Vec3f, p.vertex_vector.point_cloud)) {
                .unchanged => {},
                .cleared => vpvr.setPointCloudVectorData(pc, null),
                .changed => |data| vpvr.setPointCloudVectorData(pc, data),
            }
        },
        .incidence_graph => |_| {
            // TODO
        },
        .none => {},
    }
    c.ImGui_PopID();

    const p = switch (vpvr.app_ctx.selected_model) {
        .surface_mesh => |sm| vpvr.surface_mesh_parameters.getPtr(sm).?,
        .point_cloud => |pc| vpvr.point_cloud_parameters.getPtr(pc).?,
        .incidence_graph => unreachable, // TODO
        .none => unreachable,
    };

    c.ImGui_Text("Vector scale");
    c.ImGui_PushID("VectorScale");
    if (c.ImGui_SliderFloatEx("", &p.point_vector_shader_parameters.vector_scale, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
        vpvr.app_ctx.requestRedraw();
    }
    c.ImGui_PopID();
    c.ImGui_Text("Vector radius");
    c.ImGui_PushID("VectorRadius");
    if (c.ImGui_SliderFloatEx("", &p.point_vector_shader_parameters.cone_radius, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
        vpvr.app_ctx.requestRedraw();
    }
    c.ImGui_PopID();
    if (c.ImGui_ColorEdit3("Vector color", &p.point_vector_shader_parameters.vector_color, c.ImGuiColorEditFlags_NoInputs)) {
        vpvr.app_ctx.requestRedraw();
    }
}
