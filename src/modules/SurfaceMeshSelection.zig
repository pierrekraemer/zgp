const SurfaceMeshSelection = @This();

const std = @import("std");
const assert = std.debug.assert;

// const imgui_utils = @import("../utils/imgui.zig");
// const zgp_log = std.log.scoped(.zgp);

const zgp = @import("../main.zig");
const c = zgp.c;

const Module = @import("Module.zig");

selecting: bool = false,

module: Module = .{
    .name = "Surface Mesh Selection",
    .vtable = &.{
        .sdlEvent = sdlEvent,
        // .uiPanel = uiPanel,
    },
},

pub fn init() SurfaceMeshSelection {
    return .{};
}

pub fn deinit(_: *SurfaceMeshSelection) void {}

pub fn sdlEvent(m: *Module, event: *const c.SDL_Event) void {
    const sms: *SurfaceMeshSelection = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &zgp.surface_mesh_store;
    const view = &zgp.view;

    switch (event.type) {
        c.SDL_EVENT_KEY_DOWN => {
            switch (event.key.key) {
                c.SDLK_S => sms.selecting = true,
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
                        if (info.bvh.bvh_ptr) |_| {
                            if (view.pixelWorldRayIfGeometry(event.button.x, event.button.y)) |ray| {
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

// /// Part of the Module interface.
// /// Describe the right-click menu interface.
// pub fn uiPanel(m: *Module) void {
//     const sms: *SurfaceMeshSelection = @alignCast(@fieldParentPtr("module", m));
//     const sm_store = &zgp.surface_mesh_store;
// }
