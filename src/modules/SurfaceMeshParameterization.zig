const SurfaceMeshParameterization = @This();

const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("c");

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfacePoint = @import("../models/surface/SurfacePoint.zig");
const PointCloud = @import("../models/point/PointCloud.zig");
const invalid_index = @import("../utils/data.zig").invalid_index;

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec2f = vec.Vec2f;
const bvh = @import("../geometry/bvh.zig");
const geometry_utils = @import("../geometry/utils.zig");

const sampling = @import("../models/surface/sampling.zig");
const distance = @import("../models/surface/distance.zig");
const intrinsic_triangulation = @import("../models/surface/intrinsic_triangulation.zig");

const ParameterizationData = struct {
    app_ctx: *AppContext,

    // the underlying SurfaceMesh on which the parameterization is computed
    surface_mesh: *SurfaceMesh,

    // IT context of the underlying SurfaceMesh
    // the Delaunay intrinsic triangulation is used to compute geodesic distances & tangent space shortest paths lifting
    it_ctx: ?intrinsic_triangulation.ITContext = null,

    // samples are SurfacePoints that lie on the underlying SurfaceMesh (snapped to vertices, for now)
    // each sample gives rise to a local parameterization patch
    samples: ?*PointCloud = null,
    sample_surface_point: PointCloud.CellData(SurfacePoint) = undefined, // for each sample, the corresponding SurfacePoint on the underlying SurfaceMesh
    sample_position: PointCloud.CellData(Vec3f) = undefined, // optional, only useful for inspection of the samples
    sample_color: PointCloud.CellData(Vec3f) = undefined, // optional, only useful for inspection of the samples

    // the samples SurfaceMesh is a triangulation of the samples
    // it is computed as the dual of the discrete geodesic Voronoi diagram of the samples, computed on the Delaunay intrinsic triangulation of the underlying SurfaceMesh
    // each vertex of the samples SurfaceMesh corresponds to a sample
    // each edge of the samples SurfaceMesh is associated with a shortest edge path on the underlying SurfaceMesh
    samples_surface_mesh: ?*SurfaceMesh = null,
    ssm_vertex_sample: SurfaceMesh.CellData(.vertex, PointCloud.Point) = undefined, // for each vertex, the corresponding sample
    ssm_edge_path: SurfaceMesh.CellData(.edge, std.ArrayList(SurfaceMesh.Dart)) = undefined, // for each edge, the corresponding shortest edge path on the underlying SurfaceMesh
    ssm_vertex_position: SurfaceMesh.CellData(.vertex, Vec3f) = undefined, // optional, only useful for inspection of the samples SurfaceMesh

    // a parameterization patch is computed for each sample within the region of the underlying SurfaceMesh that corresponds to the 1-ring of the sample in the samples SurfaceMesh
    // each triangle of the samples SurfaceMesh corresponds to a region of the underlying SurfaceMesh delimited by the shortest edge paths between the 3 samples of the triangle
    // each triangle of the underlying SurfaceMesh is thus associated with 3 parameterization patches, one for each of the 3 samples of the triangle of the samples SurfaceMesh that contains it
    // for each of these 3 patches, the TriangleUVs data stores the index of the sample along with the UV coordinates of the 3 vertices of the triangle in that patch
    triangle_uvs: SurfaceMesh.CellData(.face, TriangleUVs) = undefined,
    // for each face of the underlying SurfaceMesh, the canonical dart used to represent it, so that the vertices of the face can be accessed in a consistent order
    // no matter which dart of the face is used to reach it (initialized in parameterizeSamplePatches)
    triangle_dart: SurfaceMesh.CellData(.face, SurfaceMesh.Dart) = undefined,

    uv_computed: bool = false,

    const TriangleUVs = struct {
        samples: [3]u32, // the index of the 3 samples (i.e. patches) that contain the triangle
        uvs: [3][3]Vec2f, // the UV coordinates of the 3 vertices of the triangle in each of the 3 patches
        distance_to_boundary: [3][3]f32, // the distance of the 3 vertices of the triangle to the boundary of the patch in which it is contained (in the UV space of that patch)

        // samples are snapped to vertices of the underlying SurfaceMesh
        // the X axis of the UV coordinates frame of a sample corresponds to a Dart of its underlying SurfaceMesh vertex
        // this Dart is the one that is used as the zero angle reference in the intrinsic triangulation initialized from the underlying SurfaceMesh

        // const t_uvs: TriangleUVs = ... // given a TriangleUVs
        // const s = t_uvs.samples[0]; // and its first sample
        // const sm_v = pd.sample_surface_point.value(s).type.vertex; // underlying SurfaceMesh vertex corresponding to the sample
        // const it_v = pd.intrinsic_triangulation_data.extrinsic_vertex_intrinsic_vertex.value(sm_v); // intrinsic vertex corresponding to the underlying SurfaceMesh vertex
        // const it_v_sp = pd.intrinsic_triangulation_data.intrinsic_vertex_extrinsic_sp.value(it_v); // extrinsic SurfacePoint (i.e. in the underlying SurfaceMesh and here necessarily of vertex type) corresponding to the intrinsic vertex
        // const uv_origin_dart = it_v_sp.type.vertex.dart();

        // this is a bit convoluted, but necessary
        // sm_v is already a vertex of the underlying SurfaceMesh, however, sm_v.dart() might not be the same as
        // the Dart used to represent the extrinsic SurfacePoint associated to the corresponding intrinsic vertex (it_v_sp.type.vertex.dart())
        // which is the one that is used as the zero angle reference for the tangent space of the intrinsic vertex (and thus for the UV coordinates of the patch associated to the sample)
        // so we go from sample -> underlying SurfaceMesh vertex -> intrinsic vertex -> extrinsic SurfacePoint -> Dart

        pub fn init() TriangleUVs {
            return .{
                .samples = .{ invalid_index, invalid_index, invalid_index },
                .uvs = .{
                    .{ vec.zero2f, vec.zero2f, vec.zero2f },
                    .{ vec.zero2f, vec.zero2f, vec.zero2f },
                    .{ vec.zero2f, vec.zero2f, vec.zero2f },
                },
                .distance_to_boundary = .{
                    .{ 0.0, 0.0, 0.0 },
                    .{ 0.0, 0.0, 0.0 },
                    .{ 0.0, 0.0, 0.0 },
                },
            };
        }

        pub fn registerSample(tri_uvs: *TriangleUVs, sample: u32) !void {
            for (tri_uvs.samples, 0..) |s, i| {
                if (s == sample) {
                    return error.TriangleAlreadyInPatch;
                }
                if (s == invalid_index) {
                    tri_uvs.samples[i] = sample;
                    return;
                }
            }
            return error.TriangleBelongsToMoreThan3Patches;
        }
    };

    fn generateSamples(
        pd: *ParameterizationData,
        sm_bvh: *bvh.TrianglesBVH,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),
        poisson_radius: f32,
    ) !void {
        if (pd.samples) |samples| {
            samples.clearRetainingCapacity();
        } else {
            var buf: [64]u8 = undefined;
            const pc_name = std.fmt.bufPrint(&buf, "{s}_param_samples", .{pd.app_ctx.surface_mesh_store.surfaceMeshName(pd.surface_mesh).?}) catch "__param_samples";
            pd.samples = try pd.app_ctx.point_cloud_store.createPointCloud(pc_name);
            pd.sample_position = try pd.samples.?.addData(Vec3f, "position");
            pd.sample_surface_point = try pd.samples.?.addData(SurfacePoint, "surface_point");
            pd.sample_color = try pd.samples.?.addData(Vec3f, "color");
            pd.app_ctx.point_cloud_store.setPointCloudStdData(pd.samples.?, .{ .position = pd.sample_position });
        }

        const t = std.Io.Timestamp.now(pd.app_ctx.io, .real);

        try sampling.poissonDiskSamplePointsOnSurface(
            pd.app_ctx,
            pd.surface_mesh,
            sm_bvh,
            vertex_position,
            face_normal,
            pd.samples.?,
            pd.sample_position,
            pd.sample_surface_point,
            poisson_radius,
        );

        // snap samples to vertices
        // map each vertex index to the first sample that is snapped to it so that we can detect & remove samples that are snapped to the same vertex
        var vertex_sample: std.AutoHashMapUnmanaged(u32, PointCloud.Point) = .empty;
        defer vertex_sample.deinit(pd.app_ctx.allocator);
        // var connectivity_updated = false;
        var point_it = pd.samples.?.pointIterator();
        while (point_it.next()) |sample| {
            var snapped_to: SurfaceMesh.Cell = undefined;
            const sp = pd.sample_surface_point.valuePtr(sample);
            switch (sp.type) {
                .vertex => |v| {
                    snapped_to = v;
                },
                .edge => |e| {
                    const d = e.cell.dart();
                    const v0: SurfaceMesh.Cell = .{ .vertex = d };
                    const v1: SurfaceMesh.Cell = .{ .vertex = pd.surface_mesh.phi1(d) };
                    // if (e.t < 0.1) {
                    //     snapped_to = v0;
                    // } else if (e.t > 0.9) {
                    //     snapped_to = v1;
                    // } else {
                    //     const pos = sp.readData(Vec3f, .vertex, vertex_position);
                    //     snapped_to = try pd.surface_mesh.cutEdge(e.cell);
                    //     vertex_position.valuePtr(snapped_to).* = pos;
                    //     connectivity_updated = true;
                    // }
                    snapped_to = if (e.t < 0.5) v0 else v1;
                },
                .face => |f| {
                    const d = f.cell.dart();
                    const v0: SurfaceMesh.Cell = .{ .vertex = d };
                    const v1: SurfaceMesh.Cell = .{ .vertex = pd.surface_mesh.phi1(d) };
                    const v2: SurfaceMesh.Cell = .{ .vertex = pd.surface_mesh.phi_1(d) };
                    // if (f.bcoords[0] > 0.9) {
                    //     snapped_to = v0;
                    // } else if (f.bcoords[1] > 0.9) {
                    //     snapped_to = v1;
                    // } else if (f.bcoords[2] > 0.9) {
                    //     snapped_to = v2;
                    // } else {
                    //     const pos = sp.readData(Vec3f, .vertex, vertex_position);
                    //     const d2 = pd.surface_mesh.phi2(d);
                    //     pd.surface_mesh.removeFace(f.cell);
                    //     snapped_to = try pd.surface_mesh.closeHoleWithUmbrella(d2);
                    //     vertex_position.valuePtr(snapped_to).* = pos;
                    //     connectivity_updated = true;
                    // }
                    if (f.bcoords[0] >= f.bcoords[1] and f.bcoords[0] >= f.bcoords[2]) {
                        snapped_to = v0;
                    } else if (f.bcoords[1] >= f.bcoords[0] and f.bcoords[1] >= f.bcoords[2]) {
                        snapped_to = v1;
                    } else {
                        snapped_to = v2;
                    }
                },
            }
            const snapped_to_index = pd.surface_mesh.cellIndex(snapped_to);
            if (vertex_sample.get(snapped_to_index)) |_| {
                pd.samples.?.removePoint(sample); // remove this sample as it is snapped to a vertex that already has a sample
            } else {
                try vertex_sample.put(pd.app_ctx.allocator, snapped_to_index, sample);
                sp.*.type = .{ .vertex = snapped_to };
                pd.sample_position.valuePtr(sample).* = vertex_position.value(snapped_to);
            }
        }

        // assign random colors to the samples
        point_it.reset();
        var r = pd.app_ctx.rng.random();
        while (point_it.next()) |point| {
            pd.sample_color.valuePtr(point).* = .{ 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32) };
        }

        const elapsed: f64 = @floatFromInt(std.Io.Timestamp.untilNow(t, pd.app_ctx.io, .real).nanoseconds);
        zgp_log.info("Samples computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});

        // if (connectivity_updated) {
        //     if (builtin.mode == .Debug) {
        //         const ok = try pd.surface_mesh.checkIntegrity();
        //         if (!ok) {
        //             zgp_log.err("SurfaceMesh integrity check failed after snapping samples to vertices", .{});
        //             return error.InvalidSurfaceMesh;
        //         }
        //     }
        //     pd.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(pd.surface_mesh, .vertex, Vec3f, vertex_position);
        //     pd.app_ctx.surface_mesh_store.surfaceMeshConnectivityUpdated(pd.surface_mesh);
        // }

        pd.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(pd.samples.?);
        pd.app_ctx.point_cloud_store.pointCloudDataUpdated(pd.samples.?, Vec3f, pd.sample_position);
        pd.app_ctx.point_cloud_store.pointCloudDataUpdated(pd.samples.?, Vec3f, pd.sample_color);
        pd.app_ctx.requestRedraw();
    }

    fn connectSamples(
        pd: *ParameterizationData,
        edge_length: SurfaceMesh.CellData(.edge, f32),
    ) !void {
        if (pd.samples == null) {
            return error.SamplesNotGenerated;
        }

        // create or clear the samples SurfaceMesh and its associated data
        if (pd.samples_surface_mesh) |ssm| {
            var edge_path_it = pd.ssm_edge_path.data.iterator();
            while (edge_path_it.next()) |path| {
                path.deinit(pd.app_ctx.allocator);
            }
            ssm.clearRetainingCapacity();
        } else {
            var buf: [64]u8 = undefined;
            const ssm_name = std.fmt.bufPrint(&buf, "{s}_param_ssm", .{pd.app_ctx.surface_mesh_store.surfaceMeshName(pd.surface_mesh).?}) catch "__param_ssm";
            pd.samples_surface_mesh = try pd.app_ctx.surface_mesh_store.createSurfaceMesh(ssm_name);
            pd.ssm_vertex_position = try pd.samples_surface_mesh.?.addData(.vertex, Vec3f, "position");
            pd.ssm_vertex_sample = try pd.samples_surface_mesh.?.addData(.vertex, PointCloud.Point, "sample");
            pd.ssm_edge_path = try pd.samples_surface_mesh.?.addData(.edge, std.ArrayList(SurfaceMesh.Dart), "edge_path");
            pd.app_ctx.surface_mesh_store.setSurfaceMeshStdData(pd.samples_surface_mesh.?, .{ .vertex_position = pd.ssm_vertex_position });
        }

        const t = std.Io.Timestamp.now(pd.app_ctx.io, .real);

        // each sample corresponds to a vertex in the underlying SurfaceMesh (samples have been snapped to vertices)
        // these vertices are used as the source vertices of a multi-source Dijkstra algorithm
        // that is performed on the intrinsic triangulation

        var it_source_vertices: std.ArrayList(SurfaceMesh.Cell) = try .initCapacity(pd.app_ctx.allocator, pd.samples.?.nbPoints());
        defer it_source_vertices.deinit(pd.app_ctx.allocator);

        // maps each source vertex of the underlying SurfaceMesh (represented by its index) back to its corresponding sample
        var source_vertex_sample: std.AutoArrayHashMapUnmanaged(u32, PointCloud.Point) = .empty;
        defer source_vertex_sample.deinit(pd.app_ctx.allocator);

        var point_it = pd.samples.?.pointIterator();
        while (point_it.next()) |sample| {
            const sp = pd.sample_surface_point.value(sample);
            if (sp.type == .vertex) { // all samples are snapped to vertices, so this is always true
                const it_v = pd.it_ctx.?.extrinsic_vertex_intrinsic_vertex.value(sp.type.vertex);
                try it_source_vertices.append(pd.app_ctx.allocator, it_v);
                try source_vertex_sample.put(pd.app_ctx.allocator, pd.surface_mesh.cellIndex(sp.type.vertex), sample);
            } else unreachable; // all samples are snapped to vertices, so this should never happen
        }

        // compute the closest source vertex and distance to it for each vertex in the intrinsic triangulation
        const it_closest_source_distance = try pd.it_ctx.?.intrinsic_surface_mesh.addData(.vertex, f32, "it_closest_source_distance");
        defer pd.it_ctx.?.intrinsic_surface_mesh.removeData(.vertex, f32, it_closest_source_distance);
        const it_closest_source_vertex = try pd.it_ctx.?.intrinsic_surface_mesh.addData(.vertex, ?SurfaceMesh.Cell, "it_closest_source_vertex");
        defer pd.it_ctx.?.intrinsic_surface_mesh.removeData(.vertex, ?SurfaceMesh.Cell, it_closest_source_vertex);
        try distance.multiSourceDijkstraDistancesAndSources(
            pd.app_ctx,
            pd.it_ctx.?.intrinsic_surface_mesh,
            it_source_vertices.items,
            pd.it_ctx.?.intrinsic_edge_length,
            it_closest_source_distance,
            it_closest_source_vertex,
        );

        // for inspection purposes only,
        // copy back the closest source distance and corresponding sample color in the underlying SurfaceMesh
        const vertex_distance, _ = try pd.surface_mesh.getOrAddData(.vertex, f32, "closest_source_distance");
        const vertex_color, _ = try pd.surface_mesh.getOrAddData(.vertex, Vec3f, "closest_sample_color");
        var it_v_it: SurfaceMesh.CellIterator = try .init(pd.it_ctx.?.intrinsic_surface_mesh, .vertex);
        defer it_v_it.deinit();
        while (it_v_it.next()) |it_v| {
            // v is the vertex in the underlying SurfaceMesh corresponding to the intrinsic vertex it_v
            const v = pd.it_ctx.?.intrinsic_vertex_extrinsic_sp.value(it_v).type.vertex;
            vertex_distance.valuePtr(v).* = it_closest_source_distance.value(it_v);
            // if the closest source vertex of it_v is not defined, it means it was not reachable from any source vertex
            if (it_closest_source_vertex.value(it_v)) |it_sv| {
                // sv is the vertex in the underlying SurfaceMesh corresponding to the intrinsic source vertex it_sv
                const sv = pd.it_ctx.?.intrinsic_vertex_extrinsic_sp.value(it_sv).type.vertex;
                const sample = source_vertex_sample.get(pd.surface_mesh.cellIndex(sv)).?; // get the sample corresponding to the closest source vertex
                vertex_color.valuePtr(v).* = pd.sample_color.value(sample);
            } else {
                std.debug.print("Vertex {d} is not reachable from any source vertex\n", .{pd.surface_mesh.cellIndex(v)});
            }
        }
        pd.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(pd.surface_mesh, .vertex, f32, vertex_distance);
        pd.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(pd.surface_mesh, .vertex, Vec3f, vertex_color);

        // build the samples SurfaceMesh as the dual of the partition of the underlying SurfaceMesh induced by the computed closest source vertices
        defer {
            // declare connectivity and position update after the samples SurfaceMesh has been built
            pd.app_ctx.surface_mesh_store.surfaceMeshConnectivityUpdated(pd.samples_surface_mesh.?);
            pd.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(pd.samples_surface_mesh.?, .vertex, Vec3f, pd.ssm_vertex_position);
        }
        // the following data is used to reconstruct the adjacency between faces after they have been created
        const ssm_darts_of_vertex = try pd.samples_surface_mesh.?.addData(.vertex, std.ArrayList(SurfaceMesh.Dart), "darts_of_vertex");
        defer pd.samples_surface_mesh.?.removeData(.vertex, std.ArrayList(SurfaceMesh.Dart), ssm_darts_of_vertex);
        var darts_array_lists_arena = std.heap.ArenaAllocator.init(pd.app_ctx.allocator);
        defer darts_array_lists_arena.deinit();
        // this data is used to map each sample to the index of its corresponding vertex in the samples SurfaceMesh
        const sample_ssm_vertex_index = try pd.samples.?.addData(u32, "sample_ssm_vertex_index");
        defer pd.samples.?.removeData(u32, sample_ssm_vertex_index);
        // create a vertex in the samples SurfaceMesh for each sample
        point_it.reset();
        while (point_it.next()) |sample| {
            const sp = pd.sample_surface_point.value(sample);
            if (sp.type == .vertex) { // all samples are snapped to vertices, so this is always true
                const vertex_index = try pd.samples_surface_mesh.?.getDataIndex(.vertex); // get a new vertex index
                pd.ssm_vertex_position.valuePtrByIndex(vertex_index).* = pd.sample_position.value(sample); // copy the position of the sample to the new vertex
                pd.ssm_vertex_sample.valuePtrByIndex(vertex_index).* = sample; // map the new vertex to the sample
                sample_ssm_vertex_index.valuePtr(sample).* = vertex_index; // map the sample to the new vertex index
                ssm_darts_of_vertex.valuePtrByIndex(vertex_index).* = try .initCapacity(darts_array_lists_arena.allocator(), 8);
            } else unreachable; // all samples are snapped to vertices, so this should never happen
        }
        // create a face in the samples SurfaceMesh for each face in the intrinsic triangulation that has 3 different closest source vertices
        // TODO:
        // - enumerate the edges of the encountered faces (i.e. pairs of samples)
        // - detect edges that are shared by more than 2 faces -> this usually corresponds to pinched edges in the samples SurfaceMesh due to a lack of samples in thin tubular regions of the underlying SurfaceMesh
        // - try to find a relevant place to add a new sample and start the process again
        var it_f_it: SurfaceMesh.CellIterator = try .init(pd.it_ctx.?.intrinsic_surface_mesh, .face);
        defer it_f_it.deinit();
        while (it_f_it.next()) |f| {
            const it_sv0 = it_closest_source_vertex.value(.{ .vertex = f.dart() });
            const it_sv1 = it_closest_source_vertex.value(.{ .vertex = pd.it_ctx.?.intrinsic_surface_mesh.phi1(f.dart()) });
            const it_sv2 = it_closest_source_vertex.value(.{ .vertex = pd.it_ctx.?.intrinsic_surface_mesh.phi_1(f.dart()) });
            if (it_sv0 != null and it_sv1 != null and it_sv2 != null) {
                const sv0 = pd.it_ctx.?.intrinsic_vertex_extrinsic_sp.value(it_sv0.?).type.vertex; // get the corresponding vertex in the underlying SurfaceMesh
                const sv1 = pd.it_ctx.?.intrinsic_vertex_extrinsic_sp.value(it_sv1.?).type.vertex;
                const sv2 = pd.it_ctx.?.intrinsic_vertex_extrinsic_sp.value(it_sv2.?).type.vertex;
                const s0 = source_vertex_sample.get(pd.surface_mesh.cellIndex(sv0)).?; // these vertices are source vertices, so they must have a corresponding sample
                const s1 = source_vertex_sample.get(pd.surface_mesh.cellIndex(sv1)).?;
                const s2 = source_vertex_sample.get(pd.surface_mesh.cellIndex(sv2)).?;
                if (s0 != s1 and s1 != s2 and s2 != s0) {
                    const s0_ssm_vertex_index = sample_ssm_vertex_index.value(s0); // get the vertex indices in the samples SurfaceMesh corresponding to the samples
                    const s1_ssm_vertex_index = sample_ssm_vertex_index.value(s1);
                    const s2_ssm_vertex_index = sample_ssm_vertex_index.value(s2);
                    const face = try pd.samples_surface_mesh.?.addUnboundedFace(3); // create a new triangle face in the samples SurfaceMesh
                    const d0 = face.dart();
                    const d1 = pd.samples_surface_mesh.?.phi1(d0);
                    const d2 = pd.samples_surface_mesh.?.phi1(d1);
                    // index the darts of the new face with the corresponding vertex indices in the samples SurfaceMesh
                    pd.samples_surface_mesh.?.setDartCellIndex(d0, .vertex, s0_ssm_vertex_index);
                    pd.samples_surface_mesh.?.setDartCellIndex(d1, .vertex, s1_ssm_vertex_index);
                    pd.samples_surface_mesh.?.setDartCellIndex(d2, .vertex, s2_ssm_vertex_index);
                    // register the new darts in the darts_of_vertex data of the vertices of the samples SurfaceMesh (used to reconstruct phi2)
                    try ssm_darts_of_vertex.valuePtrByIndex(s0_ssm_vertex_index).append(darts_array_lists_arena.allocator(), d0);
                    try ssm_darts_of_vertex.valuePtrByIndex(s1_ssm_vertex_index).append(darts_array_lists_arena.allocator(), d1);
                    try ssm_darts_of_vertex.valuePtrByIndex(s2_ssm_vertex_index).append(darts_array_lists_arena.allocator(), d2);
                }
            }
        }
        // reconstruct the adjacency between faces in the samples SurfaceMesh
        var nb_boundary_edges: u32 = 0;
        var ssm_dart_it = pd.samples_surface_mesh.?.dartIterator();
        while (ssm_dart_it.next()) |d| {
            if (pd.samples_surface_mesh.?.phi2(d) == d) {
                const vertex_index = pd.samples_surface_mesh.?.dartCellIndex(d, .vertex);
                const next_vertex_index = pd.samples_surface_mesh.?.dartCellIndex(pd.samples_surface_mesh.?.phi1(d), .vertex);
                const next_vertex_darts = ssm_darts_of_vertex.valueByIndex(next_vertex_index);
                const opposite_dart = for (next_vertex_darts.items) |d2| {
                    if (pd.samples_surface_mesh.?.dartCellIndex(pd.samples_surface_mesh.?.phi1(d2), .vertex) == vertex_index) {
                        break d2;
                    }
                } else null;
                if (opposite_dart) |d2| {
                    if (pd.samples_surface_mesh.?.phi2(d2) != d2) {
                        zgp_log.err("Dart {} is already phi2-linked", .{d2});
                        pd.samples_surface_mesh.?.clearRetainingCapacity();
                        return error.InvalidSamplesSurfaceMesh;
                    }
                    pd.samples_surface_mesh.?.phi2Sew(d, d2);
                } else {
                    nb_boundary_edges += 1;
                }
            }
        }
        if (nb_boundary_edges > 0) { // should not happen
            zgp_log.info("found {d} boundary edges", .{nb_boundary_edges});
            const nb_boundary_faces = try pd.samples_surface_mesh.?.close();
            zgp_log.info("closed {d} boundary faces", .{nb_boundary_faces});
        }
        // vertices were already indexed above, but we need to index the edges and faces of the samples SurfaceMesh
        try pd.samples_surface_mesh.?.indexCells(.edge);
        try pd.samples_surface_mesh.?.indexCells(.face);

        if (builtin.mode == .Debug) {
            const ok = try pd.samples_surface_mesh.?.checkIntegrity();
            if (!ok) {
                zgp_log.err("Samples SurfaceMesh integrity check failed", .{});
                return error.InvalidSamplesSurfaceMesh;
            }
        }

        // for each edge of the samples SurfaceMesh, compute the corresponding shortest edge path in the underlying SurfaceMesh
        const shortest_paths_set = try pd.surface_mesh.getOrAddCellSet(.edge, "shortest_paths");
        shortest_paths_set.clear();
        // the edges of the shortest paths are marked in the underlying SurfaceMesh so that we can compute the triangles of the
        // underlying SurfaceMesh region enclosed by the 3 shortest edge paths of each face of the samples SurfaceMesh
        var edge_marker = try SurfaceMesh.CellMarker.init(pd.surface_mesh, .edge);
        defer edge_marker.deinit();
        // as we are running many shortest path computations, we can reuse the same ShortestEdgePathContext for all of them
        // (avoids allocating and deallocating the incoming_dart data and the dart_queue for each edge)
        const incoming_dart = try pd.surface_mesh.addData(.vertex, ?SurfaceMesh.Dart, "__incoming_dart");
        defer pd.surface_mesh.removeData(.vertex, ?SurfaceMesh.Dart, incoming_dart);
        var queue: distance.ShortestEdgePathDartQueue = .empty;
        defer queue.deinit(pd.app_ctx.allocator);
        const shortest_edge_path_ctx: distance.ShortestEdgePathContext = .{
            .surface_mesh = pd.surface_mesh,
            .edge_weight = edge_length,
            .incoming_dart = incoming_dart,
            .dart_queue = &queue,
        };
        var ssm_e_it = try SurfaceMesh.CellIterator.init(pd.samples_surface_mesh.?, .edge);
        defer ssm_e_it.deinit();
        while (ssm_e_it.next()) |e| {
            const s_start = pd.ssm_vertex_sample.value(.{ .vertex = e.dart() });
            const s_end = pd.ssm_vertex_sample.value(.{ .vertex = pd.samples_surface_mesh.?.phi1(e.dart()) });
            const start_v: SurfaceMesh.Cell = pd.sample_surface_point.value(s_start).type.vertex;
            const end_v: SurfaceMesh.Cell = pd.sample_surface_point.value(s_end).type.vertex;
            const path = try distance.shortestEdgePathBetweenVerticesWithContext(
                pd.app_ctx,
                start_v,
                end_v,
                shortest_edge_path_ctx,
            );
            for (path.items) |d| {
                try shortest_paths_set.add(.{ .edge = d });
                edge_marker.mark(.{ .edge = d });
            }
            pd.ssm_edge_path.valuePtr(e).* = path;
        }
        pd.app_ctx.surface_mesh_store.surfaceMeshCellSetUpdated(pd.surface_mesh, shortest_paths_set);
        pd.app_ctx.requestRedraw();

        const elapsed: f64 = @floatFromInt(std.Io.Timestamp.untilNow(t, pd.app_ctx.io, .real).nanoseconds);
        zgp_log.info("Samples SurfaceMesh computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
    }

    fn parameterizeSamplePatches(
        pd: *ParameterizationData,
    ) !void {
        if (pd.samples_surface_mesh == null) {
            return error.SamplesNotConnected;
        }

        if (!pd.uv_computed) {
            pd.triangle_dart = try pd.surface_mesh.addData(.face, SurfaceMesh.Dart, "triangle_dart");
            pd.triangle_uvs = try pd.surface_mesh.addData(.face, TriangleUVs, "triangle_uvs");
        }

        const t = std.Io.Timestamp.now(pd.app_ctx.io, .real);

        // init the triangle canonical Dart & UVs data
        var sm_f_it: SurfaceMesh.CellIterator = try .init(pd.surface_mesh, .face);
        defer sm_f_it.deinit();
        while (sm_f_it.next()) |f| {
            pd.triangle_dart.valuePtr(f).* = f.dart();
            pd.triangle_uvs.valuePtr(f).* = .init();
        }

        // storage for the UV coordinates of the vertices of the patch currently being processed, in the tangent
        // space of its origin vertex; reused (and fully overwritten before being read) for each patch
        var current_patch_uv = try pd.surface_mesh.addData(.vertex, Vec2f, "__current_patch_uv");
        defer pd.surface_mesh.removeData(.vertex, Vec2f, current_patch_uv);
        // storage for the distance of the vertices of the patch currently being processed to the boundary of the patch; reused (and fully overwritten before being read) for each patch
        var current_patch_distance_to_boundary = try pd.surface_mesh.addData(.vertex, f32, "__current_patch_distance_to_boundary");
        defer pd.surface_mesh.removeData(.vertex, f32, current_patch_distance_to_boundary);

        // this data is used to store the incoming dart for each vertex in the shortest path tree
        // a null value indicates a vertex that has not been reached yet
        var incoming_dart = try pd.it_ctx.?.intrinsic_surface_mesh.addData(.vertex, ?SurfaceMesh.Dart, "__incoming_dart");
        defer pd.it_ctx.?.intrinsic_surface_mesh.removeData(.vertex, ?SurfaceMesh.Dart, incoming_dart);

        // Priority queue type for darts of the SurfaceMesh to expand from, ordered by their distance from the origin vertex
        const DartInfo = struct {
            const DartInfo = @This();
            dart: SurfaceMesh.Dart,
            distance: f32, // distance, as a sum of edge lengths, from the origin vertex to the vertex pointed to by the dart
            uv: Vec2f, // UV coordinate of the vertex of the dart in the patch of the origin vertex
            global_angle: f32, // angle formed by the edge of the dart w.r.t. the tangent space of the origin vertex
            pub fn cmp(_: void, a: DartInfo, b: DartInfo) std.math.Order {
                const distance_order = std.math.order(a.distance, b.distance);
                if (distance_order != .eq) return distance_order;
                // tie-breaker: use Dart indices to have a deterministic order
                return std.math.order(a.dart, b.dart);
            }
        };
        const DartQueue = std.PriorityQueue(DartInfo, void, DartInfo.cmp);

        // the dart queue used to expand the shortest path tree from the origin vertex
        var dart_queue: DartQueue = .empty;
        defer dart_queue.deinit(pd.app_ctx.allocator);

        // the set of vertex indices (in the underlying SurfaceMesh) that belong to the patch of the origin vertex,
        // established during the flood fill over the faces of the underlying SurfaceMesh (see below)
        // vertices are progressively removed from this set as their UV coordinates are computed and the expansion is stopped when the set is empty
        // this design is due to the fact that the UV coordinates are computed on the intrinsic triangulation which does not share the same connectivity
        var patch_vertex_indices_set: std.AutoArrayHashMapUnmanaged(u32, void) = .empty;
        defer patch_vertex_indices_set.deinit(pd.app_ctx.allocator);
        // the list of vertex indices (in the underlying SurfaceMesh) that belong to the patch of the origin vertex
        // built progressively while removing vertices from the patch_vertex_indices_set as their UV coordinates are computed
        // used afterwards to compute the distance of each vertex of the patch to the boundary of the patch
        var patch_vertex_indices: std.ArrayList(u32) = .empty;
        defer patch_vertex_indices.deinit(pd.app_ctx.allocator);
        // the set of edge indices (in the underlying SurfaceMesh) that bound the patch
        // built from the edge paths registered on the edges of the samples SurfaceMesh that are opposite to the origin vertex in each of its incident faces
        // used to delimit the flood fill over the faces of the underlying SurfaceMesh that belong to the patch of the origin vertex
        var patch_boundary_edge_indices: std.AutoArrayHashMapUnmanaged(u32, void) = .empty;
        defer patch_boundary_edge_indices.deinit(pd.app_ctx.allocator);
        // the list of segments (pairs of vertex indices in the underlying SurfaceMesh) that bound the patch (built alongside the patch_boundary_edge_indices)
        // used to compute the distance of each vertex of the patch to the boundary of the patch
        var patch_boundary_segments: std.ArrayList([2]u32) = .empty;
        defer patch_boundary_segments.deinit(pd.app_ctx.allocator);
        // the queue and marker used to flood fill the faces of the underlying SurfaceMesh that belong to the patch
        // used to establish the set of vertices that belong to the patch, starting from the faces incident to the origin vertex
        var patch_faces: std.ArrayList(SurfaceMesh.Cell) = .empty;
        defer patch_faces.deinit(pd.app_ctx.allocator);
        var patch_faces_visited: SurfaceMesh.CellMarker = try .init(pd.surface_mesh, .face);
        defer patch_faces_visited.deinit();

        var problematic_faces = try pd.surface_mesh.getOrAddCellSet(.face, "problematic_faces");
        problematic_faces.clear();
        var problematic_vertices = try pd.surface_mesh.getOrAddCellSet(.vertex, "problematic_vertices");
        problematic_vertices.clear();

        var ssm_v_it: SurfaceMesh.CellIterator = try .init(pd.samples_surface_mesh.?, .vertex);
        defer ssm_v_it.deinit();
        while (ssm_v_it.next()) |ssm_v| {
            const sample = pd.ssm_vertex_sample.value(ssm_v);
            const sm_origin_v = pd.sample_surface_point.value(sample).type.vertex;
            const it_origin_v = pd.it_ctx.?.extrinsic_vertex_intrinsic_vertex.value(sm_origin_v);
            const origin_v_index = pd.surface_mesh.cellIndex(sm_origin_v);

            // collect the edges that delimit the patch of the underlying SurfaceMesh that will be parameterized around the origin vertex
            patch_boundary_edge_indices.clearRetainingCapacity();
            patch_boundary_segments.clearRetainingCapacity();
            {
                var dart_it = pd.samples_surface_mesh.?.cellDartIterator(ssm_v);
                while (dart_it.next()) |d| {
                    const d1 = pd.samples_surface_mesh.?.phi1(d);
                    const edge_path = pd.ssm_edge_path.value(.{ .edge = d1 });
                    for (edge_path.items) |dart| {
                        try patch_boundary_edge_indices.put(pd.app_ctx.allocator, pd.surface_mesh.cellIndex(.{ .edge = dart }), {});
                        try patch_boundary_segments.append(pd.app_ctx.allocator, .{
                            pd.surface_mesh.cellIndex(.{ .vertex = dart }),
                            pd.surface_mesh.cellIndex(.{ .vertex = pd.surface_mesh.phi1(dart) }),
                        });
                    }
                }
            }
            // flood fill the faces of the underlying SurfaceMesh, starting from the faces incident to the origin vertex
            // and without crossing the boundary edges collected above, to establish the list of vertices that belong to the patch
            // and register the sample in each triangle of the patch
            // WARNING: in some degenerate cases, in a samples SurfaceMesh triangle ABC, the shortest path from A to C may completely overlap with the shortest path from A to B and B to C (the shortest path from A to C goes through B)
            // in these cases, the triangle ABC has an empty region in the underlying SurfaceMesh, and some triangles incident to the origin vertex actually do not belong to the patch of the origin vertex
            // and the flood fill will not be bounded by the boundary edges and will go over the whole mesh
            patch_vertex_indices_set.clearRetainingCapacity();
            patch_vertex_indices.clearRetainingCapacity();
            patch_faces.clearRetainingCapacity();
            {
                var problematic = false;
                var origin_dart_it = pd.surface_mesh.cellDartIterator(sm_origin_v);
                while (origin_dart_it.next()) |d| {
                    const f: SurfaceMesh.Cell = .{ .face = d };
                    if (!patch_faces_visited.isMarked(f)) {
                        patch_faces_visited.mark(f);
                        try patch_faces.append(pd.app_ctx.allocator, f);
                        pd.triangle_uvs.valuePtr(f).registerSample(sample) catch {
                            // std.debug.print("Error registering sample {d} in triangle {d}: {}\n", .{ sample, pd.surface_mesh.cellIndex(f), err });
                            try problematic_faces.add(f);
                            problematic = true;
                        };
                    }
                }
                var i: usize = 0;
                while (i < patch_faces.items.len) : (i += 1) {
                    const f = patch_faces.items[i];
                    var face_dart_it = pd.surface_mesh.cellDartIterator(f);
                    while (face_dart_it.next()) |d| {
                        try patch_vertex_indices_set.put(pd.app_ctx.allocator, pd.surface_mesh.cellIndex(.{ .vertex = d }), {});
                        if (patch_boundary_edge_indices.contains(pd.surface_mesh.cellIndex(.{ .edge = d }))) {
                            continue; // do not cross a patch boundary edge
                        }
                        const nf: SurfaceMesh.Cell = .{ .face = pd.surface_mesh.phi2(d) };
                        if (!patch_faces_visited.isMarked(nf)) {
                            patch_faces_visited.mark(nf);
                            try patch_faces.append(pd.app_ctx.allocator, nf);
                            pd.triangle_uvs.valuePtr(nf).registerSample(sample) catch {
                                // std.debug.print("Error registering sample {d} in triangle {d}: {}\n", .{ sample, pd.surface_mesh.cellIndex(nf), err });
                                try problematic_faces.add(nf);
                                problematic = true;
                            };
                        }
                    }
                }
                if (problematic and patch_faces.items.len > 1000) {
                    try problematic_vertices.add(sm_origin_v);
                }
                // unmark the visited faces so the marker can be reused for the next origin vertex
                for (patch_faces.items) |f| {
                    patch_faces_visited.unmark(f);
                }
                // the origin vertex is never popped from the shortest path tree expansion below, so remove it now
                _ = patch_vertex_indices_set.swapRemove(origin_v_index);
                try patch_vertex_indices.append(pd.app_ctx.allocator, origin_v_index);
            }

            // initialize the queue with the darts outgoing from the origin vertex
            dart_queue.clearRetainingCapacity();
            {
                const origin_v_angle_sum = pd.it_ctx.?.extrinsic_vertex_angle_sum.valueByIndex(origin_v_index);
                var dart_it = pd.it_ctx.?.intrinsic_surface_mesh.cellDartIterator(it_origin_v);
                while (dart_it.next()) |d| {
                    try dart_queue.push(
                        pd.app_ctx.allocator,
                        .{
                            .dart = d,
                            .distance = pd.it_ctx.?.intrinsic_edge_length.value(.{ .edge = d }),
                            .uv = .{ 0.0, 0.0 },
                            .global_angle = pd.it_ctx.?.intrinsic_halfedge_extrinsic_sp_angle.value(.{ .halfedge = d }) / origin_v_angle_sum * std.math.tau,
                        },
                    );
                }
                current_patch_uv.valuePtrByIndex(origin_v_index).* = .{ 0.0, 0.0 };
            }

            incoming_dart.data.fill(null);
            while (dart_queue.pop()) |d_info| {
                const pointed_v: SurfaceMesh.Cell = .{ .vertex = pd.it_ctx.?.intrinsic_surface_mesh.phi1(d_info.dart) };
                const pointed_v_index = pd.it_ctx.?.intrinsic_surface_mesh.cellIndex(pointed_v);
                // if the pointed vertex has already been reached, or is the origin vertex, skip it
                if (incoming_dart.value(pointed_v) != null or pointed_v_index == origin_v_index) {
                    continue;
                }
                // the queue is ordered by distance, so the first time we reach a vertex is the shortest path to it
                incoming_dart.valuePtr(pointed_v).* = d_info.dart;

                // the UV coordinate of pointed_v is the UV coordinate of v + the vector from v to pointed_v in the tangent space of the origin vertex
                const l = pd.it_ctx.?.intrinsic_edge_length.value(.{ .edge = d_info.dart });
                const uv = vec.add2f(d_info.uv, .{
                    l * std.math.cos(d_info.global_angle),
                    l * std.math.sin(d_info.global_angle),
                });

                // the UV coordinate is only recorded if the vertex belongs to the patch of the origin vertex;
                // the patch is completely covered when all of its vertices have been reached, and the expansion can then stop
                if (patch_vertex_indices_set.swapRemove(pointed_v_index)) { // return true if the vertex was in the set and has been removed
                    try patch_vertex_indices.append(pd.app_ctx.allocator, pointed_v_index);
                    current_patch_uv.valuePtrByIndex(pointed_v_index).* = uv;
                    if (patch_vertex_indices_set.count() == 0) {
                        break; // all vertices of the patch have been reached, we can stop the expansion
                    }
                }
                // otherwise, enqueue the edges outgoing from pointed_v
                var dart_it = pd.it_ctx.?.intrinsic_surface_mesh.cellDartIterator(pointed_v);
                // a_prev is the angle of the edge from pointed_v to v (i.e. looking back in the shortest path towards the origin vertex)
                // in the local tangent space of pointed_v
                const pointed_v_angle_sum = pd.it_ctx.?.extrinsic_vertex_angle_sum.valueByIndex(pointed_v_index);
                const a_prev = pd.it_ctx.?.intrinsic_halfedge_extrinsic_sp_angle.value(.{
                    .halfedge = pd.it_ctx.?.intrinsic_surface_mesh.phi2(d_info.dart),
                }) / pointed_v_angle_sum * std.math.tau;
                while (dart_it.next()) |out_d| {
                    const nv: SurfaceMesh.Cell = .{ .vertex = pd.it_ctx.?.intrinsic_surface_mesh.phi1(out_d) };
                    // if the neighbor vertex across the edge has already been reached, skip it
                    if (incoming_dart.value(nv) != null) {
                        continue;
                    }
                    // a is the angle of the edge from pointed_v to nv in the local tangent space of pointed_v
                    const a = pd.it_ctx.?.intrinsic_halfedge_extrinsic_sp_angle.value(.{ .halfedge = out_d }) / pointed_v_angle_sum * std.math.tau;
                    const delta_a = a - a_prev; // this encodes the difference between where we go and where we come from
                    try dart_queue.push(
                        pd.app_ctx.allocator,
                        .{
                            .dart = out_d,
                            .distance = d_info.distance + pd.it_ctx.?.intrinsic_edge_length.value(.{ .edge = out_d }),
                            .uv = uv,
                            // the global angle (i.e. angle in the tangent space of the origin vertex) for this outgoing dart
                            // is the global angle of the edge we come from + delta_a + PI (modulo 2*PI)
                            .global_angle = @mod(d_info.global_angle + delta_a + std.math.pi, std.math.tau),
                        },
                    );
                }
            }

            // compute the distance of each vertex of the patch to the boundary of the patch, in the UV space of the patch
            for (patch_vertex_indices.items) |v_index| {
                const p = current_patch_uv.valueByIndex(v_index);
                var min_dist_squared = std.math.floatMax(f32);
                for (patch_boundary_segments.items) |segment| {
                    const a = current_patch_uv.valueByIndex(segment[0]);
                    const b = current_patch_uv.valueByIndex(segment[1]);
                    const dist = geometry_utils.squaredDistanceSegmentPoint(a, b, p);
                    if (dist < min_dist_squared) {
                        min_dist_squared = dist;
                    }
                }
                current_patch_distance_to_boundary.valuePtrByIndex(v_index).* = std.math.sqrt(min_dist_squared);
            }

            // re-center the patch's UV space on its farthest-from-the-boundary vertex instead of on the origin (sample) vertex
            // and normalize the distance to boundary values accordingly, so that the distance at the origin is 1 and the distance on the boundary is 0
            {
                var farthest_v_index = origin_v_index;
                var farthest_dist = current_patch_distance_to_boundary.valueByIndex(origin_v_index);
                for (patch_vertex_indices.items) |v_index| {
                    const d = current_patch_distance_to_boundary.valueByIndex(v_index);
                    if (d > farthest_dist) {
                        farthest_dist = d;
                        farthest_v_index = v_index;
                    }
                }
                const new_origin_uv = current_patch_uv.valueByIndex(farthest_v_index);
                for (patch_vertex_indices.items) |v_index| {
                    current_patch_uv.valuePtrByIndex(v_index).* = vec.sub2f(current_patch_uv.valueByIndex(v_index), new_origin_uv);
                    // commented out version normalizes the distance smoothly to 0 at the boundary and 1 at the farthest vertex, even if the farthest vertex is not the origin vertex
                    // not useful now that the origin of the patch is re-centered on the farthest vertex
                    current_patch_distance_to_boundary.valuePtrByIndex(v_index).* /= farthest_dist; // / (current_patch_distance_to_boundary.valueByIndex(v_index) + vec.norm2f(current_patch_uv.valueByIndex(v_index)));
                }
            }

            // now that the UV coordinates and distance to boundary of the patch vertices are known, write them directly into the triangle_uvs
            // data of the patch faces, in the order induced by the canonical dart of each triangle
            for (patch_faces.items) |f| {
                const tri_dart = pd.triangle_dart.value(f);
                const v0_index = pd.surface_mesh.cellIndex(.{ .vertex = tri_dart });
                const v1_index = pd.surface_mesh.cellIndex(.{ .vertex = pd.surface_mesh.phi1(tri_dart) });
                const v2_index = pd.surface_mesh.cellIndex(.{ .vertex = pd.surface_mesh.phi_1(tri_dart) });
                const tri_uvs = pd.triangle_uvs.valuePtr(f);
                const slot = for (tri_uvs.samples, 0..) |s, idx| {
                    if (s == sample) break idx;
                } else continue; // unreachable; // the sample was registered in this face during the flood fill above, so it must be found
                tri_uvs.uvs[slot] = .{
                    current_patch_uv.valueByIndex(v0_index),
                    current_patch_uv.valueByIndex(v1_index),
                    current_patch_uv.valueByIndex(v2_index),
                };
                tri_uvs.distance_to_boundary[slot] = .{
                    current_patch_distance_to_boundary.valueByIndex(v0_index),
                    current_patch_distance_to_boundary.valueByIndex(v1_index),
                    current_patch_distance_to_boundary.valueByIndex(v2_index),
                };
            }
        }

        pd.app_ctx.surface_mesh_store.surfaceMeshCellSetUpdated(pd.surface_mesh, problematic_faces);
        pd.app_ctx.surface_mesh_store.surfaceMeshCellSetUpdated(pd.surface_mesh, problematic_vertices);
        pd.app_ctx.requestRedraw();

        pd.uv_computed = true;

        const elapsed: f64 = @floatFromInt(std.Io.Timestamp.untilNow(t, pd.app_ctx.io, .real).nanoseconds);
        zgp_log.info("Patches parameterized in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
    }

    // this function is called when the underlying SurfaceMesh is destroyed
    fn surfaceMeshDestroyed(pd: *ParameterizationData) !void {
        if (pd.samples_surface_mesh) |ssm| {
            pd.app_ctx.surface_mesh_store.destroySurfaceMesh(ssm); // triggers the samplesSurfaceMeshDestroyed function
        }
        if (pd.samples) |samples| {
            pd.app_ctx.point_cloud_store.destroyPointCloud(samples); // triggers the samplesDestroyed function
        }
    }

    // this function is called when then samples PointCloud is destroyed
    fn samplesDestroyed(pd: *ParameterizationData) !void {
        pd.samples = null;
        pd.sample_position = undefined;
        pd.sample_surface_point = undefined;
        pd.sample_color = undefined;
        // if the samples SurfaceMesh exists, destroy it
        if (pd.samples_surface_mesh) |ssm| {
            pd.app_ctx.surface_mesh_store.destroySurfaceMesh(ssm); // triggers the samplesSurfaceMeshDestroyed function
        }
    }

    // this function is called when the samples SurfaceMesh is destroyed
    fn samplesSurfaceMeshDestroyed(pd: *ParameterizationData) !void {
        var edge_path_it = pd.ssm_edge_path.data.iterator();
        while (edge_path_it.next()) |path| {
            path.deinit(pd.app_ctx.allocator);
        }
        pd.samples_surface_mesh = null;
        pd.ssm_vertex_position = undefined;
        pd.ssm_vertex_sample = undefined;
        pd.ssm_edge_path = undefined;
    }
};

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Parameterization",
    .supported_models = .{ .surface_mesh = true },
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .pointCloudDestroyed = pointCloudDestroyed,
        .rightPanel = rightPanel,
    },
},
surface_meshes_data: std.AutoHashMapUnmanaged(*SurfaceMesh, ParameterizationData) = .empty,

pub fn init(app_ctx: *AppContext) SurfaceMeshParameterization {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(smp: *SurfaceMeshParameterization) void {
    var it = smp.surface_meshes_data.valueIterator();
    while (it.next()) |pd| {
        if (pd.samples_surface_mesh) |_| {
            var edge_path_it = pd.ssm_edge_path.data.iterator();
            while (edge_path_it.next()) |path| {
                path.deinit(smp.app_ctx.allocator);
            }
        }
    }
    smp.surface_meshes_data.deinit(smp.app_ctx.allocator);
}

pub fn surfaceMeshParameterizationData(smp: *SurfaceMeshParameterization, surface_mesh: *SurfaceMesh) *ParameterizationData {
    return smp.surface_meshes_data.getPtr(surface_mesh).?;
}

/// Part of the Module interface.
/// Create and store a ParameterizationData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smp: *SurfaceMeshParameterization = @alignCast(@fieldParentPtr("module", m));
    smp.surface_meshes_data.put(smp.app_ctx.allocator, surface_mesh, .{
        .app_ctx = smp.app_ctx,
        .surface_mesh = surface_mesh,
    }) catch |err| {
        std.debug.print("Failed to store ParameterizationData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// If the destroyed SurfaceMesh is used as samples SurfaceMesh for a SurfaceMesh, inform the associated ParameterizationData.
/// If the destroyed SurfaceMesh is the underlying SurfaceMesh of a ParameterizationData, inform the associated ParameterizationData.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smp: *SurfaceMeshParameterization = @alignCast(@fieldParentPtr("module", m));
    // first case: the destroyed SurfaceMesh is used as samples SurfaceMesh for a SurfaceMesh
    var it = smp.surface_meshes_data.valueIterator();
    while (it.next()) |pd| {
        if (pd.samples_surface_mesh == surface_mesh) {
            pd.samplesSurfaceMeshDestroyed() catch |err| {
                std.debug.print("Failed to handle destroyed samples SurfaceMesh for SurfaceMesh: {}\n", .{err});
            };
            // we can return here because a samples SurfaceMesh cannot be itself the underlying SurfaceMesh of a ParameterizationData
            // (or can it?)
            return;
        }
    }
    // second case: the destroyed SurfaceMesh is the underlying SurfaceMesh of a ParameterizationData
    const pd = smp.surface_meshes_data.getPtr(surface_mesh).?;
    pd.surfaceMeshDestroyed() catch |err| {
        std.debug.print("Failed to handle destroyed underlying SurfaceMesh for ParameterizationData: {}\n", .{err});
    };
    // remove the ParameterizationData from the hashmap
    _ = smp.surface_meshes_data.remove(surface_mesh);
}

/// Part of the Module interface.
/// If the destroyed PointCloud is used as samples for a SurfaceMesh, inform the associated ParameterizationData.
pub fn pointCloudDestroyed(m: *Module, point_cloud: *PointCloud) void {
    const smp: *SurfaceMeshParameterization = @alignCast(@fieldParentPtr("module", m));
    var it = smp.surface_meshes_data.valueIterator();
    while (it.next()) |pd| {
        if (pd.samples == point_cloud) {
            pd.samplesDestroyed() catch |err| {
                std.debug.print("Failed to handle destroyed samples PointCloud for SurfaceMesh: {}\n", .{err});
            };
            break;
        }
    }
}

/// Part of the Module interface.
/// Show a UI panel to control the sampling of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const smp: *SurfaceMeshParameterization = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &smp.app_ctx.surface_mesh_store;

    assert(smp.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = smp.app_ctx.selected_model.surface_mesh;
    const pd = smp.surface_meshes_data.getPtr(sm).?;
    const info = sm_store.surfaceMeshInfo(sm);

    const UiData = struct {
        var poisson_radius: f32 = 0.03;
        var selected_vertex_set: ?*SurfaceMesh.CellSet = null;
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    {
        c.ImGui_SeparatorText("Samples generation");
        c.ImGui_Text("Minimum distance");
        c.ImGui_PushID("Minimum distance");
        _ = c.ImGui_InputFloat("", @ptrCast(&UiData.poisson_radius));
        c.ImGui_PopID();
        const disabled =
            !info.bvh.initialized or
            info.std_datas.vertex_position == null or
            info.std_datas.face_normal == null;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx("Generate samples", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            pd.generateSamples(
                &info.bvh,
                info.std_datas.vertex_position.?,
                info.std_datas.face_normal.?,
                UiData.poisson_radius,
            ) catch |err| {
                std.debug.print("Error during sampling: {}\n", .{err});
            };
        }
        if (disabled) {
            imgui_utils.tooltip(
                \\ Requires:
                \\ - a BVH
                \\ Following data should be available:
                \\ - std vertex_position
                \\ - std face_normal
            );
            c.ImGui_EndDisabled();
        }
    }
    {
        c.ImGui_SeparatorText("Samples connectivity");
        const disabled =
            pd.samples == null or
            info.std_datas.edge_length == null or
            info.std_datas.corner_angle == null;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx("Connect samples", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            // if needed, initialize the intrinsic triangulation context and flip edges to make it Delaunay
            // WARNING: strong hypothesis that the underlying SurfaceMesh is not modified between successive calls
            // otherwise, the intrinsic triangulation should be re-initialized and the Delaunay flip should be performed again
            if (pd.it_ctx == null) {
                pd.it_ctx = intrinsic_triangulation.ITContext.init(
                    smp.app_ctx,
                    sm,
                    info.std_datas.edge_length.?,
                    info.std_datas.corner_angle.?,
                ) catch null;
                if (pd.it_ctx) |it_ctx| {
                    it_ctx.flipToDelaunay() catch |err| {
                        std.debug.print("Error during intrinsic triangulation Delaunay flip: {}\n", .{err});
                    };
                }
            }
            pd.connectSamples(info.std_datas.edge_length.?) catch |err| {
                std.debug.print("Error during samples connectivity computation: {}\n", .{err});
            };
        }
        if (disabled) {
            imgui_utils.tooltip(
                \\ Requires:
                \\ - generated samples
                \\ Following data should be available:
                \\ - std edge_length
                \\ - std corner_angle
            );
            c.ImGui_EndDisabled();
        }
    }
    {
        c.ImGui_SeparatorText("Sample patches parameterization");
        const disabled =
            pd.samples == null or
            pd.samples_surface_mesh == null;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx("Parameterize sample patches", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            pd.parameterizeSamplePatches() catch |err| {
                std.debug.print("Error during sample patches parameterization: {}\n", .{err});
            };
        }
        if (disabled) {
            imgui_utils.tooltip(
                \\ Requires:
                \\ - generated & connected samples
            );
            c.ImGui_EndDisabled();
        }
    }
    {
        c.ImGui_SeparatorText("Display vertices UVs");
        if (pd.samples_surface_mesh) |ssm| {
            c.ImGui_Text("Samples SurfaceMesh Vertex set:");
            c.ImGui_PushID("vertex set");
            switch (imgui_utils.surfaceMeshCellSetComboBox(ssm, .vertex, UiData.selected_vertex_set)) {
                .unchanged => {},
                .cleared => UiData.selected_vertex_set = null,
                .changed => |cell_set| UiData.selected_vertex_set = cell_set,
            }
            c.ImGui_PopID();
            const disabled = !pd.uv_computed or
                UiData.selected_vertex_set == null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Display UVs", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                const vertex_uv, _ = sm.getOrAddData(.vertex, Vec2f, "vertex_uv") catch |err| {
                    std.debug.print("Failed to get or add vertex_uv data: {}\n", .{err});
                    return;
                };
                vertex_uv.data.fill(.{ 0.0, 0.0 });
                const vertex_boundary_dist, _ = sm.getOrAddData(.vertex, f32, "vertex_boundary_dist") catch |err| {
                    std.debug.print("Failed to get or add vertex_boundary_dist data: {}\n", .{err});
                    return;
                };
                vertex_boundary_dist.data.fill(0.0);
                var selected_samples = std.ArrayList(u32).initCapacity(smp.app_ctx.allocator, UiData.selected_vertex_set.?.cells.items.len) catch |err| {
                    std.debug.print("Failed to initialize selected_samples array: {}\n", .{err});
                    return;
                };
                defer selected_samples.deinit(smp.app_ctx.allocator);
                for (UiData.selected_vertex_set.?.cells.items) |v| {
                    selected_samples.appendAssumeCapacity(pd.ssm_vertex_sample.value(v));
                }
                var f_it = SurfaceMesh.CellIterator.init(sm, .face) catch |err| {
                    std.debug.print("Failed to initialize face iterator: {}\n", .{err});
                    return;
                };
                defer f_it.deinit();
                while (f_it.next()) |f| {
                    const tri_dart = pd.triangle_dart.value(f);
                    const tri_uvs = pd.triangle_uvs.value(f);
                    for (tri_uvs.samples, 0..) |s, idx| {
                        for (selected_samples.items) |selected_sample| {
                            if (s == selected_sample) {
                                const v0_index = pd.surface_mesh.cellIndex(.{ .vertex = tri_dart });
                                const v1_index = pd.surface_mesh.cellIndex(.{ .vertex = pd.surface_mesh.phi1(tri_dart) });
                                const v2_index = pd.surface_mesh.cellIndex(.{ .vertex = pd.surface_mesh.phi_1(tri_dart) });
                                vertex_uv.valuePtrByIndex(v0_index).* = tri_uvs.uvs[idx][0];
                                vertex_uv.valuePtrByIndex(v1_index).* = tri_uvs.uvs[idx][1];
                                vertex_uv.valuePtrByIndex(v2_index).* = tri_uvs.uvs[idx][2];
                                vertex_boundary_dist.valuePtrByIndex(v0_index).* = tri_uvs.distance_to_boundary[idx][0];
                                vertex_boundary_dist.valuePtrByIndex(v1_index).* = tri_uvs.distance_to_boundary[idx][1];
                                vertex_boundary_dist.valuePtrByIndex(v2_index).* = tri_uvs.distance_to_boundary[idx][2];
                            }
                        }
                    }
                }
                sm_store.surfaceMeshDataUpdated(sm, .vertex, Vec2f, vertex_uv);
                sm_store.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_boundary_dist);
                smp.app_ctx.requestRedraw();
            }
            if (disabled) {
                c.ImGui_EndDisabled();
            }
        }
    }
}
