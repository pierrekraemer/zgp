const vec = @import("vec.zig");
const Vec4f = vec.Vec4f;
const mat = @import("mat.zig");
const Mat4f = mat.Mat4f;

pub const SQEM = struct {
    A: Mat4f,
    b: Vec4f,
    c: f32,
};

pub const zero: SQEM = .{
    .A = mat.zero4f,
    .b = vec.zero4f,
    .c = 0.0,
};

pub fn add(a: SQEM, b: SQEM) SQEM {
    return .{
        .A = mat.add4f(a.A, b.A),
        .b = vec.add4f(a.b, b.b),
        .c = a.c + b.c,
    };
}

pub fn mulScalar(q: SQEM, s: f32) SQEM {
    return .{
        .A = mat.mulScalar4f(q.A, s),
        .b = vec.mulScalar4f(q.b, s),
        .c = q.c * s,
    };
}

pub fn gradient(q: SQEM, p: Vec4f) Vec4f {
    return mat.mulVec4f(q.A, p) - q.b;
}
