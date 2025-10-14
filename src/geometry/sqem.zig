const vec = @import("vec.zig");
const Vec4f = vec.Vec4f;
const mat = @import("mat.zig");
const Mat4f = mat.Mat4f;

pub const SQEM = struct {
    A: Mat4f,
    b: Vec4f,
    c: f32,

    pub fn add(a: *SQEM, b: *const SQEM) void {
        a.A = mat.add4f(a.A, b.A);
        a.b = vec.add4f(a.b, b.b);
        a.c += b.c;
    }

    pub fn mulScalar(sq: *SQEM, s: f32) void {
        sq.A = mat.mulScalar4f(sq.A, s);
        sq.b = vec.mulScalar4f(sq.b, s);
        sq.c *= s;
    }

    pub fn gradient(sq: *SQEM, p: Vec4f) Vec4f {
        return mat.mulVec4f(sq.A, p) - sq.b;
    }

    pub fn eval(sq: *SQEM, p: Vec4f) f32 {
        return 0.5 * vec.dot4f(p, mat.mulVec4f(sq.A, p)) - vec.dot4f(sq.b, p) + sq.c;
    }
};

pub const zero: SQEM = .{
    .A = mat.zero4f,
    .b = vec.zero4f,
    .c = 0.0,
};
