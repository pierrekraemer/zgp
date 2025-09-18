const SurfaceMeshRenderer = @This();

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

const PointSphere = @import("../rendering/shaders/point_sphere/PointSphere.zig");
const PointSphereColorPerVertex = @import("../rendering/shaders/point_sphere_color_per_vertex/PointSphereColorPerVertex.zig");
const LineBold = @import("../rendering/shaders/line_bold/LineBold.zig");
const TriFlat = @import("../rendering/shaders/tri_flat/TriFlat.zig");
const TriFlatColorPerVertex = @import("../rendering/shaders/tri_flat_color_per_vertex/TriFlatColorPerVertex.zig");
const VBO = @import("../rendering/VBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3 = vec.Vec3;

const mat = @import("../geometry/mat.zig");
const Mat4 = mat.Mat4;

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
    vertex_vector_data: ?SurfaceMesh.CellData(.vertex, Vec3) = null, // data used if definedOn is vertex & type is vector
    vertex_scalar_data: ?SurfaceMesh.CellData(.vertex, f32) = null, // data used if definedOn is vertex & type is scalar
    face_vector_data: ?SurfaceMesh.CellData(.face, Vec3) = null, // data used if definedOn is face & type is vector
    face_scalar_data: ?SurfaceMesh.CellData(.face, f32) = null, // data used if definedOn is face & type is scalar
};

const SurfaceMeshRendererParameters = struct {
    point_sphere_shader_parameters: PointSphere.Parameters,
    point_sphere_color_per_vertex_shader_parameters: PointSphereColorPerVertex.Parameters,
    line_bold_shader_parameters: LineBold.Parameters,
    tri_flat_shader_parameters: TriFlat.Parameters,
    tri_flat_color_per_vertex_shader_parameters: TriFlatColorPerVertex.Parameters,

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
            .line_bold_shader_parameters = LineBold.Parameters.init(),
            .tri_flat_shader_parameters = TriFlat.Parameters.init(),
            .tri_flat_color_per_vertex_shader_parameters = TriFlatColorPerVertex.Parameters.init(),
        };
    }

    pub fn deinit(self: *SurfaceMeshRendererParameters) void {
        self.point_sphere_shader_parameters.deinit();
        self.point_sphere_color_per_vertex_shader_parameters.deinit();
        self.line_bold_shader_parameters.deinit();
        self.tri_flat_shader_parameters.deinit();
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

/// Return a Module interface for the SurfaceMeshRenderer.
pub fn module(smr: *SurfaceMeshRenderer) Module {
    return Module.init(smr);
}

/// Part of the Module interface.
/// Return the name of the module.
pub fn name(_: *SurfaceMeshRenderer) []const u8 {
    return "Surface Mesh Renderer";
}

/// Part of the Module interface.
/// Create and store a SurfaceMeshRendererParameters for the new SurfaceMesh.
pub fn surfaceMeshAdded(smr: *SurfaceMeshRenderer, surface_mesh: *SurfaceMesh) void {
    smr.parameters.put(surface_mesh, SurfaceMeshRendererParameters.init()) catch {
        std.debug.print("Failed to create SurfaceMeshRendererParameters for new SurfaceMesh\n", .{});
        return;
    };
}

/// Part of the Module interface.
/// Update the SurfaceMeshRendererParameters when a standard data of the SurfaceMesh changes.
pub fn surfaceMeshStdDataChanged(
    smr: *SurfaceMeshRenderer,
    surface_mesh: *SurfaceMesh,
    std_data: SurfaceMeshStdData,
) void {
    const p = smr.parameters.getPtr(surface_mesh) orelse return;
    switch (std_data) {
        .vertex_position => |maybe_vertex_position| {
            if (maybe_vertex_position) |vertex_position| {
                const position_vbo: VBO = zgp.models_registry.dataVBO(Vec3, vertex_position.data) catch {
                    std.debug.print("Failed to get VBO for vertex positions\n", .{});
                    return;
                };
                p.point_sphere_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.point_sphere_color_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.line_bold_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.tri_flat_color_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            } else {
                p.point_sphere_shader_parameters.unsetVertexAttribArray(.position);
                p.point_sphere_color_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
                p.line_bold_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_shader_parameters.unsetVertexAttribArray(.position);
                p.tri_flat_color_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
            }
        },
        else => return, // Ignore other standard data changes
    }
}

fn setSurfaceMeshDrawVerticesColorData(
    smr: *SurfaceMeshRenderer,
    surface_mesh: *SurfaceMesh,
    T: type,
    comptime cell_type: SurfaceMesh.CellType,
    data: ?SurfaceMesh.CellData(cell_type, T),
) void {
    const p = smr.parameters.getPtr(surface_mesh) orelse return;
    switch (@typeInfo(T)) {
        .float => {
            switch (cell_type) {
                .vertex => {
                    p.draw_vertices_color.vertex_scalar_data = data;
                    // Not supported yet
                    // if (p.draw_vertices_color.vertex_scalar_data) |scalar| {
                    // const scalar_vbo = zgp.models_registry.dataVBO(f32, scalar.data) catch {
                    //     imgui_log.err("Failed to get VBO for vertex scalar colors\n", .{});
                    //     return;
                    // };
                    // p.point_sphere_scalar_per_vertex_shader_parameters.setVertexAttribArray(.scalar, scalar_vbo, 0, 0);
                    // } else {
                    // p.point_sphere_scalar_per_vertex_shader_parameters.unsetVertexAttribArray(.scalar);
                    // }
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
                        const vector_vbo = zgp.models_registry.dataVBO(Vec3, vector.data) catch {
                            imgui_log.err("Failed to get VBO for vertex vector colors\n", .{});
                            return;
                        };
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
    T: type,
    comptime cell_type: SurfaceMesh.CellType,
    data: ?SurfaceMesh.CellData(cell_type, T),
) void {
    const p = smr.parameters.getPtr(surface_mesh) orelse return;
    switch (@typeInfo(T)) {
        .float => {
            switch (cell_type) {
                .vertex => {
                    p.draw_faces_color.vertex_scalar_data = data;
                    // Not supported yet
                    // if (p.draw_faces_color.vertex_scalar_data) |scalar| {
                    // const scalar_vbo = zgp.models_registry.dataVBO(f32, scalar.data) catch {
                    //     imgui_log.err("Failed to get VBO for vertex scalar colors\n", .{});
                    //     return;
                    // };
                    // p.tri_flat_scalar_per_vertex_shader_parameters.setVertexAttribArray(.scalar, scalar_vbo, 0, 0);
                    // } else {
                    // p.tri_flat_scalar_per_vertex_shader_parameters.unsetVertexAttribArray(.scalar);
                    // }
                },
                .face => {
                    p.draw_faces_color.face_scalar_data = data;
                    // Not supported yet
                    // if (p.draw_faces_color.face_scalar_data) |scalar| {
                    // const scalar_vbo = zgp.models_registry.dataVBO(f32, scalar.data) catch {
                    //     imgui_log.err("Failed to get VBO for face scalarcolors\n", .{});
                    //     return;
                    // };
                    // p.tri_flat_scalar_per_face_shader_parameters.setVertexAttribArray(.scalar, scalar_vbo, 0, 0);
                    // } else {
                    // p.tri_flat_scalar_per_face_shader_parameters.unsetVertexAttribArray(.scalar);
                    // }
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
                        const vector_vbo = zgp.models_registry.dataVBO(Vec3, vector.data) catch {
                            imgui_log.err("Failed to get VBO for vertex vector colors\n", .{});
                            return;
                        };
                        p.tri_flat_color_per_vertex_shader_parameters.setVertexAttribArray(.color, vector_vbo, 0, 0);
                    } else {
                        p.tri_flat_color_per_vertex_shader_parameters.unsetVertexAttribArray(.color);
                    }
                },
                .face => {
                    p.draw_faces_color.face_vector_data = data;
                    // Not supported yet
                    // if (p.draw_faces_color.face_vector_data) |vector| {
                    // const vector_vbo = zgp.models_registry.dataVBO(Vec3, vector.data) catch {
                    //     imgui_log.err("Failed to get VBO for faces vector colors\n", .{});
                    //     return;
                    // };
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
pub fn draw(smr: *SurfaceMeshRenderer, view_matrix: Mat4, projection_matrix: Mat4) void {
    var sm_it = zgp.models_registry.surface_meshes.iterator();
    while (sm_it.next()) |entry| {
        const sm = entry.value_ptr.*;
        const info = zgp.models_registry.surfaceMeshInfo(sm);
        const p = smr.parameters.getPtr(sm) orelse continue;
        if (p.draw_faces) {
            switch (p.draw_faces_color.defined_on) {
                .global => {
                    p.tri_flat_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                    p.tri_flat_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                    p.tri_flat_shader_parameters.draw(info.triangles_ibo);
                },
                .vertex => {
                    switch (p.draw_faces_color.type) {
                        .scalar => {
                            // Not supported yet
                            // TODO: write TriFlatScalarPerVertexShader
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
                            // Not supported yet
                            // TODO: write PointSphereScalarPerVertexShader
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
            p.line_bold_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            p.line_bold_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            p.line_bold_shader_parameters.line_color = .{ 1.0, 0.0, 0.0, 1.0 }; // Red for boundaries
            p.line_bold_shader_parameters.draw(info.boundaries_ibo);
        }
    }
}

/// Part of the Module interface.
/// Show a UI panel to control the SurfaceMeshRendererParameters of the selected SurfaceMesh.
pub fn uiPanel(smr: *SurfaceMeshRenderer) void {
    const UiCB = struct {
        const ColorDataSelectedContext = struct {
            surface_mesh_renderer: *SurfaceMeshRenderer,
            surface_mesh: *SurfaceMesh,
            draw_cell_type: SurfaceMesh.CellType, // .vertex or .face
        };
        fn onColorDataSelected(
            comptime cell_type: SurfaceMesh.CellType,
            comptime T: type,
            data: ?SurfaceMesh.CellData(cell_type, T),
            ctx: ColorDataSelectedContext,
        ) void {
            switch (ctx.draw_cell_type) {
                .vertex => ctx.surface_mesh_renderer.setSurfaceMeshDrawVerticesColorData(ctx.surface_mesh, T, cell_type, data),
                .face => ctx.surface_mesh_renderer.setSurfaceMeshDrawFacesColorData(ctx.surface_mesh, T, cell_type, data),
                else => unreachable,
            }
        }
    };

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - c.ImGui_GetStyle().*.ItemSpacing.x * 2);

    if (zgp.models_registry.selected_surface_mesh) |sm| {
        const surface_mesh_renderer_parameters = smr.parameters.getPtr(sm);
        if (surface_mesh_renderer_parameters) |p| {
            c.ImGui_SeparatorText("Vertices");
            if (c.ImGui_Checkbox("draw vertices", &p.draw_vertices)) {
                zgp.requestRedraw();
            }
            if (p.draw_vertices) {
                c.ImGui_Text("Size");
                c.ImGui_PushID("DrawVerticesSize");
                if (c.ImGui_SliderFloatEx("", &p.point_sphere_shader_parameters.point_size, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
                    // sync value to color per vertex shader
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
                            .scalar => imgui_utils.surfaceMeshCellDataComboBox(
                                sm,
                                .vertex,
                                f32,
                                p.draw_vertices_color.vertex_scalar_data,
                                UiCB.ColorDataSelectedContext{ .surface_mesh_renderer = smr, .surface_mesh = sm, .draw_cell_type = .vertex },
                                &UiCB.onColorDataSelected,
                            ),
                            .vector => imgui_utils.surfaceMeshCellDataComboBox(
                                sm,
                                .vertex,
                                Vec3,
                                p.draw_vertices_color.vertex_vector_data,
                                UiCB.ColorDataSelectedContext{ .surface_mesh_renderer = smr, .surface_mesh = sm, .draw_cell_type = .vertex },
                                &UiCB.onColorDataSelected,
                            ),
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
                            .scalar => imgui_utils.surfaceMeshCellDataComboBox(
                                sm,
                                .vertex,
                                f32,
                                p.draw_faces_color.vertex_scalar_data,
                                UiCB.ColorDataSelectedContext{ .surface_mesh_renderer = smr, .surface_mesh = sm, .draw_cell_type = .face },
                                &UiCB.onColorDataSelected,
                            ),
                            .vector => imgui_utils.surfaceMeshCellDataComboBox(
                                sm,
                                .vertex,
                                Vec3,
                                p.draw_faces_color.vertex_vector_data,
                                UiCB.ColorDataSelectedContext{ .surface_mesh_renderer = smr, .surface_mesh = sm, .draw_cell_type = .face },
                                &UiCB.onColorDataSelected,
                            ),
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
                            .scalar => imgui_utils.surfaceMeshCellDataComboBox(
                                sm,
                                .face,
                                f32,
                                p.draw_faces_color.face_scalar_data,
                                UiCB.ColorDataSelectedContext{ .surface_mesh_renderer = smr, .surface_mesh = sm, .draw_cell_type = .face },
                                &UiCB.onColorDataSelected,
                            ),
                            .vector => imgui_utils.surfaceMeshCellDataComboBox(
                                sm,
                                .face,
                                Vec3,
                                p.draw_faces_color.face_vector_data,
                                UiCB.ColorDataSelectedContext{ .surface_mesh_renderer = smr, .surface_mesh = sm, .draw_cell_type = .face },
                                &UiCB.onColorDataSelected,
                            ),
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
        } else {
            c.ImGui_Text("No parameters found for the selected Surface Mesh");
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }

    c.ImGui_PopItemWidth();
}
