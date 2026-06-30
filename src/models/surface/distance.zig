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

const laplacian = @import("laplacian.zig");
const gradient = @import("gradient.zig");

/// Compute the shortest edge path between two vertices of the SurfaceMesh using Dijkstra's algorithm.
/// Returns an ArrayList(Dart) representing the oriented edges of the path (caller is responsible for deinit the returned ArrayList).
pub fn shortestEdgePathBetweenVertices(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    v_start: SurfaceMesh.Cell,
    v_end: SurfaceMesh.Cell,
    edge_weight: SurfaceMesh.CellData(.edge, f32),
) !std.ArrayList(SurfaceMesh.Dart) {
    assert(v_start.cellType() == .vertex);
    assert(v_end.cellType() == .vertex);

    // this data is used to store the incoming dart for each vertex in the shortest path tree
    // a null value indicates a vertex that has not been reached yet
    var incoming_dart = try sm.addData(.vertex, ?SurfaceMesh.Dart, "__incoming_dart");
    defer sm.removeData(.vertex, ?SurfaceMesh.Dart, incoming_dart);
    incoming_dart.data.fill(null);

    const DartInfo = struct {
        const DartInfo = @This();
        dart: SurfaceMesh.Dart,
        distance: f32,
        pub fn cmp(_: void, a: DartInfo, b: DartInfo) std.math.Order {
            const distance_order = std.math.order(a.distance, b.distance);
            if (distance_order != .eq) return distance_order;
            // tie-breaker: use Dart indices to have a deterministic order
            return std.math.order(a.dart, b.dart);
        }
    };
    const DartQueue = std.PriorityQueue(DartInfo, void, DartInfo.cmp);

    var queue: DartQueue = .empty;
    defer queue.deinit(app_ctx.allocator);
    // initialize the queue with the darts outgoing from the starting vertex
    {
        var dart_it = sm.cellDartIterator(v_start);
        while (dart_it.next()) |d| {
            try queue.push(
                app_ctx.allocator,
                .{ .dart = d, .distance = edge_weight.value(.{ .edge = d }) },
            );
        }
    }
    while (queue.pop()) |d_info| {
        const pointed_v: SurfaceMesh.Cell = .{ .vertex = sm.phi1(d_info.dart) };
        if (incoming_dart.value(pointed_v) != null or sm.cellIndex(pointed_v) == sm.cellIndex(v_start)) {
            // this vertex has already been reached, or is the starting vertex, skip it
            continue;
        }
        incoming_dart.valuePtr(pointed_v).* = d_info.dart;
        if (sm.cellIndex(pointed_v) == sm.cellIndex(v_end)) {
            // reconstruct the path from v_end to v_start using the incoming_dart data
            var path: std.ArrayList(SurfaceMesh.Dart) = try .initCapacity(app_ctx.allocator, 16);
            try path.append(app_ctx.allocator, d_info.dart);
            var current_d = d_info.dart;
            while (incoming_dart.value(.{ .vertex = current_d })) |incoming| {
                try path.append(app_ctx.allocator, incoming);
                current_d = incoming;
            }
            // reverse the path to get it from v_start to v_end
            std.mem.reverse(SurfaceMesh.Dart, path.items);
            return path;
        }
        // expand the neighbors of the current pointed vertex
        var dart_it = sm.cellDartIterator(pointed_v);
        while (dart_it.next()) |d| {
            const nv: SurfaceMesh.Cell = .{ .vertex = sm.phi1(d) };
            if (incoming_dart.value(nv) == null) {
                const weight = edge_weight.value(.{ .edge = d });
                // a smaller distance will naturally be popped from the priority queue first
                try queue.push(app_ctx.allocator, .{ .dart = d, .distance = d_info.distance + weight });
            }
        }
    }
    // no path found
    return .empty;
}

/// Compute the geodesic distance from each vertex of the SurfaceMesh to its closest source vertex using the heat method.
/// The vertex_distance data is filled with the computed distances.
pub fn computeVertexGeodesicDistancesFromSource(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    source_vertices: []SurfaceMesh.Cell,
    diffusion_time: f32,
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    edge_length: SurfaceMesh.CellData(.edge, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    vertex_distance: SurfaceMesh.CellData(.vertex, f32),
) !void {
    var vertex_it: SurfaceMesh.CellIterator = try .init(sm, .vertex);
    defer vertex_it.deinit();

    // index vertices with consecutive indices (for matrix assembly)
    var vertex_index = try sm.addData(.vertex, u32, "__vertex_index");
    defer sm.removeData(.vertex, u32, vertex_index);
    var nb_vertices: u32 = 0;
    while (vertex_it.next()) |v| : (nb_vertices += 1) {
        vertex_index.valuePtr(v).* = nb_vertices;
    }

    // warning: use eigen.Scalar (f64) for matrix coefficients
    // and for heat values (diffusion, gradient) to improve numerical precision

    // setup Laplacian matrix Lc
    const nb_edges = sm.nbCells(.edge);
    var triplets = try std.ArrayList(SparseMatrix.Triplet).initCapacity(sm.allocator, 4 * nb_edges);
    defer triplets.deinit(sm.allocator);
    var edge_it: SurfaceMesh.CellIterator = try .init(sm, .edge);
    defer edge_it.deinit();
    while (edge_it.next()) |edge| {
        const d = edge.dart();
        const dd = sm.phi2(d);
        const i = vertex_index.value(.{ .vertex = d });
        const j = vertex_index.value(.{ .vertex = dd });
        const w_ij = laplacian.edgeCotanWeight(sm, edge, halfedge_cotan_weight);
        // off-diagonal
        triplets.appendAssumeCapacity(.{ .row = @intCast(i), .col = @intCast(j), .value = @floatCast(w_ij) });
        triplets.appendAssumeCapacity(.{ .row = @intCast(j), .col = @intCast(i), .value = @floatCast(w_ij) });
        // diagonal
        triplets.appendAssumeCapacity(.{ .row = @intCast(i), .col = @intCast(i), .value = @floatCast(-w_ij) });
        triplets.appendAssumeCapacity(.{ .row = @intCast(j), .col = @intCast(j), .value = @floatCast(-w_ij) });
    }
    var Lc: SparseMatrix = .initFromTriplets(@intCast(nb_vertices), @intCast(nb_vertices), triplets.items);
    defer Lc.deinit();

    // setup mass-matrix A (vertex areas) and
    // initial heat vector heat_0 (1.0 at source vertices, 0.0 elsewhere)
    var massCoeffs: std.ArrayList(eigen.Scalar) = .empty;
    defer massCoeffs.deinit(sm.allocator);
    try massCoeffs.resize(sm.allocator, nb_vertices);
    var heat_0: std.ArrayList(eigen.Scalar) = .empty;
    defer heat_0.deinit(sm.allocator);
    try heat_0.resize(sm.allocator, nb_vertices);
    vertex_it.reset();
    while (vertex_it.next()) |v| {
        const idx = vertex_index.value(v);
        massCoeffs.items[idx] = @floatCast(vertex_area.value(v));
        heat_0.items[idx] = 0.0;
    }
    for (source_vertices) |sv| {
        const idx = vertex_index.value(sv);
        heat_0.items[idx] = 1.0; // set source vertices heat to 1.0
    }
    var A: SparseMatrix = .initDiagonalFromArray(massCoeffs.items);
    defer A.deinit();

    // compute time step t = mean_edge_length^2
    const mean_edge_length = geometry_utils.meanValue(f32, edge_length.data);
    const t = mean_edge_length * mean_edge_length * diffusion_time;

    // compute M = A - t * Lc
    var M: SparseMatrix = .init(@intCast(nb_vertices), @intCast(nb_vertices));
    defer M.deinit();
    Lc.mulScalar(@floatCast(-t), M);
    A.addSparseMatrix(M, M);

    // solve M * heat_t = heat_0 (backward Euler time step of the heat equation)
    var heat_t: std.ArrayList(eigen.Scalar) = .empty;
    defer heat_t.deinit(sm.allocator);
    try heat_t.resize(sm.allocator, nb_vertices);
    M.solveSymmetricSparseLinearSystem(heat_0.items, heat_t.items);

    // store heat_t in a vertex data (f64)
    var vertex_heat = try sm.addData(.vertex, f64, "__vertex_heat");
    defer sm.removeData(.vertex, f64, vertex_heat);
    vertex_it.reset();
    while (vertex_it.next()) |v| {
        const idx = vertex_index.value(v);
        vertex_heat.valuePtr(v).* = heat_t.items[idx];
    }

    // compute the gradient of heat_t on each face
    var face_heat_grad = try sm.addData(.face, Vec3d, "__face_heat_grad");
    defer sm.removeData(.face, Vec3d, face_heat_grad);
    try gradient.computeScalarFieldFaceGradients(
        app_ctx,
        sm,
        vertex_position,
        vertex_heat,
        face_area,
        face_normal,
        face_heat_grad,
    );

    // negate and normalize the face gradients
    var grad_it = face_heat_grad.data.iterator();
    while (grad_it.next()) |grad| {
        grad.* = vec.mulScalar3d(
            vec.normalized3d(grad.*),
            -1.0,
        );
    }

    // compute the divergence of the face gradients at each vertex
    var vertex_heat_grad_div = try sm.addData(.vertex, f64, "__vertex_heat_grad_div");
    defer sm.removeData(.vertex, f64, vertex_heat_grad_div);
    try gradient.computeVectorFieldVertexDivergences(
        app_ctx,
        sm,
        halfedge_cotan_weight,
        vertex_position,
        face_heat_grad,
        vertex_heat_grad_div,
    );

    // setup div vector
    var div: std.ArrayList(eigen.Scalar) = .empty;
    defer div.deinit(sm.allocator);
    try div.resize(sm.allocator, nb_vertices);
    vertex_it.reset();
    while (vertex_it.next()) |v| {
        const idx = vertex_index.value(v);
        div.items[idx] = @floatCast(vertex_heat_grad_div.value(v));
    }

    // solve Lc * dist = div (Poisson equation)
    var dist: std.ArrayList(eigen.Scalar) = .empty;
    defer dist.deinit(sm.allocator);
    try dist.resize(sm.allocator, nb_vertices);
    Lc.solveSymmetricSparseLinearSystem(div.items, dist.items);

    // shift distance values s.t. min distance is 0.0 and store them in vertex_distance
    const min_dist = std.mem.min(eigen.Scalar, dist.items);
    vertex_it.reset();
    while (vertex_it.next()) |v| {
        const idx = vertex_index.value(v);
        vertex_distance.valuePtr(v).* = @floatCast(dist.items[idx] - min_dist);
    }
}
