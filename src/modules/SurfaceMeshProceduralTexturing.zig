const SurfaceMeshProceduralTexturing = @This();

const std = @import("std");
const assert = std.debug.assert;

// const imgui_utils = @import("../utils/imgui.zig");
// const zgp_log = std.log.scoped(.zgp);

const zgp = @import("../main.zig");
const c = zgp.c;

const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const TnBData = struct {
    surface_mesh: *SurfaceMesh,
    vertex_position: ?SurfaceMesh.CellData(.vertex, Vec3f) = null,
    vertex_ref_edge: ?SurfaceMesh.CellData(.vertex, SurfaceMesh.Cell) = null,
    initialized: bool = false,

    pub fn init(tbd: *TnBData, vertex_position: SurfaceMesh.CellData(.vertex, Vec3f)) !void {
        tbd.vertex_position = vertex_position;
        if (!tbd.initialized) {
            tbd.vertex_ref_edge = try tbd.surface_mesh.addData(.vertex, SurfaceMesh.Cell, "__vertex_ref_edge");
        }
        tbd.initialized = true;

        try tbd.computeVertexRefEdges();
    }

    pub fn deinit(tbd: *TnBData) void {
        if (tbd.initialized) {
            tbd.surface_mesh.removeData(.vertex, tbd.vertex_ref_edge.?.gen());
            tbd.initialized = false;
        }
    }

    fn computeVertexRefEdges(tbd: *TnBData) !void {
        assert(tbd.initialized);
        var v_it = try SurfaceMesh.CellIterator(.vertex).init(tbd.surface_mesh);
        defer v_it.deinit();
        while (v_it.next()) |v| {
            tbd.vertex_ref_edge.?.valuePtr(v).* = .{ .edge = v.dart() };
        }
    }
};

module: Module = .{
    .name = "Surface Mesh Procedural Texturing",
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .sdlEvent = sdlEvent,
        .uiPanel = uiPanel,
    },
},

allocator: std.mem.Allocator,
surface_meshes_data: std.AutoHashMap(*SurfaceMesh, TnBData),

pub fn init(allocator: std.mem.Allocator) SurfaceMeshProceduralTexturing {
    return .{
        .allocator = allocator,
        .surface_meshes_data = .init(allocator),
    };
}

pub fn deinit(smpt: *SurfaceMeshProceduralTexturing) void {
    smpt.surface_meshes_data.deinit();
}

/// Part of the Module interface.
/// Create and store a TnBData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smpt: *SurfaceMeshProceduralTexturing = @alignCast(@fieldParentPtr("module", m));
    smpt.surface_meshes_data.put(surface_mesh, .{
        .surface_mesh = surface_mesh,
    }) catch |err| {
        std.debug.print("Failed to store TnBData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Remove the TnBData associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smpt: *SurfaceMeshProceduralTexturing = @alignCast(@fieldParentPtr("module", m));
    const tnb_data = smpt.surface_meshes_data.getPtr(surface_mesh) orelse return;
    tnb_data.deinit();
    _ = smpt.surface_meshes_data.remove(surface_mesh);
}

/// Part of the Module interface.
/// Manage SDL events.
pub fn sdlEvent(m: *Module, event: *const c.SDL_Event) void {
    const smpt: *SurfaceMeshProceduralTexturing = @alignCast(@fieldParentPtr("module", m));
    _ = smpt;
    // const sm_store = &zgp.surface_mesh_store;
    // const view = &zgp.view;

    switch (event.type) {
        c.SDL_EVENT_KEY_DOWN => {
            switch (event.key.key) {
                else => {},
            }
        },
        c.SDL_EVENT_KEY_UP => {
            switch (event.key.key) {
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            switch (event.button.button) {
                else => {},
            }
        },
        else => {},
    }
}

/// Part of the Module interface.
/// Describe the right-click menu interface.
pub fn uiPanel(m: *Module) void {
    const smpt: *SurfaceMeshProceduralTexturing = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &zgp.surface_mesh_store;

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (zgp.surface_mesh_store.selected_surface_mesh) |sm| {
        const info = sm_store.surfaceMeshInfo(sm);
        const tnb_data = smpt.surface_meshes_data.getPtr(sm).?;

        const disabled = info.std_data.vertex_position == null;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx(if (tnb_data.initialized) "Reinitialize data" else "Initialize data", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            _ = tnb_data.init(info.std_data.vertex_position.?) catch |err| {
                std.debug.print("Failed to initialize Procedural Texturing data for SurfaceMesh: {}\n", .{err});
            };
        }
        if (disabled) {
            c.ImGui_EndDisabled();
        }
        if (tnb_data.initialized) {
            // parameters & buttons here
        }
    } else {
        c.ImGui_Text("No SurfaceMesh selected");
    }
}
