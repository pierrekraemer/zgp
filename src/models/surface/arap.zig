const std = @import("std");
const assert = std.debug.assert;

const AppContext = @import("../../main.zig").AppContext;
const SurfaceMesh = @import("SurfaceMesh.zig");
const invalid_index = @import("../../utils//data.zig").invalid_index;

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
const intrinsic_triangulation = @import("intrinsic_triangulation.zig");

/// Compute the best-fit rotation for a vertex from its one-ring,
/// using the SVD of the covariance matrix between rest and current edge vectors.
/// Returns the 3x3 rotation matrix R_i.
pub fn computeVertexOneRingRotation(
    sm: *const SurfaceMesh,
    v: SurfaceMesh.Cell,
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
    vertex_position_rest: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
) Mat3f {
    assert(v.cellType() == .vertex);

    // Build the covariance matrix S = sum_j w_ij * e_ij_rest * e_ij_current^T
    var S: Mat3d = mat.zero3d;

    const v_idx = sm.cellIndex(v);

    const p_rest = vertex_position_rest.valueByIndex(v_idx);
    const p_current = vertex_position.valueByIndex(v_idx);

    var dart_it = sm.cellDartIterator(v);
    while (dart_it.next()) |d| {
        const nv: SurfaceMesh.Cell = .{ .vertex = sm.phi1(d) };
        const nv_idx = sm.cellIndex(nv);

        // edge vectors in rest and current poses
        const e_rest = vec.vec3dFromVec3f(vec.sub3f(
            vertex_position_rest.valueByIndex(nv_idx),
            p_rest,
        ));
        const e_current = vec.vec3dFromVec3f(vec.sub3f(
            vertex_position.valueByIndex(nv_idx),
            p_current,
        ));

        // cotan weight of the edge (sum of both halfedge cotan weights)
        const w: f64 = @floatCast(laplacian.edgeCotanWeight(sm, .{ .edge = d }, halfedge_cotan_weight));

        // S += w * e_rest * e_current^T
        S = mat.add3d(S, mat.mulScalar3d(mat.outerProduct3d(e_rest, e_current), w));
    }

    // SVD: S = U * diag(sigma) * V^T
    var U, _, const V = eigen.svd3d(S);

    // Handle reflections: if det(V * U^T) < 0, negate the column of U corresponding to the smallest singular value
    // Compute det(V * U^T) by computing det(V) * det(U) (for column-major Mat3d, det = col0 . (col1 x col2))
    const det_U = vec.dot3d(U[0], vec.cross3d(U[1], U[2]));
    const det_V = vec.dot3d(V[0], vec.cross3d(V[1], V[2]));
    if (det_U * det_V < 0) {
        // Singular values are sorted in decreasing order by Eigen's JacobiSVD (smallest singular value is in column 2)
        U[2] = vec.mulScalar3d(U[2], -1.0);
    }

    // R = V * U^T
    const R = mat.mul3d(V, mat.transpose3d(U));

    return mat.mat3fFromMat3d(R);
}

/// ARAP deformation context.
pub const ARAPContext = struct {
    surface_mesh: *SurfaceMesh, // the original SurfaceMesh
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32), // defined on the original SurfaceMesh (given)
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f), // defined on the original SurfaceMesh (given)

    vertex_position_rest: SurfaceMesh.CellData(.vertex, Vec3f), // defined on the original SurfaceMesh (generated)
    vertex_rotation: SurfaceMesh.CellData(.vertex, Mat3f), // defined on the original SurfaceMesh (generated)
    nb_free: u32,
    free_vertex_index: SurfaceMesh.CellData(.vertex, u32), // defined on the original SurfaceMesh (generated)

    // optional pointer to an intrinsic triangulation context associated with the original SurfaceMesh
    // allows to compute on the intrinsic Delaunay triangulation if wanted
    it_ctx: ?*intrinsic_triangulation.ITContext,

    // if the intrinsic triangulation is used, its connectivity and halfedge cotan weights are used to compute the Laplacian and vertex rotations
    // and these two fields point to the intrinsic triangulation SurfaceMesh and its halfedge cotan weights
    // otherwise they point to the original SurfaceMesh and its halfedge cotan weights
    compute_surface_mesh: *SurfaceMesh,
    compute_halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),

    // WARNING!
    // the intrinsic mesh never adds/removes vertices (only Delaunay flips are performed on it), so vertex indices are shared between the two meshes
    // access to vertex data that is defined on the extrinsic mesh from Cells (i.e. Darts) obtained while walking connectivity on the intrinsic mesh can be done,
    // but only via `valueByIndex`/`valuePtrByIndex` using the indices obtained by cellIndex on the intrinsic mesh
    // rather than via `value`/`valuePtr`, which would silently re-derive the index associated with the Dart on the original mesh which may have changed due to Delaunay flips

    factorized_L: FactorizedSparseMatrix, // cached factorization of the Laplacian matrix for free vertices (nb_free x nb_free)

    rhs_mat: eigen.DenseMatrix, // preallocated buffer for the right-hand side of the linear system (nb_free x 3)
    solve_mat: eigen.DenseMatrix, // preallocated buffer for the solution of the linear system (nb_free x 3)

    pub fn init(
        app_ctx: *AppContext,
        sm: *SurfaceMesh,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
        fixed_set: *SurfaceMesh.CellSet,
        handle_set: *SurfaceMesh.CellSet,
        it_ctx: ?*intrinsic_triangulation.ITContext, // defined if using intrinsic Delaunay triangulation, null otherwise
    ) !ARAPContext {
        // Create & initialize vertex rest positions
        var vertex_position_rest = try sm.addData(.vertex, Vec3f, "__arap_rest_positions");
        vertex_position_rest.data.copyFrom(vertex_position.data);

        // Create & initialize vertex rotation matrices
        var vertex_rotation = try sm.addData(.vertex, Mat3f, "__arap_vertex_rotation");
        vertex_rotation.data.fill(mat.identity3f);

        // Create consecutive indices for free vertices
        var free_vertex_index = try sm.addData(.vertex, u32, "__arap_free_vertex_index");
        var vertex_it: SurfaceMesh.CellIterator = try .init(sm, .vertex);
        defer vertex_it.deinit();
        var nb_free: u32 = 0;
        while (vertex_it.next()) |v| {
            if (fixed_set.contains(v) or handle_set.contains(v)) {
                free_vertex_index.valuePtr(v).* = invalid_index; // sentinel value for constrained vertices
            } else {
                free_vertex_index.valuePtr(v).* = nb_free;
                nb_free += 1;
            }
        }

        assert((if (it_ctx) |ctx| ctx.extrinsic_surface_mesh else sm) == sm); // ensure we are given the right intrinsic triangulation context
        const compute_surface_mesh = if (it_ctx) |ctx| ctx.intrinsic_surface_mesh else sm;
        const compute_halfedge_cotan_weight = if (it_ctx) |ctx| ctx.intrinsic_halfedge_cotan_weight else halfedge_cotan_weight;

        // Build the Laplacian matrix for free vertices (nb_free x nb_free)
        // L_ii = -sum_j w_ij (for j being all neighbors, both free and constrained)
        // L_ij = w_ij (only if both i and j are free)
        const nb_edges = compute_surface_mesh.nbCells(.edge);
        var triplets = try std.ArrayList(SparseMatrix.Triplet).initCapacity(app_ctx.allocator, 4 * nb_edges);
        defer triplets.deinit(app_ctx.allocator);
        var edge_it: SurfaceMesh.CellIterator = try .init(compute_surface_mesh, .edge);
        defer edge_it.deinit();
        while (edge_it.next()) |edge| {
            const d = edge.dart();
            const dd = compute_surface_mesh.phi2(d);
            const i = free_vertex_index.valueByIndex(compute_surface_mesh.cellIndex(.{ .vertex = d }));
            const j = free_vertex_index.valueByIndex(compute_surface_mesh.cellIndex(.{ .vertex = dd }));
            const w_ij: eigen.Scalar = @floatCast(laplacian.edgeCotanWeight(compute_surface_mesh, edge, compute_halfedge_cotan_weight));
            if (i != invalid_index and j != invalid_index) {
                // off-diagonal
                triplets.appendAssumeCapacity(.{ .row = @intCast(i), .col = @intCast(j), .value = w_ij });
                triplets.appendAssumeCapacity(.{ .row = @intCast(j), .col = @intCast(i), .value = w_ij });
            }
            // diagonal: each edge contributes to both endpoints (if free)
            if (i != invalid_index) {
                triplets.appendAssumeCapacity(.{ .row = @intCast(i), .col = @intCast(i), .value = -w_ij });
            }
            if (j != invalid_index) {
                triplets.appendAssumeCapacity(.{ .row = @intCast(j), .col = @intCast(j), .value = -w_ij });
            }
        }

        // initialize Laplacian sparse matrix and factorize it
        var L: SparseMatrix = .initFromTriplets(@intCast(nb_free), @intCast(nb_free), triplets.items);
        defer L.deinit();
        const factorized_L: FactorizedSparseMatrix = .init(L, @intCast(nb_free));

        // allocate buffers for the right-hand side and solution matrices (nb_free x 3)
        const rhs_mat: eigen.DenseMatrix = .init(@intCast(nb_free), 3);
        const solve_mat: eigen.DenseMatrix = .init(@intCast(nb_free), 3);

        return .{
            .surface_mesh = sm,
            .halfedge_cotan_weight = halfedge_cotan_weight,
            .vertex_position = vertex_position,
            .vertex_position_rest = vertex_position_rest,
            .vertex_rotation = vertex_rotation,
            .nb_free = nb_free,
            .free_vertex_index = free_vertex_index,
            .it_ctx = it_ctx,
            .compute_surface_mesh = compute_surface_mesh,
            .compute_halfedge_cotan_weight = compute_halfedge_cotan_weight,
            .factorized_L = factorized_L,
            .rhs_mat = rhs_mat,
            .solve_mat = solve_mat,
        };
    }

    pub fn deinit(ctx: *ARAPContext) void {
        ctx.solve_mat.deinit();
        ctx.rhs_mat.deinit();
        ctx.factorized_L.deinit();
        ctx.surface_mesh.removeData(.vertex, u32, ctx.free_vertex_index);
        ctx.surface_mesh.removeData(.vertex, Mat3f, ctx.vertex_rotation);
        ctx.surface_mesh.removeData(.vertex, Vec3f, ctx.vertex_position_rest);
    }

    /// Run the ARAP local/global solve & updates vertex_position
    pub fn solve(
        ctx: *ARAPContext,
        app_ctx: *AppContext,
    ) !void {
        // === Local step: compute best-fit rotation for each vertex ===

        const ComputeVertexRotationTask = struct {
            const ComputeVertexRotationTask = @This();

            surface_mesh: *const SurfaceMesh,
            halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
            vertex_position_rest: SurfaceMesh.CellData(.vertex, Vec3f),
            vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
            vertex_rotation: SurfaceMesh.CellData(.vertex, Mat3f),

            pub fn run(t: *const ComputeVertexRotationTask, v: SurfaceMesh.Cell) void {
                const v_idx = t.surface_mesh.cellIndex(v);
                t.vertex_rotation.valuePtrByIndex(v_idx).* = computeVertexOneRingRotation(
                    t.surface_mesh,
                    v,
                    t.halfedge_cotan_weight,
                    t.vertex_position_rest,
                    t.vertex_position,
                );
            }
        };

        var pctr: SurfaceMesh.ParallelCellTaskRunner = try .init(ctx.compute_surface_mesh, .vertex);
        defer pctr.deinit();
        try pctr.run(app_ctx, ComputeVertexRotationTask{
            .surface_mesh = ctx.compute_surface_mesh,
            .halfedge_cotan_weight = ctx.compute_halfedge_cotan_weight,
            .vertex_position_rest = ctx.vertex_position_rest,
            .vertex_position = ctx.vertex_position,
            .vertex_rotation = ctx.vertex_rotation,
        });

        // === Global step: solve for new positions ===

        // prepare the right-hand side matrix (nb_free x 3)
        const SetupVertexRHSTask = struct {
            const SetupVertexRHSTask = @This();

            surface_mesh: *const SurfaceMesh,
            halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
            vertex_position_rest: SurfaceMesh.CellData(.vertex, Vec3f),
            vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
            vertex_rotation: SurfaceMesh.CellData(.vertex, Mat3f),
            free_vertex_index: SurfaceMesh.CellData(.vertex, u32),
            rhs_mat: eigen.DenseMatrix,

            pub fn run(t: *SetupVertexRHSTask, v: SurfaceMesh.Cell) void {
                const v_idx = t.surface_mesh.cellIndex(v);
                const fi = t.free_vertex_index.valueByIndex(v_idx);
                if (fi == invalid_index) return; // constrained vertex

                var rhs_val: Vec3d = vec.zero3d;

                // iterate over one-ring neighbors
                var dart_it = t.surface_mesh.cellDartIterator(v);
                while (dart_it.next()) |d| {
                    const vn: SurfaceMesh.Cell = .{ .vertex = t.surface_mesh.phi1(d) };
                    const vn_idx = t.surface_mesh.cellIndex(vn);

                    const w_ij: eigen.Scalar = @floatCast(laplacian.edgeCotanWeight(t.surface_mesh, .{ .edge = d }, t.halfedge_cotan_weight));

                    // Rest edge vector
                    const e_rest = vec.sub3f(
                        t.vertex_position_rest.valueByIndex(vn_idx),
                        t.vertex_position_rest.valueByIndex(v_idx),
                    );

                    // Rotated edge: (R_i + R_j) / 2 * e_rest
                    const rotated_e = mat.mulVec3f(
                        mat.mulScalar3f(
                            mat.add3f(t.vertex_rotation.valueByIndex(v_idx), t.vertex_rotation.valueByIndex(vn_idx)),
                            0.5,
                        ),
                        e_rest,
                    );

                    rhs_val = vec.add3d(rhs_val, vec.mulScalar3d(vec.vec3dFromVec3f(rotated_e), w_ij));

                    // if neighbor is constrained, move its contribution to the RHS
                    // L_ij = w_ij, so: rhs -= L_ij * p_j => rhs -= w_ij * p_j
                    if (t.free_vertex_index.valueByIndex(vn_idx) == invalid_index) {
                        rhs_val = vec.sub3d(rhs_val, vec.mulScalar3d(
                            vec.vec3dFromVec3f(t.vertex_position.valueByIndex(vn_idx)),
                            w_ij,
                        ));
                    }
                }

                t.rhs_mat.setRow(@intCast(fi), &rhs_val);
            }
        };

        pctr.reset();
        try pctr.run(app_ctx, SetupVertexRHSTask{
            .surface_mesh = ctx.compute_surface_mesh,
            .halfedge_cotan_weight = ctx.compute_halfedge_cotan_weight,
            .vertex_position_rest = ctx.vertex_position_rest,
            .vertex_position = ctx.vertex_position,
            .vertex_rotation = ctx.vertex_rotation,
            .free_vertex_index = ctx.free_vertex_index,
            .rhs_mat = ctx.rhs_mat,
        });

        // Solve L * x = rhs
        ctx.factorized_L.solveMultipleRHS(ctx.rhs_mat, ctx.solve_mat, 3);

        // Write solved positions back
        const WriteSolvedPositionsTask = struct {
            const WriteSolvedPositionsTask = @This();

            surface_mesh: *const SurfaceMesh,
            free_vertex_index: SurfaceMesh.CellData(.vertex, u32),
            vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
            solve_mat: eigen.DenseMatrix,

            pub fn run(t: *WriteSolvedPositionsTask, v: SurfaceMesh.Cell) void {
                const v_idx = t.surface_mesh.cellIndex(v);
                const fi = t.free_vertex_index.valueByIndex(v_idx);
                if (fi == invalid_index) return; // constrained vertex
                var solved_row: [3]eigen.Scalar = undefined;
                t.solve_mat.getRow(@intCast(fi), &solved_row);
                t.vertex_position.valuePtrByIndex(v_idx).* = vec.vec3fFromVec3d(.{ solved_row[0], solved_row[1], solved_row[2] });
            }
        };

        pctr.reset();
        try pctr.run(app_ctx, WriteSolvedPositionsTask{
            .surface_mesh = ctx.compute_surface_mesh,
            .free_vertex_index = ctx.free_vertex_index,
            .vertex_position = ctx.vertex_position,
            .solve_mat = ctx.solve_mat,
        });
    }
};
