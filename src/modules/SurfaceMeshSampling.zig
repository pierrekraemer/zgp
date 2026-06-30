const SurfaceMeshSampling = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("c");

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfacePoint = @import("../models/surface/SurfacePoint.zig");
const PointCloud = @import("../models/point/PointCloud.zig");
const IncidenceGraph = @import("../models/incidenceGraph/IncidenceGraph.zig");

const Data = @import("../utils/data.zig").Data;
const DataGen = @import("../utils/data.zig").DataGen;

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const bvh = @import("../geometry/bvh.zig");

const sampling = @import("../models/surface/sampling.zig");
const distance = @import("../models/surface/distance.zig");
const gradient = @import("../models/surface/gradient.zig");

const SamplingData = struct {
    app_ctx: *AppContext,
    surface_mesh: *SurfaceMesh,

    samples: *PointCloud = undefined,
    point_position: PointCloud.CellData(Vec3f) = undefined,
    point_color: PointCloud.CellData(Vec3f) = undefined,
    point_surface_point: PointCloud.CellData(SurfacePoint) = undefined,

    vertex_closest_sample: SurfaceMesh.CellData(.vertex, PointCloud.Point) = undefined,
    vertex_color: SurfaceMesh.CellData(.vertex, Vec3f) = undefined,

    samples_connection_graph: *IncidenceGraph = undefined,
    scg_vertex_position: IncidenceGraph.CellData(.vertex, Vec3f) = undefined,

    initialized: bool = false,

    fn init(sd: *SamplingData, pointcloud_name: []const u8) !void {
        if (!sd.initialized) {
            // create samples PointCloud & data
            sd.samples = try sd.app_ctx.point_cloud_store.createPointCloud(pointcloud_name);
            sd.point_position = try sd.samples.addData(Vec3f, "position");
            sd.point_color = try sd.samples.addData(Vec3f, "color");
            sd.point_surface_point = try sd.samples.addData(SurfacePoint, "surface_point");
            sd.app_ctx.point_cloud_store.setPointCloudStdData(sd.samples, .{ .position = sd.point_position });

            // create SurfaceMesh data to store the closest sample for each vertex of the SurfaceMesh
            sd.vertex_closest_sample = try sd.surface_mesh.addData(.vertex, PointCloud.Point, "closest_sample");
            sd.vertex_color = try sd.surface_mesh.addData(.vertex, Vec3f, "closest_sample_color");

            // create samples connection IncidenceGraph & data
            var buf: [64]u8 = undefined;
            const scg_name = std.fmt.bufPrint(&buf, "{s}_scg", .{pointcloud_name}) catch "__scg";
            sd.samples_connection_graph = try sd.app_ctx.incidence_graph_store.createIncidenceGraph(scg_name);
            sd.scg_vertex_position = try sd.samples_connection_graph.addData(.vertex, Vec3f, "position");
            sd.app_ctx.incidence_graph_store.setIncidenceGraphStdData(sd.samples_connection_graph, .{ .vertex_position = sd.scg_vertex_position });

            sd.initialized = true;
        } else {
            sd.samples.clearRetainingCapacity();
            sd.samples_connection_graph.clearRetainingCapacity();
        }

        sd.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(sd.samples);
        sd.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples, Vec3f, sd.point_position);
        sd.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples, Vec3f, sd.point_color);

        sd.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(sd.samples_connection_graph);
        sd.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(sd.samples_connection_graph, .vertex, Vec3f, sd.scg_vertex_position);
    }

    // do not destroy the PointCloud here
    // this function is only called after having being notified of the PointCloud destruction
    fn deinit(sd: *SamplingData) void {
        sd.samples = undefined;
        sd.point_position = undefined;
        sd.point_color = undefined;
        sd.point_surface_point = undefined;
        if (sd.initialized) {
            sd.surface_mesh.removeData(.vertex, PointCloud.Point, sd.vertex_closest_sample);
        }
        sd.initialized = false;
    }

    fn pushDataToPointCloud(
        sd: *SamplingData,
        comptime T: type,
        comptime cell_type: SurfaceMesh.CellType,
        src_data: SurfaceMesh.CellData(cell_type, T),
    ) !void {
        assert(sd.initialized);

        const Task = struct {
            const Task = @This();

            surface_point: PointCloud.CellData(SurfacePoint),
            src_data: SurfaceMesh.CellData(cell_type, T),
            dst_data: PointCloud.CellData(T),

            pub fn run(t: *const Task, point: PointCloud.Point) void {
                t.dst_data.valuePtr(point).* = t.surface_point.value(point).readData(T, cell_type, t.src_data);
            }
        };

        const dst_data = try sd.samples.getOrAddData(T, src_data.name());

        var pctr: PointCloud.ParallelPointTaskRunner = try .init(sd.samples);
        defer pctr.deinit();
        try pctr.run(sd.app_ctx, Task{
            .surface_point = sd.point_surface_point,
            .src_data = src_data,
            .dst_data = dst_data,
        });

        sd.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples, T, dst_data);
        sd.app_ctx.requestRedraw();
    }

    fn snapSamplesToSurfaceMeshVertices(
        sd: *SamplingData,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    ) void {
        assert(sd.initialized);

        var point_it = sd.samples.pointIterator();
        while (point_it.next()) |point| {
            switch (sd.point_surface_point.value(point).type) {
                .vertex => {},
                .edge => |e| {
                    const d = e.cell.dart();
                    const v0: SurfaceMesh.Cell = .{ .vertex = d };
                    const v1: SurfaceMesh.Cell = .{ .vertex = sd.surface_mesh.phi1(d) };
                    if (e.t < 0.5) {
                        sd.point_surface_point.valuePtr(point).* = .{ .surface_mesh = sd.surface_mesh, .type = .{ .vertex = v0 } };
                        sd.point_position.valuePtr(point).* = vertex_position.value(v0);
                    } else {
                        sd.point_surface_point.valuePtr(point).* = .{ .surface_mesh = sd.surface_mesh, .type = .{ .vertex = v1 } };
                        sd.point_position.valuePtr(point).* = vertex_position.value(v1);
                    }
                },
                .face => |f| {
                    const d = f.cell.dart();
                    const v0: SurfaceMesh.Cell = .{ .vertex = d };
                    const v1: SurfaceMesh.Cell = .{ .vertex = sd.surface_mesh.phi1(d) };
                    const v2: SurfaceMesh.Cell = .{ .vertex = sd.surface_mesh.phi_1(d) };
                    if (f.bcoords[0] >= f.bcoords[1] and f.bcoords[0] >= f.bcoords[2]) {
                        sd.point_surface_point.valuePtr(point).* = .{ .surface_mesh = sd.surface_mesh, .type = .{ .vertex = v0 } };
                        sd.point_position.valuePtr(point).* = vertex_position.value(v0);
                    } else if (f.bcoords[1] >= f.bcoords[0] and f.bcoords[1] >= f.bcoords[2]) {
                        sd.point_surface_point.valuePtr(point).* = .{ .surface_mesh = sd.surface_mesh, .type = .{ .vertex = v1 } };
                        sd.point_position.valuePtr(point).* = vertex_position.value(v1);
                    } else {
                        sd.point_surface_point.valuePtr(point).* = .{ .surface_mesh = sd.surface_mesh, .type = .{ .vertex = v2 } };
                        sd.point_position.valuePtr(point).* = vertex_position.value(v2);
                    }
                },
            }
        }
        sd.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples, Vec3f, sd.point_position);
        sd.app_ctx.requestRedraw();
    }

    fn connectSamples(
        sd: *SamplingData,
        halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_area: SurfaceMesh.CellData(.vertex, f32),
        edge_length: SurfaceMesh.CellData(.edge, f32),
        face_area: SurfaceMesh.CellData(.face, f32),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),
    ) !void {
        // first compute the closest sample for each vertex of the SurfaceMesh

        // compute the geodesic distance from each vertex of the SurfaceMesh to its closest sample
        // (only consider samples that are vertex SurfacePoints for now)
        // TODO: support samples that are edge or face SurfacePoints
        const closest_sample_distance = try sd.surface_mesh.addData(.vertex, f32, "closest_sample_distance");
        defer sd.surface_mesh.removeData(.vertex, f32, closest_sample_distance);
        var source_vertices: std.ArrayList(SurfaceMesh.Cell) = try .initCapacity(sd.app_ctx.allocator, sd.samples.nbPoints());
        defer source_vertices.deinit(sd.app_ctx.allocator);
        var point_it = sd.samples.pointIterator();
        while (point_it.next()) |point| {
            const sp = sd.point_surface_point.value(point);
            if (sp.type == .vertex) {
                try source_vertices.append(sd.app_ctx.allocator, sp.type.vertex);
            }
        }
        try distance.computeVertexGeodesicDistancesFromSource(
            sd.app_ctx,
            sd.surface_mesh,
            source_vertices.items, // source should be SurfacePoints
            1.0,
            halfedge_cotan_weight,
            vertex_position,
            vertex_area,
            edge_length,
            face_area,
            face_normal,
            closest_sample_distance,
        );

        // starting from each sample, assign its closest sample to each vertex of the SurfaceMesh by making a
        // flood fill using the geodesic distances computed above as the priority for the flood fill

        // priority queue to store the vertices of the SurfaceMesh to expand from, ordered by their distance to their closest sample
        const VertexQueueContext = struct {
            surface_mesh: *SurfaceMesh,
        };
        const VertexInfo = struct {
            const VertexInfo = @This();
            vertex: SurfaceMesh.Cell,
            point: PointCloud.Point,
            distance: f32,
            pub fn cmp(ctx: VertexQueueContext, a: VertexInfo, b: VertexInfo) std.math.Order {
                const distance_order = std.math.order(a.distance, b.distance);
                if (distance_order != .eq) return distance_order;
                // tie-breaker: use vertex indices to have a deterministic order
                return std.math.order(ctx.surface_mesh.cellIndex(a.vertex), ctx.surface_mesh.cellIndex(b.vertex));
            }
        };
        const VertexQueue = std.PriorityQueue(VertexInfo, VertexQueueContext, VertexInfo.cmp);

        var queue: VertexQueue = .initContext(.{ .surface_mesh = sd.surface_mesh });
        defer queue.deinit(sd.app_ctx.allocator);
        var vertex_marker: SurfaceMesh.CellMarker = try .init(sd.surface_mesh, .vertex);
        defer vertex_marker.deinit();
        point_it.reset();
        while (point_it.next()) |point| {
            const sp = sd.point_surface_point.value(point);
            if (sp.type == .vertex) {
                const v = sp.type.vertex;
                try queue.push(sd.app_ctx.allocator, .{
                    .vertex = v,
                    .point = point,
                    .distance = closest_sample_distance.value(v),
                });
            }
        }
        while (queue.pop()) |v_info| {
            if (vertex_marker.isMarked(v_info.vertex)) {
                continue;
            }
            vertex_marker.mark(v_info.vertex);
            sd.vertex_closest_sample.valuePtr(v_info.vertex).* = v_info.point;
            const cur_dist = closest_sample_distance.value(v_info.vertex);
            var dart_it = sd.surface_mesh.cellDartIterator(v_info.vertex);
            while (dart_it.next()) |d| {
                const next_v: SurfaceMesh.Cell = .{ .vertex = sd.surface_mesh.phi1(d) };
                if (!vertex_marker.isMarked(next_v)) {
                    const next_dist = closest_sample_distance.value(next_v);
                    if (next_dist > cur_dist) { // only expand to vertices that are further away from their closest sample
                        try queue.push(sd.app_ctx.allocator, .{
                            .vertex = next_v,
                            .point = v_info.point,
                            .distance = next_dist,
                        });
                    }
                }
            }
        }

        // update the samples connection graph
        var sample_neighbors = try sd.samples.addData(std.AutoArrayHashMapUnmanaged(PointCloud.Point, void), "__sample_neighbors");
        defer sd.samples.removeData(std.AutoArrayHashMapUnmanaged(PointCloud.Point, void), sample_neighbors);
        point_it.reset();
        while (point_it.next()) |point| {
            sample_neighbors.valuePtr(point).* = .empty;
        }
        defer {
            point_it.reset();
            while (point_it.next()) |point| {
                sample_neighbors.valuePtr(point).deinit(sd.app_ctx.allocator);
            }
        }
        var e_it: SurfaceMesh.CellIterator = try .init(sd.surface_mesh, .edge);
        defer e_it.deinit();
        while (e_it.next()) |e| {
            const s1 = sd.vertex_closest_sample.value(.{ .vertex = e.dart() });
            const s2 = sd.vertex_closest_sample.value(.{ .vertex = sd.surface_mesh.phi1(e.dart()) });
            if (s1 != s2) {
                try sample_neighbors.valuePtr(s1).put(sd.app_ctx.allocator, s2, {});
                try sample_neighbors.valuePtr(s2).put(sd.app_ctx.allocator, s1, {});
            }
        }
        var sample_scg_vertex = try sd.samples.addData(IncidenceGraph.Cell, "__sample_scg_vertex");
        defer sd.samples.removeData(IncidenceGraph.Cell, sample_scg_vertex);
        sd.samples_connection_graph.clearRetainingCapacity();
        point_it.reset();
        while (point_it.next()) |point| {
            const v = try sd.samples_connection_graph.addVertex();
            sample_scg_vertex.valuePtr(point).* = v;
            sd.scg_vertex_position.valuePtr(v).* = sd.point_position.value(point);
            const p_neighbors = sample_neighbors.valuePtr(point);
            for (p_neighbors.keys()) |pn| {
                if (pn < point) {
                    const sn_v = sample_scg_vertex.value(pn);
                    _ = try sd.samples_connection_graph.addEdge(v, sn_v);
                }
            }
        }
        sd.app_ctx.incidence_graph_store.incidenceGraphConnectivityUpdated(sd.samples_connection_graph);
        sd.app_ctx.incidence_graph_store.incidenceGraphDataUpdated(sd.samples_connection_graph, .vertex, Vec3f, sd.scg_vertex_position);

        // assign to each vertex the color of its closest sample
        var vertex_it: SurfaceMesh.CellIterator = try .init(sd.surface_mesh, .vertex);
        defer vertex_it.deinit();
        while (vertex_it.next()) |v| {
            sd.vertex_color.valuePtr(v).* = sd.point_color.value(sd.vertex_closest_sample.value(v));
        }
        sd.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sd.surface_mesh, .vertex, Vec3f, sd.vertex_color);

        // first version of on surface edge paths between connected samples
        const shortest_paths_set = try sd.surface_mesh.getOrAddCellSet(.edge, "shortest_paths");
        shortest_paths_set.clear();
        point_it.reset();
        while (point_it.next()) |point| {
            const p_neighbors = sample_neighbors.valuePtr(point);
            for (p_neighbors.keys()) |pn| {
                if (pn < point) {
                    const start_v = sd.point_surface_point.value(point).type.vertex;
                    const end_v = sd.point_surface_point.value(pn).type.vertex;
                    var path = try distance.shortestEdgePathBetweenVertices(
                        sd.app_ctx,
                        sd.surface_mesh,
                        start_v,
                        end_v,
                        edge_length,
                    );
                    defer path.deinit(sd.app_ctx.allocator);
                    for (path.items) |d| {
                        try shortest_paths_set.add(.{ .edge = d });
                    }
                }
            }
        }
        sd.app_ctx.surface_mesh_store.surfaceMeshCellSetUpdated(sd.surface_mesh, shortest_paths_set);

        sd.app_ctx.requestRedraw();
    }
};

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Sampling",
    .supported_models = .{ .surface_mesh = true },
    .vtable = &.{
        .pointCloudDestroyed = pointCloudDestroyed,
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .rightPanel = rightPanel,
    },
},
surface_meshes_data: std.AutoHashMapUnmanaged(*SurfaceMesh, SamplingData) = .empty,

pub fn init(app_ctx: *AppContext) SurfaceMeshSampling {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(sms: *SurfaceMeshSampling) void {
    sms.surface_meshes_data.deinit(sms.app_ctx.allocator);
}

/// Part of the Module interface.
/// Deinit the SamplingData associated to the destroyed PointCloud.
pub fn pointCloudDestroyed(m: *Module, point_cloud: *PointCloud) void {
    const sms: *SurfaceMeshSampling = @alignCast(@fieldParentPtr("module", m));
    var it = sms.surface_meshes_data.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.samples == point_cloud) {
            entry.value_ptr.deinit();
            break;
        }
    }
}

/// Part of the Module interface.
/// Create and store a SamplingData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const sms: *SurfaceMeshSampling = @alignCast(@fieldParentPtr("module", m));
    sms.surface_meshes_data.put(sms.app_ctx.allocator, surface_mesh, .{
        .app_ctx = sms.app_ctx,
        .surface_mesh = surface_mesh,
    }) catch |err| {
        std.debug.print("Failed to store SamplingData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Remove the SamplingData associated to the destroyed SurfaceMesh
/// and remove the associated SurfacePoint data from the PointCloud (if it exists).
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const sms: *SurfaceMeshSampling = @alignCast(@fieldParentPtr("module", m));
    const sd = sms.surface_meshes_data.getPtr(surface_mesh).?;
    if (sd.initialized) {
        // the SurfacePoint data is no longer valid after the SurfaceMesh is destroyed
        sd.samples.removeData(SurfacePoint, sd.point_surface_point);
    }
    _ = sms.surface_meshes_data.remove(surface_mesh);
}

fn uniformSampling(
    sms: *SurfaceMeshSampling,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    nb_points: usize,
    pointcloud_name: []const u8,
) !void {
    const t = std.Io.Timestamp.now(sms.app_ctx.io, .real);

    const sd = sms.surface_meshes_data.getPtr(sm).?;
    try sd.init(pointcloud_name);

    try sampling.uniformlySamplePointsOnSurface(
        sms.app_ctx,
        sm,
        vertex_position,
        face_area,
        sd.samples,
        sd.point_position,
        sd.point_surface_point,
        nb_points,
    );
    const elapsed: f64 = @floatFromInt(std.Io.Timestamp.untilNow(t, sms.app_ctx.io, .real).nanoseconds);
    zgp_log.info("Uniform sampling computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});

    // assign random colors to the samples
    var point_it = sd.samples.pointIterator();
    while (point_it.next()) |point| {
        var r = sms.app_ctx.rng.random();
        sd.point_color.valuePtr(point).* = .{ 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32) };
    }

    sms.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(sd.samples);
    sms.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples, Vec3f, sd.point_position);
    sms.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples, Vec3f, sd.point_color);

    sms.app_ctx.requestRedraw();
}

fn poissonDiskSampling(
    sms: *SurfaceMeshSampling,
    sm: *SurfaceMesh,
    sm_bvh: *bvh.TrianglesBVH,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    poisson_radius: f32,
    pointcloud_name: []const u8,
) !void {
    const t = std.Io.Timestamp.now(sms.app_ctx.io, .real);

    const sd = sms.surface_meshes_data.getPtr(sm).?;
    try sd.init(pointcloud_name);

    try sampling.poissonDiskSamplePointsOnSurface(
        sms.app_ctx,
        sm,
        sm_bvh,
        vertex_position,
        face_normal,
        sd.samples,
        sd.point_position,
        sd.point_surface_point,
        poisson_radius,
    );
    const elapsed: f64 = @floatFromInt(std.Io.Timestamp.untilNow(t, sms.app_ctx.io, .real).nanoseconds);
    zgp_log.info("Poisson disk sampling computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});

    // assign random colors to the samples
    var point_it = sd.samples.pointIterator();
    while (point_it.next()) |point| {
        var r = sms.app_ctx.rng.random();
        sd.point_color.valuePtr(point).* = .{ 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32) };
    }

    sms.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(sd.samples);
    sms.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples, Vec3f, sd.point_position);
    sms.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples, Vec3f, sd.point_color);

    sms.app_ctx.requestRedraw();
}

/// Part of the Module interface.
/// Show a UI panel to control the sampling of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const sms: *SurfaceMeshSampling = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &sms.app_ctx.surface_mesh_store;

    assert(sms.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = sms.app_ctx.selected_model.surface_mesh;

    const DataTypes = union(enum) { u32: u32, f32: f32, Vec3f: Vec3f };
    const DataTypesTag = std.meta.Tag(DataTypes);
    const UiData = struct {
        var nb_points: usize = 1000;
        var poisson_radius: f32 = 0.02;
        var pointcloud_name_buf: [32]u8 = @splat(0);
        var selected_surface_mesh_cell_type: SurfaceMesh.CellType = .vertex;
        var selected_data_type: DataTypesTag = .Vec3f;
        var selected_data_gen: ?*DataGen = null;
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const info = sm_store.surfaceMeshInfo(sm);
    const sd = sms.surface_meshes_data.getPtr(sm).?;

    if (!sd.initialized) {
        c.ImGui_Text("Samples PointCloud name:");
        _ = c.ImGui_InputText("##Name", &UiData.pointcloud_name_buf, UiData.pointcloud_name_buf.len, c.ImGuiInputTextFlags_CharsNoBlank);
    } else {
        c.ImGui_TextDisabled("Samples PointCloud: ");
        c.ImGui_SameLine();
        c.ImGui_Text(sms.app_ctx.point_cloud_store.pointCloudName(sd.samples).?);
        c.ImGui_Separator();
    }
    const pointcloud_name = if (!sd.initialized) std.mem.sliceTo(&UiData.pointcloud_name_buf, 0) else "_"; // only used when not initialized

    {
        c.ImGui_SeparatorText("Uniform sampling");
        c.ImGui_Text("Number of points");
        c.ImGui_PushID("Number of points");
        _ = c.ImGui_InputInt("", @ptrCast(&UiData.nb_points));
        c.ImGui_PopID();
        const disabled =
            info.std_datas.vertex_position == null or
            info.std_datas.face_area == null or
            pointcloud_name.len == 0;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx("Uniform sampling", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            sms.uniformSampling(
                sm,
                info.std_datas.vertex_position.?,
                info.std_datas.face_area.?,
                UiData.nb_points,
                pointcloud_name,
            ) catch |err| {
                std.debug.print("Error during uniform sampling: {}\n", .{err});
            };
            UiData.pointcloud_name_buf = @splat(0);
        }
        if (disabled) {
            imgui_utils.tooltip(
                \\ Requires:
                \\ - an already sampled PointCloud or a name
                \\ Following data should be available:
                \\ - std vertex_position
                \\ - std face_area
            );
            c.ImGui_EndDisabled();
        }
    }

    {
        c.ImGui_SeparatorText("Poisson disk sampling");
        c.ImGui_Text("Minimum distance");
        c.ImGui_PushID("Minimum distance");
        _ = c.ImGui_InputFloat("", @ptrCast(&UiData.poisson_radius));
        c.ImGui_PopID();
        const disabled =
            !info.bvh.initialized or
            info.std_datas.vertex_position == null or
            info.std_datas.face_normal == null or
            pointcloud_name.len == 0;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx("Poisson disk sampling", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            sms.poissonDiskSampling(
                sm,
                &info.bvh,
                info.std_datas.vertex_position.?,
                info.std_datas.face_normal.?,
                UiData.poisson_radius,
                pointcloud_name,
            ) catch |err| {
                std.debug.print("Error during Poisson disk sampling: {}\n", .{err});
            };
            UiData.pointcloud_name_buf = @splat(0);
        }
        if (disabled) {
            imgui_utils.tooltip(
                \\ Requires:
                \\ - an already sampled PointCloud or a name
                \\ - a BVH
                \\ Following data should be available:
                \\ - std vertex_position
                \\ - std face_normal
            );
            c.ImGui_EndDisabled();
        }
    }

    if (sd.initialized) {
        c.ImGui_SeparatorText("Samples post-processing");

        {
            const disabled = info.std_datas.vertex_position == null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Snap samples to vertices", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                sd.snapSamplesToSurfaceMeshVertices(info.std_datas.vertex_position.?);
            }
            if (disabled) {
                imgui_utils.tooltip(
                    \\ Requires:
                    \\ - an already sampled PointCloud
                    \\ Following data should be available:
                    \\ - std vertex_position
                );
                c.ImGui_EndDisabled();
            }
        }

        {
            if (c.ImGui_ButtonEx("Select samples vertices", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                var vertex_set = sm.getOrAddCellSet(.vertex, "selected_samples_vertices") catch |err| {
                    std.debug.print("Error creating vertex set: {}\n", .{err});
                    return;
                };
                vertex_set.clear();
                var point_it = sd.samples.pointIterator();
                while (point_it.next()) |point| {
                    const sp = sd.point_surface_point.value(point);
                    if (sp.type == .vertex) {
                        vertex_set.add(sp.type.vertex) catch |err| {
                            std.debug.print("Error adding vertex to set: {}\n", .{err});
                        };
                    }
                }
                sm_store.surfaceMeshCellSetUpdated(sm, vertex_set);
                sms.app_ctx.requestRedraw();
            }
        }

        {
            const disabled = info.std_datas.halfedge_cotan_weight == null or
                info.std_datas.vertex_position == null or
                info.std_datas.vertex_area == null or
                info.std_datas.edge_length == null or
                info.std_datas.face_area == null or
                info.std_datas.face_normal == null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Connect samples", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                sd.connectSamples(
                    info.std_datas.halfedge_cotan_weight.?,
                    info.std_datas.vertex_position.?,
                    info.std_datas.vertex_area.?,
                    info.std_datas.edge_length.?,
                    info.std_datas.face_area.?,
                    info.std_datas.face_normal.?,
                ) catch |err| {
                    std.debug.print("Error connecting samples: {}\n", .{err});
                };
            }
            if (disabled) {
                imgui_utils.tooltip(
                    \\ Requires:
                    \\ - an already sampled PointCloud
                    \\ Following data should be available:
                    \\ - std halfedge_cotan_weight
                    \\ - std vertex_position
                    \\ - std vertex_area
                    \\ - std edge_length
                    \\ - std face_area
                    \\ - std face_normal
                );
                c.ImGui_EndDisabled();
            }
        }

        c.ImGui_SeparatorText("Push data SurfaceMesh -> PointCloud");
        {
            c.ImGui_Text("Cell type:");
            c.ImGui_PushID("cell type");
            if (c.ImGui_BeginCombo("", @tagName(UiData.selected_surface_mesh_cell_type), 0)) {
                defer c.ImGui_EndCombo();
                inline for ([_]SurfaceMesh.CellType{ .vertex, .edge, .face }) |cell_type| {
                    const is_selected = UiData.selected_surface_mesh_cell_type == cell_type;
                    if (c.ImGui_SelectableEx(@tagName(cell_type), is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                        UiData.selected_surface_mesh_cell_type = cell_type;
                        UiData.selected_data_gen = null;
                    }
                    if (is_selected) {
                        c.ImGui_SetItemDefaultFocus();
                    }
                }
            }
            c.ImGui_PopID();
            c.ImGui_Text("Data type:");
            c.ImGui_PushID("data type");
            if (c.ImGui_BeginCombo("", @tagName(UiData.selected_data_type), 0)) {
                defer c.ImGui_EndCombo();
                inline for (@typeInfo(DataTypesTag).@"enum".fields) |data_type| {
                    const is_selected = @intFromEnum(UiData.selected_data_type) == data_type.value;
                    if (c.ImGui_SelectableEx(data_type.name, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                        if (!is_selected) {
                            UiData.selected_data_type = @enumFromInt(data_type.value);
                            UiData.selected_data_gen = null;
                        }
                    }
                    if (is_selected) {
                        c.ImGui_SetItemDefaultFocus();
                    }
                }
            }
            c.ImGui_PopID();
            c.ImGui_Text("Source data:");
            inline for ([_]SurfaceMesh.CellType{ .vertex, .edge, .face }) |cell_type| {
                if (UiData.selected_surface_mesh_cell_type == cell_type) {
                    inline for (@typeInfo(DataTypesTag).@"enum".fields) |data_type| {
                        if (UiData.selected_data_type == @as(DataTypesTag, @enumFromInt(data_type.value))) {
                            const T = @FieldType(DataTypes, data_type.name);
                            const selected_cell_data: ?SurfaceMesh.CellData(cell_type, T) = if (UiData.selected_data_gen) |data_gen| blk: {
                                const selected_data: *Data(T) = @fieldParentPtr("data_gen", data_gen);
                                break :blk .{
                                    .surface_mesh = sm,
                                    .data = selected_data,
                                };
                            } else null;
                            switch (imgui_utils.surfaceMeshCellDataComboBox(sm, cell_type, @FieldType(DataTypes, data_type.name), selected_cell_data)) {
                                .unchanged => {},
                                .cleared => UiData.selected_data_gen = null,
                                .changed => |data| UiData.selected_data_gen = &data.data.data_gen,
                            }
                            const disabled = selected_cell_data == null;
                            if (disabled) {
                                c.ImGui_BeginDisabled(true);
                            }
                            if (c.ImGui_ButtonEx(c.ICON_FA_DATABASE ++ " Push data", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                                sd.pushDataToPointCloud(T, cell_type, selected_cell_data.?) catch |err| {
                                    std.debug.print("Error pushing data from SurfaceMesh to PointCloud: {}\n", .{err});
                                };
                            }
                            if (disabled) {
                                imgui_utils.tooltip(
                                    \\ Requires:
                                    \\ - an already sampled PointCloud
                                    \\ - a selected source data
                                );
                                c.ImGui_EndDisabled();
                            }
                        }
                    }
                }
            }
        }
    }
}
