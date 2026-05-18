const SurfaceMeshIntrinsicTriangulation = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("c");

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfacePoint = @import("../models/surface/SurfacePoint.zig");

const Data = @import("../utils/data.zig").Data;
const DataGen = @import("../utils/data.zig").DataGen;

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const length = @import("../models/surface/length.zig");

const ITData = struct {
    app_ctx: *AppContext,

    extrinsic_surface_mesh: *SurfaceMesh = undefined,
    extrinsic_vertex_position: SurfaceMesh.CellData(.vertex, Vec3f) = undefined,

    intrinsic_surface_mesh: *SurfaceMesh = undefined,
    intrinsic_vertex_sp: SurfaceMesh.CellData(.vertex, SurfacePoint) = undefined,
    intrinsic_edge_length: SurfaceMesh.CellData(.edge, f32) = undefined,

    initialized: bool = false,

    fn init(itd: *ITData, extrinsic_surface_mesh: *SurfaceMesh, extrinsic_vertex_position: SurfaceMesh.CellData(.vertex, Vec3f)) !void {
        if (itd.initialized) {
            itd.intrinsic_surface_mesh.deinit();
            itd.app_ctx.allocator.destroy(itd.intrinsic_surface_mesh);
        }
        itd.intrinsic_surface_mesh = try extrinsic_surface_mesh.cloneWithoutCellData();
        itd.intrinsic_vertex_sp = try itd.intrinsic_surface_mesh.addData(.vertex, SurfacePoint, "sp");
        itd.intrinsic_edge_length = try itd.intrinsic_surface_mesh.addData(.edge, f32, "length");

        itd.extrinsic_surface_mesh = extrinsic_surface_mesh;
        itd.extrinsic_vertex_position = extrinsic_vertex_position;

        // after cloning, darts/cells of the intrinsic SurfaceMesh have the same indices as those of the extrinsic SurfaceMesh
        // so we can directly use intrinsic Cells to refer to the corresponding extrinsic Cells
        // and read extrinsic vertex positions using the intrinsic vertex indices

        // initialize intrinsic vertex SurfacePoints (vertex type)
        var int_vertex_it: SurfaceMesh.CellIterator = try .init(itd.intrinsic_surface_mesh, .vertex);
        defer int_vertex_it.deinit();
        while (int_vertex_it.next()) |v| {
            const sp: SurfacePoint = .{
                .surface_mesh = itd.extrinsic_surface_mesh,
                .type = .{
                    .vertex = v,
                },
            };
            itd.intrinsic_vertex_sp.valuePtr(v).* = sp;
        }

        // initialize intrinsic edge lengths using the extrinsic vertex positions
        try length.computeEdgeLengths(itd.app_ctx, itd.intrinsic_surface_mesh, itd.extrinsic_vertex_position, itd.intrinsic_edge_length);

        itd.initialized = true;
    }

    // the intrinsic SurfaceMesh must be deinit & destroyed here as it is not known by the SurfaceMeshStore
    fn deinit(itd: *ITData) void {
        if (itd.initialized) {
            itd.intrinsic_surface_mesh.deinit();
            itd.app_ctx.allocator.destroy(itd.intrinsic_surface_mesh);
            itd.initialized = false;
        }
    }
};

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Intrinsic Triangulation",
    .supported_models = .{ .surface_mesh = true },
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .rightPanel = rightPanel,
    },
},
surface_meshes_data: std.AutoHashMapUnmanaged(*SurfaceMesh, ITData) = .empty,

pub fn init(app_ctx: *AppContext) SurfaceMeshIntrinsicTriangulation {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(smit: *SurfaceMeshIntrinsicTriangulation) void {
    var it = smit.surface_meshes_data.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    smit.surface_meshes_data.deinit(smit.app_ctx.allocator);
}

/// Part of the Module interface.
/// Create and store a ITData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smit: *SurfaceMeshIntrinsicTriangulation = @alignCast(@fieldParentPtr("module", m));
    smit.surface_meshes_data.put(smit.app_ctx.allocator, surface_mesh, .{ .app_ctx = smit.app_ctx }) catch |err| {
        std.debug.print("Failed to store ITData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Deinit & remove the ITData associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smit: *SurfaceMeshIntrinsicTriangulation = @alignCast(@fieldParentPtr("module", m));
    smit.surface_meshes_data.getPtr(surface_mesh).?.deinit();
    _ = smit.surface_meshes_data.remove(surface_mesh);
}

/// Part of the Module interface.
/// Show a UI panel to control the sampling of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const smit: *SurfaceMeshIntrinsicTriangulation = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &smit.app_ctx.surface_mesh_store;

    assert(smit.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = smit.app_ctx.selected_model.surface_mesh;

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const info = sm_store.surfaceMeshInfo(sm);
    const itd = smit.surface_meshes_data.getPtr(sm).?;

    if (!itd.initialized) {
        const disabled =
            info.std_datas.vertex_position == null;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx("Initialize intrinsic triangulation", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            itd.init(sm, info.std_datas.vertex_position.?) catch |err| {
                std.debug.print("Error initializing intrinsic triangulation: {}\n", .{err});
            };
        }
        if (disabled) {
            imgui_utils.tooltip(
                \\ Following data should be available:
                \\ - std vertex_position
            );
            c.ImGui_EndDisabled();
        }
    }

    if (itd.initialized) {
        if (c.ImGui_ButtonEx("Deinitialize intrinsic triangulation", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            itd.deinit();
        }
    }
}
