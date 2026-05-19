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
const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const geometry_utils = @import("../geometry/utils.zig");

const length = @import("../models/surface/length.zig");
const area = @import("../models/surface/area.zig");
const laplacian = @import("../models/surface/laplacian.zig");

const ITData = struct {
    app_ctx: *AppContext,

    extrinsic_surface_mesh: *SurfaceMesh = undefined,
    extrinsic_vertex_position: SurfaceMesh.CellData(.vertex, Vec3f) = undefined,
    extrinsic_edge_length: SurfaceMesh.CellData(.edge, f32) = undefined,
    extrinsic_corner_angle: SurfaceMesh.CellData(.corner, f32) = undefined,

    intrinsic_surface_mesh: *SurfaceMesh = undefined,
    intrinsic_edge_length: SurfaceMesh.CellData(.edge, f32) = undefined,
    intrinsic_face_area: SurfaceMesh.CellData(.face, f32) = undefined,
    intrinsic_halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32) = undefined,
    intrinsic_vertex_sp: SurfaceMesh.CellData(.vertex, SurfacePoint) = undefined,
    intrinsic_vertex_angle_sum: SurfaceMesh.CellData(.vertex, f32) = undefined,
    intrinsic_vertex_ref_halfedge: SurfaceMesh.CellData(.vertex, SurfaceMesh.Cell) = undefined,
    intrinsic_halfedge_angle: SurfaceMesh.CellData(.halfedge, f32) = undefined,

    initialized: bool = false,

    fn init(
        itd: *ITData,
        extrinsic_surface_mesh: *SurfaceMesh,
        extrinsic_vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        extrinsic_edge_length: SurfaceMesh.CellData(.edge, f32),
        extrinsic_corner_angle: SurfaceMesh.CellData(.corner, f32),
    ) !void {
        if (itd.initialized) {
            itd.intrinsic_surface_mesh.deinit();
            itd.app_ctx.allocator.destroy(itd.intrinsic_surface_mesh);
        }
        itd.intrinsic_surface_mesh = try extrinsic_surface_mesh.cloneWithoutCellData();
        itd.intrinsic_edge_length = try itd.intrinsic_surface_mesh.addData(.edge, f32, "length");
        itd.intrinsic_face_area = try itd.intrinsic_surface_mesh.addData(.face, f32, "area");
        itd.intrinsic_halfedge_cotan_weight = try itd.intrinsic_surface_mesh.addData(.halfedge, f32, "cotan_weight");
        itd.intrinsic_vertex_sp = try itd.intrinsic_surface_mesh.addData(.vertex, SurfacePoint, "sp");
        itd.intrinsic_vertex_angle_sum = try itd.intrinsic_surface_mesh.addData(.vertex, f32, "angle_sum");
        itd.intrinsic_vertex_ref_halfedge = try itd.intrinsic_surface_mesh.addData(.vertex, SurfaceMesh.Cell, "ref_halfedge");
        itd.intrinsic_halfedge_angle = try itd.intrinsic_surface_mesh.addData(.halfedge, f32, "halfedge_angle");

        itd.extrinsic_surface_mesh = extrinsic_surface_mesh;
        itd.extrinsic_vertex_position = extrinsic_vertex_position;
        itd.extrinsic_edge_length = extrinsic_edge_length;
        itd.extrinsic_corner_angle = extrinsic_corner_angle;

        // after cloning, darts/cells of the intrinsic SurfaceMesh have the same indices as those of the extrinsic SurfaceMesh
        // so we can directly use intrinsic Cells to refer to the corresponding extrinsic Cells
        // and read extrinsic data using the intrinsic cells indices

        // initialize intrinsic edge lengths from extrinsic edge lengths
        itd.intrinsic_edge_length.data.copyFrom(extrinsic_edge_length.data);
        // compute intrinsic face areas
        try area.computeFaceAreasIntrinsic(itd.app_ctx, itd.intrinsic_surface_mesh, itd.intrinsic_edge_length, itd.intrinsic_face_area);
        // compute intrinsic halfedge cotan weights
        try laplacian.computeHalfedgeCotanWeightsIntrinsic(itd.app_ctx, itd.intrinsic_surface_mesh, itd.intrinsic_edge_length, itd.intrinsic_face_area, itd.intrinsic_halfedge_cotan_weight);

        // initialize intrinsic vertex data for signpost structure:
        // - vertex SurfacePoints (of vertex type)
        // - vertex angle sums
        // - halfedge angle in vertex w.r.t. the first dart of the vertex
        var int_vertex_it: SurfaceMesh.CellIterator = try .init(itd.intrinsic_surface_mesh, .vertex);
        defer int_vertex_it.deinit();
        while (int_vertex_it.next()) |v| {
            itd.intrinsic_vertex_sp.valuePtr(v).* = .{
                .surface_mesh = itd.extrinsic_surface_mesh,
                .type = .{ .vertex = v },
            };
            itd.intrinsic_vertex_ref_halfedge.valuePtr(v).* = .{ .halfedge = v.dart() };
            var angle_sum: f32 = 0.0;
            var d_it = itd.intrinsic_surface_mesh.cellDartIterator(v);
            while (d_it.next()) |d| {
                itd.intrinsic_halfedge_angle.valuePtr(.{ .halfedge = d }).* = angle_sum;
                angle_sum += extrinsic_corner_angle.value(.{ .corner = d });
            }
            itd.intrinsic_vertex_angle_sum.valuePtr(v).* = angle_sum;
        }

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

    fn flipToDelaunay(itd: *ITData) !void {
        var edges_queue: std.ArrayList(SurfaceMesh.Cell) = try .initCapacity(itd.app_ctx.allocator, itd.intrinsic_surface_mesh.nbCells(.edge));
        defer edges_queue.deinit(itd.app_ctx.allocator);
        var edge_it: SurfaceMesh.CellIterator = try .init(itd.intrinsic_surface_mesh, .edge);
        defer edge_it.deinit();
        while (edge_it.next()) |e| {
            try edges_queue.append(itd.app_ctx.allocator, e);
        }
        var edge_in_queue: SurfaceMesh.CellMarker = try .init(itd.intrinsic_surface_mesh, .edge);
        defer edge_in_queue.deinit();
        edge_in_queue.marker.fill(true); // all edges are initially in the queue
        var nb_flips: usize = 0;
        while (edges_queue.pop()) |e| {
            edge_in_queue.unmark(e);
            if (itd.flipEdgeIfNotDelaunay(e)) {
                // if the edge was flipped, its 4 incident edges might not be Delaunay anymore, so we add them to the queue if they are not already in
                const d = e.dart();
                const dd = itd.intrinsic_surface_mesh.phi2(d);
                const edges: [4]SurfaceMesh.Cell = .{
                    .{ .edge = itd.intrinsic_surface_mesh.phi1(d) },
                    .{ .edge = itd.intrinsic_surface_mesh.phi_1(d) },
                    .{ .edge = itd.intrinsic_surface_mesh.phi1(dd) },
                    .{ .edge = itd.intrinsic_surface_mesh.phi_1(dd) },
                };
                for (edges) |edge| {
                    if (!edge_in_queue.isMarked(edge)) {
                        try edges_queue.append(itd.app_ctx.allocator, edge);
                        edge_in_queue.mark(edge);
                    }
                }
                nb_flips += 1;
            }
        }
        zgp_log.info("Flipped {} edges to get a Delaunay intrinsic triangulation", .{nb_flips});
    }

    fn flipEdgeIfNotDelaunay(itd: *ITData, edge: SurfaceMesh.Cell) bool {
        assert(edge.cellType() == .edge);
        // check if the edge can flip (i.e. not a boundary edge and has no incident vertices of degree 2)
        if (!itd.intrinsic_surface_mesh.canFlipEdge(edge)) {
            return false;
        }
        // do not flip already Delaunay edges
        if (laplacian.edgeCotanWeight(itd.intrinsic_surface_mesh, edge, itd.intrinsic_halfedge_cotan_weight) >= 0.0) {
            return false;
        }

        // compute flipped edge length using intrinsic geometry
        const dA0 = edge.dart();
        const dA1 = itd.intrinsic_surface_mesh.phi1(dA0);
        const dA2 = itd.intrinsic_surface_mesh.phi_1(dA0);
        const dB0 = itd.intrinsic_surface_mesh.phi2(dA0);
        const dB1 = itd.intrinsic_surface_mesh.phi1(dB0);
        const dB2 = itd.intrinsic_surface_mesh.phi_1(dB0);
        const l01 = itd.intrinsic_edge_length.value(.{ .edge = dA1 });
        const l12 = itd.intrinsic_edge_length.value(.{ .edge = dA2 });
        const l23 = itd.intrinsic_edge_length.value(.{ .edge = dB1 });
        const l30 = itd.intrinsic_edge_length.value(.{ .edge = dB2 });
        const l02 = itd.intrinsic_edge_length.value(.{ .edge = dA0 });
        const p3: Vec2f = .{ 0.0, 0.0 };
        const p0: Vec2f = .{ l30, 0.0 };
        const p2 = geometry_utils.layoutTriangleVertex(p3, p0, l02, l23);
        const p1 = geometry_utils.layoutTriangleVertex(p2, p0, l01, l12);
        const l13 = vec.norm2f(vec.sub2f(p3, p1));

        // flip the edge
        itd.intrinsic_surface_mesh.flipEdge(edge);
        // update intrinsic edge length
        itd.intrinsic_edge_length.valuePtr(edge).* = l13;
        // update intrinsic face areas of the 2 faces incident to the flipped edge
        itd.intrinsic_face_area.valuePtr(.{ .face = dA0 }).* = geometry_utils.triangleAreaIntrinsic(l12, l23, l13);
        itd.intrinsic_face_area.valuePtr(.{ .face = dB0 }).* = geometry_utils.triangleAreaIntrinsic(l30, l01, l13);
        // update intrinsic halfedge cotan weights of the flipped edge and the 4 halfedges around it
        const hes: [6]SurfaceMesh.Cell = .{
            .{ .halfedge = dA0 },
            .{ .halfedge = dB0 },
            .{ .halfedge = dA1 },
            .{ .halfedge = dA2 },
            .{ .halfedge = dB1 },
            .{ .halfedge = dB2 },
        };
        for (hes) |he| {
            itd.intrinsic_halfedge_cotan_weight.valuePtr(he).* = laplacian.halfedgeCotanWeightIntrinsic(
                itd.intrinsic_surface_mesh,
                he,
                itd.intrinsic_edge_length,
                itd.intrinsic_face_area,
            );
        }

        return true;
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
            info.std_datas.vertex_position == null or
            info.std_datas.edge_length == null or
            info.std_datas.corner_angle == null;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx("Initialize intrinsic triangulation", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            itd.init(
                sm,
                info.std_datas.vertex_position.?,
                info.std_datas.edge_length.?,
                info.std_datas.corner_angle.?,
            ) catch |err| {
                std.debug.print("Error initializing intrinsic triangulation: {}\n", .{err});
            };
        }
        if (disabled) {
            imgui_utils.tooltip(
                \\ Following data should be available:
                \\ - std vertex_position
                \\ - std edge_length
                \\ - std corner_angle
            );
            c.ImGui_EndDisabled();
        }
    }

    if (itd.initialized) {
        if (c.ImGui_ButtonEx("Deinitialize intrinsic triangulation", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            itd.deinit();
        }
        c.ImGui_Separator();
        if (c.ImGui_ButtonEx("Flip to Delaunay", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            itd.flipToDelaunay() catch |err| {
                std.debug.print("Error flipping to Delaunay: {}\n", .{err});
            };
        }
    }
}
