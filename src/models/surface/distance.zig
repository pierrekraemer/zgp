const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const geometry_utils = @import("../../geometry/utils.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const eigen = @import("../../geometry/eigen.zig");
const SparseMatrix = eigen.SparseMatrix;

const laplacian = @import("laplacian.zig");
const gradient = @import("gradient.zig");

pub fn computeVertexGeodesicDistancesFromSource(
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
    var vertex_it = try SurfaceMesh.CellIterator(.vertex).init(sm);
    defer vertex_it.deinit();

    // index vertices with consecutive indices (for matrix assembly)
    var vertex_index = try sm.addData(.vertex, u32, "__vertex_index");
    defer sm.removeData(.vertex, vertex_index.gen());
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
    var edge_it = try SurfaceMesh.CellIterator(.edge).init(sm);
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
    defer sm.removeData(.vertex, vertex_heat.gen());
    vertex_it.reset();
    while (vertex_it.next()) |v| {
        const idx = vertex_index.value(v);
        vertex_heat.valuePtr(v).* = heat_t.items[idx];
    }

    // compute the gradient of heat_t on each face
    var face_heat_grad = try sm.addData(.face, Vec3d, "__face_heat_grad");
    defer sm.removeData(.face, face_heat_grad.gen());
    try gradient.computeScalarFieldFaceGradients(
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
    defer sm.removeData(.vertex, vertex_heat_grad_div.gen());
    try gradient.computeVectorFieldVertexDivergences(
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
