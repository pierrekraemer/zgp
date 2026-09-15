const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const data = @import("../../utils//data.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const mat = @import("../../geometry/mat.zig");
const Mat3f = mat.Mat3f;
const Mat3d = mat.Mat3d;
const eigen = @import("../../geometry/eigen.zig");
const SparseMatrix = eigen.SparseMatrix;
const FactorizedSparseMatrix = eigen.FactorizedSparseMatrix;

const laplacian = @import("laplacian.zig");

/// Compute the best-fit rotation for a vertex from its one-ring,
/// using the SVD of the covariance matrix between rest and current edge vectors.
/// Returns the 3x3 rotation matrix R_i.
pub fn computeVertexRotation(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
    vertex_position_rest: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_position_current: SurfaceMesh.CellData(.vertex, Vec3f),
) Mat3f {
    assert(vertex.cellType() == .vertex);

    // Build the covariance matrix S = sum_j w_ij * e_ij_rest * e_ij_current^T
    var S: Mat3d = mat.zero3d;

    const p_i_current = vertex_position_current.value(vertex);
    const p_i_rest = vertex_position_rest.value(vertex);

    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        const neighbor: SurfaceMesh.Cell = .{ .vertex = sm.phi1(d) };

        // edge vectors in rest and current poses
        const p_j_rest = vertex_position_rest.value(neighbor);
        const e_rest = vec.vec3dFromVec3f(vec.sub3f(p_i_rest, p_j_rest));

        const p_j_current = vertex_position_current.value(neighbor);
        const e_current = vec.vec3dFromVec3f(vec.sub3f(p_i_current, p_j_current));

        // cotan weight of the edge (sum of both halfedge cotan weights)
        const w: f64 = @floatCast(laplacian.edgeCotanWeight(sm, .{ .edge = d }, halfedge_cotan_weight));

        // S += w * e_rest * e_current^T
        S = mat.add3d(S, mat.mulScalar3d(mat.outerProduct3d(e_rest, e_current), w));
    }

    // SVD: S = U * diag(sigma) * V^T
    const svd_result = eigen.svd3d(S);
    const U = svd_result[0];
    // singular values in svd_result[1]
    const V = svd_result[2];

    // Handle reflections: if det(V * U^T) < 0, negate the column of U corresponding to the smallest singular value
    var U_fixed = U;
    // Compute det(V * U^T) by computing det(V) * det(U) (for column-major Mat3d, det = col0 . (col1 x col2))
    const det_U = vec.dot3d(U_fixed[0], vec.cross3d(U_fixed[1], U_fixed[2]));
    const det_V = vec.dot3d(V[0], vec.cross3d(V[1], V[2]));
    if (det_U * det_V < 0) {
        // Singular values are sorted in decreasing order by Eigen's JacobiSVD (smallest singular value is in column 2)
        U_fixed[2] = vec.mulScalar3d(U_fixed[2], -1.0);
    }

    // R = V * U^T
    const R = mat.mul3d(V, mat.transpose3d(U));

    return mat.mat3fFromMat3d(R);
}

/// ARAP deformation context.
/// Holds the pre-factorized Laplacian matrix and rest pose data.
pub const ArapContext = struct {
    allocator: std.mem.Allocator,

    surface_mesh: *SurfaceMesh,
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),

    nb_free: u32,
    free_vertex_index: SurfaceMesh.CellData(.vertex, u32), // free vertex index

    vertex_position_rest: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_rotation: SurfaceMesh.CellData(.vertex, Mat3f),

    factorized_L: FactorizedSparseMatrix,

    rhs_buf: []eigen.Scalar,
    solve_buf: []eigen.Scalar,

    pub fn init(
        allocator: std.mem.Allocator,
        sm: *SurfaceMesh,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
        fixed_set: *SurfaceMesh.CellSet,
        handle_set: *SurfaceMesh.CellSet,
    ) !ArapContext {
        // Create & initialize rest positions
        var vertex_position_rest = try sm.addData(.vertex, Vec3f, "__arap_rest_positions");
        vertex_position_rest.data.copyFrom(vertex_position.data);

        // Create & initialize rotation matrices for each vertex
        var vertex_rotation = try sm.addData(.vertex, Mat3f, "__arap_vertex_rotation");
        vertex_rotation.data.fill(mat.identity3f);

        // Create consecutive vertex indices for free vertices
        var free_vertex_index = try sm.addData(.vertex, u32, "__arap_free_vertex_index");
        var vertex_it: SurfaceMesh.CellIterator = try .init(sm, .vertex);
        defer vertex_it.deinit();
        var nb_free: u32 = 0;
        while (vertex_it.next()) |v| {
            if (fixed_set.contains(v) or handle_set.contains(v)) {
                free_vertex_index.valuePtr(v).* = data.invalid_index; // sentinel
            } else {
                free_vertex_index.valuePtr(v).* = nb_free;
                nb_free += 1;
            }
        }

        // Build the Laplacian matrix for free vertices (nb_free x nb_free)
        // L_ii = -sum_j w_ij (for j being all neighbors, both free and constrained)
        // L_ij = w_ij (only if both i and j are free)
        const nb_edges = sm.nbCells(.edge);
        var triplets = try std.ArrayList(SparseMatrix.Triplet).initCapacity(allocator, 4 * nb_edges);
        defer triplets.deinit(allocator);
        var edge_it: SurfaceMesh.CellIterator = try .init(sm, .edge);
        defer edge_it.deinit();
        while (edge_it.next()) |edge| {
            const d = edge.dart();
            const dd = sm.phi2(d);

            const v1_free_idx = free_vertex_index.value(.{ .vertex = d });
            const v2_free_idx = free_vertex_index.value(.{ .vertex = dd });

            const w_ij = laplacian.edgeCotanWeight(sm, edge, halfedge_cotan_weight);
            const w: eigen.Scalar = @floatCast(w_ij);

            if (v1_free_idx < data.invalid_index and v2_free_idx < data.invalid_index) {
                // off-diagonal entries (negative in standard Laplacian)
                triplets.appendAssumeCapacity(.{
                    .row = @intCast(v1_free_idx),
                    .col = @intCast(v2_free_idx),
                    .value = -w,
                });
                triplets.appendAssumeCapacity(.{
                    .row = @intCast(v2_free_idx),
                    .col = @intCast(v1_free_idx),
                    .value = -w,
                });
            }
            // diagonal: each edge contributes +w to both endpoints (if free)
            if (v1_free_idx < data.invalid_index) {
                triplets.appendAssumeCapacity(.{
                    .row = @intCast(v1_free_idx),
                    .col = @intCast(v1_free_idx),
                    .value = w,
                });
            }
            if (v2_free_idx < data.invalid_index) {
                triplets.appendAssumeCapacity(.{
                    .row = @intCast(v2_free_idx),
                    .col = @intCast(v2_free_idx),
                    .value = w,
                });
            }
        }

        var L: SparseMatrix = .initFromTriplets(@intCast(nb_free), @intCast(nb_free), triplets.items);
        defer L.deinit();
        const factorized_L: FactorizedSparseMatrix = .init(L, @intCast(nb_free));

        // Allocate solve buffers
        const rhs_buf = try allocator.alloc(eigen.Scalar, nb_free * 3);
        const solve_buf = try allocator.alloc(eigen.Scalar, nb_free * 3);

        return .{
            .allocator = allocator,
            .surface_mesh = sm,
            .halfedge_cotan_weight = halfedge_cotan_weight,
            .vertex_position = vertex_position,
            .nb_free = nb_free,
            .free_vertex_index = free_vertex_index,
            .vertex_position_rest = vertex_position_rest,
            .vertex_rotation = vertex_rotation,
            .factorized_L = factorized_L,
            .rhs_buf = rhs_buf,
            .solve_buf = solve_buf,
        };
    }

    pub fn deinit(ctx: *ArapContext) void {
        ctx.allocator.free(ctx.solve_buf);
        ctx.allocator.free(ctx.rhs_buf);
        ctx.factorized_L.deinit();
        ctx.surface_mesh.removeData(.vertex, u32, ctx.free_vertex_index);
        ctx.surface_mesh.removeData(.vertex, Mat3f, ctx.vertex_rotation);
        ctx.surface_mesh.removeData(.vertex, Vec3f, ctx.vertex_position_rest);
    }

    /// Run nb_iterations of the ARAP local/global solve.
    /// Updates vertex_position in place.
    pub fn solve(
        ctx: *ArapContext,
        nb_iterations: u32,
    ) !void {
        for (0..nb_iterations) |_| {
            // === Local step: compute best-fit rotation for each vertex ===
            var vertex_it: SurfaceMesh.CellIterator = try .init(ctx.surface_mesh, .vertex);
            defer vertex_it.deinit();
            while (vertex_it.next()) |v| {
                ctx.vertex_rotation.valuePtr(v).* = computeVertexRotation(
                    ctx.surface_mesh,
                    v,
                    ctx.halfedge_cotan_weight,
                    ctx.vertex_position_rest,
                    ctx.vertex_position,
                );
            }

            // === Global step: solve for new positions ===
            vertex_it.reset();
            while (vertex_it.next()) |v| {
                const fi = ctx.free_vertex_index.value(v);
                if (fi == data.invalid_index) continue; // constrained vertex

                var rhs_val: Vec3d = vec.zero3d;

                // Iterate over one-ring neighbors
                var dart_it = ctx.surface_mesh.cellDartIterator(v);
                while (dart_it.next()) |d| {
                    const neighbor: SurfaceMesh.Cell = .{ .vertex = ctx.surface_mesh.phi1(d) };
                    const w: f64 = @floatCast(laplacian.edgeCotanWeight(ctx.surface_mesh, .{ .edge = d }, ctx.halfedge_cotan_weight));

                    // Rest edge vector
                    const e_rest = vec.sub3f(ctx.vertex_position_rest.value(v), ctx.vertex_position_rest.value(neighbor));

                    // Rotated edge: (R_i + R_j) / 2 * e_rest
                    const R_i = ctx.vertex_rotation.value(v);
                    const R_j = ctx.vertex_rotation.value(neighbor);
                    const rotated_e = vec.mulScalar3f(
                        vec.add3f(
                            mat.mulVec3f(R_i, e_rest),
                            mat.mulVec3f(R_j, e_rest),
                        ),
                        0.5,
                    );

                    rhs_val = vec.add3d(rhs_val, vec.mulScalar3d(vec.vec3dFromVec3f(rotated_e), w));

                    // If neighbor is constrained, move its contribution to the RHS
                    // L_ij = -w_ij, so: rhs -= L_ij * p_j = rhs += w_ij * p_j
                    if (ctx.free_vertex_index.value(neighbor) == data.invalid_index) {
                        const p_j = ctx.vertex_position.value(neighbor);
                        rhs_val = vec.add3d(rhs_val, vec.mulScalar3d(vec.vec3dFromVec3f(p_j), w));
                    }
                }

                ctx.rhs_buf[fi + 0 * ctx.nb_free] = rhs_val[0];
                ctx.rhs_buf[fi + 1 * ctx.nb_free] = rhs_val[1];
                ctx.rhs_buf[fi + 2 * ctx.nb_free] = rhs_val[2];
            }

            // Solve L * x = rhs
            ctx.factorized_L.solve3(ctx.rhs_buf, ctx.solve_buf);

            // Write solved positions back
            vertex_it.reset();
            while (vertex_it.next()) |v| {
                const fi = ctx.free_vertex_index.value(v);
                if (fi == data.invalid_index) continue; // constrained vertex
                ctx.vertex_position.valuePtr(v).* = .{
                    @floatCast(ctx.solve_buf[fi + 0 * ctx.nb_free]),
                    @floatCast(ctx.solve_buf[fi + 1 * ctx.nb_free]),
                    @floatCast(ctx.solve_buf[fi + 2 * ctx.nb_free]),
                };
            }
        }
    }
};
