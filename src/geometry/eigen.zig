const zgp = @import("../main.zig");
const c = zgp.c;

const vec = @import("vec.zig");
const Vec4d = vec.Vec4d;
const mat = @import("mat.zig");
const Mat4d = mat.Mat4d;

pub const Index = i32;
pub const Scalar = f64;

pub const Triplet = extern struct {
    row: Index,
    col: Index,
    value: Scalar,
};

pub fn computeInverse4d(m: Mat4d) ?Mat4d {
    var inv: Mat4d = undefined;
    var invertible = false;
    c.computeInverseWithCheck(@ptrCast(&m), @ptrCast(&inv), &invertible);
    return if (invertible) inv else null;
}

pub fn solveSymmetricLinearSystem4d(A: Mat4d, b: Vec4d) Vec4d {
    var x: Vec4d = undefined;
    c.solveSymmetricLinearSystem(@ptrCast(&A), @ptrCast(&b), @ptrCast(&x));
    return x;
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
