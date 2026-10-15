const std = @import("std");

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec3d = vec.Vec3d;
const eigen = @import("../../geometry/eigen.zig");
const SparseMatrix = eigen.SparseMatrix;

const laplacian = @import("laplacian.zig");

pub fn faceDataVertexAverage(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Vertex,
    comptime T: type,
    incident_data: SurfaceMesh.FaceData(T),
) T {
    const t_info = @typeInfo(T);
    var sum: T = switch (t_info) {
        .float, .int => 0,
        .array => blk: {
            const s_info = @typeInfo(vec.ScalarTypeOf(T));
            if (s_info != .float and s_info != .int) {
                @compileError("faceDataVertexAverage only supports float, int, or array of float/int types");
            }
            break :blk vec.zero(T);
        },
        else => @compileError("faceDataVertexAverage only supports float, int, or array of float/int types"),
    };
    var count: usize = 0;
    var it = sm.vertexDartIterator(sm.dart(vertex));
    while (it.next()) |d| {
        count += 1;
        switch (t_info) {
            .float, .int => sum += incident_data.value(sm.face(d)),
            .array => sum = vec.add(sum, incident_data.value(sm.face(d))),
            else => unreachable,
        }
    }
    if (count == 0) {
        return sum; // return zero if no elements
    }
    return switch (t_info) {
        .float => sum / @as(T, @floatFromInt(count)),
        .int => sum / @as(T, @intCast(count)),
        .array => vec.divScalar(sum, @floatFromInt(count)),
        else => unreachable,
    };
}

pub fn computeFaceDataVertexAverages(
    io: std.Io,
    sm: *SurfaceMesh,
    comptime T: type,
    face_data: SurfaceMesh.FaceData(T),
    vertex_data: *SurfaceMesh.VertexData(T),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        face_data: SurfaceMesh.FaceData(T),
        vertex_data: *SurfaceMesh.VertexData(T),

        pub fn run(t: *const @This(), vertex: SurfaceMesh.Vertex) void {
            t.vertex_data.valuePtr(vertex).* = faceDataVertexAverage(
                t.surface_mesh,
                vertex,
                T,
                t.face_data,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelVertexTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .face_data = face_data,
        .vertex_data = vertex_data,
    });
}

fn rangeKernel(s: f64, sigma: f64) f64 {
    return std.math.exp((-1.0 * s * s) / (2.0 * sigma * sigma));
}

// TODO:
// - add support for intrinsic triangulation

pub fn anisotropicLaplacianFiltering(
    allocator: std.mem.Allocator,
    sm: *SurfaceMesh,
    halfedge_cotan_weight: SurfaceMesh.HalfedgeData(f32),
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    vertex_normal: SurfaceMesh.VertexData(Vec3f),
    vertex_area: SurfaceMesh.VertexData(f32),
    edge_length: SurfaceMesh.EdgeData(f32),
    sigma_r: f64,
    sigma_g: f64,
    time_step_factor: f64,
    comptime T: type,
    discrepancy: fn (T, T) f64,
    vertex_data: *SurfaceMesh.VertexData(T),
    // it_ctx: ?intrinsic_triangulation.ITContext, // TODO: support intrinsic triangulation for filtering
) !void {
    const t_info = @typeInfo(T);

    // solve (A - t · Lc(f)) x = A · f, where:
    // - A is the mass matrix (vertex areas)
    // - Lc(f) is the (negative semi-definite) cotangent Laplacian weighted by a range kernel based on the discrepancy between vertex data
    // - t is the time step (time_step_factor * mean_edge_length^2)
    // - f is the input vertex data (scalar or vector)
    // - x is the filtered vertex data

    // Create consecutive indices for vertices
    var vertex_index = try sm.addData(.vertex, u32, "__filtering_vertex_index");
    defer sm.removeData(vertex_index);
    var vertex_it = sm.vertexIterator();
    var nb_vertices: u32 = 0;
    while (vertex_it.next()) |v| : (nb_vertices += 1) {
        vertex_index.valuePtr(v).* = nb_vertices;
    }

    // WARNING: use eigen.Scalar (f64) for matrix coefficients

    // setup Laplacian matrix Lc
    const nb_edges = sm.nbCells(.edge);
    var triplets = try std.ArrayList(SparseMatrix.Triplet).initCapacity(allocator, 4 * nb_edges);
    defer triplets.deinit(allocator);
    var edge_it = sm.edgeIterator();
    while (edge_it.next()) |edge| {
        const d = sm.dart(edge);
        const vi = sm.vertex(d);
        const vj = sm.vertex(sm.phi1(d));
        const i = vertex_index.value(vi);
        const j = vertex_index.value(vj);
        const w_ij: eigen.Scalar = @floatCast(laplacian.edgeCotanWeight(sm, edge, halfedge_cotan_weight));
        // compute range kernel based on discrepancy between vertex data
        const Wr = rangeKernel(discrepancy(vertex_data.value(vi), vertex_data.value(vj)), sigma_r);
        // geometric kernel: slope of the edge w.r.t. the tangent plane of each endpoint (sin of the angle between the edge and the tangent plane),
        // symmetrized by averaging the squared slopes seen from both endpoints
        const e: Vec3d = vec.cast(f64, vec.sub(vertex_position.value(vj), vertex_position.value(vi)));
        const e_sqnorm = vec.squaredNorm(e);
        const Wg = if (e_sqnorm > 0.0) blk: {
            const hi = vec.dot(vec.cast(f64, vertex_normal.value(vi)), e);
            const hj = vec.dot(vec.cast(f64, vertex_normal.value(vj)), e);
            const slope_sq = 0.5 * (hi * hi + hj * hj) / e_sqnorm;
            break :blk rangeKernel(std.math.sqrt(slope_sq), sigma_g);
        } else 1.0;
        const W = Wr * Wg * w_ij;
        // off-diagonal
        triplets.appendAssumeCapacity(.{ .row = @intCast(i), .col = @intCast(j), .value = W });
        triplets.appendAssumeCapacity(.{ .row = @intCast(j), .col = @intCast(i), .value = W });
        // diagonal
        triplets.appendAssumeCapacity(.{ .row = @intCast(i), .col = @intCast(i), .value = -W });
        triplets.appendAssumeCapacity(.{ .row = @intCast(j), .col = @intCast(j), .value = -W });
    }
    var Lc: SparseMatrix = .initFromTriplets(@intCast(nb_vertices), @intCast(nb_vertices), triplets.items);
    defer Lc.deinit();

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

    // compute time step t = time_step_factor * mean_edge_length^2
    const mean_edge_length = edge_length.data.meanValue();
    const t = time_step_factor * mean_edge_length * mean_edge_length;

    // compute F = A - t · Lc(f)
    var F: SparseMatrix = .init(@intCast(nb_vertices), @intCast(nb_vertices));
    defer F.deinit();
    Lc.mulScalar(@floatCast(-t), F);
    A.addSparseMatrix(F, F);

    var rhs = switch (t_info) {
        .float => blk: {
            var a: std.ArrayList(f64) = .empty;
            try a.resize(allocator, nb_vertices);
            break :blk a;
        },
        .array => eigen.DenseMatrix.init(@intCast(nb_vertices), @intCast(vec.dim(T))),
        else => unreachable,
    };
    var solve = switch (t_info) {
        .float => blk: {
            var a: std.ArrayList(f64) = .empty;
            try a.resize(allocator, nb_vertices);
            break :blk a;
        },
        .array => eigen.DenseMatrix.init(@intCast(nb_vertices), @intCast(vec.dim(T))),
        else => unreachable,
    };

    // copy vertex data to rhs
    vertex_it.reset();
    while (vertex_it.next()) |v| {
        const idx = vertex_index.value(v);
        const area: eigen.Scalar = @floatCast(vertex_area.value(v));
        if (t_info == .float) {
            rhs.items[idx] = area * @as(eigen.Scalar, @floatCast(vertex_data.value(v)));
        } else if (t_info == .array) {
            var rhs_val_f64: [3]eigen.Scalar = vec.cast(f64, vertex_data.value(v));
            for (&rhs_val_f64) |*c| c.* *= area;
            rhs.setRow(@intCast(idx), &rhs_val_f64);
        }
    }

    // solve F · solve = rhs
    if (t_info == .float) {
        F.iterativeSolveSymmetricSparseLinearSystem(rhs.items, solve.items, 1000, 1e-6);
    } else if (t_info == .array) {
        F.iterativeSolveSymmetricSparseLinearSystemMultipleRHS(rhs, solve, 1000, 1e-6);
    }

    // copy filtered data back to vertex_data
    vertex_it.reset();
    while (vertex_it.next()) |v| {
        const idx = vertex_index.value(v);
        if (t_info == .float) {
            vertex_data.valuePtr(v).* = @floatCast(solve.items[idx]);
        } else if (t_info == .array) {
            var solve_val_f64: [3]eigen.Scalar = undefined;
            solve.getRow(@intCast(idx), &solve_val_f64);
            vertex_data.valuePtr(v).* = vec.cast(vec.ScalarTypeOf(T), solve_val_f64);
        }
    }
}
