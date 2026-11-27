const std = @import("std");
const assert = std.debug.assert;

const c = @import("c");

const vec = @import("vec.zig");
const Vec3d = vec.Vec3d;
const Vec4d = vec.Vec4d;
const mat = @import("mat.zig");
const Mat3d = mat.Mat3d;
const Mat4d = mat.Mat4d;

pub const Index = c.ceigen_index;
pub const Scalar = c.ceigen_scalar;

pub fn computeInverse4d(m: Mat4d) ?Mat4d {
    var inv: Mat4d = undefined;
    var invertible = false;
    c.ceigen_computeInverseWithCheck4d(@ptrCast(@constCast(&m)), @ptrCast(&inv), &invertible);
    return if (invertible) inv else null;
}

pub fn solveSymmetricLinearSystem4d(A: Mat4d, b: Vec4d) Vec4d {
    var x: Vec4d = undefined;
    c.ceigen_solveSymmetricLinearSystem4d(@ptrCast(@constCast(&A)), @ptrCast(@constCast(&b)), @ptrCast(&x));
    return x;
}

pub fn eigenSolver(m: Mat3d) struct { Vec3d, Mat3d } {
    var evals: Vec3d = undefined;
    var evecs: Mat3d = undefined;
    c.ceigen_eigenSolver3d(@ptrCast(@constCast(&m)), @ptrCast(&evals), @ptrCast(&evecs));
    return .{ evals, evecs };
}

pub fn svd3d(m: Mat3d) struct { Mat3d, Vec3d, Mat3d } {
    var U: Mat3d = undefined;
    var S: Vec3d = undefined;
    var V: Mat3d = undefined;
    c.ceigen_svd3d(@ptrCast(@constCast(&m)), @ptrCast(&U), @ptrCast(&S), @ptrCast(&V));
    return .{ U, S, V };
}

/// Column-major dense matrix of `Scalar` values with Zig-owned storage.
pub const DenseMatrix = struct {
    data: []Scalar = &.{},
    rows: Index = 0,
    cols: Index = 0,

    pub fn init(allocator: std.mem.Allocator, rows: Index, cols: Index) !DenseMatrix {
        assert(rows >= 0 and cols >= 0);
        const len: usize = @as(usize, @intCast(rows)) * @as(usize, @intCast(cols));
        const data = try allocator.alloc(Scalar, len);
        @memset(data, 0.0);
        return .{
            .data = data,
            .rows = rows,
            .cols = cols,
        };
    }

    pub fn deinit(dm: *DenseMatrix, allocator: std.mem.Allocator) void {
        if (dm.data.len > 0) {
            allocator.free(dm.data);
            dm.data = &.{};
        }
        dm.rows = 0;
        dm.cols = 0;
    }

    pub inline fn at(dm: *const DenseMatrix, row: Index, col_idx: Index) Scalar {
        assert(row >= 0 and row < dm.rows and col_idx >= 0 and col_idx < dm.cols);
        return dm.data[@as(usize, @intCast(col_idx)) * @as(usize, @intCast(dm.rows)) + @as(usize, @intCast(row))];
    }

    pub inline fn atPtr(dm: *DenseMatrix, row: Index, col_idx: Index) *Scalar {
        assert(row >= 0 and row < dm.rows and col_idx >= 0 and col_idx < dm.cols);
        return &dm.data[@as(usize, @intCast(col_idx)) * @as(usize, @intCast(dm.rows)) + @as(usize, @intCast(row))];
    }

    pub inline fn col(dm: *DenseMatrix, col_idx: Index) []Scalar {
        assert(col_idx >= 0 and col_idx < dm.cols);
        const r: usize = @intCast(dm.rows);
        const start = @as(usize, @intCast(col_idx)) * r;
        return dm.data[start .. start + r];
    }

    pub inline fn colConst(dm: *const DenseMatrix, col_idx: Index) []const Scalar {
        assert(col_idx >= 0 and col_idx < dm.cols);
        const r: usize = @intCast(dm.rows);
        const start = @as(usize, @intCast(col_idx)) * r;
        return dm.data[start .. start + r];
    }

    pub fn getRow(dm: *const DenseMatrix, row: Index, values: []Scalar) void {
        assert(row >= 0 and row < dm.rows);
        assert(values.len == @as(usize, @intCast(dm.cols)));
        const r: usize = @intCast(row);
        const stride: usize = @intCast(dm.rows);
        for (values, 0..) |*v, c_idx| {
            v.* = dm.data[c_idx * stride + r];
        }
    }

    pub fn setRow(dm: *DenseMatrix, row: Index, values: []const Scalar) void {
        assert(row >= 0 and row < dm.rows);
        assert(values.len == @as(usize, @intCast(dm.cols)));
        const r: usize = @intCast(row);
        const stride: usize = @intCast(dm.rows);
        for (values, 0..) |v, c_idx| {
            dm.data[c_idx * stride + r] = v;
        }
    }

    pub fn solveLeastSquares(dm: *const DenseMatrix, b: []const Scalar, x: []Scalar) void {
        assert(b.len == @as(usize, @intCast(dm.rows)));
        assert(x.len == @as(usize, @intCast(dm.cols)));
        if (dm.rows == 0 or dm.cols == 0) return;
        c.ceigen_solveDenseLeastSquares(dm.data.ptr, b.ptr, x.ptr, dm.rows, dm.cols);
    }
};

pub const SparseMatrix = struct {
    matrix: ?*c.CEigenSparseMatrix = null,

    pub const Triplet = c.CEigenTriplet;

    pub fn init(rows: Index, cols: Index) SparseMatrix {
        return .{
            .matrix = c.ceigen_createSparseMatrix(
                rows,
                cols,
            ),
        };
    }
    pub fn initFromTriplets(rows: Index, cols: Index, triplets: []const Triplet) SparseMatrix {
        return .{
            .matrix = c.ceigen_createSparseMatrixFromTriplets(
                rows,
                cols,
                triplets.ptr,
                @intCast(triplets.len),
            ),
        };
    }
    pub fn initDiagonalFromArray(v: []const Scalar) SparseMatrix {
        return .{
            .matrix = c.ceigen_createDiagonalSparseMatrixFromArray(
                v.ptr,
                @intCast(v.len),
            ),
        };
    }

    pub fn deinit(sm: *SparseMatrix) void {
        if (sm.matrix) |m| {
            c.ceigen_destroySparseMatrix(m);
            sm.matrix = null;
        }
    }

    pub fn mulScalar(sm: SparseMatrix, s: Scalar, result: SparseMatrix) void {
        c.ceigen_mulSparseMatrixScalar(sm.matrix.?, s, result.matrix.?);
    }

    pub fn addSparseMatrix(sm: SparseMatrix, other: SparseMatrix, result: SparseMatrix) void {
        c.ceigen_addSparseMatrices(sm.matrix.?, other.matrix.?, result.matrix.?);
    }

    pub fn directSolveSymmetricSparseLinearSystem(sm: SparseMatrix, b: []const Scalar, x: []Scalar) void {
        c.ceigen_directSolveSymmetricSparseLinearSystem(sm.matrix.?, b.ptr, x.ptr, @intCast(b.len));
    }

    pub fn iterativeSolveSymmetricSparseLinearSystem(sm: SparseMatrix, b: []const Scalar, x: []Scalar, max_iterations: Index, tolerance: Scalar) void {
        c.ceigen_iterativeSolveSymmetricSparseLinearSystem(sm.matrix.?, b.ptr, x.ptr, @intCast(b.len), max_iterations, tolerance);
    }

    pub fn iterativeSolveSymmetricSparseLinearSystemMultipleRHS(sm: SparseMatrix, b: *const DenseMatrix, x: *DenseMatrix, max_iterations: Index, tolerance: Scalar) void {
        assert(b.rows == x.rows and b.cols == x.cols);
        if (b.rows == 0 or b.cols == 0) return;
        c.ceigen_iterativeSolveSymmetricSparseLinearSystemMultipleRHS(sm.matrix.?, b.data.ptr, x.data.ptr, b.rows, b.cols, max_iterations, tolerance);
    }
};

/// A pre-factorized symmetric sparse linear system solver.
/// The matrix is factorized once at init time, then solve can be called
/// multiple times with different right-hand sides.
pub const FactorizedSparseMatrix = struct {
    solver: ?*c.CEigenFactorizedSparseMatrix = null,
    size: Index = 0,

    pub fn init(sm: SparseMatrix, size: Index) FactorizedSparseMatrix {
        return .{
            .solver = c.ceigen_factorizeSymmetricSparseMatrix(sm.matrix.?),
            .size = size,
        };
    }

    pub fn deinit(fsm: *FactorizedSparseMatrix) void {
        if (fsm.solver) |s| {
            c.ceigen_destroyFactorizedMatrix(s);
            fsm.solver = null;
        }
    }

    pub fn solve(fsm: FactorizedSparseMatrix, b: []const Scalar, x: []Scalar) void {
        c.ceigen_solveWithFactorizedMatrix(fsm.solver.?, b.ptr, x.ptr, fsm.size);
    }

    pub fn solveMultipleRHS(fsm: FactorizedSparseMatrix, b: *const DenseMatrix, x: *DenseMatrix) void {
        assert(b.rows == fsm.size and x.rows == fsm.size and b.cols == x.cols);
        if (b.rows == 0 or b.cols == 0) return;
        c.ceigen_solveWithFactorizedMatrixMultipleRHS(fsm.solver.?, b.data.ptr, x.data.ptr, b.rows, b.cols);
    }
};
