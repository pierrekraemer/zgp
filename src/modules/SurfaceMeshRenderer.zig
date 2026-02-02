const SurfaceMeshRenderer = @This();

const std = @import("std");
const gl = @import("gl");

const zgp = @import("../main.zig");
const c = zgp.c;

const imgui_utils = @import("../utils/imgui.zig");
const imgui_log = std.log.scoped(.imgui);

const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfaceMeshStdData = @import("../models/surface/SurfaceMeshStdDatas.zig").SurfaceMeshStdData;
const DataGen = @import("../utils/Data.zig").DataGen;

const PointSphere = @import("../rendering/shaders/point_sphere/PointSphere.zig");
const PointSphereColorPerVertex = @import("../rendering/shaders/point_sphere_color_per_vertex/PointSphereColorPerVertex.zig");
const PointSphereScalarPerVertex = @import("../rendering/shaders/point_sphere_scalar_per_vertex/PointSphereScalarPerVertex.zig");
const LineBold = @import("../rendering/shaders/line_bold/LineBold.zig");
const TriFlat = @import("../rendering/shaders/tri_flat/TriFlat.zig");
const TriFlatColorPerVertex = @import("../rendering/shaders/tri_flat_color_per_vertex/TriFlatColorPerVertex.zig");
const TriFlatScalarPerVertex = @import("../rendering/shaders/tri_flat_scalar_per_vertex/TriFlatScalarPerVertex.zig");
const VBO = @import("../rendering/VBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;

const ColorDefinedOn = enum {
    global,
    vertex,
    edge,
    face,
};
const ColorType = enum {
    scalar,
    vector,
};
const ColorParameters = struct {
    defined_on: ColorDefinedOn,
    type: ColorType = .vector,
    vertex_vector_data: ?SurfaceMesh.CellData(.vertex, Vec3f) = null, // data used if definedOn is vertex & type is vector
    vertex_scalar_data: ?SurfaceMesh.CellData(.vertex, f32) = null, // data used if definedOn is vertex & type is scalar
    face_vector_data: ?SurfaceMesh.CellData(.face, Vec3f) = null, // data used if definedOn is face & type is vector
    face_scalar_data: ?SurfaceMesh.CellData(.face, f32) = null, // data used if definedOn is face & type is scalar
};

const SurfaceMeshRendererParameters = struct {
    point_sphere_shader_parameters: PointSphere.Parameters,
    point_sphere_color_per_vertex_shader_parameters: PointSphereColorPerVertex.Parameters,
    point_sphere_scalar_per_vertex_shader_parameters: PointSphereScalarPerVertex.Parameters,
    line_bold_shader_parameters: LineBold.Parameters,
    tri_flat_shader_parameters: TriFlat.Parameters,
    tri_flat_color_per_vertex_shader_parameters: TriFlatColorPerVertex.Parameters,
    tri_flat_scalar_per_vertex_shader_parameters: TriFlatScalarPerVertex.Parameters,
    boundary_shader_parameters: LineBold.Parameters,

    draw_vertices: bool = true,
    draw_edges: bool = true,
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
            .point_sphere_color_per_vertex_shader_parameters = PointSphereColorPerVertex.Parameters.init(),
            .point_sphere_scalar_per_vertex_shader_parameters = PointSphereScalarPerVertex.Parameters.init(),
            .line_bold_shader_parameters = LineBold.Parameters.init(),
            .tri_flat_shader_parameters = TriFlat.Parameters.init(),
            .tri_flat_color_per_vertex_shader_parameters = TriFlatColorPerVertex.Parameters.init(),
            .tri_flat_scalar_per_vertex_shader_parameters = TriFlatScalarPerVertex.Parameters.init(),
            .boundary_shader_parameters = LineBold.Parameters.init(),
        };
    }

    pub fn deinit(self: *SurfaceMeshRendererParameters) void {
        self.point_sphere_shader_parameters.deinit();
        self.point_sphere_color_per_vertex_shader_parameters.deinit();
        self.point_sphere_scalar_per_vertex_shader_parameters.deinit();
        self.line_bold_shader_parameters.deinit();
        self.tri_flat_shader_parameters.deinit();
        self.tri_flat_color_per_vertex_shader_parameters.deinit();
        self.tri_flat_scalar_per_vertex_shader_parameters.deinit();
        self.boundary_shader_parameters.deinit();
    }
};

module: Module = .{
    .name = "Surface Mesh Renderer",
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .surfaceMeshStdDataChanged = surfaceMeshStdDataChanged,
        .surfaceMeshDataUpdated = surfaceMeshDataUpdated,
        .draw = draw,
        .uiPanel = uiPanel,
    },
},
parameters: std.AutoHashMap(*SurfaceMesh, SurfaceMeshRendererParameters),

pub fn init(allocator: std.mem.Allocator) SurfaceMeshRenderer {
    return .{
        .parameters = .init(allocator),
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

/// Part of the Module interface.
/// Create and store a SurfaceMeshRendererParameters for the new SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smr: *SurfaceMeshRenderer = @alignCast(@fieldParentPtr("module", m));
    smr.parameters.put(surface_mesh, SurfaceMeshRendererParameters.init()) catch |err| {
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
                const position_vbo: VBO = zgp.surface_mesh_store.dataVBO(.vertex, Vec3f, vertex_position);
                p.point_sphere_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.point_sphere_color_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.point_sphere_scalar_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.line_bold_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_color_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_scalar_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.boundary_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            } else {
                p.point_sphere_shader_parameters.unsetVertexAttribArray(.position);
                p.point_sphere_color_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
                p.point_sphere_scalar_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
                p.line_bold_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_color_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_scalar_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
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
                // Not supported yet
                // const min, const max = p.draw_vertices_color.face_scalar_data.?.data.minMaxValues(.{}, compareScalar);
                // p.tri_flat_scalar_per_face_shader_parameters.min_value = min;
                // p.tri_flat_scalar_per_face_shader_parameters.max_value = max;
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
                var it = d.data.iterator();
                while (it.next()) |v| {
                    if (v.* < min) min = v.*;
                    if (v.* > max) max = v.*;
                }
            }
            switch (cell_type) {
                .vertex => {
                    p.draw_vertices_color.vertex_scalar_data = data;
                    if (p.draw_vertices_color.vertex_scalar_data) |scalar| {
                        const scalar_vbo = zgp.surface_mesh_store.dataVBO(.vertex, f32, scalar);
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
                    p.draw_vertices_color.vertex_vector_data = data;
                    if (p.draw_vertices_color.vertex_vector_data) |vector| {
                        const vector_vbo = zgp.surface_mesh_store.dataVBO(.vertex, Vec3f, vector);
                        p.point_sphere_color_per_vertex_shader_parameters.setVertexAttribArray(.color, vector_vbo, 0, 0);
                    } else {
                        p.point_sphere_color_per_vertex_shader_parameters.unsetVertexAttribArray(.color);
                    }
                },
                else => unreachable,
            }
        },
        else => @compileError("SurfaceMeshRenderer bad vertex color data type"),
    }
    zgp.requestRedraw();
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
                        const scalar_vbo = zgp.surface_mesh_store.dataVBO(.vertex, f32, scalar);
                        p.tri_flat_scalar_per_vertex_shader_parameters.setVertexAttribArray(.scalar, scalar_vbo, 0, 0);
                    } else {
                        p.tri_flat_scalar_per_vertex_shader_parameters.unsetVertexAttribArray(.scalar);
                    }
                    p.tri_flat_scalar_per_vertex_shader_parameters.min_value = min;
                    p.tri_flat_scalar_per_vertex_shader_parameters.max_value = max;
                },
                .face => {
                    p.draw_faces_color.face_scalar_data = data;
                    // Not supported yet
                    // if (p.draw_faces_color.face_scalar_data) |scalar| {
                    // const scalar_vbo = zgp.surface_mesh_store.dataVBO(.face, f32, scalar);
                    // p.tri_flat_scalar_per_face_shader_parameters.setVertexAttribArray(.scalar, scalar_vbo, 0, 0);
                    // } else {
                    // p.tri_flat_scalar_per_face_shader_parameters.unsetVertexAttribArray(.scalar);
                    // }
                    // p.tri_flat_scalar_per_face_shader_parameters.min_value = min;
                    // p.tri_flat_scalar_per_face_shader_parameters.max_value = max;
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
                    p.draw_faces_color.vertex_vector_data = data;
                    if (p.draw_faces_color.vertex_vector_data) |vector| {
                        const vector_vbo = zgp.surface_mesh_store.dataVBO(.vertex, Vec3f, vector);
                        p.tri_flat_color_per_vertex_shader_parameters.setVertexAttribArray(.color, vector_vbo, 0, 0);
                    } else {
                        p.tri_flat_color_per_vertex_shader_parameters.unsetVertexAttribArray(.color);
                    }
                },
                .face => {
                    p.draw_faces_color.face_vector_data = data;
                    // Not supported yet
                    // if (p.draw_faces_color.face_vector_data) |vector| {
                    // const vector_vbo = zgp.surface_mesh_store.dataVBO(.face, Vec3f, vector);
                    // p.tri_flat_color_per_face_shader_parameters.setVertexAttribArray(.color, vector_vbo, 0, 0);
                    // } else {
                    // p.tri_flat_color_per_face_shader_parameters.unsetVertexAttribArray(.color);
                    // }
                },
                else => unreachable,
            }
        },
        else => @compileError("SurfaceMeshRenderer bad color data type"),
    }
    zgp.requestRedraw();
}

/// Part of the Module interface.
/// Render all SurfaceMeshes with their SurfaceMeshRendererParameters and the given view and projection matrices.
pub fn draw(m: *Module, view_matrix: Mat4f, projection_matrix: Mat4f) void {
    const smr: *SurfaceMeshRenderer = @alignCast(@fieldParentPtr("module", m));
    var sm_it = zgp.surface_mesh_store.surface_meshes.iterator();
    while (sm_it.next()) |entry| {
        const sm = entry.value_ptr.*;
        const info = zgp.surface_mesh_store.surfaceMeshInfo(sm);
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
                        .vector => {
                            p.tri_flat_color_per_vertex_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                            p.tri_flat_color_per_vertex_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                            p.tri_flat_color_per_vertex_shader_parameters.draw(info.triangles_ibo);
                        },
                    }
                },
                .face => {
                    switch (p.draw_faces_color.type) {
                        .scalar => {
                            // Not supported yet
                            // TODO: write TriFlatScalarPerFaceShader
                        },
                        .vector => {
                            // Not supported yet
                            // TODO: write TriFlatColorPerFaceShader
                        },
                    }
                },
                else => unreachable,
            }
            gl.Disable(gl.POLYGON_OFFSET_FILL);
        }
        if (p.draw_edges) {
            p.line_bold_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            p.line_bold_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            p.line_bold_shader_parameters.draw(info.lines_ibo);
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
                        .vector => {
                            p.point_sphere_color_per_vertex_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                            p.point_sphere_color_per_vertex_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                            p.point_sphere_color_per_vertex_shader_parameters.draw(info.points_ibo);
                        },
                    }
                },
                else => unreachable,
            }
        }
        if (p.draw_boundaries) {
            p.boundary_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            p.boundary_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            p.boundary_shader_parameters.draw(info.boundaries_ibo);
        }
    }
}

/// Part of the Module interface.
/// Show a UI panel to control the SurfaceMeshRendererParameters of the selected SurfaceMesh.
pub fn uiPanel(m: *Module) void {
    const smr: *SurfaceMeshRenderer = @alignCast(@fieldParentPtr("module", m));

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (zgp.surface_mesh_store.selected_surface_mesh) |sm| {
        const p = smr.parameters.getPtr(sm).?;

        c.ImGui_SeparatorText("Vertices");
        if (c.ImGui_Checkbox("draw vertices", &p.draw_vertices)) {
            zgp.requestRedraw();
        }
        if (p.draw_vertices) {
            c.ImGui_Text("Size");
            c.ImGui_PushID("DrawVerticesSize");
            if (c.ImGui_SliderFloatEx("", &p.point_sphere_shader_parameters.point_size, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
                // sync value to other point sphere shaders
                p.point_sphere_scalar_per_vertex_shader_parameters.point_size = p.point_sphere_shader_parameters.point_size;
                p.point_sphere_color_per_vertex_shader_parameters.point_size = p.point_sphere_shader_parameters.point_size;
                zgp.requestRedraw();
            }
            c.ImGui_PopID();
            c.ImGui_Text("Color");
            {
                c.ImGui_BeginGroup();
                defer c.ImGui_EndGroup();
                if (c.ImGui_RadioButton("Global##DrawVerticesColorGlobal", p.draw_vertices_color.defined_on == .global)) {
                    p.draw_vertices_color.defined_on = .global;
                    zgp.requestRedraw();
                }
                c.ImGui_SameLine();
                if (c.ImGui_RadioButton("Per vertex##DrawVerticesColorPerVertex", p.draw_vertices_color.defined_on == .vertex)) {
                    p.draw_vertices_color.defined_on = .vertex;
                    zgp.requestRedraw();
                }
            }
            switch (p.draw_vertices_color.defined_on) {
                .global => {
                    if (c.ImGui_ColorEdit3("Global color##DrawVerticesColorGlobalEdit", &p.point_sphere_shader_parameters.point_color, c.ImGuiColorEditFlags_NoInputs)) {
                        zgp.requestRedraw();
                    }
                },
                .vertex => {
                    {
                        c.ImGui_BeginGroup();
                        defer c.ImGui_EndGroup();
                        if (c.ImGui_RadioButton("Scalar##DrawVerticesColorVertexScalar", p.draw_vertices_color.type == .scalar)) {
                            p.draw_vertices_color.type = .scalar;
                            zgp.requestRedraw();
                        }
                        c.ImGui_SameLine();
                        if (c.ImGui_RadioButton("Vector##DrawVerticesColorVertexVector", p.draw_vertices_color.type == .vector)) {
                            p.draw_vertices_color.type = .vector;
                            zgp.requestRedraw();
                        }
                    }
                    c.ImGui_PushID("DrawVerticesColorVertexData");
                    switch (p.draw_vertices_color.type) {
                        .scalar => if (imgui_utils.surfaceMeshCellDataComboBox(
                            sm,
                            .vertex,
                            f32,
                            p.draw_vertices_color.vertex_scalar_data,
                        )) |data| {
                            smr.setSurfaceMeshDrawVerticesColorData(sm, .vertex, f32, data);
                        },
                        .vector => if (imgui_utils.surfaceMeshCellDataComboBox(
                            sm,
                            .vertex,
                            Vec3f,
                            p.draw_vertices_color.vertex_vector_data,
                        )) |data| {
                            smr.setSurfaceMeshDrawVerticesColorData(sm, .vertex, Vec3f, data);
                        },
                    }
                    c.ImGui_PopID();
                },
                else => unreachable,
            }
        }

        c.ImGui_SeparatorText("Edges");
        if (c.ImGui_Checkbox("draw edges", &p.draw_edges)) {
            zgp.requestRedraw();
        }
        if (p.draw_edges) {
            c.ImGui_Text("Width");
            c.ImGui_PushID("DrawEdgesWidth");
            if (c.ImGui_SliderFloatEx("", &p.line_bold_shader_parameters.line_width, 0.1, 10.0, "%.1f", c.ImGuiSliderFlags_Logarithmic)) {
                zgp.requestRedraw();
            }
            c.ImGui_PopID();
            if (c.ImGui_ColorEdit4("Global color##DrawEdgesColorGlobalEdit", &p.line_bold_shader_parameters.line_color, c.ImGuiColorEditFlags_NoInputs)) {
                zgp.requestRedraw();
            }
        }

        c.ImGui_SeparatorText("Faces");
        if (c.ImGui_Checkbox("draw faces", &p.draw_faces)) {
            zgp.requestRedraw();
        }
        if (p.draw_faces) {
            c.ImGui_Text("Color");
            {
                c.ImGui_BeginGroup();
                defer c.ImGui_EndGroup();
                if (c.ImGui_RadioButton("Global##DrawFacesColorGlobal", p.draw_faces_color.defined_on == .global)) {
                    p.draw_faces_color.defined_on = .global;
                    zgp.requestRedraw();
                }
                c.ImGui_SameLine();
                if (c.ImGui_RadioButton("Per vertex##DrawFacesColorPerVertex", p.draw_faces_color.defined_on == .vertex)) {
                    p.draw_faces_color.defined_on = .vertex;
                    zgp.requestRedraw();
                }
                c.ImGui_SameLine();
                if (c.ImGui_RadioButton("Per face##DrawFacesColorPerFace", p.draw_faces_color.defined_on == .face)) {
                    p.draw_faces_color.defined_on = .face;
                    zgp.requestRedraw();
                }
            }
            switch (p.draw_faces_color.defined_on) {
                .global => {
                    if (c.ImGui_ColorEdit4("Global color##DrawFacesColorGlobalEdit", &p.tri_flat_shader_parameters.vertex_color, c.ImGuiColorEditFlags_NoInputs)) {
                        zgp.requestRedraw();
                    }
                },
                .vertex => {
                    {
                        c.ImGui_BeginGroup();
                        defer c.ImGui_EndGroup();
                        if (c.ImGui_RadioButton("Scalar##DrawFacesColorVertexScalar", p.draw_faces_color.type == .scalar)) {
                            p.draw_faces_color.type = .scalar;
                            zgp.requestRedraw();
                        }
                        c.ImGui_SameLine();
                        if (c.ImGui_RadioButton("Vector##DrawFacesColorVertexVector", p.draw_faces_color.type == .vector)) {
                            p.draw_faces_color.type = .vector;
                            zgp.requestRedraw();
                        }
                    }
                    c.ImGui_PushID("DrawFacesColorVertexData");
                    switch (p.draw_faces_color.type) {
                        .scalar => {
                            if (imgui_utils.surfaceMeshCellDataComboBox(
                                sm,
                                .vertex,
                                f32,
                                p.draw_faces_color.vertex_scalar_data,
                            )) |data| {
                                smr.setSurfaceMeshDrawFacesColorData(sm, .vertex, f32, data);
                            }
                            if (c.ImGui_Checkbox("Show isolines", &p.tri_flat_scalar_per_vertex_shader_parameters.show_isolines)) {
                                zgp.requestRedraw();
                            }
                            c.ImGui_Text("Nb isolines");
                            c.ImGui_PushID("NbIsolines");
                            if (c.ImGui_SliderInt("", &p.tri_flat_scalar_per_vertex_shader_parameters.nb_isolines, 1, 100)) {
                                zgp.requestRedraw();
                            }
                            c.ImGui_PopID();
                        },
                        .vector => if (imgui_utils.surfaceMeshCellDataComboBox(
                            sm,
                            .vertex,
                            Vec3f,
                            p.draw_faces_color.vertex_vector_data,
                        )) |data| {
                            smr.setSurfaceMeshDrawFacesColorData(sm, .vertex, Vec3f, data);
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
                            zgp.requestRedraw();
                        }
                        c.ImGui_SameLine();
                        if (c.ImGui_RadioButton("Vector##DrawFacesColorFaceVector", p.draw_faces_color.type == .vector)) {
                            p.draw_faces_color.type = .vector;
                            zgp.requestRedraw();
                        }
                    }
                    c.ImGui_PushID("DrawFacesColorFaceData");
                    switch (p.draw_faces_color.type) {
                        .scalar => if (imgui_utils.surfaceMeshCellDataComboBox(
                            sm,
                            .face,
                            f32,
                            p.draw_faces_color.face_scalar_data,
                        )) |data| {
                            smr.setSurfaceMeshDrawFacesColorData(sm, .face, f32, data);
                        },
                        .vector => if (imgui_utils.surfaceMeshCellDataComboBox(
                            sm,
                            .face,
                            Vec3f,
                            p.draw_faces_color.face_vector_data,
                        )) |data| {
                            smr.setSurfaceMeshDrawFacesColorData(sm, .face, Vec3f, data);
                        },
                    }
                    c.ImGui_PopID();
                },
                else => unreachable,
            }
        }

        c.ImGui_SeparatorText("Boundaries");
        if (c.ImGui_Checkbox("draw boundaries", &p.draw_boundaries)) {
            zgp.requestRedraw();
        }
        if (p.draw_boundaries) {
            c.ImGui_Text("Width");
            c.ImGui_PushID("DrawBoundariesWidth");
            if (c.ImGui_SliderFloatEx("", &p.boundary_shader_parameters.line_width, 0.1, 10.0, "%.1f", c.ImGuiSliderFlags_Logarithmic)) {
                zgp.requestRedraw();
            }
            c.ImGui_PopID();
            if (c.ImGui_ColorEdit4("Global color##DrawBoundariesColorGlobalEdit", &p.boundary_shader_parameters.line_color, c.ImGuiColorEditFlags_NoInputs)) {
                zgp.requestRedraw();
            }
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }
}
