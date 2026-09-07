const SurfaceMeshRenderer = @This();

const std = @import("std");
const assert = std.debug.assert;
const gl = @import("gl");

const c = @import("c");

const imgui_utils = @import("../ui/imgui.zig");
const imgui_log = std.log.scoped(.imgui);

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfaceMeshStdData = @import("../models/SurfaceMeshStore.zig").SurfaceMeshStdData;
const DataGen = @import("../utils/data.zig").DataGen;

const PointSphere = @import("../rendering/shaders/point_sphere/PointSphere.zig");
const PointSphereScalarPerVertex = @import("../rendering/shaders/point_sphere_scalar_per_vertex/PointSphereScalarPerVertex.zig");
const PointSphereRGBPerVertex = @import("../rendering/shaders/point_sphere_rgb_per_vertex/PointSphereRGBPerVertex.zig");
const Line = @import("../rendering/shaders/line/Line.zig");
const LineCylinder = @import("../rendering/shaders/line_cylinder/LineCylinder.zig");
const TriFlat = @import("../rendering/shaders/tri_flat/TriFlat.zig");
const TriFlatScalarPerVertex = @import("../rendering/shaders/tri_flat_scalar_per_vertex/TriFlatScalarPerVertex.zig");
const TriFlatUVPerVertex = @import("../rendering/shaders/tri_flat_uv_per_vertex/TriFlatUVPerVertex.zig");
const TriFlatRGBPerVertex = @import("../rendering/shaders/tri_flat_rgb_per_vertex/TriFlatRGBPerVertex.zig");
const TriFlatScalarPerFace = @import("../rendering/shaders/tri_flat_scalar_per_face/TriFlatScalarPerFace.zig");
const TriFlatRGBPerFace = @import("../rendering/shaders/tri_flat_rgb_per_face/TriFlatRGBPerFace.zig");
const VBO = @import("../rendering/VBO.zig");

const eigen = @import("../geometry/eigen.zig");
const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec2f = vec.Vec2f;
const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;

const ColorDefinedOn = enum {
    global,
    vertex,
    face,
};
const ColorType = enum {
    scalar,
    uv,
    rgb,
};
const ColorParameters = struct {
    defined_on: ColorDefinedOn,
    type: ColorType = .rgb,
    vertex_scalar_data: ?SurfaceMesh.CellData(.vertex, f32) = null, // data used if defined_on is vertex & type is scalar
    vertex_uv_data: ?SurfaceMesh.CellData(.vertex, Vec2f) = null, // data used if defined_on is vertex & type is uv
    vertex_rgb_data: ?SurfaceMesh.CellData(.vertex, Vec3f) = null, // data used if defined_on is vertex & type is rgb
    face_scalar_data: ?SurfaceMesh.CellData(.face, f32) = null, // data used if defined_on is face & type is scalar
    face_rgb_data: ?SurfaceMesh.CellData(.face, Vec3f) = null, // data used if defined_on is face & type is rgb
};

const SurfaceMeshRendererParameters = struct {
    point_sphere_shader_parameters: PointSphere.Parameters,
    point_sphere_scalar_per_vertex_shader_parameters: PointSphereScalarPerVertex.Parameters,
    point_sphere_rgb_per_vertex_shader_parameters: PointSphereRGBPerVertex.Parameters,
    line_shader_parameters: Line.Parameters,
    line_cylinder_shader_parameters: LineCylinder.Parameters,
    tri_flat_shader_parameters: TriFlat.Parameters,
    tri_flat_scalar_per_vertex_shader_parameters: TriFlatScalarPerVertex.Parameters,
    tri_flat_uv_per_vertex_shader_parameters: TriFlatUVPerVertex.Parameters,
    tri_flat_rgb_per_vertex_shader_parameters: TriFlatRGBPerVertex.Parameters,
    tri_flat_scalar_per_face_shader_parameters: TriFlatScalarPerFace.Parameters,
    tri_flat_rgb_per_face_shader_parameters: TriFlatRGBPerFace.Parameters,
    boundary_shader_parameters: LineCylinder.Parameters,

    draw_vertices: bool = true,
    draw_edges: bool = true,
    draw_edges_as_cylinders: bool = false,
    draw_faces: bool = true,
    draw_boundaries: bool = false,

    draw_vertices_color: ColorParameters = .{
        .defined_on = .global, // authorized values: global, vertex
    },
    draw_faces_color: ColorParameters = .{
        .defined_on = .global, // authorized values: global, vertex, face
    },

    pub fn init() SurfaceMeshRendererParameters {
        return .{
            .point_sphere_shader_parameters = PointSphere.Parameters.init(),
            .point_sphere_scalar_per_vertex_shader_parameters = PointSphereScalarPerVertex.Parameters.init(),
            .point_sphere_rgb_per_vertex_shader_parameters = PointSphereRGBPerVertex.Parameters.init(),
            .line_shader_parameters = Line.Parameters.init(),
            .line_cylinder_shader_parameters = LineCylinder.Parameters.init(),
            .tri_flat_shader_parameters = TriFlat.Parameters.init(),
            .tri_flat_scalar_per_vertex_shader_parameters = TriFlatScalarPerVertex.Parameters.init(),
            .tri_flat_uv_per_vertex_shader_parameters = TriFlatUVPerVertex.Parameters.init(),
            .tri_flat_rgb_per_vertex_shader_parameters = TriFlatRGBPerVertex.Parameters.init(),
            .tri_flat_scalar_per_face_shader_parameters = TriFlatScalarPerFace.Parameters.init(),
            .tri_flat_rgb_per_face_shader_parameters = TriFlatRGBPerFace.Parameters.init(),
            .boundary_shader_parameters = LineCylinder.Parameters.init(),
        };
    }

    pub fn deinit(self: *SurfaceMeshRendererParameters) void {
        self.point_sphere_shader_parameters.deinit();
        self.point_sphere_scalar_per_vertex_shader_parameters.deinit();
        self.point_sphere_rgb_per_vertex_shader_parameters.deinit();
        self.line_shader_parameters.deinit();
        self.line_cylinder_shader_parameters.deinit();
        self.tri_flat_shader_parameters.deinit();
        self.tri_flat_scalar_per_vertex_shader_parameters.deinit();
        self.tri_flat_uv_per_vertex_shader_parameters.deinit();
        self.tri_flat_rgb_per_vertex_shader_parameters.deinit();
        self.tri_flat_scalar_per_face_shader_parameters.deinit();
        self.tri_flat_rgb_per_face_shader_parameters.deinit();
        self.boundary_shader_parameters.deinit();
    }
};

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Renderer",
    .supported_models = .{ .surface_mesh = true },
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .surfaceMeshStdDataChanged = surfaceMeshStdDataChanged,
        .surfaceMeshDataUpdated = surfaceMeshDataUpdated,
        .draw = draw,
        .rightPanel = rightPanel,
    },
},
parameters: std.AutoHashMapUnmanaged(*SurfaceMesh, SurfaceMeshRendererParameters) = .empty,

pub fn init(app_ctx: *AppContext) SurfaceMeshRenderer {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(smr: *SurfaceMeshRenderer) void {
    var p_it = smr.parameters.iterator();
    while (p_it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    smr.parameters.deinit(smr.app_ctx.allocator);
}

/// Part of the Module interface.
/// Create and store a SurfaceMeshRendererParameters for the new SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smr: *SurfaceMeshRenderer = @alignCast(@fieldParentPtr("module", m));
    smr.parameters.put(smr.app_ctx.allocator, surface_mesh, SurfaceMeshRendererParameters.init()) catch |err| {
        std.debug.print("Failed to create SurfaceMeshRendererParameters for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Destroy the SurfaceMeshRendererParameters associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smr: *SurfaceMeshRenderer = @alignCast(@fieldParentPtr("module", m));
    const p = smr.parameters.getPtr(surface_mesh) orelse return;
    p.deinit();
    _ = smr.parameters.remove(surface_mesh);
}

/// Part of the Module interface.
/// Update the SurfaceMeshRendererParameters when a standard data of the SurfaceMesh changes.
pub fn surfaceMeshStdDataChanged(
    m: *Module,
    surface_mesh: *SurfaceMesh,
    std_data: SurfaceMeshStdData,
) void {
    const smr: *SurfaceMeshRenderer = @alignCast(@fieldParentPtr("module", m));
    const p = smr.parameters.getPtr(surface_mesh) orelse return;
    switch (std_data) {
        .vertex_position => |maybe_vertex_position| {
            if (maybe_vertex_position) |vertex_position| {
                const position_vbo: VBO = smr.app_ctx.surface_mesh_store.dataVBO(.vertex, Vec3f, vertex_position);
                p.point_sphere_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.point_sphere_scalar_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.point_sphere_rgb_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.line_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.line_cylinder_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_scalar_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_uv_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_rgb_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_scalar_per_face_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_rgb_per_face_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.boundary_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            } else {
                p.point_sphere_shader_parameters.unsetVertexAttribArray(.position);
                p.point_sphere_scalar_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
                p.point_sphere_rgb_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
                p.line_shader_parameters.unsetVertexAttribArray(.position);
                p.line_cylinder_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_scalar_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_uv_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_rgb_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_scalar_per_face_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_rgb_per_face_shader_parameters.unsetVertexAttribArray(.position);
                p.boundary_shader_parameters.unsetVertexAttribArray(.position);
            }
        },
        else => return, // Ignore other standard data changes
    }
}

const CompareScalarContext = struct {};
fn compareScalar(_: CompareScalarContext, a: f32, b: f32) std.math.Order {
    return std.math.order(a, b);
}

/// Part of the Module interface.
/// Check if the updated data is used here for coloring and update the associated min/max values.
pub fn surfaceMeshDataUpdated(
    m: *Module,
    surface_mesh: *SurfaceMesh,
    cell_type: SurfaceMesh.CellType,
    data_gen: *const DataGen,
) void {
    const smr: *SurfaceMeshRenderer = @alignCast(@fieldParentPtr("module", m));
    const p = smr.parameters.getPtr(surface_mesh) orelse return;
    switch (cell_type) {
        .vertex => {
            if (p.draw_vertices_color.vertex_scalar_data != null and
                p.draw_vertices_color.vertex_scalar_data.?.gen() == data_gen)
            {
                const min, const max = p.draw_vertices_color.vertex_scalar_data.?.data.minMaxValues(CompareScalarContext{}, compareScalar);
                p.point_sphere_scalar_per_vertex_shader_parameters.min_value = min;
                p.point_sphere_scalar_per_vertex_shader_parameters.max_value = max;
            }
            if (p.draw_faces_color.vertex_scalar_data != null and
                p.draw_faces_color.vertex_scalar_data.?.gen() == data_gen)
            {
                const min, const max = p.draw_faces_color.vertex_scalar_data.?.data.minMaxValues(CompareScalarContext{}, compareScalar);
                p.tri_flat_scalar_per_vertex_shader_parameters.min_value = min;
                p.tri_flat_scalar_per_vertex_shader_parameters.max_value = max;
            }
        },
        .face => {
            if (p.draw_vertices_color.face_scalar_data != null and
                p.draw_vertices_color.face_scalar_data.?.gen() == data_gen)
            {
                const min, const max = p.draw_vertices_color.face_scalar_data.?.data.minMaxValues(CompareScalarContext{}, compareScalar);
                p.tri_flat_scalar_per_face_shader_parameters.min_value = min;
                p.tri_flat_scalar_per_face_shader_parameters.max_value = max;
            }
        },
        else => return, // Ignore other cell types
    }
}

fn setSurfaceMeshDrawVerticesColorData(
    smr: *SurfaceMeshRenderer,
    surface_mesh: *SurfaceMesh,
    comptime cell_type: SurfaceMesh.CellType,
    T: type,
    data: ?SurfaceMesh.CellData(cell_type, T),
) void {
    const p = smr.parameters.getPtr(surface_mesh) orelse return;
    switch (@typeInfo(T)) {
        .float => {
            var min: f32 = std.math.floatMax(f32);
            var max: f32 = std.math.floatMin(f32);
            if (data) |d| {
                min, max = d.data.minMaxValues(CompareScalarContext{}, compareScalar);
            }
            switch (cell_type) {
                .vertex => {
                    p.draw_vertices_color.vertex_scalar_data = data;
                    if (p.draw_vertices_color.vertex_scalar_data) |scalar| {
                        const scalar_vbo = smr.app_ctx.surface_mesh_store.dataVBO(.vertex, f32, scalar);
                        p.point_sphere_scalar_per_vertex_shader_parameters.setVertexAttribArray(.scalar, scalar_vbo, 0, 0);
                    } else {
                        p.point_sphere_scalar_per_vertex_shader_parameters.unsetVertexAttribArray(.scalar);
                    }
                    p.point_sphere_scalar_per_vertex_shader_parameters.min_value = min;
                    p.point_sphere_scalar_per_vertex_shader_parameters.max_value = max;
                },
                else => unreachable,
            }
        },
        .array => {
            if (@typeInfo(@typeInfo(T).array.child) != .float) {
                @compileError("SurfaceMeshRenderer bad vertex color data type");
            }
            switch (cell_type) {
                .vertex => {
                    p.draw_vertices_color.vertex_rgb_data = data;
                    if (p.draw_vertices_color.vertex_rgb_data) |rgb| {
                        const rgb_vbo = smr.app_ctx.surface_mesh_store.dataVBO(.vertex, Vec3f, rgb);
                        p.point_sphere_rgb_per_vertex_shader_parameters.setVertexAttribArray(.rgb, rgb_vbo, 0, 0);
                    } else {
                        p.point_sphere_rgb_per_vertex_shader_parameters.unsetVertexAttribArray(.rgb);
                    }
                },
                else => unreachable,
            }
        },
        else => @compileError("SurfaceMeshRenderer bad vertex color data type"),
    }
    smr.app_ctx.requestRedraw();
}

fn setSurfaceMeshDrawFacesColorData(
    smr: *SurfaceMeshRenderer,
    surface_mesh: *SurfaceMesh,
    comptime cell_type: SurfaceMesh.CellType,
    T: type,
    data: ?SurfaceMesh.CellData(cell_type, T),
) void {
    const p = smr.parameters.getPtr(surface_mesh) orelse return;
    switch (@typeInfo(T)) {
        .float => {
            var min: f32 = std.math.floatMax(f32);
            var max: f32 = std.math.floatMin(f32);
            if (data) |d| {
                var it = d.data.iterator();
                while (it.next()) |v| {
                    if (v.* < min) min = v.*;
                    if (v.* > max) max = v.*;
                }
            }
            switch (cell_type) {
                .vertex => {
                    p.draw_faces_color.vertex_scalar_data = data;
                    if (p.draw_faces_color.vertex_scalar_data) |scalar| {
                        const scalar_vbo = smr.app_ctx.surface_mesh_store.dataVBO(.vertex, f32, scalar);
                        p.tri_flat_scalar_per_vertex_shader_parameters.setVertexAttribArray(.scalar, scalar_vbo, 0, 0);
                    } else {
                        p.tri_flat_scalar_per_vertex_shader_parameters.unsetVertexAttribArray(.scalar);
                    }
                    p.tri_flat_scalar_per_vertex_shader_parameters.min_value = min;
                    p.tri_flat_scalar_per_vertex_shader_parameters.max_value = max;
                },
                .face => {
                    p.draw_faces_color.face_scalar_data = data;
                    if (p.draw_faces_color.face_scalar_data) |scalar| {
                        const scalar_vbo = smr.app_ctx.surface_mesh_store.dataVBO(.face, f32, scalar);
                        p.tri_flat_scalar_per_face_shader_parameters.face_scalar_buffer = scalar_vbo;
                    } else {
                        p.tri_flat_scalar_per_face_shader_parameters.face_scalar_buffer = null;
                    }
                    p.tri_flat_scalar_per_face_shader_parameters.min_value = min;
                    p.tri_flat_scalar_per_face_shader_parameters.max_value = max;
                },
                else => unreachable,
            }
        },
        .array => {
            if (@typeInfo(@typeInfo(T).array.child) != .float) {
                @compileError("SurfaceMeshRenderer bad color data type");
            }
            switch (cell_type) {
                .vertex => {
                    switch (@typeInfo(T).array.len) {
                        2 => {
                            p.draw_faces_color.vertex_uv_data = data;
                            if (p.draw_faces_color.vertex_uv_data) |uv| {
                                const uv_vbo = smr.app_ctx.surface_mesh_store.dataVBO(.vertex, Vec2f, uv);
                                p.tri_flat_uv_per_vertex_shader_parameters.setVertexAttribArray(.uv, uv_vbo, 0, 0);
                            } else {
                                p.tri_flat_uv_per_vertex_shader_parameters.unsetVertexAttribArray(.uv);
                            }
                        },
                        3 => {
                            p.draw_faces_color.vertex_rgb_data = data;
                            if (p.draw_faces_color.vertex_rgb_data) |rgb| {
                                const rgb_vbo = smr.app_ctx.surface_mesh_store.dataVBO(.vertex, Vec3f, rgb);
                                p.tri_flat_rgb_per_vertex_shader_parameters.setVertexAttribArray(.rgb, rgb_vbo, 0, 0);
                            } else {
                                p.tri_flat_rgb_per_vertex_shader_parameters.unsetVertexAttribArray(.rgb);
                            }
                        },
                        else => unreachable,
                    }
                },
                .face => {
                    p.draw_faces_color.face_rgb_data = data;
                    if (p.draw_faces_color.face_rgb_data) |rgb| {
                        const rgb_vbo = smr.app_ctx.surface_mesh_store.dataVBO(.face, Vec3f, rgb);
                        p.tri_flat_rgb_per_face_shader_parameters.face_rgb_buffer = rgb_vbo;
                    } else {
                        p.tri_flat_rgb_per_face_shader_parameters.face_rgb_buffer = null;
                    }
                },
                else => unreachable,
            }
        },
        else => @compileError("SurfaceMeshRenderer bad color data type"),
    }
    smr.app_ctx.requestRedraw();
}

/// Part of the Module interface.
/// Render all SurfaceMeshes with their SurfaceMeshRendererParameters and the given view and projection matrices.
pub fn draw(m: *Module, view_matrix: Mat4f, projection_matrix: Mat4f) void {
    const smr: *SurfaceMeshRenderer = @alignCast(@fieldParentPtr("module", m));
    var sm_it = smr.app_ctx.surface_mesh_store.surface_meshes.iterator();
    while (sm_it.next()) |entry| {
        const sm = entry.value_ptr.*;
        const info = smr.app_ctx.surface_mesh_store.surfaceMeshInfo(sm);
        const p = smr.parameters.getPtr(sm).?;
        if (p.draw_faces) {
            gl.Enable(gl.POLYGON_OFFSET_FILL);
            gl.PolygonOffset(1.0, 1.0);
            switch (p.draw_faces_color.defined_on) {
                .global => {
                    p.tri_flat_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                    p.tri_flat_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                    p.tri_flat_shader_parameters.draw(info.triangles_ibo);
                },
                .vertex => {
                    switch (p.draw_faces_color.type) {
                        .scalar => {
                            p.tri_flat_scalar_per_vertex_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                            p.tri_flat_scalar_per_vertex_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                            p.tri_flat_scalar_per_vertex_shader_parameters.draw(info.triangles_ibo);
                        },
                        .uv => {
                            p.tri_flat_uv_per_vertex_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                            p.tri_flat_uv_per_vertex_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                            p.tri_flat_uv_per_vertex_shader_parameters.draw(info.triangles_ibo);
                        },
                        .rgb => {
                            p.tri_flat_rgb_per_vertex_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                            p.tri_flat_rgb_per_vertex_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                            p.tri_flat_rgb_per_vertex_shader_parameters.draw(info.triangles_ibo);
                        },
                    }
                },
                .face => {
                    switch (p.draw_faces_color.type) {
                        .scalar => {
                            p.tri_flat_scalar_per_face_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                            p.tri_flat_scalar_per_face_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                            p.tri_flat_scalar_per_face_shader_parameters.draw(info.triangles_ibo);
                        },
                        .uv => {
                            // not supported
                        },
                        .rgb => {
                            p.tri_flat_rgb_per_face_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                            p.tri_flat_rgb_per_face_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                            p.tri_flat_rgb_per_face_shader_parameters.draw(info.triangles_ibo);
                        },
                    }
                },
            }
            gl.Disable(gl.POLYGON_OFFSET_FILL);
        }
        if (p.draw_edges) {
            if (p.draw_edges_as_cylinders) {
                gl.Enable(gl.CULL_FACE);
                gl.CullFace(gl.BACK);
                p.line_cylinder_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                p.line_cylinder_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                p.line_cylinder_shader_parameters.draw(info.lines_ibo);
                gl.Disable(gl.CULL_FACE);
            } else {
                p.line_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                p.line_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                p.line_shader_parameters.viewport_size = .{
                    @floatFromInt(smr.app_ctx.view.width),
                    @floatFromInt(smr.app_ctx.view.height),
                };
                p.line_shader_parameters.draw(info.lines_ibo);
            }
        }
        if (p.draw_vertices) {
            switch (p.draw_vertices_color.defined_on) {
                .global => {
                    p.point_sphere_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                    p.point_sphere_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                    p.point_sphere_shader_parameters.draw(info.points_ibo);
                },
                .vertex => {
                    switch (p.draw_vertices_color.type) {
                        .scalar => {
                            p.point_sphere_scalar_per_vertex_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                            p.point_sphere_scalar_per_vertex_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                            p.point_sphere_scalar_per_vertex_shader_parameters.draw(info.points_ibo);
                        },
                        .uv => {
                            // not supported
                        },
                        .rgb => {
                            p.point_sphere_rgb_per_vertex_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                            p.point_sphere_rgb_per_vertex_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                            p.point_sphere_rgb_per_vertex_shader_parameters.draw(info.points_ibo);
                        },
                    }
                },
                else => unreachable,
            }
        }
        if (p.draw_boundaries) {
            gl.Enable(gl.CULL_FACE);
            gl.CullFace(gl.BACK);
            p.boundary_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            p.boundary_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            p.boundary_shader_parameters.draw(info.boundaries_ibo);
            gl.Disable(gl.CULL_FACE);
        }
    }
}

/// Part of the Module interface.
/// Show a UI panel to control the SurfaceMeshRendererParameters of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const smr: *SurfaceMeshRenderer = @alignCast(@fieldParentPtr("module", m));

    assert(smr.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = smr.app_ctx.selected_model.surface_mesh;

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const p = smr.parameters.getPtr(sm).?;

    c.ImGui_SeparatorText("Vertices");
    if (c.ImGui_Checkbox("draw vertices", &p.draw_vertices)) {
        smr.app_ctx.requestRedraw();
    }
    if (p.draw_vertices) {
        c.ImGui_Text("Size");
        c.ImGui_PushID("DrawVerticesSize");
        if (c.ImGui_SliderFloatEx("", &p.point_sphere_shader_parameters.sphere_radius, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
            // sync value to other point sphere shaders
            p.point_sphere_scalar_per_vertex_shader_parameters.sphere_radius = p.point_sphere_shader_parameters.sphere_radius;
            p.point_sphere_rgb_per_vertex_shader_parameters.sphere_radius = p.point_sphere_shader_parameters.sphere_radius;
            smr.app_ctx.requestRedraw();
        }
        c.ImGui_PopID();
        c.ImGui_Text("Color");
        {
            c.ImGui_BeginGroup();
            defer c.ImGui_EndGroup();
            if (c.ImGui_RadioButton("Global##DrawVerticesColorGlobal", p.draw_vertices_color.defined_on == .global)) {
                p.draw_vertices_color.defined_on = .global;
                smr.app_ctx.requestRedraw();
            }
            c.ImGui_SameLine();
            if (c.ImGui_RadioButton("Per vertex##DrawVerticesColorPerVertex", p.draw_vertices_color.defined_on == .vertex)) {
                p.draw_vertices_color.defined_on = .vertex;
                smr.app_ctx.requestRedraw();
            }
        }
        switch (p.draw_vertices_color.defined_on) {
            .global => {
                if (c.ImGui_ColorEdit3("Global color##DrawVerticesColorGlobalEdit", &p.point_sphere_shader_parameters.sphere_color, c.ImGuiColorEditFlags_NoInputs)) {
                    smr.app_ctx.requestRedraw();
                }
            },
            .vertex => {
                {
                    c.ImGui_BeginGroup();
                    defer c.ImGui_EndGroup();
                    if (c.ImGui_RadioButton("Scalar##DrawVerticesColorVertexScalar", p.draw_vertices_color.type == .scalar)) {
                        p.draw_vertices_color.type = .scalar;
                        smr.app_ctx.requestRedraw();
                    }
                    c.ImGui_SameLine();
                    if (c.ImGui_RadioButton("RGB##DrawVerticesColorVertexRGB", p.draw_vertices_color.type == .rgb)) {
                        p.draw_vertices_color.type = .rgb;
                        smr.app_ctx.requestRedraw();
                    }
                }
                c.ImGui_PushID("DrawVerticesColorVertexData");
                switch (p.draw_vertices_color.type) {
                    .scalar => switch (imgui_utils.surfaceMeshCellDataComboBox(sm, .vertex, f32, p.draw_vertices_color.vertex_scalar_data)) {
                        .unchanged => {},
                        .cleared => smr.setSurfaceMeshDrawVerticesColorData(sm, .vertex, f32, null),
                        .changed => |data| smr.setSurfaceMeshDrawVerticesColorData(sm, .vertex, f32, data),
                    },
                    .uv => {
                        // not supported
                    },
                    .rgb => switch (imgui_utils.surfaceMeshCellDataComboBox(sm, .vertex, Vec3f, p.draw_vertices_color.vertex_rgb_data)) {
                        .unchanged => {},
                        .cleared => smr.setSurfaceMeshDrawVerticesColorData(sm, .vertex, Vec3f, null),
                        .changed => |data| smr.setSurfaceMeshDrawVerticesColorData(sm, .vertex, Vec3f, data),
                    },
                }
                c.ImGui_PopID();
            },
            else => unreachable,
        }
    }

    c.ImGui_SeparatorText("Edges");
    if (c.ImGui_Checkbox("draw edges", &p.draw_edges)) {
        smr.app_ctx.requestRedraw();
    }
    if (p.draw_edges) {
        if (c.ImGui_Checkbox("draw edges as cylinders", &p.draw_edges_as_cylinders)) {
            smr.app_ctx.requestRedraw();
        }
        if (p.draw_edges_as_cylinders) {
            c.ImGui_Text("Width (world)");
            c.ImGui_PushID("DrawEdgesWidth");
            if (c.ImGui_SliderFloatEx("", &p.line_cylinder_shader_parameters.cylinder_radius, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
                smr.app_ctx.requestRedraw();
            }
            c.ImGui_PopID();
        } else {
            c.ImGui_Text("Width (screen)");
            c.ImGui_PushID("DrawEdgesWidth");
            if (c.ImGui_SliderFloatEx("", &p.line_shader_parameters.line_width, 0.1, 5.0, "%.1f", c.ImGuiSliderFlags_None)) {
                smr.app_ctx.requestRedraw();
            }
            c.ImGui_PopID();
        }
        if (c.ImGui_ColorEdit4("Global color##DrawEdgesColorGlobalEdit", &p.line_cylinder_shader_parameters.cylinder_color, c.ImGuiColorEditFlags_NoInputs)) {
            p.line_shader_parameters.line_color = p.line_cylinder_shader_parameters.cylinder_color;
            smr.app_ctx.requestRedraw();
        }
    }

    c.ImGui_SeparatorText("Faces");
    if (c.ImGui_Checkbox("draw faces", &p.draw_faces)) {
        smr.app_ctx.requestRedraw();
    }
    if (p.draw_faces) {
        c.ImGui_Text("Color");
        {
            c.ImGui_BeginGroup();
            defer c.ImGui_EndGroup();
            if (c.ImGui_RadioButton("Global##DrawFacesColorGlobal", p.draw_faces_color.defined_on == .global)) {
                p.draw_faces_color.defined_on = .global;
                smr.app_ctx.requestRedraw();
            }
            c.ImGui_SameLine();
            if (c.ImGui_RadioButton("Per vertex##DrawFacesColorPerVertex", p.draw_faces_color.defined_on == .vertex)) {
                p.draw_faces_color.defined_on = .vertex;
                smr.app_ctx.requestRedraw();
            }
            c.ImGui_SameLine();
            if (c.ImGui_RadioButton("Per face##DrawFacesColorPerFace", p.draw_faces_color.defined_on == .face)) {
                p.draw_faces_color.defined_on = .face;
                smr.app_ctx.requestRedraw();
            }
        }
        switch (p.draw_faces_color.defined_on) {
            .global => {
                if (c.ImGui_ColorEdit4("Global color##DrawFacesColorGlobalEdit", &p.tri_flat_shader_parameters.vertex_color, c.ImGuiColorEditFlags_NoInputs)) {
                    smr.app_ctx.requestRedraw();
                }
            },
            .vertex => {
                {
                    c.ImGui_BeginGroup();
                    defer c.ImGui_EndGroup();
                    if (c.ImGui_RadioButton("Scalar##DrawFacesColorVertexScalar", p.draw_faces_color.type == .scalar)) {
                        p.draw_faces_color.type = .scalar;
                        smr.app_ctx.requestRedraw();
                    }
                    c.ImGui_SameLine();
                    if (c.ImGui_RadioButton("UV##DrawFacesColorVertexUV", p.draw_faces_color.type == .uv)) {
                        p.draw_faces_color.type = .uv;
                        smr.app_ctx.requestRedraw();
                    }
                    c.ImGui_SameLine();
                    if (c.ImGui_RadioButton("RGB##DrawFacesColorVertexRGB", p.draw_faces_color.type == .rgb)) {
                        p.draw_faces_color.type = .rgb;
                        smr.app_ctx.requestRedraw();
                    }
                }
                c.ImGui_PushID("DrawFacesColorVertexData");
                switch (p.draw_faces_color.type) {
                    .scalar => {
                        switch (imgui_utils.surfaceMeshCellDataComboBox(sm, .vertex, f32, p.draw_faces_color.vertex_scalar_data)) {
                            .unchanged => {},
                            .cleared => smr.setSurfaceMeshDrawFacesColorData(sm, .vertex, f32, null),
                            .changed => |data| smr.setSurfaceMeshDrawFacesColorData(sm, .vertex, f32, data),
                        }
                        if (c.ImGui_Checkbox("Draw isolines", &p.tri_flat_scalar_per_vertex_shader_parameters.draw_isolines)) {
                            smr.app_ctx.requestRedraw();
                        }
                        c.ImGui_Text("Nb isolines");
                        c.ImGui_PushID("NbIsolines");
                        if (c.ImGui_SliderInt("", &p.tri_flat_scalar_per_vertex_shader_parameters.nb_isolines, 1, 100)) {
                            smr.app_ctx.requestRedraw();
                        }
                        c.ImGui_PopID();
                    },
                    .uv => {
                        switch (imgui_utils.surfaceMeshCellDataComboBox(sm, .vertex, Vec2f, p.draw_faces_color.vertex_uv_data)) {
                            .unchanged => {},
                            .cleared => smr.setSurfaceMeshDrawFacesColorData(sm, .vertex, Vec2f, null),
                            .changed => |data| smr.setSurfaceMeshDrawFacesColorData(sm, .vertex, Vec2f, data),
                        }
                        if (c.ImGui_Checkbox("Radial", &p.tri_flat_uv_per_vertex_shader_parameters.radial)) {
                            smr.app_ctx.requestRedraw();
                        }
                    },
                    .rgb => switch (imgui_utils.surfaceMeshCellDataComboBox(sm, .vertex, Vec3f, p.draw_faces_color.vertex_rgb_data)) {
                        .unchanged => {},
                        .cleared => smr.setSurfaceMeshDrawFacesColorData(sm, .vertex, Vec3f, null),
                        .changed => |data| smr.setSurfaceMeshDrawFacesColorData(sm, .vertex, Vec3f, data),
                    },
                }
                c.ImGui_PopID();
            },
            .face => {
                {
                    c.ImGui_BeginGroup();
                    defer c.ImGui_EndGroup();
                    if (c.ImGui_RadioButton("Scalar##DrawFacesColorFaceScalar", p.draw_faces_color.type == .scalar)) {
                        p.draw_faces_color.type = .scalar;
                        smr.app_ctx.requestRedraw();
                    }
                    c.ImGui_SameLine();
                    if (c.ImGui_RadioButton("RGB##DrawFacesColorFaceRGB", p.draw_faces_color.type == .rgb)) {
                        p.draw_faces_color.type = .rgb;
                        smr.app_ctx.requestRedraw();
                    }
                }
                c.ImGui_PushID("DrawFacesColorFaceData");
                switch (p.draw_faces_color.type) {
                    .scalar => switch (imgui_utils.surfaceMeshCellDataComboBox(sm, .face, f32, p.draw_faces_color.face_scalar_data)) {
                        .unchanged => {},
                        .cleared => smr.setSurfaceMeshDrawFacesColorData(sm, .face, f32, null),
                        .changed => |data| smr.setSurfaceMeshDrawFacesColorData(sm, .face, f32, data),
                    },
                    .uv => {
                        // not supported
                    },
                    .rgb => switch (imgui_utils.surfaceMeshCellDataComboBox(sm, .face, Vec3f, p.draw_faces_color.face_rgb_data)) {
                        .unchanged => {},
                        .cleared => smr.setSurfaceMeshDrawFacesColorData(sm, .face, Vec3f, null),
                        .changed => |data| smr.setSurfaceMeshDrawFacesColorData(sm, .face, Vec3f, data),
                    },
                }
                c.ImGui_PopID();
            },
        }
    }

    c.ImGui_SeparatorText("Boundaries");
    if (c.ImGui_Checkbox("draw boundaries", &p.draw_boundaries)) {
        smr.app_ctx.requestRedraw();
    }
    if (p.draw_boundaries) {
        c.ImGui_Text("Width");
        c.ImGui_PushID("DrawBoundariesWidth");
        if (c.ImGui_SliderFloatEx("", &p.boundary_shader_parameters.cylinder_radius, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
            smr.app_ctx.requestRedraw();
        }
        c.ImGui_PopID();
        if (c.ImGui_ColorEdit4("Global color##DrawBoundariesColorGlobalEdit", &p.boundary_shader_parameters.cylinder_color, c.ImGuiColorEditFlags_NoInputs)) {
            smr.app_ctx.requestRedraw();
        }
    }
}
