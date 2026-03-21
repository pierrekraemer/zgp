const SurfaceMeshDeformation = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");

const c = @import("../main.zig").c;

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfaceMeshStdData = @import("../models/SurfaceMeshStore.zig").SurfaceMeshStdData;

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;

const DeformationData = struct {
    selected_vertex_set: ?*SurfaceMesh.CellSet = null,
};

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Deformation",
    .supported_models = .{ .surface_mesh = true },
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .sdlEvent = sdlEvent,
        .rightPanel = rightPanel,
    },
},
surface_meshes_data: std.AutoHashMap(*SurfaceMesh, DeformationData),
dragging: bool = false,
drag_z: f32 = 0,

pub fn init(app_ctx: *AppContext) SurfaceMeshDeformation {
    return .{
        .app_ctx = app_ctx,
        .surface_meshes_data = .init(app_ctx.allocator),
    };
}

pub fn deinit(smd: *SurfaceMeshDeformation) void {
    smd.surface_meshes_data.deinit();
}

/// Part of the Module interface.
/// Create and store a DeformationData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smd: *SurfaceMeshDeformation = @alignCast(@fieldParentPtr("module", m));
    smd.surface_meshes_data.put(surface_mesh, .{}) catch |err| {
        std.debug.print("Failed to store DeformationData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Remove the DeformationData associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smd: *SurfaceMeshDeformation = @alignCast(@fieldParentPtr("module", m));
    _ = smd.surface_meshes_data.remove(surface_mesh);
}

/// Part of the Module interface.
/// Manage SDL events.
pub fn sdlEvent(m: *Module, event: *const c.SDL_Event) bool {
    const smd: *SurfaceMeshDeformation = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &smd.app_ctx.surface_mesh_store;
    const view = &smd.app_ctx.view;

    assert(smd.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = smd.app_ctx.selected_model.surface_mesh;
    const dd = smd.surface_meshes_data.getPtr(sm).?;
    if (dd.selected_vertex_set == null) return false;

    return switch (event.type) {
        c.SDL_EVENT_KEY_DOWN => blk: {
            switch (event.key.key) {
                c.SDLK_D => {
                    const info = sm_store.surfaceMeshInfo(sm);
                    // compute and store the average depth of the selected vertices
                    // used to compute the world-space translation corresponding to mouse movement in the view when dragging
                    if (info.std_datas.vertex_position != null and dd.selected_vertex_set.?.indices.items.len > 0) {
                        smd.drag_z = 0;
                        for (dd.selected_vertex_set.?.indices.items) |vertex_id| {
                            const p = view.worldToView(info.std_datas.vertex_position.?.valueByIndex(vertex_id));
                            if (p) |p_view| {
                                smd.drag_z += p_view[2];
                            }
                        }
                        smd.drag_z /= @floatFromInt(dd.selected_vertex_set.?.indices.items.len);
                        smd.dragging = true;
                    }
                },
                else => {},
            }
            break :blk false;
        },
        c.SDL_EVENT_KEY_UP => blk: {
            switch (event.key.key) {
                c.SDLK_D => smd.dragging = false,
                else => {},
            }
            break :blk false;
        },
        c.SDL_EVENT_MOUSE_MOTION => blk: {
            if (smd.dragging) {
                const info = sm_store.surfaceMeshInfo(sm);
                const p_now = view.viewToWorldZ(event.motion.x, event.motion.y, smd.drag_z);
                const p_prev = view.viewToWorldZ(event.motion.x - event.motion.xrel, event.motion.y - event.motion.yrel, smd.drag_z);
                if (p_now != null and p_prev != null) {
                    const tr = vec.sub3f(p_now.?, p_prev.?);
                    for (dd.selected_vertex_set.?.indices.items) |vertex_id| {
                        const pos = info.std_datas.vertex_position.?.valuePtrByIndex(vertex_id);
                        pos.* = vec.add3f(pos.*, tr);
                    }
                    sm_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, info.std_datas.vertex_position.?);
                    smd.app_ctx.requestRedraw();
                    break :blk true;
                }
            }
            break :blk false;
        },
        else => false,
    };
}

/// Part of the Module interface.
/// Show a UI panel to control the deformation of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const smd: *SurfaceMeshDeformation = @alignCast(@fieldParentPtr("module", m));

    assert(smd.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = smd.app_ctx.selected_model.surface_mesh;
    const dd = smd.surface_meshes_data.getPtr(sm).?;

    c.ImGui_Text("Vertex set:");
    c.ImGui_PushID("vertex set");
    switch (imgui_utils.surfaceMeshCellSetComboBox(sm, .vertex, dd.selected_vertex_set)) {
        .unchanged => {},
        .cleared => dd.selected_vertex_set = null,
        .changed => |cell_set| dd.selected_vertex_set = cell_set,
    }
    c.ImGui_PopID();
}
