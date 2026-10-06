const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const invalid_index = @import("../../utils//data.zig").invalid_index;

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const SimdVec4f = vec.SimdVec4f;
const mat = @import("../../geometry/mat.zig");
const Mat3f = mat.Mat3f;
const Mat3d = mat.Mat3d;
const SimdMat4f = mat.SimdMat4f;
const geometry_utils = @import("../../geometry/utils.zig");
const eigen = @import("../../geometry/eigen.zig");
const SparseMatrix = eigen.SparseMatrix;
const FactorizedSparseMatrix = eigen.FactorizedSparseMatrix;

const laplacian = @import("laplacian.zig");
const intrinsic_triangulation = @import("intrinsic_triangulation.zig");

/// Compute the best-fit rotation for a vertex from its one-ring using Horn's method (no SVD).
/// Returns the optimal rotation as a unit quaternion.
pub fn computeVertexOneRingRotation(
    sm: *const SurfaceMesh,
    v: SurfaceMesh.Vertex,
    previous_rotation: SimdVec4f,
    halfedge_cotan_weight: SurfaceMesh.HalfedgeData(f32),
    vertex_position_rest: SurfaceMesh.VertexData(SimdVec4f),
    vertex_position: SurfaceMesh.VertexData(Vec3f),
) SimdVec4f {
    // Build the covariance matrix S = sum_j w_ij * e_ij_rest * e_ij_current^T
    var S: SimdMat4f = .{ @splat(0.0), @splat(0.0), @splat(0.0), @splat(0.0) };
    const p_rest = vertex_position_rest.value(v);
    const p_current = vec.simdFromVec3f(vertex_position.value(v));
    var dart_it = sm.vertexDartIterator(sm.dart(v));
    while (dart_it.next()) |d| {
        const nv = sm.vertex(sm.phi1(d));
        const nv_current = vec.simdFromVec3f(vertex_position.value(nv));
        // edge vectors in rest and current poses
        const e_rest = vertex_position_rest.value(nv) - p_rest;
        const e_current = nv_current - p_current;
        // cotan weight of the edge (sum of both halfedge cotan weights)
        const w = laplacian.edgeCotanWeight(sm, sm.edge(d), halfedge_cotan_weight);
        // S += w * e_rest * e_current^T
        S = mat.simdAdd4f(S, mat.simdMulScalar4f(mat.simdOuterProduct4f(e_rest, e_current), w));
    }

    // Horn's Absolute Orientation Method:
    // The dominant eigenvector of N is the unit quaternion representing the optimal rotation.
    // S is column-major so S_ij = S[j][i]
    var N = SimdMat4f{
        SimdVec4f{ S[0][0] + S[1][1] + S[2][2], S[2][1] - S[1][2], S[0][2] - S[2][0], S[1][0] - S[0][1] },
        SimdVec4f{ S[2][1] - S[1][2], S[0][0] - S[1][1] - S[2][2], S[1][0] + S[0][1], S[0][2] + S[2][0] },
        SimdVec4f{ S[0][2] - S[2][0], S[1][0] + S[0][1], -S[0][0] + S[1][1] - S[2][2], S[2][1] + S[1][2] },
        SimdVec4f{ S[1][0] - S[0][1], S[0][2] + S[2][0], S[2][1] + S[1][2], -S[0][0] - S[1][1] + S[2][2] },
    };
    // Shift N to make it positive definite (prevents power iteration from oscillating to negative eigenvalues)
    // Use the L1 matrix norm (max absolute column sum) as a safe upper bound on the spectral radius (Gershgorin Circle Theorem).
    const c0 = @reduce(.Add, @abs(N[0]));
    const c1 = @reduce(.Add, @abs(N[1]));
    const c2 = @reduce(.Add, @abs(N[2]));
    const c3 = @reduce(.Add, @abs(N[3]));
    const max_eval_bound = @max(@max(c0, c1), @max(c2, c3));
    if (max_eval_bound < 1e-8) return previous_rotation;
    // Pre-normalize N so its eigenvalues are strictly between [-1, 1],
    // then shift the diagonal by 1.0 so eigenvalues are strictly in [0, 2].
    // This prevents f32 overflow, eliminating the need to normalize the vector inside the loop.
    const inv_shift = @as(SimdVec4f, @splat(1.0 / max_eval_bound));
    N[0] = N[0] * inv_shift;
    N[1] = N[1] * inv_shift;
    N[2] = N[2] * inv_shift;
    N[3] = N[3] * inv_shift;
    N[0][0] += 1.0;
    N[1][1] += 1.0;
    N[2][2] += 1.0;
    N[3][3] += 1.0;
    var q = previous_rotation; // already guaranteed to be a valid unit quaternion
    // 3 iterations of Power Iteration
    inline for (0..3) |_| {
        q = mat.simdMulVec4f(N, q);
    }
    // Normalize just once at the end
    const len2 = vec.simdDot4f(q, q);
    if (len2 > 1e-16) {
        q = q * @as(SimdVec4f, @splat(1.0 / @sqrt(len2)));
    } else {
        q = previous_rotation;
    }
    return q;
}

/// ARAP deformation context.
pub const ARAPContext = struct {
    io: std.Io,

    surface_mesh: *SurfaceMesh, // the original SurfaceMesh
    vertex_position: SurfaceMesh.VertexData(Vec3f), // defined on the original SurfaceMesh, updated by the ARAP solver

    vertex_position_rest: SurfaceMesh.VertexData(SimdVec4f), // created on the original SurfaceMesh
    vertex_rotation: SurfaceMesh.VertexData(SimdVec4f), // created on the original SurfaceMesh
    nb_free: u32,
    free_vertex_index: SurfaceMesh.VertexData(u32), // created on the original SurfaceMesh

    // if an IT context is provided upon init, it is supposed to be Delaunay,
    // and its connectivity and halfedge cotan weights are used to compute the Laplacian and vertex rotations;
    // the following two fields thus either point to the IT SurfaceMesh and its halfedge cotan weights
    // or to the original SurfaceMesh and its halfedge cotan weights
    compute_surface_mesh: *SurfaceMesh,
    compute_halfedge_cotan_weight: SurfaceMesh.HalfedgeData(f32),

    // WARNING!
    // - if provided, the IT context should not be deinitialized while the ARAP context is still alive
    // - the intrinsic mesh never adds/removes vertices (only Delaunay flips are performed on it), so vertex indices are shared between the two meshes
    // access to vertex data that is defined on the extrinsic mesh from Cells (i.e. Darts) obtained while walking connectivity on the intrinsic mesh can be done,
    // but only via `valueByIndex`/`valuePtrByIndex` using the indices obtained by cellIndex on the intrinsic mesh
    // rather than via `value`/`valuePtr`, which would silently re-derive the index associated with the Dart on the original mesh which may have changed due to Delaunay flips

    factorized_L: FactorizedSparseMatrix, // cached factorization of the Laplacian matrix for free vertices (nb_free x nb_free)

    rhs_mat: eigen.DenseMatrix, // preallocated buffer for the right-hand side of the linear system (nb_free x 3)
    solve_mat: eigen.DenseMatrix, // preallocated buffer for the solution of the linear system (nb_free x 3)

    nb_iterations: i32 = 5, // number of ARAP iterations to perform in a single solve() call

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        sm: *SurfaceMesh,
        vertex_position: SurfaceMesh.VertexData(Vec3f),
        halfedge_cotan_weight: SurfaceMesh.HalfedgeData(f32),
        fixed_set: *SurfaceMesh.VertexSet,
        handle_set: *SurfaceMesh.VertexSet,
        it_ctx: ?intrinsic_triangulation.ITContext,
    ) !ARAPContext {
        // Create & initialize vertex rest positions (stored as SimdVec4f)
        const vertex_position_rest = try sm.addData(.vertex, SimdVec4f, "__arap_rest_position_simd");
        var it = vertex_position.data.constIterator();
        while (it.next()) |elem| {
            vertex_position_rest.data.valuePtr(elem.idx).* = vec.simdFromVec3f(elem.value_ptr.*);
        }
        // Create & initialize vertex rotation matrices (stored as quaternions in SimdVec4f)
        var vertex_rotation = try sm.addData(.vertex, SimdVec4f, "__arap_vertex_rotation_simd");
        vertex_rotation.data.fill(.{ 1.0, 0.0, 0.0, 0.0 });

        // Create consecutive indices for free vertices
        var free_vertex_index = try sm.addData(.vertex, u32, "__arap_free_vertex_index");
        var vertex_it = sm.vertexIterator();
        var nb_free: u32 = 0;
        while (vertex_it.next()) |v| {
            if (fixed_set.contains(v) or handle_set.contains(v)) {
                free_vertex_index.valuePtr(v).* = invalid_index; // sentinel value for constrained vertices
            } else {
                free_vertex_index.valuePtr(v).* = nb_free;
                nb_free += 1;
            }
        }

        if (it_ctx) |ctx| {
            assert(ctx.extrinsic_surface_mesh == sm);
            // assert(ctx.is_delaunay); // TODO: not available for now
        }
        const compute_surface_mesh = if (it_ctx) |ctx| ctx.intrinsic_surface_mesh else sm;
        const compute_halfedge_cotan_weight = if (it_ctx) |ctx| ctx.intrinsic_halfedge_cotan_weight else halfedge_cotan_weight;

        // Build the Laplacian matrix for free vertices (nb_free x nb_free)
        // L_ii = -sum_j w_ij (for j being all neighbors, both free and constrained)
        // L_ij = w_ij (only if both i and j are free)
        const nb_edges = compute_surface_mesh.nbCells(.edge);
        var triplets = try std.ArrayList(SparseMatrix.Triplet).initCapacity(allocator, 4 * nb_edges);
        defer triplets.deinit(allocator);
        var edge_it = compute_surface_mesh.edgeIterator();
        while (edge_it.next()) |edge| {
            const d = compute_surface_mesh.dart(edge);
            const dd = compute_surface_mesh.phi2(d);
            const i = free_vertex_index.value(compute_surface_mesh.vertex(d)); // the intrinsic mesh shares the same vertex indices as the extrinsic mesh
            const j = free_vertex_index.value(compute_surface_mesh.vertex(dd));
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

        // pre-allocate buffers for the right-hand side and solution matrices (nb_free x 3)
        const rhs_mat: eigen.DenseMatrix = .init(@intCast(nb_free), 3);
        const solve_mat: eigen.DenseMatrix = .init(@intCast(nb_free), 3);

        return .{
            .io = io,
            .surface_mesh = sm,
            .vertex_position = vertex_position,
            .vertex_position_rest = vertex_position_rest,
            .vertex_rotation = vertex_rotation,
            .nb_free = nb_free,
            .free_vertex_index = free_vertex_index,
            .compute_surface_mesh = compute_surface_mesh,
            .compute_halfedge_cotan_weight = compute_halfedge_cotan_weight,
            .factorized_L = factorized_L,
            .rhs_mat = rhs_mat,
            .solve_mat = solve_mat,
        };
    }

    pub fn deinit(arap_ctx: *ARAPContext) void {
        arap_ctx.solve_mat.deinit();
        arap_ctx.rhs_mat.deinit();
        arap_ctx.factorized_L.deinit();
        arap_ctx.surface_mesh.removeData(arap_ctx.free_vertex_index);
        arap_ctx.surface_mesh.removeData(arap_ctx.vertex_rotation);
        arap_ctx.surface_mesh.removeData(arap_ctx.vertex_position_rest);
    }

    /// Run the ARAP local/global solve & updates vertex_position
    pub fn solve(arap_ctx: *ARAPContext) !void {
        const ComputeVertexRotationTask = struct {
            surface_mesh: *const SurfaceMesh,
            halfedge_cotan_weight: SurfaceMesh.HalfedgeData(f32),
            vertex_position_rest: SurfaceMesh.VertexData(SimdVec4f),
            vertex_position: SurfaceMesh.VertexData(Vec3f),
            vertex_rotation: *SurfaceMesh.VertexData(SimdVec4f),

            pub fn run(t: *const @This(), v: SurfaceMesh.Vertex) void {
                const v_rotation = t.vertex_rotation.valuePtr(v);
                v_rotation.* = computeVertexOneRingRotation(
                    t.surface_mesh,
                    v,
                    v_rotation.*,
                    t.halfedge_cotan_weight,
                    t.vertex_position_rest,
                    t.vertex_position,
                );
            }
        };

        const SetupVertexRHSTask = struct {
            surface_mesh: *const SurfaceMesh,
            halfedge_cotan_weight: SurfaceMesh.HalfedgeData(f32),
            vertex_position_rest: SurfaceMesh.VertexData(SimdVec4f),
            vertex_position: SurfaceMesh.VertexData(Vec3f),
            vertex_rotation: SurfaceMesh.VertexData(SimdVec4f),
            free_vertex_index: SurfaceMesh.VertexData(u32),
            rhs_mat: eigen.DenseMatrix,

            pub fn run(t: *@This(), v: SurfaceMesh.Vertex) void {
                const fi = t.free_vertex_index.value(v);
                if (fi == invalid_index) return; // constrained vertex

                var rhs_val: SimdVec4f = vec.zero4f;
                const v_pos_rest = t.vertex_position_rest.value(v);

                // iterate over one-ring neighbors
                var dart_it = t.surface_mesh.vertexDartIterator(t.surface_mesh.dart(v));
                while (dart_it.next()) |d| {
                    const vn = t.surface_mesh.vertex(t.surface_mesh.phi1(d));

                    const w_ij = laplacian.edgeCotanWeight(t.surface_mesh, t.surface_mesh.edge(d), t.halfedge_cotan_weight);

                    // Rest edge vector
                    const e_rest: SimdVec4f = t.vertex_position_rest.value(vn) - v_pos_rest;
                    // Rotated edge: (R_i + R_j) / 2 * e_rest
                    const rotated_e_i = geometry_utils.rotateVectorByQuaternion(t.vertex_rotation.value(v), e_rest);
                    const rotated_e_j = geometry_utils.rotateVectorByQuaternion(t.vertex_rotation.value(vn), e_rest);
                    const rotated_e = (rotated_e_i + rotated_e_j) * @as(SimdVec4f, @splat(0.5 * w_ij));
                    rhs_val += rotated_e;

                    // if neighbor is constrained, move its contribution to the RHS
                    // L_ij = w_ij, so: rhs -= L_ij * p_j => rhs -= w_ij * p_j
                    if (t.free_vertex_index.value(vn) == invalid_index) {
                        rhs_val -= vec.simdFromVec3f(t.vertex_position.value(vn)) * @as(SimdVec4f, @splat(w_ij));
                    }
                }

                // set the right-hand side for this free vertex
                const rhs_array: [3]f64 = .{ @floatCast(rhs_val[0]), @floatCast(rhs_val[1]), @floatCast(rhs_val[2]) };
                t.rhs_mat.setRow(@intCast(fi), &rhs_array);
            }
        };

        const WriteSolvedPositionsTask = struct {
            surface_mesh: *const SurfaceMesh,
            free_vertex_index: SurfaceMesh.VertexData(u32),
            solve_mat: eigen.DenseMatrix,
            vertex_position: *SurfaceMesh.VertexData(Vec3f),

            pub fn run(t: *@This(), v: SurfaceMesh.Vertex) void {
                const fi = t.free_vertex_index.value(v);
                if (fi == invalid_index) return; // constrained vertex
                var solved_row: [3]eigen.Scalar = undefined;
                t.solve_mat.getRow(@intCast(fi), &solved_row);
                t.vertex_position.valuePtr(v).* = vec.vec3fFromVec3d(.{ solved_row[0], solved_row[1], solved_row[2] });
            }
        };

        var pctr: SurfaceMesh.ParallelVertexTaskRunner = try .init(arap_ctx.compute_surface_mesh);
        defer pctr.deinit();

        for (0..@intCast(arap_ctx.nb_iterations)) |_| {
            // compute best-fit rotation for each vertex
            try pctr.run(arap_ctx.io, ComputeVertexRotationTask{
                .surface_mesh = arap_ctx.compute_surface_mesh,
                .halfedge_cotan_weight = arap_ctx.compute_halfedge_cotan_weight,
                .vertex_position_rest = arap_ctx.vertex_position_rest,
                .vertex_position = arap_ctx.vertex_position,
                .vertex_rotation = &arap_ctx.vertex_rotation,
            });

            // prepare the right-hand side matrix (nb_free x 3)
            pctr.reset();
            try pctr.run(arap_ctx.io, SetupVertexRHSTask{
                .surface_mesh = arap_ctx.compute_surface_mesh,
                .halfedge_cotan_weight = arap_ctx.compute_halfedge_cotan_weight,
                .vertex_position_rest = arap_ctx.vertex_position_rest,
                .vertex_position = arap_ctx.vertex_position,
                .vertex_rotation = arap_ctx.vertex_rotation,
                .free_vertex_index = arap_ctx.free_vertex_index,
                .rhs_mat = arap_ctx.rhs_mat,
            });

            // Solve L * x = rhs
            arap_ctx.factorized_L.solveMultipleRHS(arap_ctx.rhs_mat, arap_ctx.solve_mat, 3);

            // Write solved positions back
            pctr.reset();
            try pctr.run(arap_ctx.io, WriteSolvedPositionsTask{
                .surface_mesh = arap_ctx.compute_surface_mesh,
                .free_vertex_index = arap_ctx.free_vertex_index,
                .solve_mat = arap_ctx.solve_mat,
                .vertex_position = &arap_ctx.vertex_position,
            });
        }
    }
};
