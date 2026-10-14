const SurfaceMeshDirectionField = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("c");

const AppContext = @import("../AppContext.zig");
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const direction_field = @import("../models/surface/direction_field.zig");
const gradient = @import("../models/surface/gradient.zig");
const filtering = @import("../models/surface/filtering.zig");

const DirectionFieldData = struct {
    app_ctx: *AppContext,
    surface_mesh: *SurfaceMesh,

    vertex_scalar_field: ?SurfaceMesh.VertexData(f32) = null,
    vertex_direction_field: ?SurfaceMesh.VertexData(Vec3f) = null,

    sdf_ctx: ?direction_field.SmoothestDirectionFieldContext = null,
    // maybe there will be other direction field computation contexts in the future

    fn initSmoothestDirectionFieldContext(
        dfd: *DirectionFieldData,
    ) !void {
        assert(dfd.sdf_ctx == null);
        dfd.sdf_ctx = try .init();
    }

    fn deinit(dfd: *DirectionFieldData) void {
        if (dfd.sdf_ctx) |*sdf_ctx| {
            sdf_ctx.deinit();
            dfd.sdf_ctx = null;
        }
    }
};

app_ctx: *AppContext = undefined,
module: Module = .{
    .name = "Surface Mesh Direction Field",
    .supported_models = .{ .surface_mesh = true },
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .rightPanel = rightPanel,
    },
},
surface_meshes_data: std.AutoHashMapUnmanaged(*SurfaceMesh, DirectionFieldData) = .empty,

/// Modules are default-constructed in AppContext init function, and then initialized in AppContext wireUp function.
pub fn init(smdf: *SurfaceMeshDirectionField, app_ctx: *AppContext) !void {
    smdf.app_ctx = app_ctx;
    try app_ctx.surface_mesh_store.addListener(&smdf.module);
}

pub fn deinit(smdf: *SurfaceMeshDirectionField) void {
    var it = smdf.surface_meshes_data.valueIterator();
    while (it.next()) |dfd| {
        dfd.deinit();
    }
    smdf.surface_meshes_data.deinit(smdf.app_ctx.allocator);
    smdf.app_ctx.surface_mesh_store.removeListener(&smdf.module);
}

/// Part of the Module interface.
/// Create and store a DirectionFieldData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smdf: *SurfaceMeshDirectionField = @alignCast(@fieldParentPtr("module", m));
    smdf.surface_meshes_data.put(smdf.app_ctx.allocator, surface_mesh, .{
        .app_ctx = smdf.app_ctx,
        .surface_mesh = surface_mesh,
    }) catch |err| {
        std.debug.print("Failed to store DirectionFieldData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Remove the DirectionFieldData associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smdf: *SurfaceMeshDirectionField = @alignCast(@fieldParentPtr("module", m));
    if (smdf.surface_meshes_data.getPtr(surface_mesh)) |dfd| {
        dfd.deinit();
    }
    _ = smdf.surface_meshes_data.remove(surface_mesh);
}

/// Part of the Module interface.
/// Show a UI panel to compute a vertex direction field on the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const smdf: *SurfaceMeshDirectionField = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &smdf.app_ctx.surface_mesh_store;

    assert(smdf.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = smdf.app_ctx.selected_model.surface_mesh;
    const dfd = smdf.surface_meshes_data.getPtr(sm).?;
    const info = sm_store.surfaceMeshInfo(sm);

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    c.ImGui_SeparatorText("As gradient of vertex scalar field");

    c.ImGui_Text("Scalar field");
    c.ImGui_PushID("ScalarFieldComboBox");
    switch (imgui_utils.surfaceMeshCellDataComboBox(sm, .vertex, f32, dfd.vertex_scalar_field)) {
        .unchanged => {},
        .cleared => dfd.vertex_scalar_field = null,
        .changed => |data| dfd.vertex_scalar_field = data,
    }
    c.ImGui_PopID();

    c.ImGui_Text("Direction field");
    c.ImGui_PushID("DirectionFieldComboBox");
    switch (imgui_utils.surfaceMeshCellDataComboBox(sm, .vertex, Vec3f, dfd.vertex_direction_field)) {
        .unchanged => {},
        .cleared => dfd.vertex_direction_field = null,
        .changed => |data| dfd.vertex_direction_field = data,
    }
    c.ImGui_PopID();

    if (c.ImGui_ButtonEx(c.ICON_FA_DATABASE ++ " Create direction field data", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
        if (dfd.vertex_direction_field == null) {
            const maybe_data = sm.addData(.vertex, Vec3f, "direction_field");
            if (maybe_data) |data| {
                dfd.vertex_direction_field = data;
            } else |err| {
                zgp_log.err("Error adding direction field data: {}", .{err});
            }
        }
    }

    const disabled =
        dfd.vertex_scalar_field == null or
        dfd.vertex_direction_field == null or
        info.std_datas.vertex_position == null or
        info.std_datas.face_area == null or
        info.std_datas.face_normal == null;
    if (disabled) {
        c.ImGui_BeginDisabled(true);
    }
    if (c.ImGui_ButtonEx("Compute vertex gradient", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) blk: {
        var face_gradient = sm.addData(.face, Vec3f, "face_gradient") catch |err| {
            zgp_log.err("Error adding face gradient data: {}", .{err});
            break :blk;
        };
        defer sm.removeData(face_gradient);
        gradient.computeVertexScalarFieldFaceGradients(
            smdf.app_ctx.io,
            sm,
            info.std_datas.vertex_position.?,
            info.std_datas.face_area.?,
            info.std_datas.face_normal.?,
            f32,
            dfd.vertex_scalar_field.?,
            &face_gradient,
        ) catch |err| {
            zgp_log.err("Error computing face gradient of vertex scalar field: {}", .{err});
            break :blk;
        };
        filtering.computeFaceDataVertexAverages(
            smdf.app_ctx.io,
            sm,
            Vec3f,
            face_gradient,
            &dfd.vertex_direction_field.?,
        ) catch |err| {
            zgp_log.err("Error computing vertex average of incident face gradients: {}", .{err});
            break :blk;
        };
        sm_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, dfd.vertex_direction_field.?);
        smdf.app_ctx.view.requestRedraw();
    }
    if (disabled) {
        imgui_utils.tooltip(
            \\ Following data should be available:
            \\ - selected vertex scalar field
            \\ - selected vertex direction field
            \\ - vertex position
            \\ - face area
            \\ - face normal
        );
        c.ImGui_EndDisabled();
    }
}
