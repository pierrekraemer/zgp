const zgp = @import("../main.zig");
const c = zgp.c;

pub const Index = i32;
pub const Scalar = f64;

pub const Triplet = packed struct {
    row: Index,
    col: Index,
    value: Scalar,
};

pub const SparseMatrix = struct {
    matrix: ?*anyopaque,

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

    pub fn deinit(self: *SparseMatrix) void {
        if (self.matrix) |m| {
            c.destroySparseMatrix(m);
            self.matrix = null;
        }
    }
};

pub fn mulScalar(M: SparseMatrix, s: Scalar, result: SparseMatrix) void {
    c.mulSparseMatrixScalar(M.matrix.?, s, result.matrix.?);
}

pub fn addSparseMatrices(A: SparseMatrix, B: SparseMatrix, result: SparseMatrix) void {
    c.addSparseMatrices(A.matrix.?, B.matrix.?, result.matrix.?);
}

pub fn solveSymmetricSparseLinearSystem(M: SparseMatrix, b: []const Scalar, x: []Scalar) void {
    c.solveSymmetricSparseLinearSystem(M.matrix.?, b.ptr, x.ptr, @intCast(b.len));
}
