const SurfaceMeshDeformation = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");

const c = @import("c");

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfaceMeshStdData = @import("../models/SurfaceMeshStore.zig").SurfaceMeshStdData;

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;

const arap = @import("../models/surface/arap.zig");

const DeformationMode = enum {
    SimpleTranslation,
    ARAP,
};

const DeformationData = struct {
    fixed_vertex_set: ?*SurfaceMesh.CellSet = null, // anchored vertices
    handle_vertex_set: ?*SurfaceMesh.CellSet = null, // handle vertices (moved by user)
    arap_ctx: ?arap.ArapContext = null, // initialized ARAP context
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
surface_meshes_data: std.AutoHashMapUnmanaged(*SurfaceMesh, DeformationData) = .empty,
deformation_mode: DeformationMode = .SimpleTranslation,
arap_iterations: i32 = 5,
dragging: bool = false,
drag_z: f32 = 0,

pub fn init(app_ctx: *AppContext) SurfaceMeshDeformation {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(smd: *SurfaceMeshDeformation) void {
    var it = smd.surface_meshes_data.valueIterator();
    while (it.next()) |dd| {
        if (dd.arap_ctx) |*ctx| {
            ctx.deinit();
        }
    }
    smd.surface_meshes_data.deinit(smd.app_ctx.allocator);
}

/// Part of the Module interface.
/// Create and store a DeformationData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smd: *SurfaceMeshDeformation = @alignCast(@fieldParentPtr("module", m));
    smd.surface_meshes_data.put(smd.app_ctx.allocator, surface_mesh, .{}) catch |err| {
        std.debug.print("Failed to store DeformationData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Remove the DeformationData associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smd: *SurfaceMeshDeformation = @alignCast(@fieldParentPtr("module", m));
    if (smd.surface_meshes_data.getPtr(surface_mesh)) |dd| {
        if (dd.arap_ctx) |*ctx| {
            ctx.deinit();
        }
    }
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
    const info = sm_store.surfaceMeshInfo(sm);

    const can_drag = info.std_datas.vertex_position != null and
        info.std_datas.halfedge_cotan_weight != null and
        dd.handle_vertex_set != null and
        dd.handle_vertex_set.?.cells.items.len > 0 and
        (smd.deformation_mode == .SimpleTranslation or (smd.deformation_mode == .ARAP and dd.arap_ctx != null));

    if (!can_drag) {
        return false;
    }

    return switch (event.type) {
        c.SDL_EVENT_KEY_DOWN => blk: {
            switch (event.key.key) {
                c.SDLK_D => {
                    // compute and store the average depth of the handle vertices
                    smd.drag_z = 0;
                    for (dd.handle_vertex_set.?.indices.items) |vertex_id| {
                        const p = view.worldToView(info.std_datas.vertex_position.?.valueByIndex(vertex_id));
                        if (p) |p_view| {
                            smd.drag_z += p_view[2];
                        }
                    }
                    smd.drag_z /= @floatFromInt(dd.handle_vertex_set.?.indices.items.len);
                    smd.dragging = true;
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
                const p_now = view.viewToWorldZ(event.motion.x, event.motion.y, smd.drag_z);
                const p_prev = view.viewToWorldZ(event.motion.x - event.motion.xrel, event.motion.y - event.motion.yrel, smd.drag_z);
                if (p_now != null and p_prev != null) {
                    const tr = vec.sub3f(p_now.?, p_prev.?);
                    // Translate handle vertices
                    for (dd.handle_vertex_set.?.indices.items) |vertex_id| {
                        const pos = info.std_datas.vertex_position.?.valuePtrByIndex(vertex_id);
                        pos.* = vec.add3f(pos.*, tr);
                    }
                    if (smd.deformation_mode == .ARAP) {
                        dd.arap_ctx.?.solve(@intCast(smd.arap_iterations)) catch |err| {
                            std.debug.print("Failed to solve ARAP: {}\n", .{err});
                            break :blk false;
                        };
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
    const sm_store = &smd.app_ctx.surface_mesh_store;

    assert(smd.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = smd.app_ctx.selected_model.surface_mesh;
    const dd = smd.surface_meshes_data.getPtr(sm).?;
    const info = sm_store.surfaceMeshInfo(sm);

    c.ImGui_SeparatorText("Deformation mode");
    if (c.ImGui_RadioButton("Simple Translation", smd.deformation_mode == .SimpleTranslation)) {
        smd.deformation_mode = .SimpleTranslation;
    }
    c.ImGui_SameLine();
    if (c.ImGui_RadioButton("ARAP", smd.deformation_mode == .ARAP)) {
        smd.deformation_mode = .ARAP;
    }

    c.ImGui_Text("Handle vertices:");
    c.ImGui_PushID("handle vertex set");
    switch (imgui_utils.surfaceMeshCellSetComboBox(sm, .vertex, dd.handle_vertex_set)) {
        .unchanged => {},
        .cleared => dd.handle_vertex_set = null,
        .changed => |cell_set| dd.handle_vertex_set = cell_set,
    }
    c.ImGui_PopID();

    if (smd.deformation_mode == .ARAP) {
        c.ImGui_Separator();
        c.ImGui_Text("Fixed vertices:");
        c.ImGui_PushID("fixed vertex set");
        switch (imgui_utils.surfaceMeshCellSetComboBox(sm, .vertex, dd.fixed_vertex_set)) {
            .unchanged => {},
            .cleared => dd.fixed_vertex_set = null,
            .changed => |cell_set| dd.fixed_vertex_set = cell_set,
        }
        c.ImGui_PopID();

        c.ImGui_Text("ARAP iterations:");
        _ = c.ImGui_SliderIntEx("", &smd.arap_iterations, 1, 20, "%d%%", c.ImGuiSliderFlags_AlwaysClamp);

        c.ImGui_Separator();

        // Initialize ARAP button
        {
            const disabled = dd.fixed_vertex_set == null or
                dd.fixed_vertex_set.?.cells.items.len == 0 or
                dd.handle_vertex_set == null or
                dd.handle_vertex_set.?.cells.items.len == 0 or
                info.std_datas.vertex_position == null or
                info.std_datas.halfedge_cotan_weight == null or
                dd.arap_ctx != null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx(
                if (dd.arap_ctx != null) "ARAP initialized" else "Initialize ARAP",
                c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 },
            )) {
                dd.arap_ctx = arap.ArapContext.init(
                    smd.app_ctx.allocator,
                    sm,
                    info.std_datas.vertex_position.?,
                    info.std_datas.halfedge_cotan_weight.?,
                    dd.fixed_vertex_set.?,
                    dd.handle_vertex_set.?,
                ) catch |err| blk: {
                    std.debug.print("Failed to initialize ARAP: {}\n", .{err});
                    break :blk null;
                };
            }
            if (disabled) {
                if (dd.arap_ctx != null) {
                    imgui_utils.tooltip("ARAP is already initialized. Reset first.");
                } else {
                    imgui_utils.tooltip(
                        \\ Requires:
                        \\ - at least 1 vertex in the fixed vertex set
                        \\ - at least 1 vertex in the handle vertex set
                        \\ Following data should be available:
                        \\ - std vertex_position
                    );
                }
                c.ImGui_EndDisabled();
            }
        }

        // Reset ARAP button
        {
            const disabled = dd.arap_ctx == null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Reset ARAP", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                if (dd.arap_ctx) |*ctx| {
                    ctx.deinit();
                    dd.arap_ctx = null;
                }
            }
            if (disabled) {
                c.ImGui_EndDisabled();
            }
        }
    }
}
