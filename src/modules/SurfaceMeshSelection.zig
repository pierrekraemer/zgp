const SurfaceMeshSelection = @This();

const std = @import("std");
const gl = @import("gl");
const assert = std.debug.assert;

const zgp_log = std.log.scoped(.zgp);

const c = @import("../main.zig").c;

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfaceMeshStdData = @import("../models/SurfaceMeshStore.zig").SurfaceMeshStdData;

const PointSphere = @import("../rendering/shaders/point_sphere/PointSphere.zig");
const LineCylinder = @import("../rendering/shaders/line_cylinder/LineCylinder.zig");
const TriFlat = @import("../rendering/shaders/tri_flat/TriFlat.zig");
const VBO = @import("../rendering/VBO.zig");
const IBO = @import("../rendering/IBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;

const SelectionData = struct {
    point_sphere_shader_parameters: PointSphere.Parameters,
    line_cylinder_shader_parameters: LineCylinder.Parameters,
    tri_flat_shader_parameters: TriFlat.Parameters,

    pub fn init() SelectionData {
        var p = PointSphere.Parameters.init();
        p.sphere_radius = 0.002;
        p.sphere_color = .{ 0.0, 1.0, 0.0, 1.0 };
        var l = LineCylinder.Parameters.init();
        l.cylinder_radius = 0.001;
        l.cylinder_color = .{ 0.0, 1.0, 0.0, 1.0 };
        var t = TriFlat.Parameters.init();
        t.vertex_color = .{ 0.0, 1.0, 0.0, 1.0 };
        return .{
            .point_sphere_shader_parameters = p,
            .line_cylinder_shader_parameters = l,
            .tri_flat_shader_parameters = t,
        };
    }

    pub fn deinit(sd: *SelectionData) void {
        sd.point_sphere_shader_parameters.deinit();
        sd.line_cylinder_shader_parameters.deinit();
        sd.tri_flat_shader_parameters.deinit();
    }
};

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Selection",
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .surfaceMeshStdDataChanged = surfaceMeshStdDataChanged,
        .draw = draw,
        .sdlEvent = sdlEvent,
        .rightPanel = rightPanel,
    },
},
surface_meshes_data: std.AutoHashMap(*SurfaceMesh, SelectionData),

selecting: bool = false,
selecting_cell_type: SurfaceMesh.CellType = .vertex,
hovered_cell: ?SurfaceMesh.Cell = null,
hovered_cell_ibo: IBO,

pub fn init(app_ctx: *AppContext) SurfaceMeshSelection {
    return .{
        .app_ctx = app_ctx,
        .surface_meshes_data = .init(app_ctx.allocator),
        .hovered_cell_ibo = .init(),
    };
}

pub fn deinit(sms: *SurfaceMeshSelection) void {
    var smdata_it = sms.surface_meshes_data.iterator();
    while (smdata_it.next()) |entry| {
        var d = entry.value_ptr.*;
        d.deinit();
    }
    sms.surface_meshes_data.deinit();
}

/// Part of the Module interface.
/// Create and store a SelectionData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const sms: *SurfaceMeshSelection = @alignCast(@fieldParentPtr("module", m));
    sms.surface_meshes_data.put(surface_mesh, SelectionData.init()) catch |err| {
        std.debug.print("Failed to store SelectionData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Remove the SelectionData associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const sms: *SurfaceMeshSelection = @alignCast(@fieldParentPtr("module", m));
    const sd = sms.surface_meshes_data.getPtr(surface_mesh) orelse return;
    sd.deinit();
    _ = sms.surface_meshes_data.remove(surface_mesh);
}

/// Part of the Module interface.
/// Update the SurfaceMeshRendererParameters when a standard data of the SurfaceMesh changes.
pub fn surfaceMeshStdDataChanged(
    m: *Module,
    surface_mesh: *SurfaceMesh,
    std_data: SurfaceMeshStdData,
) void {
    const sms: *SurfaceMeshSelection = @alignCast(@fieldParentPtr("module", m));
    const sd = sms.surface_meshes_data.getPtr(surface_mesh) orelse return;
    switch (std_data) {
        .vertex_position => |maybe_vertex_position| {
            if (maybe_vertex_position) |vertex_position| {
                const position_vbo: VBO = sms.app_ctx.surface_mesh_store.dataVBO(.vertex, Vec3f, vertex_position);
                sd.point_sphere_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                sd.line_cylinder_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                sd.tri_flat_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            } else {
                sd.point_sphere_shader_parameters.unsetVertexAttribArray(.position);
                sd.line_cylinder_shader_parameters.unsetVertexAttribArray(.position);
                sd.tri_flat_shader_parameters.unsetVertexAttribArray(.position);
            }
        },
        else => return, // Ignore other standard data changes
    }
}

/// Part of the Module interface.
/// Render the selected cells of the currently selected SurfaceMesh.
pub fn draw(m: *Module, view_matrix: Mat4f, projection_matrix: Mat4f) void {
    const sms: *SurfaceMeshSelection = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &sms.app_ctx.surface_mesh_store;

    // only draw selection for the currently selected SurfaceMesh
    const sm = sm_store.selected_surface_mesh orelse return;
    const info = sm_store.surfaceMeshInfo(sm);

    const sd = sms.surface_meshes_data.getPtr(sm) orelse return;

    // draw selected vertices
    if (info.vertex_set.cells.items.len > 0) {
        sd.point_sphere_shader_parameters.model_view_matrix = @bitCast(view_matrix);
        sd.point_sphere_shader_parameters.projection_matrix = @bitCast(projection_matrix);
        sd.point_sphere_shader_parameters.draw(info.vertex_set_ibo);
    }

    // draw selected edges
    if (info.edge_set.cells.items.len > 0) {
        sd.line_cylinder_shader_parameters.model_view_matrix = @bitCast(view_matrix);
        sd.line_cylinder_shader_parameters.projection_matrix = @bitCast(projection_matrix);
        sd.line_cylinder_shader_parameters.draw(info.edge_set_ibo);
    }

    // draw selected faces
    if (info.face_set.cells.items.len > 0) {
        gl.Enable(gl.POLYGON_OFFSET_FILL);
        gl.PolygonOffset(1.0, 0.0);
        sd.tri_flat_shader_parameters.model_view_matrix = @bitCast(view_matrix);
        sd.tri_flat_shader_parameters.projection_matrix = @bitCast(projection_matrix);
        sd.tri_flat_shader_parameters.draw(info.face_set_ibo);
        gl.Disable(gl.POLYGON_OFFSET_FILL);
    }

    // draw currently hovered cell
    if (sms.selecting and sms.hovered_cell != null) {
        const cell_type = sms.hovered_cell.?.cellType();
        switch (cell_type) {
            .vertex => {
                const sphere_radius_backup = sd.point_sphere_shader_parameters.sphere_radius;
                sd.point_sphere_shader_parameters.sphere_radius *= 1.1;
                const sphere_color_backup = sd.point_sphere_shader_parameters.sphere_color;
                sd.point_sphere_shader_parameters.sphere_color = .{ sphere_color_backup[0], sphere_color_backup[1], sphere_color_backup[2], 0.5 };
                sd.point_sphere_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                sd.point_sphere_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                gl.Enable(gl.BLEND);
                gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
                sd.point_sphere_shader_parameters.draw(sms.hovered_cell_ibo);
                gl.Disable(gl.BLEND);
                sd.point_sphere_shader_parameters.sphere_radius = sphere_radius_backup;
                sd.point_sphere_shader_parameters.sphere_color = sphere_color_backup;
            },
            .edge => {
                const cylinder_radius_backup = sd.line_cylinder_shader_parameters.cylinder_radius;
                sd.line_cylinder_shader_parameters.cylinder_radius *= 1.1;
                const cylinder_color_backup = sd.line_cylinder_shader_parameters.cylinder_color;
                sd.line_cylinder_shader_parameters.cylinder_color = .{ cylinder_color_backup[0], cylinder_color_backup[1], cylinder_color_backup[2], 0.5 };
                sd.line_cylinder_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                sd.line_cylinder_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                gl.Enable(gl.BLEND);
                gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
                sd.line_cylinder_shader_parameters.draw(sms.hovered_cell_ibo);
                gl.Disable(gl.BLEND);
                sd.line_cylinder_shader_parameters.cylinder_radius = cylinder_radius_backup;
                sd.line_cylinder_shader_parameters.cylinder_color = cylinder_color_backup;
            },
            .face => {
                const vertex_color_backup = sd.tri_flat_shader_parameters.vertex_color;
                sd.tri_flat_shader_parameters.vertex_color = vec.mulScalar4f(vertex_color_backup, 0.5);
                sd.tri_flat_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                sd.tri_flat_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                gl.Enable(gl.POLYGON_OFFSET_FILL);
                gl.PolygonOffset(0.5, 0.0);
                sd.tri_flat_shader_parameters.draw(sms.hovered_cell_ibo);
                gl.Disable(gl.POLYGON_OFFSET_FILL);
                sd.tri_flat_shader_parameters.vertex_color = vertex_color_backup;
            },
            else => unreachable,
        }
    }
}

/// Part of the Module interface.
/// Manage SDL events.
pub fn sdlEvent(m: *Module, event: *const c.SDL_Event) void {
    const sms: *SurfaceMeshSelection = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &sms.app_ctx.surface_mesh_store;
    const view = &sms.app_ctx.view;

    switch (event.type) {
        c.SDL_EVENT_KEY_DOWN => {
            switch (event.key.key) {
                c.SDLK_S => if (sm_store.selected_surface_mesh) |_| {
                    sms.selecting = true;
                },
                else => {},
            }
        },
        c.SDL_EVENT_KEY_UP => {
            switch (event.key.key) {
                c.SDLK_S => {
                    sms.selecting = false;
                    sms.hovered_cell = null;
                    sms.hovered_cell_ibo.fillFromIndexSlice(&.{}, &.{}) catch |err| {
                        std.debug.print("Failed to clear hovered cell IBO: {}\n", .{err});
                        return;
                    };
                    sms.app_ctx.requestRedraw();
                },
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_MOTION => {
            if (sms.selecting) {
                const sm = sm_store.selected_surface_mesh.?;
                const info = sm_store.surfaceMeshInfo(sm);
                if (info.bvh.bvh_ptr) |_| {
                    if (view.viewToWorldRayIfGeometry(event.motion.x, event.motion.y)) |ray| {
                        switch (sms.selecting_cell_type) {
                            .vertex => {
                                sms.hovered_cell = info.bvh.intersectedVertex(ray);
                            },
                            .edge => {
                                sms.hovered_cell = info.bvh.intersectedEdge(ray);
                            },
                            .face => {
                                sms.hovered_cell = info.bvh.intersectedTriangle(ray);
                            },
                            else => unreachable,
                        }
                        sms.hovered_cell_ibo.fillFromCellSlice(sm, &[_]SurfaceMesh.Cell{sms.hovered_cell.?}, sms.app_ctx.allocator) catch |err| {
                            std.debug.print("Failed to fill selecting cell IBO: {}\n", .{err});
                            return;
                        };
                    } else {
                        // no cell is currently hovered, clear the selecting cell
                        sms.hovered_cell = null;
                        sms.hovered_cell_ibo.fillFromIndexSlice(&.{}, &.{}) catch |err| {
                            std.debug.print("Failed to clear selecting cell IBO: {}\n", .{err});
                            return;
                        };
                    }
                    sms.app_ctx.requestRedraw();
                }
            }
        },
        c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            switch (event.button.button) {
                c.SDL_BUTTON_LEFT => {
                    if (sms.selecting) {
                        const sm = sm_store.selected_surface_mesh.?;
                        const info = sm_store.surfaceMeshInfo(sm);
                        // TODO: fallback to brute-force search if the BVH is not available
                        if (info.bvh.bvh_ptr) |_| {
                            if (view.viewToWorldRayIfGeometry(event.button.x, event.button.y)) |ray| {
                                switch (sms.selecting_cell_type) {
                                    .vertex => {
                                        if (info.bvh.intersectedVertex(ray)) |v| {
                                            const modState = c.SDL_GetModState();
                                            if ((modState & c.SDL_KMOD_SHIFT) != 0) {
                                                info.vertex_set.remove(v);
                                            } else {
                                                info.vertex_set.add(v) catch |err| {
                                                    std.debug.print("Failed to add vertex to vertex_set: {}\n", .{err});
                                                    return;
                                                };
                                            }
                                            sm_store.surfaceMeshCellSetUpdated(sm, .vertex);
                                            sms.app_ctx.requestRedraw();
                                        }
                                    },
                                    .edge => {
                                        if (info.bvh.intersectedEdge(ray)) |e| {
                                            const modState = c.SDL_GetModState();
                                            if ((modState & c.SDL_KMOD_SHIFT) != 0) {
                                                info.edge_set.remove(e);
                                            } else {
                                                info.edge_set.add(e) catch |err| {
                                                    std.debug.print("Failed to add edge to edge_set: {}\n", .{err});
                                                    return;
                                                };
                                            }
                                            sm_store.surfaceMeshCellSetUpdated(sm, .edge);
                                            sms.app_ctx.requestRedraw();
                                        }
                                    },
                                    .face => {
                                        if (info.bvh.intersectedTriangle(ray)) |f| {
                                            const modState = c.SDL_GetModState();
                                            if ((modState & c.SDL_KMOD_SHIFT) != 0) {
                                                info.face_set.remove(f);
                                            } else {
                                                info.face_set.add(f) catch |err| {
                                                    std.debug.print("Failed to add face to face_set: {}\n", .{err});
                                                    return;
                                                };
                                            }
                                            sm_store.surfaceMeshCellSetUpdated(sm, .face);
                                            sms.app_ctx.requestRedraw();
                                        }
                                    },
                                    else => {},
                                }
                            }
                        }
                    }
                },
                else => {},
            }
        },
        else => {},
    }
}

/// Part of the Module interface.
/// Show a UI panel to control the selected cells of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const sms: *SurfaceMeshSelection = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &sms.app_ctx.surface_mesh_store;

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (sm_store.selected_surface_mesh) |sm| {
        const sd = sms.surface_meshes_data.getPtr(sm).?;
        const info = sm_store.surfaceMeshInfo(sm);

        c.ImGui_TextWrapped("Hold (shift+)'S' to (de)select cells");
        if (info.bvh.bvh_ptr == null) {
            c.ImGui_TextWrapped("A BVH must exist for the SurfaceMesh to select cells");
        }
        c.ImGui_Separator();

        var buf: [64]u8 = undefined;

        inline for ([_]SurfaceMesh.CellType{ .vertex, .edge, .face }) |cell_type| {
            c.ImGui_PushID(@tagName(cell_type));
            defer c.ImGui_PopID();
            switch (cell_type) {
                .vertex => {
                    const text = std.fmt.bufPrintZ(&buf, "Vertices | #selected: {d}", .{info.vertex_set.cells.items.len}) catch "";
                    c.ImGui_SeparatorText(text);
                    if (c.ImGui_RadioButton("Vertex", sms.selecting_cell_type == .vertex)) {
                        sms.selecting_cell_type = .vertex;
                    }
                    c.ImGui_SameLine();
                    const disabled = info.vertex_set.cells.items.len == 0;
                    if (disabled) {
                        c.ImGui_BeginDisabled(true);
                    }
                    if (c.ImGui_Button(if (info.vertex_set.cells.items.len > 0) "Clear selection" else "No selection to clear")) {
                        info.vertex_set.clear();
                        sm_store.surfaceMeshCellSetUpdated(sm, cell_type);
                        sms.app_ctx.requestRedraw();
                    }
                    if (disabled) {
                        c.ImGui_EndDisabled();
                    }

                    c.ImGui_Text("Size");
                    c.ImGui_PushID("DrawSelectedVerticesSize");
                    if (c.ImGui_SliderFloatEx("", &sd.point_sphere_shader_parameters.sphere_radius, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
                        sms.app_ctx.requestRedraw();
                    }
                    c.ImGui_PopID();
                    if (c.ImGui_ColorEdit3("Color##SelectedVerticesColorEdit", &sd.point_sphere_shader_parameters.sphere_color, c.ImGuiColorEditFlags_NoInputs)) {
                        sms.app_ctx.requestRedraw();
                    }
                },
                .edge => {
                    const text = std.fmt.bufPrintZ(&buf, "Edges | #selected: {d}", .{info.edge_set.cells.items.len}) catch "";
                    c.ImGui_SeparatorText(text);
                    if (c.ImGui_RadioButton("Edge", sms.selecting_cell_type == .edge)) {
                        sms.selecting_cell_type = .edge;
                    }
                    c.ImGui_SameLine();
                    const disabled = info.edge_set.cells.items.len == 0;
                    if (disabled) {
                        c.ImGui_BeginDisabled(true);
                    }
                    if (c.ImGui_Button(if (info.edge_set.cells.items.len > 0) "Clear selection" else "No selection to clear")) {
                        info.edge_set.clear();
                        sm_store.surfaceMeshCellSetUpdated(sm, cell_type);
                        sms.app_ctx.requestRedraw();
                    }
                    if (disabled) {
                        c.ImGui_EndDisabled();
                    }

                    c.ImGui_Text("Size");
                    c.ImGui_PushID("DrawSelectedEdgesSize");
                    if (c.ImGui_SliderFloatEx("", &sd.line_cylinder_shader_parameters.cylinder_radius, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
                        sms.app_ctx.requestRedraw();
                    }
                    c.ImGui_PopID();
                    if (c.ImGui_ColorEdit3("Color##SelectedEdgesColorEdit", &sd.line_cylinder_shader_parameters.cylinder_color, c.ImGuiColorEditFlags_NoInputs)) {
                        sms.app_ctx.requestRedraw();
                    }
                },
                .face => {
                    const text = std.fmt.bufPrintZ(&buf, "Faces | #selected: {d}", .{info.face_set.cells.items.len}) catch "";
                    c.ImGui_SeparatorText(text);
                    if (c.ImGui_RadioButton("Face", sms.selecting_cell_type == .face)) {
                        sms.selecting_cell_type = .face;
                    }
                    c.ImGui_SameLine();
                    const disabled = info.face_set.cells.items.len == 0;
                    if (disabled) {
                        c.ImGui_BeginDisabled(true);
                    }
                    if (c.ImGui_Button(if (info.face_set.cells.items.len > 0) "Clear selection" else "No selection to clear")) {
                        info.face_set.clear();
                        sm_store.surfaceMeshCellSetUpdated(sm, cell_type);
                        sms.app_ctx.requestRedraw();
                    }
                    if (disabled) {
                        c.ImGui_EndDisabled();
                    }

                    if (c.ImGui_ColorEdit4("Global color##SelectedFacesColorEdit", &sd.tri_flat_shader_parameters.vertex_color, c.ImGuiColorEditFlags_NoInputs)) {
                        sms.app_ctx.requestRedraw();
                    }
                },
                else => {},
            }
        }
    } else {
        c.ImGui_Text("No SurfaceMesh selected");
    }
}
