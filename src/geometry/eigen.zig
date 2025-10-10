const zgp = @import("../main.zig");
const c = zgp.c;

const mat = @import("mat.zig");
const Mat4d = mat.Mat4d;

pub const Index = i32;
pub const Scalar = f64;

pub const Triplet = packed struct {
    row: Index,
    col: Index,
    value: Scalar,
};

pub fn computeInverse(m: Mat4d) ?Mat4d {
    var inv: Mat4d = undefined;
    var invertible = false;
    c.computeInverseWithCheck(@ptrCast(&m), @ptrCast(&inv), &invertible);
    return if (invertible) inv else null;
}

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
