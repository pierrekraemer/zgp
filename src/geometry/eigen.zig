const c = @import("c");

const vec = @import("vec.zig");
const Vec3d = vec.Vec3d;
const Vec4d = vec.Vec4d;
const mat = @import("mat.zig");
const Mat3d = mat.Mat3d;
const Mat4d = mat.Mat4d;

pub const Index = i32;
pub const Scalar = f64;

pub fn computeInverse4d(m: Mat4d) ?Mat4d {
    var inv: Mat4d = undefined;
    var invertible = false;
    c.computeInverseWithCheck4d(@ptrCast(@constCast(&m)), @ptrCast(&inv), &invertible);
    return if (invertible) inv else null;
}

pub fn solveSymmetricLinearSystem4d(A: Mat4d, b: Vec4d) Vec4d {
    var x: Vec4d = undefined;
    c.solveSymmetricLinearSystem4d(@ptrCast(@constCast(&A)), @ptrCast(@constCast(&b)), @ptrCast(&x));
    return x;
}

pub fn eigenSolver(m: Mat3d) struct { Vec3d, Mat3d } {
    var evals: Vec3d = undefined;
    var evecs: Mat3d = undefined;
    c.eigenSolver3d(@ptrCast(@constCast(&m)), @ptrCast(&evals), @ptrCast(&evecs));
    return .{ evals, evecs };
}

pub fn svd3d(m: Mat3d) struct { Mat3d, Vec3d, Mat3d } {
    var U: Mat3d = undefined;
    var S: Vec3d = undefined;
    var V: Mat3d = undefined;
    c.svd3d(@ptrCast(@constCast(&m)), @ptrCast(&U), @ptrCast(&S), @ptrCast(&V));
    return .{ U, S, V };
}

pub const DenseMatrix = struct {
    matrix: ?*anyopaque = null,

    pub fn init(rows: Index, cols: Index) DenseMatrix {
        return .{
            .matrix = c.createDenseMatrix(
                rows,
                cols,
            ),
        };
    }

    pub fn deinit(dm: *DenseMatrix) void {
        if (dm.matrix) |m| {
            c.destroyDenseMatrix(m);
            dm.matrix = null;
        }
    }

    pub fn setRow(dm: *DenseMatrix, row: Index, values: []const Scalar) void {
        c.setDenseMatrixRow(dm.matrix.?, row, values.ptr, @intCast(values.len));
    }

    pub fn solveLeastSquares(dm: *DenseMatrix, b: []const Scalar, x: []Scalar) void {
        c.solveDenseLeastSquares(dm.matrix.?, b.ptr, x.ptr, @intCast(b.len), @intCast(x.len));
    }
};

pub const SparseMatrix = struct {
    matrix: ?*anyopaque = null,

    pub const Triplet = extern struct {
        row: Index,
        col: Index,
        value: Scalar,
    };

    pub fn init(rows: Index, cols: Index) SparseMatrix {
        return .{
            .matrix = c.createSparseMatrix(
                rows,
                cols,
            ),
        };
    }
    pub fn initFromTriplets(rows: Index, cols: Index, triplets: []Triplet) SparseMatrix {
        return .{
            .matrix = c.createSparseMatrixFromTriplets(
                rows,
                cols,
                triplets.ptr,
                @intCast(triplets.len),
            ),
        };
    }
    pub fn initDiagonalFromArray(v: []const Scalar) SparseMatrix {
        return .{
            .matrix = c.createDiagonalSparseMatrixFromArray(
                v.ptr,
                @intCast(v.len),
            ),
        };
    }

    pub fn deinit(sm: *SparseMatrix) void {
        if (sm.matrix) |m| {
            c.destroySparseMatrix(m);
            sm.matrix = null;
        }
    }

    pub fn mulScalar(sm: SparseMatrix, s: Scalar, result: SparseMatrix) void {
        c.mulSparseMatrixScalar(sm.matrix.?, s, result.matrix.?);
    }

    pub fn addSparseMatrix(sm: SparseMatrix, other: SparseMatrix, result: SparseMatrix) void {
        c.addSparseMatrices(sm.matrix.?, other.matrix.?, result.matrix.?);
    }

    pub fn solveSymmetricSparseLinearSystem(sm: SparseMatrix, b: []const Scalar, x: []Scalar) void {
        c.solveSymmetricSparseLinearSystem(sm.matrix.?, b.ptr, x.ptr, @intCast(b.len));
    }
};

/// A pre-factorized symmetric sparse linear system solver.
/// The matrix is factorized once at init time, then solve can be called
/// multiple times with different right-hand sides.
pub const FactorizedSparseMatrix = struct {
    solver: ?*anyopaque = null,
    size: Index = 0,

    pub fn init(sm: SparseMatrix, size: Index) FactorizedSparseMatrix {
        return .{
            .solver = c.factorizeSymmetricSparseMatrix(sm.matrix.?),
            .size = size,
        };
    }

    pub fn deinit(fsm: *FactorizedSparseMatrix) void {
        if (fsm.solver) |s| {
            c.destroyFactorizedMatrix(s);
            fsm.solver = null;
        }
    }

    pub fn solve(fsm: FactorizedSparseMatrix, b: []const Scalar, x: []Scalar) void {
        c.solveWithFactorizedMatrix(fsm.solver.?, b.ptr, x.ptr, fsm.size);
    }

    pub fn solve3(fsm: FactorizedSparseMatrix, b: []const Scalar, x: []Scalar) void {
        c.solveWithFactorizedMatrixMultipleRHS(fsm.solver.?, b.ptr, x.ptr, fsm.size, 3);
    }
};
