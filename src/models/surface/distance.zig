const std = @import("std");
const assert = std.debug.assert;

const AppContext = @import("../../main.zig").AppContext;
const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const geometry_utils = @import("../../geometry/utils.zig");
const eigen = @import("../../geometry/eigen.zig");
const SparseMatrix = eigen.SparseMatrix;
const FactorizedSparseMatrix = eigen.FactorizedSparseMatrix;

const laplacian = @import("laplacian.zig");
const gradient = @import("gradient.zig");
const intrinsic_triangulation = @import("intrinsic_triangulation.zig");

pub const ShortestEdgePathContext = struct {
    surface_mesh: *SurfaceMesh,
    edge_weight: SurfaceMesh.CellData(.edge, f32),
    incoming_dart: SurfaceMesh.CellData(.vertex, ?SurfaceMesh.Dart),
    dart_queue: ShortestEdgePathDartQueue,

    // Priority queue type for darts of the SurfaceMesh to expand from, ordered by increasing distance
    const ShortestEdgePathDartInfo = struct {
        dart: SurfaceMesh.Dart,
        distance: f32,
        pub fn cmp(_: void, a: ShortestEdgePathDartInfo, b: ShortestEdgePathDartInfo) std.math.Order {
            const distance_order = std.math.order(a.distance, b.distance);
            if (distance_order != .eq) return distance_order;
            // tie-breaker: use Dart indices to have a deterministic order
            return std.math.order(a.dart, b.dart);
        }
    };
    pub const ShortestEdgePathDartQueue = std.PriorityQueue(ShortestEdgePathDartInfo, void, ShortestEdgePathDartInfo.cmp);

    pub fn init(
        surface_mesh: *SurfaceMesh,
        edge_weight: SurfaceMesh.CellData(.edge, f32),
    ) !ShortestEdgePathContext {
        const incoming_dart = try surface_mesh.addData(.vertex, ?SurfaceMesh.Dart, "__incoming_dart");

        return .{
            .surface_mesh = surface_mesh,
            .edge_weight = edge_weight,
            .incoming_dart = incoming_dart,
            .dart_queue = .empty,
        };
    }

    pub fn deinit(sep_ctx: *ShortestEdgePathContext, allocator: std.mem.Allocator) void {
        sep_ctx.dart_queue.deinit(allocator);
        sep_ctx.surface_mesh.removeData(.vertex, ?SurfaceMesh.Dart, sep_ctx.incoming_dart);
    }

    /// Compute the shortest edge path between two vertices of the SurfaceMesh using Dijkstra's algorithm.
    /// Returns an ArrayList(Dart) representing the oriented edges of the path (caller owns the returned ArrayList).
    pub fn shortestEdgePathBetweenVertices(
        sep_ctx: *ShortestEdgePathContext,
        allocator: std.mem.Allocator,
        v_start: SurfaceMesh.Cell,
        v_end: SurfaceMesh.Cell,
    ) !std.ArrayList(SurfaceMesh.Dart) {
        assert(v_start.cellType() == .vertex);
        assert(v_end.cellType() == .vertex);

        sep_ctx.incoming_dart.data.fill(null);
        sep_ctx.dart_queue.clearRetainingCapacity();

        const v_start_idx = sep_ctx.surface_mesh.cellIndex(v_start);
        const v_end_idx = sep_ctx.surface_mesh.cellIndex(v_end);

        // initialize the queue with the darts outgoing from the starting vertex
        {
            var dart_it = sep_ctx.surface_mesh.cellDartIterator(v_start);
            while (dart_it.next()) |d| {
                try sep_ctx.dart_queue.push(
                    allocator,
                    .{ .dart = d, .distance = sep_ctx.edge_weight.value(.{ .edge = d }) },
                );
            }
        }
        while (sep_ctx.dart_queue.pop()) |d_info| {
            const pointed_v: SurfaceMesh.Cell = .{ .vertex = sep_ctx.surface_mesh.phi1(d_info.dart) };
            const pointed_v_idx = sep_ctx.surface_mesh.cellIndex(pointed_v);
            if (sep_ctx.incoming_dart.value(pointed_v) != null or pointed_v_idx == v_start_idx) {
                // this vertex has already been reached, or is the starting vertex, skip it
                continue;
            }
            // the queue is ordered by distance, so the first time we reach a vertex is the shortest path to it
            sep_ctx.incoming_dart.valuePtr(pointed_v).* = d_info.dart;
            // if we reached the end vertex, we can reconstruct the path and return it
            if (pointed_v_idx == v_end_idx) {
                // reconstruct the path from v_end to v_start using the incoming_dart data
                var path: std.ArrayList(SurfaceMesh.Dart) = try .initCapacity(allocator, 16);
                try path.append(allocator, d_info.dart);
                var current_d = d_info.dart;
                // follow the incoming darts until reaching the starting vertex which has no incoming dart
                while (sep_ctx.incoming_dart.value(.{ .vertex = current_d })) |incoming| {
                    try path.append(allocator, incoming);
                    current_d = incoming;
                }
                // reverse the path to get it from v_start to v_end
                std.mem.reverse(SurfaceMesh.Dart, path.items);
                return path;
            }
            // otherwise, expand the search to the neighbors of the current pointed vertex
            var dart_it = sep_ctx.surface_mesh.cellDartIterator(pointed_v);
            while (dart_it.next()) |d| {
                const nv: SurfaceMesh.Cell = .{ .vertex = sep_ctx.surface_mesh.phi1(d) };
                if (sep_ctx.incoming_dart.value(nv) == null) {
                    const weight = sep_ctx.edge_weight.value(.{ .edge = d });
                    try sep_ctx.dart_queue.push(allocator, .{
                        .dart = d,
                        .distance = d_info.distance + weight,
                    });
                }
            }
        }
        // no path found
        return .empty;
    }
};

/// Perform a multi-source Dijkstra's algorithm to compute the shortest distance from each vertex of the SurfaceMesh to its closest source vertex.
/// The vertex_distance data is filled with the computed distances.
/// The vertex_source data is filled with the closest source vertex for each vertex.
pub fn multiSourceDijkstraDistancesAndSources(
    allocator: std.mem.Allocator,
    sm: *SurfaceMesh,
    source_vertices: []SurfaceMesh.Cell,
    edge_weight: SurfaceMesh.CellData(.edge, f32),
    vertex_distance: SurfaceMesh.CellData(.vertex, f32),
    vertex_source: SurfaceMesh.CellData(.vertex, ?SurfaceMesh.Cell),
) !void {
    assert(source_vertices.len > 0);

    // initialize all vertex distances to infinity and sources to null
    vertex_distance.data.fill(std.math.inf(f32));
    vertex_source.data.fill(null);

    // Priority queue type for vertices of the SurfaceMesh, ordered by their distance from the closest source vertex
    const VertexQueueContext = struct {
        surface_mesh: *const SurfaceMesh,
    };
    const VertexInfo = struct {
        const VertexInfo = @This();
        vertex: SurfaceMesh.Cell,
        distance: f32,
        pub fn cmp(ctx: VertexQueueContext, a: VertexInfo, b: VertexInfo) std.math.Order {
            const distance_order = std.math.order(a.distance, b.distance);
            if (distance_order != .eq) return distance_order;
            // tie-breaker: use vertex indices to have a deterministic order
            return std.math.order(ctx.surface_mesh.cellIndex(a.vertex), ctx.surface_mesh.cellIndex(b.vertex));
        }
    };
    const VertexQueue = std.PriorityQueue(VertexInfo, VertexQueueContext, VertexInfo.cmp);

    var queue: VertexQueue = .initContext(.{ .surface_mesh = sm });
    defer queue.deinit(allocator);

    // initialize the queue with the source vertices
    for (source_vertices) |v| {
        vertex_distance.valuePtr(v).* = 0.0;
        vertex_source.valuePtr(v).* = v;
        try queue.push(allocator, .{ .vertex = v, .distance = 0.0 });
    }

    while (queue.pop()) |v_info| {
        const v = v_info.vertex;
        if (vertex_distance.value(v) < v_info.distance) {
            continue; // this vertex has already been reached with a smaller distance, skip it
        }
        // expand the neighbors of the current vertex
        var dart_it = sm.cellDartIterator(v);
        while (dart_it.next()) |d| {
            const nv: SurfaceMesh.Cell = .{ .vertex = sm.phi1(d) };
            const weight = edge_weight.value(.{ .edge = d });
            const new_distance = v_info.distance + weight;
            if (new_distance < vertex_distance.value(nv)) {
                vertex_distance.valuePtr(nv).* = new_distance;
                vertex_source.valuePtr(nv).* = vertex_source.value(v);
                try queue.push(allocator, .{ .vertex = nv, .distance = new_distance });
            }
        }
    }
}

/// Context for computing geodesic distances on a SurfaceMesh using the heat method.
pub const HeatMethodContext = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    surface_mesh: *SurfaceMesh,
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    edge_length: SurfaceMesh.CellData(.edge, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),

    vertex_index: SurfaceMesh.CellData(.vertex, u32),
    vertex_heat: SurfaceMesh.CellData(.vertex, eigen.Scalar),
    face_heat_grad: SurfaceMesh.CellData(.face, Vec3d),
    vertex_heat_grad_div: SurfaceMesh.CellData(.vertex, eigen.Scalar),

    factorized_L: FactorizedSparseMatrix, // cached factorization of the Laplacian matrix
    factorized_H: FactorizedSparseMatrix, // cached factorization of the heat diffusion matrix

    heat_0: std.ArrayList(eigen.Scalar), // preallocated vector for initial heat values (1.0 at source vertices, 0.0 elsewhere)
    heat_t: std.ArrayList(eigen.Scalar), // preallocated vector for heat values after diffusion
    div: std.ArrayList(eigen.Scalar), // preallocated vector for gradient divergence values
    dist: std.ArrayList(eigen.Scalar), // preallocated vector for distance values after solving the Poisson equation

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        sm: *SurfaceMesh,
        halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_area: SurfaceMesh.CellData(.vertex, f32),
        edge_length: SurfaceMesh.CellData(.edge, f32),
        face_area: SurfaceMesh.CellData(.face, f32),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),
        diffusion_time: f32,
        // it_ctx: ?intrinsic_triangulation.ITContext,
    ) !HeatMethodContext {
        // Create consecutive indices for vertices
        var vertex_index = try sm.addData(.vertex, u32, "__heat_method_vertex_index");
        var vertex_it: SurfaceMesh.CellIterator = try .init(sm, .vertex);
        defer vertex_it.deinit();
        var nb_vertices: u32 = 0;
        while (vertex_it.next()) |v| : (nb_vertices += 1) {
            vertex_index.valuePtr(v).* = nb_vertices;
        }

        // WARNING: use eigen.Scalar (f64) for matrix coefficients
        // and for heat values (diffusion, gradient) to improve numerical precision

        const vertex_heat = try sm.addData(.vertex, eigen.Scalar, "__heat_method_vertex_heat");
        const face_heat_grad = try sm.addData(.face, Vec3d, "__heat_method_face_heat_grad");
        const vertex_heat_grad_div = try sm.addData(.vertex, eigen.Scalar, "__heat_method_vertex_heat_grad_div");

        // setup Laplacian matrix Lc
        const nb_edges = sm.nbCells(.edge);
        var triplets = try std.ArrayList(SparseMatrix.Triplet).initCapacity(allocator, 4 * nb_edges);
        defer triplets.deinit(allocator);
        var edge_it: SurfaceMesh.CellIterator = try .init(sm, .edge);
        defer edge_it.deinit();
        while (edge_it.next()) |edge| {
            const d = edge.dart();
            const dd = sm.phi2(d);
            const i = vertex_index.value(.{ .vertex = d });
            const j = vertex_index.value(.{ .vertex = dd });
            const w_ij: eigen.Scalar = @floatCast(laplacian.edgeCotanWeight(sm, edge, halfedge_cotan_weight));
            // off-diagonal
            triplets.appendAssumeCapacity(.{ .row = @intCast(i), .col = @intCast(j), .value = w_ij });
            triplets.appendAssumeCapacity(.{ .row = @intCast(j), .col = @intCast(i), .value = w_ij });
            // diagonal
            triplets.appendAssumeCapacity(.{ .row = @intCast(i), .col = @intCast(i), .value = -w_ij });
            triplets.appendAssumeCapacity(.{ .row = @intCast(j), .col = @intCast(j), .value = -w_ij });
        }
        var Lc: SparseMatrix = .initFromTriplets(@intCast(nb_vertices), @intCast(nb_vertices), triplets.items);
        defer Lc.deinit();

        const factorized_L: FactorizedSparseMatrix = .init(Lc, @intCast(nb_vertices));

        // setup mass-matrix A (vertex areas)
        var massCoeffs: std.ArrayList(eigen.Scalar) = .empty;
        defer massCoeffs.deinit(allocator);
        try massCoeffs.resize(allocator, nb_vertices);
        vertex_it.reset();
        while (vertex_it.next()) |v| {
            const idx = vertex_index.value(v);
            massCoeffs.items[idx] = @floatCast(vertex_area.value(v));
        }
        var A: SparseMatrix = .initDiagonalFromArray(massCoeffs.items);
        defer A.deinit();

        // compute time step t = mean_edge_length^2
        const mean_edge_length = geometry_utils.meanValue(f32, edge_length.data);
        const t = mean_edge_length * mean_edge_length * diffusion_time;

        // compute H = A - t * Lc
        var H: SparseMatrix = .init(@intCast(nb_vertices), @intCast(nb_vertices));
        defer H.deinit();
        Lc.mulScalar(@floatCast(-t), H);
        A.addSparseMatrix(H, H);

        const factorized_H: FactorizedSparseMatrix = .init(H, @intCast(nb_vertices));

        var heat_0: std.ArrayList(eigen.Scalar) = .empty;
        try heat_0.resize(allocator, nb_vertices);
        var heat_t: std.ArrayList(eigen.Scalar) = .empty;
        try heat_t.resize(allocator, nb_vertices);
        var div: std.ArrayList(eigen.Scalar) = .empty;
        try div.resize(allocator, nb_vertices);
        var dist: std.ArrayList(eigen.Scalar) = .empty;
        try dist.resize(allocator, nb_vertices);

        return .{
            .allocator = allocator,
            .io = io,
            .surface_mesh = sm,
            .halfedge_cotan_weight = halfedge_cotan_weight,
            .vertex_position = vertex_position,
            .vertex_area = vertex_area,
            .edge_length = edge_length,
            .face_area = face_area,
            .face_normal = face_normal,
            .vertex_index = vertex_index,
            .vertex_heat = vertex_heat,
            .face_heat_grad = face_heat_grad,
            .vertex_heat_grad_div = vertex_heat_grad_div,
            .factorized_L = factorized_L,
            .factorized_H = factorized_H,
            .heat_0 = heat_0,
            .heat_t = heat_t,
            .div = div,
            .dist = dist,
        };
    }

    pub fn deinit(hm_ctx: *HeatMethodContext) void {
        hm_ctx.factorized_L.deinit();
        hm_ctx.factorized_H.deinit();
        hm_ctx.heat_0.deinit(hm_ctx.allocator);
        hm_ctx.heat_t.deinit(hm_ctx.allocator);
        hm_ctx.div.deinit(hm_ctx.allocator);
        hm_ctx.dist.deinit(hm_ctx.allocator);
        hm_ctx.surface_mesh.removeData(.vertex, f64, hm_ctx.vertex_heat_grad_div);
        hm_ctx.surface_mesh.removeData(.face, Vec3d, hm_ctx.face_heat_grad);
        hm_ctx.surface_mesh.removeData(.vertex, f64, hm_ctx.vertex_heat);
        hm_ctx.surface_mesh.removeData(.vertex, u32, hm_ctx.vertex_index);
    }

    /// Compute the geodesic distance from each vertex of the SurfaceMesh to its closest source vertex using the heat method.
    /// The vertex_distance data is filled with the computed distances.
    pub fn computeGeodesicDistancesFromSource(
        hm_ctx: *HeatMethodContext,
        source_vertices: []SurfaceMesh.Cell,
        vertex_distance: SurfaceMesh.CellData(.vertex, f32),
    ) !void {
        // setup heat_0 vector: 1.0 at source vertices, 0.0 elsewhere
        @memset(hm_ctx.heat_0.items, 0.0);
        for (source_vertices) |sv| {
            const idx = hm_ctx.vertex_index.value(sv);
            hm_ctx.heat_0.items[idx] = 1.0; // set source vertices heat to 1.0
        }

        // solve H * heat_t = heat_0 (heat diffusion)
        hm_ctx.factorized_H.solve(hm_ctx.heat_0.items, hm_ctx.heat_t.items);

        // store heat_t in a vertex data
        var vertex_it: SurfaceMesh.CellIterator = try .init(hm_ctx.surface_mesh, .vertex);
        defer vertex_it.deinit();
        while (vertex_it.next()) |v| {
            const idx = hm_ctx.vertex_index.value(v);
            hm_ctx.vertex_heat.valuePtr(v).* = hm_ctx.heat_t.items[idx];
        }

        // compute the gradient of heat_t on each face
        try gradient.computeScalarFieldFaceGradients(
            hm_ctx.io,
            hm_ctx.surface_mesh,
            hm_ctx.vertex_position,
            hm_ctx.vertex_heat,
            hm_ctx.face_area,
            hm_ctx.face_normal,
            hm_ctx.face_heat_grad,
        );

        // negate and normalize the face gradients
        var grad_it = hm_ctx.face_heat_grad.data.iterator();
        while (grad_it.next()) |grad| {
            grad.* = vec.mulScalar3d(
                vec.normalized3d(grad.*),
                -1.0,
            );
        }

        // compute the divergence of the face gradients at each vertex
        try gradient.computeVectorFieldVertexDivergences(
            hm_ctx.io,
            hm_ctx.surface_mesh,
            hm_ctx.halfedge_cotan_weight,
            hm_ctx.vertex_position,
            hm_ctx.face_heat_grad,
            hm_ctx.vertex_heat_grad_div,
        );

        // setup div vector
        vertex_it.reset();
        while (vertex_it.next()) |v| {
            const idx = hm_ctx.vertex_index.value(v);
            hm_ctx.div.items[idx] = @floatCast(hm_ctx.vertex_heat_grad_div.value(v));
        }

        // solve L * dist = div (Poisson equation)
        hm_ctx.factorized_L.solve(hm_ctx.div.items, hm_ctx.dist.items);

        // shift distance values s.t. min distance is 0.0 and store them in vertex_distance
        const min_dist = std.mem.min(eigen.Scalar, hm_ctx.dist.items);
        vertex_it.reset();
        while (vertex_it.next()) |v| {
            const idx = hm_ctx.vertex_index.value(v);
            vertex_distance.valuePtr(v).* = @floatCast(hm_ctx.dist.items[idx] - min_dist);
        }
    }
};
