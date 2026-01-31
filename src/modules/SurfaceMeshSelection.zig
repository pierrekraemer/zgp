const SurfaceMeshSelection = @This();

const std = @import("std");
const gl = @import("gl");
const assert = std.debug.assert;

// const imgui_utils = @import("../utils/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const zgp = @import("../main.zig");
const c = zgp.c;

const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfaceMeshStdData = @import("../models/surface/SurfaceMeshStdDatas.zig").SurfaceMeshStdData;

const PointSphere = @import("../rendering/shaders/point_sphere/PointSphere.zig");
const TriFlat = @import("../rendering/shaders/tri_flat/TriFlat.zig");
const VBO = @import("../rendering/VBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;

const SelectionData = struct {
    point_sphere_shader_parameters: PointSphere.Parameters,
    tri_flat_shader_parameters: TriFlat.Parameters,

    pub fn init() SelectionData {
        var p = PointSphere.Parameters.init();
        p.point_size = 0.002;
        p.point_color = .{ 0.0, 1.0, 0.0, 1.0 };
        var t = TriFlat.Parameters.init();
        t.vertex_color = .{ 0.0, 1.0, 0.0, 1.0 };
        return .{
            .point_sphere_shader_parameters = p,
            .tri_flat_shader_parameters = t,
        };
    }

    pub fn deinit(sd: *SelectionData) void {
        sd.point_sphere_shader_parameters.deinit();
        sd.tri_flat_shader_parameters.deinit();
    }
};

allocator: std.mem.Allocator,
surface_meshes_data: std.AutoHashMap(*SurfaceMesh, SelectionData),

selecting: bool = false,
selecting_cell_type: SurfaceMesh.CellType = .vertex,

module: Module = .{
    .name = "Surface Mesh Selection",
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .surfaceMeshStdDataChanged = surfaceMeshStdDataChanged,
        .draw = draw,
        .sdlEvent = sdlEvent,
        .uiPanel = uiPanel,
    },
},

pub fn init(allocator: std.mem.Allocator) SurfaceMeshSelection {
    return .{
        .allocator = allocator,
        .surface_meshes_data = .init(allocator),
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
                const position_vbo: VBO = zgp.surface_mesh_store.dataVBO(.vertex, Vec3f, vertex_position);
                sd.point_sphere_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                sd.tri_flat_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            } else {
                sd.point_sphere_shader_parameters.unsetVertexAttribArray(.position);
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
    const sm_store = &zgp.surface_mesh_store;

    // only draw selection for the currently selected SurfaceMesh
    const sm = sm_store.selected_surface_mesh orelse return;
    const info = sm_store.surfaceMeshInfo(sm);

    const sd = sms.surface_meshes_data.getPtr(sm) orelse return;

    sd.point_sphere_shader_parameters.model_view_matrix = @bitCast(view_matrix);
    sd.point_sphere_shader_parameters.projection_matrix = @bitCast(projection_matrix);
    sd.point_sphere_shader_parameters.draw(info.vertex_set_ibo);

    gl.PolygonOffset(0.0, 1.5);
    sd.tri_flat_shader_parameters.model_view_matrix = @bitCast(view_matrix);
    sd.tri_flat_shader_parameters.projection_matrix = @bitCast(projection_matrix);
    sd.tri_flat_shader_parameters.draw(info.face_set_ibo);
    gl.PolygonOffset(1.0, 1.5);

    // TODO: implement edge sets rendering
}

/// Part of the Module interface.
/// Manage SDL events.
pub fn sdlEvent(m: *Module, event: *const c.SDL_Event) void {
    const sms: *SurfaceMeshSelection = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &zgp.surface_mesh_store;
    const view = &zgp.view;

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
                c.SDLK_S => sms.selecting = false,
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            switch (event.button.button) {
                c.SDL_BUTTON_LEFT => {
                    if (sms.selecting and sm_store.selected_surface_mesh != null) {
                        const sm = sm_store.selected_surface_mesh.?;
                        const info = sm_store.surfaceMeshInfo(sm);
                        // TODO: fallback to brute-force search if the BVH is not available
                        if (info.bvh.bvh_ptr) |_| {
                            if (view.pixelWorldRayIfGeometry(event.button.x, event.button.y)) |ray| {
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
                                        }
                                    },
                                    .edge => {},
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
pub fn uiPanel(m: *Module) void {
    const sms: *SurfaceMeshSelection = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &zgp.surface_mesh_store;

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (sm_store.selected_surface_mesh) |sm| {
        const sd = sms.surface_meshes_data.getPtr(sm).?;
        const info = sm_store.surfaceMeshInfo(sm);

        if (sms.selecting) {
            c.ImGui_Text("Selection mode: ON (hold 'S' to select)");
        } else {
            c.ImGui_Text("Selection mode: OFF (hold 'S' to select)");
        }
        c.ImGui_Separator();

        inline for ([_]SurfaceMesh.CellType{ .vertex, .edge, .face }) |cell_type| {
            // TODO: improve UI for cell sets (clear, invert, etc.)
            c.ImGui_PushID(@tagName(cell_type));
            defer c.ImGui_PopID();
            if (c.ImGui_RadioButton(@tagName(cell_type), sms.selecting_cell_type == cell_type)) {
                sms.selecting_cell_type = cell_type;
            }
            switch (cell_type) {
                .vertex => {
                    c.ImGui_Text("#vertices in set: %d", info.vertex_set.cells.items.len);
                    if (c.ImGui_ButtonEx(
                        if (info.vertex_set.cells.items.len > 0) "Clear selection" else "No selection to clear",
                        c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 },
                    )) {
                        info.vertex_set.clear();
                        sm_store.surfaceMeshCellSetUpdated(sm, cell_type);
                    }

                    c.ImGui_Text("Size");
                    c.ImGui_PushID("DrawSelectedVerticesSize");
                    if (c.ImGui_SliderFloatEx("", &sd.point_sphere_shader_parameters.point_size, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
                        zgp.requestRedraw();
                    }
                    c.ImGui_PopID();
                    if (c.ImGui_ColorEdit3("Color##SelectedVerticesColorEdit", &sd.point_sphere_shader_parameters.point_color, c.ImGuiColorEditFlags_NoInputs)) {
                        zgp.requestRedraw();
                    }
                },
                .edge => {
                    c.ImGui_Text("#edges in set: %d", info.edge_set.cells.items.len);
                    if (c.ImGui_ButtonEx(
                        if (info.edge_set.cells.items.len > 0) "Clear selection" else "No selection to clear",
                        c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 },
                    )) {
                        info.edge_set.clear();
                        sm_store.surfaceMeshCellSetUpdated(sm, cell_type);
                    }
                },
                .face => {
                    c.ImGui_Text("#faces in set: %d", info.face_set.cells.items.len);
                    if (c.ImGui_ButtonEx(
                        if (info.face_set.cells.items.len > 0) "Clear selection" else "No selection to clear",
                        c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 },
                    )) {
                        info.face_set.clear();
                        sm_store.surfaceMeshCellSetUpdated(sm, cell_type);
                    }
                },
                else => {},
            }
            c.ImGui_Separator();
        }
    } else {
        c.ImGui_Text("No SurfaceMesh selected");
    }
}
