const SurfaceMeshDeformation = @This();

const std = @import("std");
const assert = std.debug.assert;

const zgp = @import("../main.zig");
const c = zgp.c;

const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfaceMeshStdData = @import("../models/surface/SurfaceMeshStdDatas.zig").SurfaceMeshStdData;

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;

dragging: bool = false,
drag_z: f32 = 0,

module: Module = .{
    .name = "Surface Mesh Deformation",
    .vtable = &.{
        .sdlEvent = sdlEvent,
    },
},

pub fn init() SurfaceMeshDeformation {
    return .{};
}

pub fn deinit(_: *SurfaceMeshDeformation) void {}

/// Part of the Module interface.
/// Manage SDL events.
pub fn sdlEvent(m: *Module, event: *const c.SDL_Event) void {
    const smd: *SurfaceMeshDeformation = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &zgp.surface_mesh_store;
    const view = &zgp.view;

    switch (event.type) {
        c.SDL_EVENT_KEY_DOWN => {
            switch (event.key.key) {
                c.SDLK_D => if (sm_store.selected_surface_mesh) |sm| {
                    const info = sm_store.surfaceMeshInfo(sm);
                    // compute and store the average depth of the selected vertices to drag them at a constant depth while deforming
                    if (info.std_data.vertex_position != null and info.vertex_set.indices.items.len > 0) {
                        smd.drag_z = 0;
                        for (info.vertex_set.indices.items) |vertex_id| {
                            const p = view.worldToView(info.std_data.vertex_position.?.valueByIndex(vertex_id));
                            if (p) |p_view| {
                                smd.drag_z += p_view[2];
                            }
                        }
                        smd.drag_z /= @floatFromInt(info.vertex_set.indices.items.len);
                        smd.dragging = true;
                    }
                },
                else => {},
            }
        },
        c.SDL_EVENT_KEY_UP => {
            switch (event.key.key) {
                c.SDLK_D => smd.dragging = false,
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_MOTION => {
            if (smd.dragging) {
                const sm = sm_store.selected_surface_mesh.?;
                const info = sm_store.surfaceMeshInfo(sm);
                const p1 = view.viewToWorldZ(event.motion.x, event.motion.y, smd.drag_z);
                const p0 = view.viewToWorldZ(event.motion.x - event.motion.xrel, event.motion.y - event.motion.yrel, smd.drag_z);
                if (p0 != null and p1 != null) {
                    const tr = vec.sub3f(p1.?, p0.?);
                    for (info.vertex_set.indices.items) |vertex_id| {
                        const pos = info.std_data.vertex_position.?.valuePtrByIndex(vertex_id);
                        pos.* = vec.add3f(pos.*, tr);
                    }
                    sm_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, info.std_data.vertex_position.?);
                }
            }
        },
        else => {},
    }
}

/// Part of the Module interface.
/// Show a UI panel to control the selected cells of the selected SurfaceMesh.
pub fn uiPanel(m: *Module) void {
    const sms: *SurfaceMeshDeformation = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &zgp.surface_mesh_store;

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

        inline for ([_]SurfaceMesh.CellType{ .vertex, .edge, .face }) |cell_type| {
            c.ImGui_PushID(@tagName(cell_type));
            defer c.ImGui_PopID();
            if (c.ImGui_RadioButton(@tagName(cell_type), sms.selecting_cell_type == cell_type)) {
                sms.selecting_cell_type = cell_type;
            }
            switch (cell_type) {
                .vertex => {
                    c.ImGui_SameLine();
                    c.ImGui_Text("(#vertices in set: %d)", info.vertex_set.cells.items.len);
                    const disabled = info.vertex_set.cells.items.len == 0;
                    if (disabled) {
                        c.ImGui_BeginDisabled(true);
                    }
                    if (c.ImGui_ButtonEx(
                        if (info.vertex_set.cells.items.len > 0) "Clear selection" else "No selection to clear",
                        c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 },
                    )) {
                        info.vertex_set.clear();
                        sm_store.surfaceMeshCellSetUpdated(sm, cell_type);
                    }
                    if (disabled) {
                        c.ImGui_EndDisabled();
                    }

                    c.ImGui_Text("Size");
                    c.ImGui_PushID("DrawSelectedVerticesSize");
                    if (c.ImGui_SliderFloatEx("", &sd.point_sphere_shader_parameters.sphere_radius, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
                        zgp.requestRedraw();
                    }
                    c.ImGui_PopID();
                    if (c.ImGui_ColorEdit3("Color##SelectedVerticesColorEdit", &sd.point_sphere_shader_parameters.sphere_color, c.ImGuiColorEditFlags_NoInputs)) {
                        zgp.requestRedraw();
                    }
                },
                .edge => {
                    c.ImGui_SameLine();
                    c.ImGui_Text("(#edges in set: %d)", info.edge_set.cells.items.len);
                    const disabled = info.edge_set.cells.items.len == 0;
                    if (disabled) {
                        c.ImGui_BeginDisabled(true);
                    }
                    if (c.ImGui_ButtonEx(
                        if (info.edge_set.cells.items.len > 0) "Clear selection" else "No selection to clear",
                        c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 },
                    )) {
                        info.edge_set.clear();
                        sm_store.surfaceMeshCellSetUpdated(sm, cell_type);
                    }
                    if (disabled) {
                        c.ImGui_EndDisabled();
                    }
                },
                .face => {
                    c.ImGui_SameLine();
                    c.ImGui_Text("(#faces in set: %d)", info.face_set.cells.items.len);
                    const disabled = info.face_set.cells.items.len == 0;
                    if (disabled) {
                        c.ImGui_BeginDisabled(true);
                    }
                    if (c.ImGui_ButtonEx(
                        if (info.face_set.cells.items.len > 0) "Clear selection" else "No selection to clear",
                        c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 },
                    )) {
                        info.face_set.clear();
                        sm_store.surfaceMeshCellSetUpdated(sm, cell_type);
                    }
                    if (disabled) {
                        c.ImGui_EndDisabled();
                    }

                    if (c.ImGui_ColorEdit4("Global color##SelectedFacesColorEdit", &sd.tri_flat_shader_parameters.vertex_color, c.ImGuiColorEditFlags_NoInputs)) {
                        zgp.requestRedraw();
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
