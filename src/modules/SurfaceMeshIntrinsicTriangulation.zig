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
const IncidenceGraph = @import("../models/incidenceGraph/IncidenceGraph.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const intrinsic_triangulation = @import("../models/surface/intrinsic_triangulation.zig");

pub const ITData = struct {
    app_ctx: *AppContext,
    surface_mesh: *SurfaceMesh,

    it_ctx: ?intrinsic_triangulation.ITContext = null, // optional IT context

    // this IncidenceGraph and its vertex positions are used to store & visualize the traced intrinsic edges on the extrinsic mesh
    // TODO: this is a temporary solution
    intrinsic_edges_ig: ?*IncidenceGraph = null,
    ig_vertex_position: IncidenceGraph.CellData(.vertex, Vec3f) = undefined,

    pub fn initITContext(
        itd: *ITData,
        edge_length: SurfaceMesh.CellData(.edge, f32),
        corner_angle: SurfaceMesh.CellData(.corner, f32),
    ) !void {
        assert(itd.it_ctx == null);
        assert(edge_length.surface_mesh == itd.surface_mesh);
        assert(corner_angle.surface_mesh == itd.surface_mesh);

        itd.it_ctx = try .init(
            itd.app_ctx,
            itd.surface_mesh,
            edge_length,
            corner_angle,
        );
    }

    fn deinit(itd: *ITData) void {
        if (itd.it_ctx) |*ctx| {
            ctx.deinit();
        }
        // the incidence graph is owned by the IncidenceGraphStore, it can stay alive
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
    var it = smit.surface_meshes_data.valueIterator();
    while (it.next()) |itd| {
        itd.deinit();
    }
    smit.surface_meshes_data.deinit(smit.app_ctx.allocator);
}

/// Get the IT data for a given SurfaceMesh.
pub fn surfaceMeshITData(smit: *SurfaceMeshIntrinsicTriangulation, surface_mesh: *SurfaceMesh) *ITData {
    return smit.surface_meshes_data.getPtr(surface_mesh).?;
}

/// Part of the Module interface.
/// Create and store a ITData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smit: *SurfaceMeshIntrinsicTriangulation = @alignCast(@fieldParentPtr("module", m));
    smit.surface_meshes_data.put(smit.app_ctx.allocator, surface_mesh, .{
        .app_ctx = smit.app_ctx,
        .surface_mesh = surface_mesh,
    }) catch |err| {
        std.debug.print("Failed to store ITData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Deinit & remove the ITData associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smit: *SurfaceMeshIntrinsicTriangulation = @alignCast(@fieldParentPtr("module", m));
    if (smit.surface_meshes_data.getPtr(surface_mesh)) |itd| {
        itd.deinit();
    }
    _ = smit.surface_meshes_data.remove(surface_mesh);
}

/// Part of the Module interface.
/// Show a UI panel to control the sampling of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const smit: *SurfaceMeshIntrinsicTriangulation = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &smit.app_ctx.surface_mesh_store;

    assert(smit.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = smit.app_ctx.selected_model.surface_mesh;
    const itd = smit.surface_meshes_data.getPtr(sm).?;
    const info = sm_store.surfaceMeshInfo(sm);

    const UiData = struct {
        var selected_vertex_set: ?*SurfaceMesh.CellSet = null;
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (itd.it_ctx) |*it_ctx| {
        if (c.ImGui_ButtonEx("Deinitialize intrinsic triangulation", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            itd.deinit();
        }
        c.ImGui_Separator();
        if (c.ImGui_ButtonEx("Flip to Delaunay triangulation", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            it_ctx.flipToDelaunay() catch |err| {
                std.debug.print("Error flipping to Delaunay: {}\n", .{err});
            };
        }
        if (c.ImGui_ButtonEx("Refine Delaunay triangulation", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            it_ctx.refineDelaunay(std.math.pi / 7.0) catch |err| {
                std.debug.print("Error refining Delaunay: {}\n", .{err});
            };
        }
        {
            c.ImGui_Text("Shortest geodesic vertex set:");
            c.ImGui_PushID("shortest geodesic vertex set");
            switch (imgui_utils.surfaceMeshCellSetComboBox(sm, .vertex, UiData.selected_vertex_set)) {
                .unchanged => {},
                .cleared => UiData.selected_vertex_set = null,
                .changed => |cell_set| UiData.selected_vertex_set = cell_set,
            }
            c.ImGui_PopID();
            const disabled = UiData.selected_vertex_set == null or
                UiData.selected_vertex_set.?.cells.items.len != 2;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Flip out shortest geodesic", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                it_ctx.flipOutShortestGeodesic(
                    it_ctx.extrinsic_vertex_intrinsic_vertex.value(UiData.selected_vertex_set.?.cells.items[0]),
                    it_ctx.extrinsic_vertex_intrinsic_vertex.value(UiData.selected_vertex_set.?.cells.items[1]),
                    null,
                    null,
                ) catch |err| {
                    std.debug.print("Error flipping out shortest geodesic: {}\n", .{err});
                };
            }
            if (disabled) {
                imgui_utils.tooltip(
                    \\ Select a vertex set with exactly 2 vertices to flip out the shortest geodesic.
                );
                c.ImGui_EndDisabled();
            }
        }
        {
            const disabled = info.std_datas.vertex_position == null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Trace intrinsic edges", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                itd.traceIntrinsicEdges(info.std_datas.vertex_position.?) catch |err| {
                    std.debug.print("Error tracing intrinsic edges: {}\n", .{err});
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
    } else {
        const disabled =
            info.std_datas.edge_length == null or
            info.std_datas.corner_angle == null;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx("Initialize intrinsic triangulation", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            itd.initITContext(
                info.std_datas.edge_length.?,
                info.std_datas.corner_angle.?,
            ) catch |err| {
                std.debug.print("Failed to initialize intrinsic triangulation: {}\n", .{err});
            };
        }
        if (disabled) {
            imgui_utils.tooltip(
                \\ Following data should be available:
                \\ - std edge_length
                \\ - std corner_angle
            );
            c.ImGui_EndDisabled();
        }
    }
}
