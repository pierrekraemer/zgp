const SurfaceMeshSelection = @This();

const std = @import("std");
const assert = std.debug.assert;
const gl = @import("gl");

const imgui_utils = @import("../ui/imgui.zig");
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
const Vec4f = vec.Vec4f;
const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;

const color = @import("../utils/color.zig");
const selection = @import("../models/surface/selection.zig");

const SelectionData = struct {
    point_sphere_shader_parameters: PointSphere.Parameters,
    line_cylinder_shader_parameters: LineCylinder.Parameters,
    tri_flat_shader_parameters: TriFlat.Parameters,

    selected_cell_set: ?*SurfaceMesh.CellSet = null,

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

const SelectionMode = enum {
    single,
    within_sphere,
};

const SelectionAction = enum {
    add,
    remove,
};

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Selection",
    .supported_models = .{ .surface_mesh = true },
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

selection_mode: SelectionMode = .single,
selection_radius: f32 = 0.05,
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
        entry.value_ptr.deinit();
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
/// Render the selected cells of the currently selected SurfaceMesh & CellSet.
pub fn draw(m: *Module, view_matrix: Mat4f, projection_matrix: Mat4f) void {
    const sms: *SurfaceMeshSelection = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &sms.app_ctx.surface_mesh_store;

    // only draw selection for the currently selected SurfaceMesh & CellSet
    if (sms.app_ctx.selected_model.modelType() != .surface_mesh) return;
    const sm = sms.app_ctx.selected_model.surface_mesh;
    const sd = sms.surface_meshes_data.getPtr(sm).?;
    if (sd.selected_cell_set == null) return;

    if (sd.selected_cell_set.?.cells.items.len > 0) {
        switch (sd.selected_cell_set.?.cell_type) {
            .vertex => {
                sd.point_sphere_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                sd.point_sphere_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                sd.point_sphere_shader_parameters.draw(sm_store.cellSetIBO(sd.selected_cell_set.?));
            },
            .edge => {
                sd.line_cylinder_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                sd.line_cylinder_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                sd.line_cylinder_shader_parameters.draw(sm_store.cellSetIBO(sd.selected_cell_set.?));
            },
            .face => {
                gl.Enable(gl.POLYGON_OFFSET_FILL);
                gl.PolygonOffset(1.0, 0.0);
                sd.tri_flat_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                sd.tri_flat_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                sd.tri_flat_shader_parameters.draw(sm_store.cellSetIBO(sd.selected_cell_set.?));
                gl.Disable(gl.POLYGON_OFFSET_FILL);
            },
            else => unreachable,
        }
    }

    // draw currently hovered cell
    if (sms.selecting and sms.hovered_cell != null) {
        const modState = c.SDL_GetModState();
        const action: SelectionAction = if (modState & c.SDL_KMOD_SHIFT != 0) .remove else .add;
        const cell_type = sms.hovered_cell.?.cellType(); // or sms.selecting_cell_type
        switch (cell_type) {
            .vertex => {
                const sphere_radius_backup = sd.point_sphere_shader_parameters.sphere_radius;
                switch (sms.selection_mode) {
                    .single => sd.point_sphere_shader_parameters.sphere_radius *= 1.1,
                    .within_sphere => sd.point_sphere_shader_parameters.sphere_radius = sms.selection_radius,
                }
                const sphere_color_backup = sd.point_sphere_shader_parameters.sphere_color;
                const sphere_color_basis = switch (sms.selecting_cell_type) {
                    .vertex => sd.point_sphere_shader_parameters.sphere_color,
                    .edge => sd.line_cylinder_shader_parameters.cylinder_color,
                    .face => sd.tri_flat_shader_parameters.vertex_color,
                    else => unreachable,
                };
                const sphere_color: Vec4f = switch (action) {
                    .add => .{ sphere_color_basis[0], sphere_color_basis[1], sphere_color_basis[2], 0.5 },
                    .remove => blk: {
                        const opposite_color = color.perceptualOppositeRGB(.{ sphere_color_basis[0], sphere_color_basis[1], sphere_color_basis[2] });
                        break :blk .{ opposite_color[0], opposite_color[1], opposite_color[2], 0.8 };
                    },
                };
                sd.point_sphere_shader_parameters.sphere_color = sphere_color;
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
                const cylinder_color: Vec4f = switch (action) {
                    .add => .{ cylinder_color_backup[0], cylinder_color_backup[1], cylinder_color_backup[2], 0.5 },
                    .remove => blk: {
                        const opposite_color = color.perceptualOppositeRGB(.{ cylinder_color_backup[0], cylinder_color_backup[1], cylinder_color_backup[2] });
                        break :blk .{ opposite_color[0], opposite_color[1], opposite_color[2], 0.8 };
                    },
                };
                sd.line_cylinder_shader_parameters.cylinder_color = cylinder_color;
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
                const vertex_color: Vec4f = switch (action) {
                    .add => vec.mulScalar4f(vertex_color_backup, 0.75),
                    .remove => blk: {
                        const opposite_color = color.perceptualOppositeRGB(.{ vertex_color_backup[0], vertex_color_backup[1], vertex_color_backup[2] });
                        break :blk .{ opposite_color[0], opposite_color[1], opposite_color[2], 0.75 };
                    },
                };
                sd.tri_flat_shader_parameters.vertex_color = vertex_color;
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
pub fn sdlEvent(m: *Module, event: *const c.SDL_Event) bool {
    const sms: *SurfaceMeshSelection = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &sms.app_ctx.surface_mesh_store;
    const view = &sms.app_ctx.view;

    assert(sms.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = sms.app_ctx.selected_model.surface_mesh;
    const sd = sms.surface_meshes_data.getPtr(sm).?;
    if (sd.selected_cell_set == null) return false;

    return sw: switch (event.type) {
        c.SDL_EVENT_KEY_DOWN => blk: {
            switch (event.key.key) {
                c.SDLK_S => {
                    const was_selecting = sms.selecting;
                    sms.selecting = true;
                    if (!was_selecting) {
                        continue :sw c.SDL_EVENT_MOUSE_MOTION; // goto mouse motion case to update hovered cell
                    }
                },
                c.SDLK_LSHIFT, c.SDLK_RSHIFT => sms.app_ctx.requestRedraw(), // shift toggles between add and remove
                else => {},
            }
            break :blk false;
        },
        c.SDL_EVENT_KEY_UP => blk: {
            switch (event.key.key) {
                c.SDLK_S => {
                    sms.selecting = false;
                    sms.hovered_cell = null;
                    sms.hovered_cell_ibo.fillFromIndexSlice(&.{}, &.{});
                    sms.app_ctx.requestRedraw();
                },
                c.SDLK_LSHIFT, c.SDLK_RSHIFT => sms.app_ctx.requestRedraw(), // shift toggles between add and remove
                else => {},
            }
            break :blk false;
        },
        c.SDL_EVENT_MOUSE_MOTION => blk: {
            if (sms.selecting) {
                const info = sm_store.surfaceMeshInfo(sm);
                // TODO: fallback to brute-force search if the BVH is not available
                if (info.bvh.initialized) {
                    var mouse_x: f32 = 0;
                    var mouse_y: f32 = 0;
                    _ = c.SDL_GetMouseState(&mouse_x, &mouse_y);
                    if (view.viewToWorldRayIfGeometry(mouse_x, mouse_y)) |ray| {
                        switch (sms.selection_mode) {
                            .single => {
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
                            },
                            .within_sphere => {
                                sms.hovered_cell = info.bvh.intersectedVertex(ray); // within sphere selection is always centered on a vertex
                            },
                        }
                        if (sms.hovered_cell) |cell| {
                            sms.hovered_cell_ibo.fillFromCellSlice(sm, &[_]SurfaceMesh.Cell{cell}, sms.app_ctx.allocator) catch |err| {
                                std.debug.print("Failed to fill selecting cell IBO: {}\n", .{err});
                                break :blk false;
                            };
                        } else {
                            sms.hovered_cell_ibo.fillFromIndexSlice(&.{}, &.{});
                        }
                    } else {
                        // no cell is currently hovered, clear the selecting cell
                        sms.hovered_cell = null;
                        sms.hovered_cell_ibo.fillFromIndexSlice(&.{}, &.{});
                    }
                    sms.app_ctx.requestRedraw();
                    break :blk true;
                }
            }
            break :blk false;
        },
        c.SDL_EVENT_MOUSE_BUTTON_DOWN => blk: {
            switch (event.button.button) {
                c.SDL_BUTTON_LEFT => {
                    if (sms.selecting) {
                        if (sms.hovered_cell) |cell| {
                            const modState = c.SDL_GetModState();
                            const action: SelectionAction = if (modState & c.SDL_KMOD_SHIFT != 0) .remove else .add;
                            switch (sms.selection_mode) {
                                .single => {
                                    switch (action) {
                                        .add => {
                                            sd.selected_cell_set.?.add(cell) catch |err| {
                                                std.debug.print("Failed to add vertex to vertex_set: {}\n", .{err});
                                                break :blk false;
                                            };
                                        },
                                        .remove => sd.selected_cell_set.?.remove(cell),
                                    }
                                    sm_store.surfaceMeshCellSetUpdated(sm, sd.selected_cell_set.?);
                                    sms.app_ctx.requestRedraw();
                                },
                                .within_sphere => {
                                    const info = sm_store.surfaceMeshInfo(sm);
                                    if (info.std_datas.vertex_position) |vertex_position| {
                                        var vertices: std.ArrayList(SurfaceMesh.Cell) = .empty;
                                        defer vertices.deinit(sm.allocator);
                                        var edges: std.ArrayList(SurfaceMesh.Cell) = .empty;
                                        defer edges.deinit(sm.allocator);
                                        var faces: std.ArrayList(SurfaceMesh.Cell) = .empty;
                                        defer faces.deinit(sm.allocator);
                                        selection.cellsWithinSphereAroundVertex(sm, cell, sms.selection_radius, vertex_position, &vertices, &edges, &faces) catch |err| {
                                            std.debug.print("Failed to select cells within sphere: {}\\n", .{err});
                                            break :blk false;
                                        };
                                        const cells_in_sphere = switch (sms.selecting_cell_type) {
                                            .vertex => vertices.items,
                                            .edge => edges.items,
                                            .face => faces.items,
                                            else => unreachable,
                                        };
                                        switch (action) {
                                            .add => {
                                                for (cells_in_sphere) |cell_in_sphere| {
                                                    sd.selected_cell_set.?.add(cell_in_sphere) catch |err| {
                                                        std.debug.print("Failed to add vertex to vertex_set: {}\n", .{err});
                                                        break :blk false;
                                                    };
                                                }
                                            },
                                            .remove => {
                                                for (cells_in_sphere) |cell_in_sphere| {
                                                    sd.selected_cell_set.?.remove(cell_in_sphere);
                                                }
                                            },
                                        }
                                        sm_store.surfaceMeshCellSetUpdated(sm, sd.selected_cell_set.?);
                                        sms.app_ctx.requestRedraw();
                                    }
                                },
                            }
                        }
                        break :blk true;
                    }
                },
                else => {},
            }
            break :blk false;
        },
        c.SDL_EVENT_MOUSE_WHEEL => blk: {
            if (sms.selecting and sms.selection_mode == .within_sphere) {
                sms.selection_radius += event.wheel.y * 0.001;
                sms.app_ctx.requestRedraw();
                break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

/// Part of the Module interface.
/// Show a UI panel to control the selected cells of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const sms: *SurfaceMeshSelection = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &sms.app_ctx.surface_mesh_store;

    assert(sms.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = sms.app_ctx.selected_model.surface_mesh;

    const UiData = struct {
        var cell_set_name_buf: [32]u8 = @splat(0);
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const sd = sms.surface_meshes_data.getPtr(sm).?;
    const info = sm_store.surfaceMeshInfo(sm);

    if (!info.bvh.initialized) {
        c.ImGui_TextWrapped("A BVH must exist on the SurfaceMesh to select cells");
    } else {
        c.ImGui_TextWrapped(
            \\ Hold:
            \\ - 'S' to select cells
            \\ - 'Shift+S' to deselect cells
        );
    }

    c.ImGui_SeparatorText("Selection mode");
    if (c.ImGui_RadioButton("Single", sms.selection_mode == .single)) {
        sms.selection_mode = .single;
    }
    c.ImGui_SameLine();
    if (c.ImGui_RadioButton("Within Sphere", sms.selection_mode == .within_sphere)) {
        sms.selection_mode = .within_sphere;
    }

    c.ImGui_SeparatorText("Cell type");
    c.ImGui_NewLine();
    inline for ([_]SurfaceMesh.CellType{ .vertex, .edge, .face }) |cell_type| {
        c.ImGui_SameLine();
        if (c.ImGui_RadioButton(@tagName(cell_type), sms.selecting_cell_type == cell_type)) {
            sms.selecting_cell_type = cell_type;
            sd.selected_cell_set = null;
            sms.app_ctx.requestRedraw();
        }
    }

    c.ImGui_SeparatorText("Cell set");
    {
        c.ImGui_Text("Cell set:");
        c.ImGui_PushID("cell set");
        switch (imgui_utils.surfaceMeshCellSetComboBox(sm, sms.selecting_cell_type, sd.selected_cell_set)) {
            .unchanged => {},
            .cleared => {
                sd.selected_cell_set = null;
                sms.app_ctx.requestRedraw();
            },
            .changed => |cell_set| {
                sd.selected_cell_set = cell_set;
                sms.app_ctx.requestRedraw();
            },
        }
        c.ImGui_PopID();

        c.ImGui_Text("Cell set name:");
        _ = c.ImGui_InputText("##Name", &UiData.cell_set_name_buf, UiData.cell_set_name_buf.len, c.ImGuiInputTextFlags_CharsNoBlank);
        const cell_set_name = std.mem.sliceTo(&UiData.cell_set_name_buf, 0);
        const disabled = cell_set_name.len == 0;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx("Create cell set", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            const cell_set = sm.addCellSet(sms.selecting_cell_type, cell_set_name) catch |err| {
                std.debug.print("Error adding cell set: {}\n", .{err});
                return;
            };
            UiData.cell_set_name_buf = @splat(0);
            sd.selected_cell_set = cell_set;
            sms.app_ctx.requestRedraw();
        }
        if (disabled) {
            imgui_utils.tooltip("Requires a cell set name");
            c.ImGui_EndDisabled();
        }
    }
    if (sd.selected_cell_set) |cell_set| {
        var buf: [64]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "#selected: {d}", .{cell_set.cells.items.len}) catch "";
        c.ImGui_Text(text);
        c.ImGui_SameLine();
        const disabled = cell_set.cells.items.len == 0;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_Button(if (cell_set.cells.items.len > 0) "Clear selection" else "No selection to clear")) {
            cell_set.clear();
            sm_store.surfaceMeshCellSetUpdated(sm, cell_set);
            sms.app_ctx.requestRedraw();
        }
        if (disabled) {
            c.ImGui_EndDisabled();
        }
    } else {
        c.ImGui_Text("No cell set selected");
    }

    c.ImGui_SeparatorText("Display");

    switch (sms.selecting_cell_type) {
        .vertex => {
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
            if (c.ImGui_ColorEdit4("Global color##SelectedFacesColorEdit", &sd.tri_flat_shader_parameters.vertex_color, c.ImGuiColorEditFlags_NoInputs)) {
                sms.app_ctx.requestRedraw();
            }
        },
        else => unreachable,
    }
}
