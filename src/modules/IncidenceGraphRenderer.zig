const IncidenceGraphRenderer = @This();

const std = @import("std");
const assert = std.debug.assert;
const gl = @import("gl");

const c = @import("../main.zig").c;

const imgui_utils = @import("../ui/imgui.zig");
const imgui_log = std.log.scoped(.imgui);

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const IncidenceGraph = @import("../models/incidenceGraph/IncidenceGraph.zig");
const IncidenceGraphStdData = @import("../models/IncidenceGraphStore.zig").IncidenceGraphStdData;
const DataGen = @import("../utils/data.zig").DataGen;

const PointSphere = @import("../rendering/shaders/point_sphere/PointSphere.zig");
const PointSphereColorPerVertex = @import("../rendering/shaders/point_sphere_color_per_vertex/PointSphereColorPerVertex.zig");
const PointSphereScalarPerVertex = @import("../rendering/shaders/point_sphere_scalar_per_vertex/PointSphereScalarPerVertex.zig");
const LineCylinder = @import("../rendering/shaders/line_cylinder/LineCylinder.zig");
const TriFlat = @import("../rendering/shaders/tri_flat/TriFlat.zig");
const TriFlatColorPerVertex = @import("../rendering/shaders/tri_flat_color_per_vertex/TriFlatColorPerVertex.zig");
const TriFlatScalarPerVertex = @import("../rendering/shaders/tri_flat_scalar_per_vertex/TriFlatScalarPerVertex.zig");
const TriFlatColorPerFace = @import("../rendering/shaders/tri_flat_color_per_face/TriFlatColorPerFace.zig");
const TriFlatScalarPerFace = @import("../rendering/shaders/tri_flat_scalar_per_face/TriFlatScalarPerFace.zig");
const VBO = @import("../rendering/VBO.zig");

const eigen = @import("../geometry/eigen.zig");
const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;

const ColorDefinedOn = enum {
    global,
    vertex,
    face,
};
const ColorType = enum {
    scalar,
    vector,
};
const ColorParameters = struct {
    defined_on: ColorDefinedOn,
    type: ColorType = .vector,
    vertex_vector_data: ?IncidenceGraph.CellData(.vertex, Vec3f) = null, // data used if definedOn is vertex & type is vector
    vertex_scalar_data: ?IncidenceGraph.CellData(.vertex, f32) = null, // data used if definedOn is vertex & type is scalar
    face_vector_data: ?IncidenceGraph.CellData(.face, Vec3f) = null, // data used if definedOn is face & type is vector
    face_scalar_data: ?IncidenceGraph.CellData(.face, f32) = null, // data used if definedOn is face & type is scalar
};

const IncidenceGraphRendererParameters = struct {
    point_sphere_shader_parameters: PointSphere.Parameters,
    point_sphere_color_per_vertex_shader_parameters: PointSphereColorPerVertex.Parameters,
    point_sphere_scalar_per_vertex_shader_parameters: PointSphereScalarPerVertex.Parameters,
    line_cylinder_shader_parameters: LineCylinder.Parameters,
    tri_flat_shader_parameters: TriFlat.Parameters,
    tri_flat_color_per_vertex_shader_parameters: TriFlatColorPerVertex.Parameters,
    tri_flat_scalar_per_vertex_shader_parameters: TriFlatScalarPerVertex.Parameters,
    tri_flat_color_per_face_shader_parameters: TriFlatColorPerFace.Parameters,
    tri_flat_scalar_per_face_shader_parameters: TriFlatScalarPerFace.Parameters,

    draw_vertices: bool = true,
    draw_edges: bool = true,
    draw_faces: bool = true,

    draw_vertices_color: ColorParameters = .{
        .defined_on = .global, // authorized values: global, vertex
    },
    draw_faces_color: ColorParameters = .{
        .defined_on = .global, // authorized values: global, vertex, face
    },

    pub fn init() IncidenceGraphRendererParameters {
        var parameters: IncidenceGraphRendererParameters = .{
            .point_sphere_shader_parameters = PointSphere.Parameters.init(),
            .point_sphere_color_per_vertex_shader_parameters = PointSphereColorPerVertex.Parameters.init(),
            .point_sphere_scalar_per_vertex_shader_parameters = PointSphereScalarPerVertex.Parameters.init(),
            .line_cylinder_shader_parameters = LineCylinder.Parameters.init(),
            .tri_flat_shader_parameters = TriFlat.Parameters.init(),
            .tri_flat_color_per_vertex_shader_parameters = TriFlatColorPerVertex.Parameters.init(),
            .tri_flat_scalar_per_vertex_shader_parameters = TriFlatScalarPerVertex.Parameters.init(),
            .tri_flat_color_per_face_shader_parameters = TriFlatColorPerFace.Parameters.init(),
            .tri_flat_scalar_per_face_shader_parameters = TriFlatScalarPerFace.Parameters.init(),
        };
        parameters.tri_flat_shader_parameters.dim_backfaces = false;
        parameters.tri_flat_color_per_vertex_shader_parameters.dim_backfaces = false;
        parameters.tri_flat_scalar_per_vertex_shader_parameters.dim_backfaces = false;
        parameters.tri_flat_color_per_face_shader_parameters.dim_backfaces = false;
        parameters.tri_flat_scalar_per_face_shader_parameters.dim_backfaces = false;
        return parameters;
    }

    pub fn deinit(self: *IncidenceGraphRendererParameters) void {
        self.point_sphere_shader_parameters.deinit();
        self.point_sphere_color_per_vertex_shader_parameters.deinit();
        self.point_sphere_scalar_per_vertex_shader_parameters.deinit();
        self.line_cylinder_shader_parameters.deinit();
        self.tri_flat_shader_parameters.deinit();
        self.tri_flat_color_per_vertex_shader_parameters.deinit();
        self.tri_flat_scalar_per_vertex_shader_parameters.deinit();
        self.tri_flat_color_per_face_shader_parameters.deinit();
        self.tri_flat_scalar_per_face_shader_parameters.deinit();
    }
};

app_ctx: *AppContext,
module: Module = .{
    .name = "Incidence Graph Renderer",
    .supported_models = .{ .incidence_graph = true },
    .vtable = &.{
        .incidenceGraphCreated = incidenceGraphCreated,
        .incidenceGraphDestroyed = incidenceGraphDestroyed,
        .incidenceGraphStdDataChanged = incidenceGraphStdDataChanged,
        .incidenceGraphDataUpdated = incidenceGraphDataUpdated,
        .draw = draw,
        .rightPanel = rightPanel,
    },
},
parameters: std.AutoHashMap(*IncidenceGraph, IncidenceGraphRendererParameters),

pub fn init(app_ctx: *AppContext) IncidenceGraphRenderer {
    return .{
        .app_ctx = app_ctx,
        .parameters = .init(app_ctx.allocator),
    };
}

pub fn deinit(smr: *IncidenceGraphRenderer) void {
    var p_it = smr.parameters.iterator();
    while (p_it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    smr.parameters.deinit();
}

/// Part of the Module interface.
/// Create and store a IncidenceGraphRendererParameters for the new IncidenceGraph.
pub fn incidenceGraphCreated(m: *Module, incidence_graph: *IncidenceGraph) void {
    const igr: *IncidenceGraphRenderer = @alignCast(@fieldParentPtr("module", m));
    igr.parameters.put(incidence_graph, IncidenceGraphRendererParameters.init()) catch |err| {
        std.debug.print("Failed to create IncidenceGraphRendererParameters for new IncidenceGraph: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Destroy the IncidenceGraphRendererParameters associated to the destroyed IncidenceGraph.
pub fn incidenceGraphDestroyed(m: *Module, incidence_graph: *IncidenceGraph) void {
    const igr: *IncidenceGraphRenderer = @alignCast(@fieldParentPtr("module", m));
    const p = igr.parameters.getPtr(incidence_graph) orelse return;
    p.deinit();
    _ = igr.parameters.remove(incidence_graph);
}

/// Part of the Module interface.
/// Update the IncidenceGraphRendererParameters when a standard data of the IncidenceGraph changes.
pub fn incidenceGraphStdDataChanged(
    m: *Module,
    incidence_graph: *IncidenceGraph,
    std_data: IncidenceGraphStdData,
) void {
    const igr: *IncidenceGraphRenderer = @alignCast(@fieldParentPtr("module", m));
    const p = igr.parameters.getPtr(incidence_graph) orelse return;
    switch (std_data) {
        .vertex_position => |maybe_vertex_position| {
            if (maybe_vertex_position) |vertex_position| {
                const position_vbo: VBO = igr.app_ctx.incidence_graph_store.dataVBO(.vertex, Vec3f, vertex_position);
                p.point_sphere_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.point_sphere_color_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.point_sphere_scalar_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.line_cylinder_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_color_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_scalar_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_color_per_face_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_scalar_per_face_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            } else {
                p.point_sphere_shader_parameters.unsetVertexAttribArray(.position);
                p.point_sphere_color_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
                p.point_sphere_scalar_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
                p.line_cylinder_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_color_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_scalar_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_color_per_face_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_scalar_per_face_shader_parameters.unsetVertexAttribArray(.position);
            }
        },
    }
}

const CompareScalarContext = struct {};
fn compareScalar(_: CompareScalarContext, a: f32, b: f32) std.math.Order {
    return std.math.order(a, b);
}

/// Part of the Module interface.
/// Check if the updated data is used here for coloring and update the associated min/max values.
pub fn incidenceGraphDataUpdated(
    m: *Module,
    incidence_graph: *IncidenceGraph,
    cell_type: IncidenceGraph.CellType,
    data_gen: *const DataGen,
) void {
    const igr: *IncidenceGraphRenderer = @alignCast(@fieldParentPtr("module", m));
    const p = igr.parameters.getPtr(incidence_graph) orelse return;
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

fn setIncidenceGraphDrawVerticesColorData(
    igr: *IncidenceGraphRenderer,
    incidence_graph: *IncidenceGraph,
    comptime cell_type: IncidenceGraph.CellType,
    T: type,
    data: ?IncidenceGraph.CellData(cell_type, T),
) void {
    const p = igr.parameters.getPtr(incidence_graph) orelse return;
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
                        const scalar_vbo = igr.app_ctx.incidence_graph_store.dataVBO(.vertex, f32, scalar);
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
                @compileError("IncidenceGraphRenderer bad vertex color data type");
            }
            switch (cell_type) {
                .vertex => {
                    p.draw_vertices_color.vertex_vector_data = data;
                    if (p.draw_vertices_color.vertex_vector_data) |vector| {
                        const vector_vbo = igr.app_ctx.incidence_graph_store.dataVBO(.vertex, Vec3f, vector);
                        p.point_sphere_color_per_vertex_shader_parameters.setVertexAttribArray(.color, vector_vbo, 0, 0);
                    } else {
                        p.point_sphere_color_per_vertex_shader_parameters.unsetVertexAttribArray(.color);
                    }
                },
                else => unreachable,
            }
        },
        else => @compileError("IncidenceGraphRenderer bad vertex color data type"),
    }
    igr.app_ctx.requestRedraw();
}

fn setIncidenceGraphDrawFacesColorData(
    igr: *IncidenceGraphRenderer,
    incidence_graph: *IncidenceGraph,
    comptime cell_type: IncidenceGraph.CellType,
    T: type,
    data: ?IncidenceGraph.CellData(cell_type, T),
) void {
    const p = igr.parameters.getPtr(incidence_graph) orelse return;
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
                        const scalar_vbo = igr.app_ctx.incidence_graph_store.dataVBO(.vertex, f32, scalar);
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
                        const scalar_vbo = igr.app_ctx.incidence_graph_store.dataVBO(.face, f32, scalar);
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
                @compileError("IncidenceGraphRenderer bad color data type");
            }
            switch (cell_type) {
                .vertex => {
                    p.draw_faces_color.vertex_vector_data = data;
                    if (p.draw_faces_color.vertex_vector_data) |vector| {
                        const vector_vbo = igr.app_ctx.incidence_graph_store.dataVBO(.vertex, Vec3f, vector);
                        p.tri_flat_color_per_vertex_shader_parameters.setVertexAttribArray(.color, vector_vbo, 0, 0);
                    } else {
                        p.tri_flat_color_per_vertex_shader_parameters.unsetVertexAttribArray(.color);
                    }
                },
                .face => {
                    p.draw_faces_color.face_vector_data = data;
                    if (p.draw_faces_color.face_vector_data) |vector| {
                        const vector_vbo = igr.app_ctx.incidence_graph_store.dataVBO(.face, Vec3f, vector);
                        p.tri_flat_color_per_face_shader_parameters.face_color_buffer = vector_vbo;
                    } else {
                        p.tri_flat_color_per_face_shader_parameters.face_color_buffer = null;
                    }
                },
                else => unreachable,
            }
        },
        else => @compileError("IncidenceGraphRenderer bad color data type"),
    }
    igr.app_ctx.requestRedraw();
}

/// Part of the Module interface.
/// Render all IncidenceGraphs with their IncidenceGraphRendererParameters and the given view and projection matrices.
pub fn draw(m: *Module, view_matrix: Mat4f, projection_matrix: Mat4f) void {
    const igr: *IncidenceGraphRenderer = @alignCast(@fieldParentPtr("module", m));
    var ig_it = igr.app_ctx.incidence_graph_store.incidence_graphs.iterator();
    while (ig_it.next()) |entry| {
        const ig = entry.value_ptr.*;
        const info = igr.app_ctx.incidence_graph_store.incidenceGraphInfo(ig);
        const p = igr.parameters.getPtr(ig).?;
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
                            p.tri_flat_scalar_per_face_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                            p.tri_flat_scalar_per_face_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                            p.tri_flat_scalar_per_face_shader_parameters.draw(info.triangles_ibo);
                        },
                        .vector => {
                            p.tri_flat_color_per_face_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                            p.tri_flat_color_per_face_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                            p.tri_flat_color_per_face_shader_parameters.draw(info.triangles_ibo);
                        },
                    }
                },
            }
            gl.Disable(gl.POLYGON_OFFSET_FILL);
        }
        if (p.draw_edges) {
            gl.Enable(gl.CULL_FACE);
            gl.CullFace(gl.BACK);
            p.line_cylinder_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            p.line_cylinder_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            p.line_cylinder_shader_parameters.draw(info.lines_ibo);
            gl.Disable(gl.CULL_FACE);
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
    }
}

/// Part of the Module interface.
/// Show a UI panel to control the IncidenceGraphRendererParameters of the selected IncidenceGraph.
pub fn rightPanel(m: *Module) void {
    const igr: *IncidenceGraphRenderer = @alignCast(@fieldParentPtr("module", m));

    assert(igr.app_ctx.selected_model.modelType() == .incidence_graph);
    const ig = igr.app_ctx.selected_model.incidence_graph;

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const p = igr.parameters.getPtr(ig).?;

    c.ImGui_SeparatorText("Vertices");
    if (c.ImGui_Checkbox("draw vertices", &p.draw_vertices)) {
        igr.app_ctx.requestRedraw();
    }
    if (p.draw_vertices) {
        c.ImGui_Text("Size");
        c.ImGui_PushID("DrawVerticesSize");
        if (c.ImGui_SliderFloatEx("", &p.point_sphere_shader_parameters.sphere_radius, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
            // sync value to other point sphere shaders
            p.point_sphere_scalar_per_vertex_shader_parameters.sphere_radius = p.point_sphere_shader_parameters.sphere_radius;
            p.point_sphere_color_per_vertex_shader_parameters.sphere_radius = p.point_sphere_shader_parameters.sphere_radius;
            igr.app_ctx.requestRedraw();
        }
        c.ImGui_PopID();
        c.ImGui_Text("Color");
        {
            c.ImGui_BeginGroup();
            defer c.ImGui_EndGroup();
            if (c.ImGui_RadioButton("Global##DrawVerticesColorGlobal", p.draw_vertices_color.defined_on == .global)) {
                p.draw_vertices_color.defined_on = .global;
                igr.app_ctx.requestRedraw();
            }
            c.ImGui_SameLine();
            if (c.ImGui_RadioButton("Per vertex##DrawVerticesColorPerVertex", p.draw_vertices_color.defined_on == .vertex)) {
                p.draw_vertices_color.defined_on = .vertex;
                igr.app_ctx.requestRedraw();
            }
        }
        switch (p.draw_vertices_color.defined_on) {
            .global => {
                if (c.ImGui_ColorEdit3("Global color##DrawVerticesColorGlobalEdit", &p.point_sphere_shader_parameters.sphere_color, c.ImGuiColorEditFlags_NoInputs)) {
                    igr.app_ctx.requestRedraw();
                }
            },
            .vertex => {
                {
                    c.ImGui_BeginGroup();
                    defer c.ImGui_EndGroup();
                    if (c.ImGui_RadioButton("Scalar##DrawVerticesColorVertexScalar", p.draw_vertices_color.type == .scalar)) {
                        p.draw_vertices_color.type = .scalar;
                        igr.app_ctx.requestRedraw();
                    }
                    c.ImGui_SameLine();
                    if (c.ImGui_RadioButton("Vector##DrawVerticesColorVertexVector", p.draw_vertices_color.type == .vector)) {
                        p.draw_vertices_color.type = .vector;
                        igr.app_ctx.requestRedraw();
                    }
                }
                c.ImGui_PushID("DrawVerticesColorVertexData");
                switch (p.draw_vertices_color.type) {
                    .scalar => switch (imgui_utils.incidenceGraphCellDataComboBox(ig, .vertex, f32, p.draw_vertices_color.vertex_scalar_data)) {
                        .unchanged => {},
                        .cleared => igr.setIncidenceGraphDrawVerticesColorData(ig, .vertex, f32, null),
                        .changed => |data| igr.setIncidenceGraphDrawVerticesColorData(ig, .vertex, f32, data),
                    },
                    .vector => switch (imgui_utils.incidenceGraphCellDataComboBox(ig, .vertex, Vec3f, p.draw_vertices_color.vertex_vector_data)) {
                        .unchanged => {},
                        .cleared => igr.setIncidenceGraphDrawVerticesColorData(ig, .vertex, Vec3f, null),
                        .changed => |data| igr.setIncidenceGraphDrawVerticesColorData(ig, .vertex, Vec3f, data),
                    },
                }
                c.ImGui_PopID();
            },
            else => unreachable,
        }
    }

    c.ImGui_SeparatorText("Edges");
    if (c.ImGui_Checkbox("draw edges", &p.draw_edges)) {
        igr.app_ctx.requestRedraw();
    }
    if (p.draw_edges) {
        c.ImGui_Text("Width");
        c.ImGui_PushID("DrawEdgesWidth");
        if (c.ImGui_SliderFloatEx("", &p.line_cylinder_shader_parameters.cylinder_radius, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
            igr.app_ctx.requestRedraw();
        }
        c.ImGui_PopID();
        if (c.ImGui_ColorEdit4("Global color##DrawEdgesColorGlobalEdit", &p.line_cylinder_shader_parameters.cylinder_color, c.ImGuiColorEditFlags_NoInputs)) {
            igr.app_ctx.requestRedraw();
        }
    }

    c.ImGui_SeparatorText("Faces");
    if (c.ImGui_Checkbox("draw faces", &p.draw_faces)) {
        igr.app_ctx.requestRedraw();
    }
    if (p.draw_faces) {
        c.ImGui_Text("Color");
        {
            c.ImGui_BeginGroup();
            defer c.ImGui_EndGroup();
            if (c.ImGui_RadioButton("Global##DrawFacesColorGlobal", p.draw_faces_color.defined_on == .global)) {
                p.draw_faces_color.defined_on = .global;
                igr.app_ctx.requestRedraw();
            }
            c.ImGui_SameLine();
            if (c.ImGui_RadioButton("Per vertex##DrawFacesColorPerVertex", p.draw_faces_color.defined_on == .vertex)) {
                p.draw_faces_color.defined_on = .vertex;
                igr.app_ctx.requestRedraw();
            }
            c.ImGui_SameLine();
            if (c.ImGui_RadioButton("Per face##DrawFacesColorPerFace", p.draw_faces_color.defined_on == .face)) {
                p.draw_faces_color.defined_on = .face;
                igr.app_ctx.requestRedraw();
            }
        }
        switch (p.draw_faces_color.defined_on) {
            .global => {
                if (c.ImGui_ColorEdit4("Global color##DrawFacesColorGlobalEdit", &p.tri_flat_shader_parameters.vertex_color, c.ImGuiColorEditFlags_NoInputs)) {
                    igr.app_ctx.requestRedraw();
                }
            },
            .vertex => {
                {
                    c.ImGui_BeginGroup();
                    defer c.ImGui_EndGroup();
                    if (c.ImGui_RadioButton("Scalar##DrawFacesColorVertexScalar", p.draw_faces_color.type == .scalar)) {
                        p.draw_faces_color.type = .scalar;
                        igr.app_ctx.requestRedraw();
                    }
                    c.ImGui_SameLine();
                    if (c.ImGui_RadioButton("Vector##DrawFacesColorVertexVector", p.draw_faces_color.type == .vector)) {
                        p.draw_faces_color.type = .vector;
                        igr.app_ctx.requestRedraw();
                    }
                }
                c.ImGui_PushID("DrawFacesColorVertexData");
                switch (p.draw_faces_color.type) {
                    .scalar => {
                        switch (imgui_utils.incidenceGraphCellDataComboBox(ig, .vertex, f32, p.draw_faces_color.vertex_scalar_data)) {
                            .unchanged => {},
                            .cleared => igr.setIncidenceGraphDrawFacesColorData(ig, .vertex, f32, null),
                            .changed => |data| igr.setIncidenceGraphDrawFacesColorData(ig, .vertex, f32, data),
                        }
                        if (c.ImGui_Checkbox("Draw isolines", &p.tri_flat_scalar_per_vertex_shader_parameters.draw_isolines)) {
                            igr.app_ctx.requestRedraw();
                        }
                        c.ImGui_Text("Nb isolines");
                        c.ImGui_PushID("NbIsolines");
                        if (c.ImGui_SliderInt("", &p.tri_flat_scalar_per_vertex_shader_parameters.nb_isolines, 1, 100)) {
                            igr.app_ctx.requestRedraw();
                        }
                        c.ImGui_PopID();
                    },
                    .vector => switch (imgui_utils.incidenceGraphCellDataComboBox(ig, .vertex, Vec3f, p.draw_faces_color.vertex_vector_data)) {
                        .unchanged => {},
                        .cleared => igr.setIncidenceGraphDrawFacesColorData(ig, .vertex, Vec3f, null),
                        .changed => |data| igr.setIncidenceGraphDrawFacesColorData(ig, .vertex, Vec3f, data),
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
                        igr.app_ctx.requestRedraw();
                    }
                    c.ImGui_SameLine();
                    if (c.ImGui_RadioButton("Vector##DrawFacesColorFaceVector", p.draw_faces_color.type == .vector)) {
                        p.draw_faces_color.type = .vector;
                        igr.app_ctx.requestRedraw();
                    }
                }
                c.ImGui_PushID("DrawFacesColorFaceData");
                switch (p.draw_faces_color.type) {
                    .scalar => switch (imgui_utils.incidenceGraphCellDataComboBox(ig, .face, f32, p.draw_faces_color.face_scalar_data)) {
                        .unchanged => {},
                        .cleared => igr.setIncidenceGraphDrawFacesColorData(ig, .face, f32, null),
                        .changed => |data| igr.setIncidenceGraphDrawFacesColorData(ig, .face, f32, data),
                    },
                    .vector => switch (imgui_utils.incidenceGraphCellDataComboBox(ig, .face, Vec3f, p.draw_faces_color.face_vector_data)) {
                        .unchanged => {},
                        .cleared => igr.setIncidenceGraphDrawFacesColorData(ig, .face, Vec3f, null),
                        .changed => |data| igr.setIncidenceGraphDrawFacesColorData(ig, .face, Vec3f, data),
                    },
                }
                c.ImGui_PopID();
            },
        }
    }
}
