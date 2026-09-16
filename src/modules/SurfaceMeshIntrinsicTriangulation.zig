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

const Data = @import("../utils/data.zig").Data;
const DataGen = @import("../utils/data.zig").DataGen;

const vec = @import("../geometry/vec.zig");
const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const geometry_utils = @import("../geometry/utils.zig");

const intrinsic_triangulation = @import("../models/surface/intrinsic_triangulation.zig");
const length = @import("../models/surface/length.zig");
const angle = @import("../models/surface/angle.zig");
const area = @import("../models/surface/area.zig");
const laplacian = @import("../models/surface/laplacian.zig");
const geodesic = @import("../models/surface/geodesic.zig");
const distance = @import("../models/surface/distance.zig");

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

    fn traceIntrinsicEdges(itd: *ITData, extrinsic_vertex_position: SurfaceMesh.CellData(.vertex, Vec3f)) !void {
        if (itd.intrinsic_edges_ig == null) {
            itd.intrinsic_edges_ig = try itd.app_ctx.incidence_graph_store.createIncidenceGraph("intrinsic_edges");
            itd.ig_vertex_position = try itd.intrinsic_edges_ig.?.addData(.vertex, Vec3f, "position");
            itd.app_ctx.incidence_graph_store.setIncidenceGraphStdData(itd.intrinsic_edges_ig.?, .{ .vertex_position = itd.ig_vertex_position });
            itd.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(itd.intrinsic_edges_ig.?);
        }

        // clear the intrinsic edges incidence graph
        itd.intrinsic_edges_ig.?.clearRetainingCapacity();

        if (itd.it_ctx == null) {
            return error.IntrinsicTriangulationNotInitialized;
        }

        var edge_it: SurfaceMesh.CellIterator = try .init(itd.it_ctx.?.intrinsic_surface_mesh, .edge);
        defer edge_it.deinit();
        while (edge_it.next()) |e| {
            const d = e.dart();

            const src_sp = itd.it_ctx.?.intrinsic_vertex_extrinsic_sp.value(.{ .vertex = d });
            const dst_sp = itd.it_ctx.?.intrinsic_vertex_extrinsic_sp.value(.{ .vertex = itd.it_ctx.?.intrinsic_surface_mesh.phi2(d) });

            // original edges trace trivially
            if (itd.it_ctx.?.intrinsic_edge_is_original.value(e)) {
                try itd.it_ctx.?.intrinsic_edge_trace.valuePtr(e).append(itd.app_ctx.allocator, src_sp);
                try itd.it_ctx.?.intrinsic_edge_trace.valuePtr(e).append(itd.app_ctx.allocator, dst_sp);

                // add the vertices and edge to the common subdivision incidence graph
                const p1 = src_sp.readData(Vec3f, .vertex, extrinsic_vertex_position);
                const p2 = dst_sp.readData(Vec3f, .vertex, extrinsic_vertex_position);
                const igv1 = try itd.intrinsic_edges_ig.?.addVertex();
                const igv2 = try itd.intrinsic_edges_ig.?.addVertex();
                itd.ig_vertex_position.valuePtr(igv1).* = p1;
                itd.ig_vertex_position.valuePtr(igv2).* = p2;
                _ = try itd.intrinsic_edges_ig.?.addEdge(igv1, igv2);

                continue;
            }

            // trace the intrinsic edge on the extrinsic mesh
            _ = try geodesic.traceGeodesic(
                itd.app_ctx,
                itd.it_ctx.?.extrinsic_surface_mesh,
                src_sp,
                itd.it_ctx.?.intrinsic_halfedge_extrinsic_sp_angle.value(.{ .halfedge = d }),
                itd.it_ctx.?.intrinsic_edge_length.value(e),
                itd.it_ctx.?.extrinsic_corner_angle,
                itd.it_ctx.?.extrinsic_edge_length,
                itd.it_ctx.?.intrinsic_edge_trace.valuePtr(e),
            );

            // TODO: trim the trace to remove spurious SurfacePoints that are on the edges
            // incident to the destination vertex of the intrinsic edge
            // and snap the last SurfacePoint to the destination vertex of the intrinsic edge

            // add the vertices and edges of the trace to the common subdivision incidence graph
            var previous_sp: ?SurfacePoint = null;
            var previous_igv: ?IncidenceGraph.Cell = null;
            for (itd.it_ctx.?.intrinsic_edge_trace.value(e).items) |sp| {
                const pos = sp.readData(Vec3f, .vertex, extrinsic_vertex_position);
                const igv = try itd.intrinsic_edges_ig.?.addVertex();
                itd.ig_vertex_position.valuePtr(igv).* = pos;
                if (previous_sp) |_| {
                    _ = try itd.intrinsic_edges_ig.?.addEdge(igv, previous_igv.?);
                }
                previous_sp = sp;
                previous_igv = igv;
            }
        }

        itd.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(itd.intrinsic_edges_ig.?, .vertex, Vec3f, itd.ig_vertex_position);
        itd.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(itd.intrinsic_edges_ig.?);
        itd.app_ctx.requestRedraw();
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
