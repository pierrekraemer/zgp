const SurfaceMeshDeformation = @This();

const std = @import("std");
const assert = std.debug.assert;

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

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Deformation",
    .vtable = &.{
        .sdlEvent = sdlEvent,
    },
},
dragging: bool = false,
drag_z: f32 = 0,

pub fn init(app_ctx: *AppContext) SurfaceMeshDeformation {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(_: *SurfaceMeshDeformation) void {}

/// Part of the Module interface.
/// Manage SDL events.
pub fn sdlEvent(m: *Module, event: *const c.SDL_Event) void {
    const smd: *SurfaceMeshDeformation = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &smd.app_ctx.surface_mesh_store;
    const view = &smd.app_ctx.view;

    switch (event.type) {
        c.SDL_EVENT_KEY_DOWN => {
            switch (event.key.key) {
                c.SDLK_D => if (sm_store.selected_surface_mesh) |sm| {
                    const info = sm_store.surfaceMeshInfo(sm);
                    // compute and store the average depth of the selected vertices
                    // used to compute the world-space translation corresponding to mouse movement in the view when dragging
                    if (info.std_datas.vertex_position != null and info.vertex_set.indices.items.len > 0) {
                        smd.drag_z = 0;
                        for (info.vertex_set.indices.items) |vertex_id| {
                            const p = view.worldToView(info.std_datas.vertex_position.?.valueByIndex(vertex_id));
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
                const p_now = view.viewToWorldZ(event.motion.x, event.motion.y, smd.drag_z);
                const p_prev = view.viewToWorldZ(event.motion.x - event.motion.xrel, event.motion.y - event.motion.yrel, smd.drag_z);
                if (p_now != null and p_prev != null) {
                    const tr = vec.sub3f(p_now.?, p_prev.?);
                    for (info.vertex_set.indices.items) |vertex_id| {
                        const pos = info.std_datas.vertex_position.?.valuePtrByIndex(vertex_id);
                        pos.* = vec.add3f(pos.*, tr);
                    }
                    sm_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, info.std_datas.vertex_position.?);
                    smd.app_ctx.requestRedraw();
                }
            }
        },
        else => {},
    }
}
