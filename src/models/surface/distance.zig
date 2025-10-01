const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const zeigen = @import("zeigen");
const geometry_utils = @import("../../geometry/utils.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;

const laplacian = @import("laplacian.zig");
const gradient = @import("gradient.zig");

pub fn computeVertexGeodesicDistancesFromSource(
    allocator: std.mem.Allocator,
    sm: *SurfaceMesh,
    source_vertex: SurfaceMesh.Cell,
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

    // warning: Eigen (via zeigen) uses double precision

    // setup Laplacian matrix Lc
    const nb_edges = sm.nbCells(.edge);
    var row_indices = try std.ArrayList(u32).initCapacity(allocator, 4 * nb_edges);
    defer row_indices.deinit(allocator);
    var col_indices = try std.ArrayList(u32).initCapacity(allocator, 4 * nb_edges);
    defer col_indices.deinit(allocator);
    var values = try std.ArrayList(f64).initCapacity(allocator, 4 * nb_edges);
    defer values.deinit(allocator);
    var edge_it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer edge_it.deinit();
    while (edge_it.next()) |edge| {
        const d = edge.dart();
        const dd = sm.phi2(d);
        const i = vertex_index.value(.{ .vertex = d });
        const j = vertex_index.value(.{ .vertex = dd });
        const w_ij = laplacian.edgeCotanWeight(sm, edge, halfedge_cotan_weight);
        // off-diagonal
        row_indices.appendAssumeCapacity(i);
        col_indices.appendAssumeCapacity(j);
        values.appendAssumeCapacity(@floatCast(w_ij));
        row_indices.appendAssumeCapacity(j);
        col_indices.appendAssumeCapacity(i);
        values.appendAssumeCapacity(@floatCast(w_ij));
        // diagonal
        row_indices.appendAssumeCapacity(i);
        col_indices.appendAssumeCapacity(i);
        values.appendAssumeCapacity(@floatCast(-w_ij));
        row_indices.appendAssumeCapacity(j);
        col_indices.appendAssumeCapacity(j);
        values.appendAssumeCapacity(@floatCast(-w_ij));
    }
    const Lc: ?*anyopaque = zeigen.createSparseMatrixFromTriplets(
        nb_vertices,
        nb_vertices,
        row_indices.items,
        col_indices.items,
        values.items,
    );
    defer zeigen.destroySparseMatrix(Lc.?);

    // setup mass-matrix A (vertex areas) and
    // initial heat vector heat_0 (1.0 at source vertex, 0.0 elsewhere)
    var massCoeffs = try std.ArrayList(f64).initCapacity(allocator, nb_vertices);
    defer massCoeffs.deinit(allocator);
    var heat_0 = try std.ArrayList(f64).initCapacity(allocator, nb_vertices);
    defer heat_0.deinit(allocator);
    const source_vertex_index = sm.cellIndex(source_vertex);
    vertex_it.reset();
    while (vertex_it.next()) |v| {
        // relies on the fact that vertex iterator visits vertices in the same order as before (when indexing them)
        massCoeffs.appendAssumeCapacity(@floatCast(vertex_area.value(v)));
        heat_0.appendAssumeCapacity(if (sm.cellIndex(v) == source_vertex_index) 1.0 else 0.0);
    }
    const A: ?*anyopaque = zeigen.createDiagonalSparseMatrixFromArray(massCoeffs.items);
    defer zeigen.destroySparseMatrix(A.?);

    // compute time step t = mean_edge_length^2
    const mean_edge_length = geometry_utils.meanValue(f32, edge_length.data);
    const t = mean_edge_length * mean_edge_length * diffusion_time;

    // compute M = A - t * Lc
    const M: ?*anyopaque = zeigen.createSparseMatrix(nb_vertices, nb_vertices);
    zeigen.mulSparseMatrixScalar(Lc.?, @floatCast(t), M.?);
    zeigen.subSparseMatrices(A.?, M.?, M.?);

    // solve M * heat_t = heat_0 (backward Euler time step of the heat equation)
    var heat_t = try std.ArrayList(f64).initCapacity(allocator, nb_vertices);
    defer heat_t.deinit(allocator);
    try heat_t.resize(allocator, nb_vertices);
    zeigen.solveSymmetricSparseLinearSystem(M.?, heat_0.items, heat_t.items);

    // store heat_t in a vertex data
    var vertex_heat = try sm.addData(.vertex, f32, "__vertex_heat");
    defer sm.removeData(.vertex, vertex_heat.gen());
    vertex_it.reset();
    while (vertex_it.next()) |v| {
        const idx = vertex_index.value(v);
        vertex_heat.valuePtr(v).* = @floatCast(heat_t.items[idx]);
    }

    // compute the gradient of heat_t on each face
    var face_heat_grad = try sm.addData(.face, Vec3f, "__face_heat_grad");
    defer sm.removeData(.face, face_heat_grad.gen());
    try gradient.computeScalarFieldFaceGradients(
        sm,
        vertex_position,
        vertex_heat,
        face_normal,
        face_area,
        face_heat_grad,
    );

    // negate and normalize the face gradients
    var grad_it = face_heat_grad.data.iterator();
    while (grad_it.next()) |grad| {
        grad.* = vec.mulScalar3f(
            vec.normalized3f(grad.*),
            -1.0,
        );
    }

    // compute the divergence of the face gradients at each vertex
    var vertex_heat_grad_div = try sm.addData(.vertex, f32, "__vertex_heat_grad_div");
    defer sm.removeData(.vertex, vertex_heat_grad_div.gen());
    try gradient.computeVectorFieldVertexDivergences(
        sm,
        halfedge_cotan_weight,
        vertex_position,
        face_heat_grad,
        vertex_heat_grad_div,
    );

    // setup div vector
    var div = try std.ArrayList(f64).initCapacity(allocator, nb_vertices);
    defer div.deinit(allocator);
    vertex_it.reset();
    while (vertex_it.next()) |v| {
        // relies on the fact that vertex iterator visits vertices in the same order as before (when indexing them)
        div.appendAssumeCapacity(@floatCast(vertex_heat_grad_div.value(v)));
    }

    // solve Lc * dist = div (Poisson equation)
    var dist = try std.ArrayList(f64).initCapacity(allocator, nb_vertices);
    defer dist.deinit(allocator);
    try dist.resize(allocator, nb_vertices);
    zeigen.solveSymmetricSparseLinearSystem(Lc.?, div.items, dist.items);

    // shift distance values s.t. min distance is 0.0 and store them in vertex_distance
    const min_dist = std.mem.min(f64, dist.items);
    vertex_it.reset();
    while (vertex_it.next()) |v| {
        const idx = vertex_index.value(v);
        vertex_distance.valuePtr(v).* = @floatCast(dist.items[idx] - min_dist);
    }
}
