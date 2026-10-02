const SurfaceMeshSelection = @This();

const std = @import("std");
const assert = std.debug.assert;
const gl = @import("gl");

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("c");

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

    selected_vertex_set: ?*SurfaceMesh.CellSet(.vertex) = null,
    selected_edge_set: ?*SurfaceMesh.CellSet(.edge) = null,
    selected_face_set: ?*SurfaceMesh.CellSet(.face) = null,

    selecting_cell_type: SurfaceMesh.CellType = .vertex,
    selection_mode: SelectionMode = .single,
    selection_radius: f32 = 0.05,

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
        .selectedModelChanged = selectedModelChanged,
        .draw = draw,
        .sdlEvent = sdlEvent,
        .rightPanel = rightPanel,
    },
},
surface_meshes_data: std.AutoHashMapUnmanaged(*SurfaceMesh, SelectionData) = .empty,

selecting: bool = false,
hovered_cell: ?SurfaceMesh.Cell = null,
hovered_cell_ibo: IBO,

pub fn init(app_ctx: *AppContext) SurfaceMeshSelection {
    return .{
        .app_ctx = app_ctx,
        .hovered_cell_ibo = .init(),
    };
}

pub fn deinit(sms: *SurfaceMeshSelection) void {
    var smdata_it = sms.surface_meshes_data.valueIterator();
    while (smdata_it.next()) |sd| {
        sd.deinit();
    }
    sms.surface_meshes_data.deinit(sms.app_ctx.allocator);
}

/// Part of the Module interface.
/// Create and store a SelectionData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const sms: *SurfaceMeshSelection = @alignCast(@fieldParentPtr("module", m));
    sms.surface_meshes_data.put(sms.app_ctx.allocator, surface_mesh, SelectionData.init()) catch |err| {
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
pub fn selectedModelChanged(m: *Module) void {
    const sms: *SurfaceMeshSelection = @alignCast(@fieldParentPtr("module", m));
    sms.selecting = false;
    sms.hovered_cell = null;
    sms.hovered_cell_ibo.fillFromIndexSlice(&.{}, &.{});
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

    switch (sd.selecting_cell_type) {
        .vertex => {
            if (sd.selected_vertex_set == null) return;
            sd.point_sphere_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            sd.point_sphere_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            sd.point_sphere_shader_parameters.draw(sm_store.cellSetIBO(.vertex, sd.selected_vertex_set.?));
        },
        .edge => {
            if (sd.selected_edge_set == null) return;
            sd.line_cylinder_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            sd.line_cylinder_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            sd.line_cylinder_shader_parameters.draw(sm_store.cellSetIBO(.edge, sd.selected_edge_set.?));
        },
        .face => {
            if (sd.selected_face_set == null) return;
            gl.Enable(gl.POLYGON_OFFSET_FILL);
            gl.PolygonOffset(1.0, 0.0);
            sd.tri_flat_shader_parameters.model_view_matrix = @bitCast(view_matrix);
            sd.tri_flat_shader_parameters.projection_matrix = @bitCast(projection_matrix);
            sd.tri_flat_shader_parameters.draw(sm_store.cellSetIBO(.face, sd.selected_face_set.?));
            gl.Disable(gl.POLYGON_OFFSET_FILL);
        },
        else => unreachable,
    }

    // draw currently hovered cell
    if (sms.selecting and sms.hovered_cell != null) {
        const modState = c.SDL_GetModState();
        const action: SelectionAction = if (modState & c.SDL_KMOD_SHIFT != 0) .remove else .add;
        const cell_type = sms.hovered_cell.?.cellType(); // or sms.selecting_cell_type
        switch (cell_type) {
            .vertex => {
                const sphere_radius_backup = sd.point_sphere_shader_parameters.sphere_radius;
                switch (sd.selection_mode) {
                    .single => sd.point_sphere_shader_parameters.sphere_radius *= 1.1,
                    .within_sphere => sd.point_sphere_shader_parameters.sphere_radius = sd.selection_radius,
                }
                const sphere_color_backup = sd.point_sphere_shader_parameters.sphere_color;
                const sphere_color_basis = switch (sd.selecting_cell_type) {
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

    switch (sd.selecting_cell_type) {
        .vertex => if (sd.selected_vertex_set == null) return false,
        .edge => if (sd.selected_edge_set == null) return false,
        .face => if (sd.selected_face_set == null) return false,
        else => unreachable,
    }

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
                // TODO: fallback to brute-force search if the BVH is not available?
                if (info.bvh.initialized) {
                    const ray = view.viewToWorldRay(event.motion.x, event.motion.y);
                    switch (sd.selection_mode) {
                        .single => {
                            switch (sd.selecting_cell_type) {
                                .vertex => {
                                    sms.hovered_cell = info.bvh.intersectedVertex(ray);
                                    if (sms.hovered_cell) |cell| {
                                        sms.hovered_cell_ibo.fillFromSurfaceMeshCellSlice(sm, .vertex, &[_]SurfaceMesh.Cell{cell}, sms.app_ctx.allocator) catch |err| {
                                            std.debug.print("Failed to fill selecting cell IBO: {}\n", .{err});
                                            break :blk false;
                                        };
                                    }
                                },
                                .edge => {
                                    sms.hovered_cell = info.bvh.intersectedEdge(ray);
                                    if (sms.hovered_cell) |cell| {
                                        sms.hovered_cell_ibo.fillFromSurfaceMeshCellSlice(sm, .edge, &[_]SurfaceMesh.Cell{cell}, sms.app_ctx.allocator) catch |err| {
                                            std.debug.print("Failed to fill selecting cell IBO: {}\n", .{err});
                                            break :blk false;
                                        };
                                    }
                                },
                                .face => {
                                    sms.hovered_cell = info.bvh.intersectedTriangle(ray);
                                    if (sms.hovered_cell) |cell| {
                                        sms.hovered_cell_ibo.fillFromSurfaceMeshCellSlice(sm, .face, &[_]SurfaceMesh.Cell{cell}, sms.app_ctx.allocator) catch |err| {
                                            std.debug.print("Failed to fill selecting cell IBO: {}\n", .{err});
                                            break :blk false;
                                        };
                                    }
                                },
                                else => unreachable,
                            }
                        },
                        .within_sphere => {
                            sms.hovered_cell = info.bvh.intersectedVertex(ray); // within sphere selection is always centered on a vertex
                            if (sms.hovered_cell) |cell| {
                                sms.hovered_cell_ibo.fillFromSurfaceMeshCellSlice(sm, .vertex, &[_]SurfaceMesh.Cell{cell}, sms.app_ctx.allocator) catch |err| {
                                    std.debug.print("Failed to fill selecting cell IBO: {}\n", .{err});
                                    break :blk false;
                                };
                            }
                        },
                    }
                    if (sms.hovered_cell == null) {
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
                            switch (sd.selection_mode) {
                                .single => {
                                    switch (action) {
                                        .add => switch (sd.selecting_cell_type) {
                                            .vertex => sd.selected_vertex_set.?.add(cell) catch |err| {
                                                std.debug.print("Failed to add vertex to vertex_set: {}\n", .{err});
                                                break :blk false;
                                            },
                                            .edge => sd.selected_edge_set.?.add(cell) catch |err| {
                                                std.debug.print("Failed to add edge to edge_set: {}\n", .{err});
                                                break :blk false;
                                            },
                                            .face => sd.selected_face_set.?.add(cell) catch |err| {
                                                std.debug.print("Failed to add face to face_set: {}\n", .{err});
                                                break :blk false;
                                            },
                                            else => unreachable,
                                        },
                                        .remove => switch (sd.selecting_cell_type) {
                                            .vertex => sd.selected_vertex_set.?.remove(cell),
                                            .edge => sd.selected_edge_set.?.remove(cell),
                                            .face => sd.selected_face_set.?.remove(cell),
                                            else => unreachable,
                                        },
                                    }
                                    switch (sd.selecting_cell_type) {
                                        .vertex => sm_store.surfaceMeshCellSetUpdated(sm, .vertex, sd.selected_vertex_set.?),
                                        .edge => sm_store.surfaceMeshCellSetUpdated(sm, .edge, sd.selected_edge_set.?),
                                        .face => sm_store.surfaceMeshCellSetUpdated(sm, .face, sd.selected_face_set.?),
                                        else => unreachable,
                                    }
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
                                        selection.cellsWithinSphereAroundVertex(sm, cell, sd.selection_radius, vertex_position, &vertices, &edges, &faces) catch |err| {
                                            std.debug.print("Failed to select cells within sphere: {}\\n", .{err});
                                            break :blk false;
                                        };
                                        const cells_in_sphere = switch (sd.selecting_cell_type) {
                                            .vertex => vertices.items,
                                            .edge => edges.items,
                                            .face => faces.items,
                                            else => unreachable,
                                        };
                                        switch (action) {
                                            .add => switch (sd.selecting_cell_type) {
                                                .vertex => for (cells_in_sphere) |cell_in_sphere| {
                                                    sd.selected_vertex_set.?.add(cell_in_sphere) catch |err| {
                                                        std.debug.print("Failed to add vertex to vertex_set: {}\n", .{err});
                                                        break :blk false;
                                                    };
                                                },
                                                .edge => for (cells_in_sphere) |cell_in_sphere| {
                                                    sd.selected_edge_set.?.add(cell_in_sphere) catch |err| {
                                                        std.debug.print("Failed to add edge to edge_set: {}\n", .{err});
                                                        break :blk false;
                                                    };
                                                },
                                                .face => for (cells_in_sphere) |cell_in_sphere| {
                                                    sd.selected_face_set.?.add(cell_in_sphere) catch |err| {
                                                        std.debug.print("Failed to add face to face_set: {}\n", .{err});
                                                        break :blk false;
                                                    };
                                                },
                                                else => unreachable,
                                            },
                                            .remove => switch (sd.selecting_cell_type) {
                                                .vertex => for (cells_in_sphere) |cell_in_sphere| {
                                                    sd.selected_vertex_set.?.remove(cell_in_sphere);
                                                },
                                                .edge => for (cells_in_sphere) |cell_in_sphere| {
                                                    sd.selected_edge_set.?.remove(cell_in_sphere);
                                                },
                                                .face => for (cells_in_sphere) |cell_in_sphere| {
                                                    sd.selected_face_set.?.remove(cell_in_sphere);
                                                },
                                                else => unreachable,
                                            },
                                        }
                                        switch (sd.selecting_cell_type) {
                                            .vertex => sm_store.surfaceMeshCellSetUpdated(sm, .vertex, sd.selected_vertex_set.?),
                                            .edge => sm_store.surfaceMeshCellSetUpdated(sm, .edge, sd.selected_edge_set.?),
                                            .face => sm_store.surfaceMeshCellSetUpdated(sm, .face, sd.selected_face_set.?),
                                            else => unreachable,
                                        }
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
            if (sms.selecting and sd.selection_mode == .within_sphere) {
                sd.selection_radius += event.wheel.y * 0.001;
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
    const info = sm_store.surfaceMeshInfo(sm);
    const sd = sms.surface_meshes_data.getPtr(sm).?;

    const UiData = struct {
        var cell_set_name_buf: [32]u8 = @splat(0);
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (!info.bvh.initialized) {
        c.ImGui_TextWrapped("A BVH must exist on the SurfaceMesh to select cells");
    } else {
        c.ImGui_TextWrapped(
            \\ Hold:
            \\ - 'S' to select cells
            \\ - 'Shift+S' to deselect cells
        );
    }

    c.ImGui_SeparatorText("Cell type");
    c.ImGui_NewLine();
    inline for ([_]SurfaceMesh.CellType{ .vertex, .edge, .face }) |cell_type| {
        c.ImGui_SameLine();
        if (c.ImGui_RadioButton(@tagName(cell_type), sd.selecting_cell_type == cell_type)) {
            sd.selecting_cell_type = cell_type;
            const cell_sets = sm.cellSetContainerPtr(cell_type);
            // if the selected CellSet of the new cell type is null, select the first CellSet of that type if it exists
            switch (cell_type) {
                .vertex => if (sd.selected_vertex_set == null and cell_sets.count() > 0) {
                    var it = cell_sets.valueIterator();
                    sd.selected_vertex_set = it.next().?;
                },
                .edge => if (sd.selected_edge_set == null and cell_sets.count() > 0) {
                    var it = cell_sets.valueIterator();
                    sd.selected_edge_set = it.next().?;
                },
                .face => if (sd.selected_face_set == null and cell_sets.count() > 0) {
                    var it = cell_sets.valueIterator();
                    sd.selected_face_set = it.next().?;
                },
                else => unreachable,
            }
            sms.app_ctx.requestRedraw();
        }
    }

    c.ImGui_SeparatorText("Selection mode");
    if (c.ImGui_RadioButton("Single", sd.selection_mode == .single)) {
        sd.selection_mode = .single;
    }
    c.ImGui_SameLine();
    if (c.ImGui_RadioButton("Within Sphere", sd.selection_mode == .within_sphere)) {
        sd.selection_mode = .within_sphere;
    }

    c.ImGui_SeparatorText("Cell set");
    {
        c.ImGui_Text("Cell set creation");
        {
            c.ImGui_PushItemWidth(c.ImGui_GetContentRegionAvail().x / 2.0 - style.*.ItemSpacing.x * 2);
            defer c.ImGui_PopItemWidth();
            _ = c.ImGui_InputText("##Name", &UiData.cell_set_name_buf, UiData.cell_set_name_buf.len, c.ImGuiInputTextFlags_CharsNoBlank);
        }
        const cell_set_name = std.mem.sliceTo(&UiData.cell_set_name_buf, 0);
        const disabled = cell_set_name.len == 0;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        c.ImGui_SameLine();
        if (c.ImGui_ButtonEx("Create", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            inline for ([_]SurfaceMesh.CellType{ .vertex, .edge, .face }) |cell_type| {
                if (cell_type == sd.selecting_cell_type) {
                    const cell_set = sm.addCellSet(cell_type, cell_set_name) catch |err| {
                        std.debug.print("Error adding cell set: {}\n", .{err});
                        return;
                    };
                    switch (cell_type) {
                        .vertex => sd.selected_vertex_set = cell_set,
                        .edge => sd.selected_edge_set = cell_set,
                        .face => sd.selected_face_set = cell_set,
                        else => unreachable,
                    }
                }
            }
            UiData.cell_set_name_buf = @splat(0);
            sms.app_ctx.requestRedraw();
        }
        if (disabled) {
            imgui_utils.tooltip("Requires a cell set name");
            c.ImGui_EndDisabled();
        }

        c.ImGui_Separator();

        c.ImGui_Text("Cell set selection");
        c.ImGui_PushID("cell set");
        inline for ([_]SurfaceMesh.CellType{ .vertex, .edge, .face }) |cell_type| {
            if (cell_type == sd.selecting_cell_type) {
                switch (imgui_utils.surfaceMeshCellSetComboBox(sm, cell_type, switch (cell_type) {
                    .vertex => sd.selected_vertex_set,
                    .edge => sd.selected_edge_set,
                    .face => sd.selected_face_set,
                    else => unreachable,
                })) {
                    .unchanged => {},
                    .cleared => {
                        switch (cell_type) {
                            .vertex => sd.selected_vertex_set = null,
                            .edge => sd.selected_edge_set = null,
                            .face => sd.selected_face_set = null,
                            else => unreachable,
                        }
                        sms.app_ctx.requestRedraw();
                    },
                    .changed => |cell_set| {
                        switch (cell_type) {
                            .vertex => sd.selected_vertex_set = cell_set,
                            .edge => sd.selected_edge_set = cell_set,
                            .face => sd.selected_face_set = cell_set,
                            else => unreachable,
                        }
                        sms.app_ctx.requestRedraw();
                    },
                }
            }
        }
        c.ImGui_PopID();
    }

    switch (sd.selecting_cell_type) {
        .vertex => {
            if (sd.selected_vertex_set) |vertex_set| {
                var buf: [64]u8 = undefined;
                const text = std.fmt.bufPrintZ(&buf, "#selected: {d}", .{vertex_set.cell_set_gen.cells.items.len}) catch "";
                c.ImGui_Text(text);
                c.ImGui_SameLine();
                const disabled = vertex_set.cell_set_gen.cells.items.len == 0;
                if (disabled) {
                    c.ImGui_BeginDisabled(true);
                }
                if (c.ImGui_Button(if (!disabled) "Clear selection" else "No selection to clear")) {
                    vertex_set.clear();
                    sm_store.surfaceMeshCellSetUpdated(sm, .vertex, vertex_set);
                    sms.app_ctx.requestRedraw();
                }
                if (disabled) {
                    c.ImGui_EndDisabled();
                }
            } else {
                c.ImGui_Text("No cell set selected");
            }
        },
        .edge => {
            if (sd.selected_edge_set) |edge_set| {
                var buf: [64]u8 = undefined;
                const text = std.fmt.bufPrintZ(&buf, "#selected: {d}", .{edge_set.cell_set_gen.cells.items.len}) catch "";
                c.ImGui_Text(text);
                c.ImGui_SameLine();
                const disabled = edge_set.cell_set_gen.cells.items.len == 0;
                if (disabled) {
                    c.ImGui_BeginDisabled(true);
                }
                if (c.ImGui_Button(if (!disabled) "Clear selection" else "No selection to clear")) {
                    edge_set.clear();
                    sm_store.surfaceMeshCellSetUpdated(sm, .edge, edge_set);
                    sms.app_ctx.requestRedraw();
                }
                if (disabled) {
                    c.ImGui_EndDisabled();
                }
            } else {
                c.ImGui_Text("No cell set selected");
            }
        },
        .face => {
            if (sd.selected_face_set) |face_set| {
                var buf: [64]u8 = undefined;
                const text = std.fmt.bufPrintZ(&buf, "#selected: {d}", .{face_set.cell_set_gen.cells.items.len}) catch "";
                c.ImGui_Text(text);
                c.ImGui_SameLine();
                const disabled = face_set.cell_set_gen.cells.items.len == 0;
                if (disabled) {
                    c.ImGui_BeginDisabled(true);
                }
                if (c.ImGui_Button(if (!disabled) "Clear selection" else "No selection to clear")) {
                    face_set.clear();
                    sm_store.surfaceMeshCellSetUpdated(sm, .face, face_set);
                    sms.app_ctx.requestRedraw();
                }
                if (disabled) {
                    c.ImGui_EndDisabled();
                }
            } else {
                c.ImGui_Text("No cell set selected");
            }
        },
        else => unreachable,
    }

    c.ImGui_SeparatorText("Display");

    switch (sd.selecting_cell_type) {
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
