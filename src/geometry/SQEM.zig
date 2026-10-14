const SQEM = @This();

const vec = @import("vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const mat = @import("mat.zig");
const Mat4f = mat.Mat4f;

const eigen = @import("eigen.zig");

A: Mat4f,
b: Vec4f,
c: f32,

pub const zero: SQEM = .{
    .A = mat.zero(Mat4f),
    .b = vec.zero(Vec4f),
    .c = 0.0,
};

// p: point on the plane
// n: normal of the plane
// w: weight
pub fn initSpherePlaneDistance(p: Vec3f, n: Vec3f, w: f32) SQEM {
    const d = vec.dot(n, p);
    const nn: Vec4f = .{ n[0], n[1], n[2], 1.0 };
    return .{
        .A = mat.mulScalar(mat.outerProduct(nn, nn), 2.0 * w),
        .b = vec.mulScalar(nn, 2.0 * d * w),
        .c = d * d * w,
    };
}

// p: point on the plane
// n: normal of the plane
// w: weight
pub fn initCenterPlaneDistance(p: Vec3f, n: Vec3f, w: f32) SQEM {
    const d = vec.dot(n, p);
    const nn: Vec4f = .{ n[0], n[1], n[2], 0.0 };
    return .{
        .A = mat.mulScalar(mat.outerProduct(nn, nn), 2.0 * w),
        .b = vec.mulScalar(nn, 2.0 * d * w),
        .c = d * d * w,
    };
}

pub fn add(a: *SQEM, b: *const SQEM) void {
    a.A = mat.add(a.A, b.A);
    a.b = vec.add(a.b, b.b);
    a.c += b.c;
}

pub fn mulScalar(sq: *SQEM, s: f32) void {
    sq.A = mat.mulScalar(sq.A, s);
    sq.b = vec.mulScalar(sq.b, s);
    sq.c *= s;
}

// pub fn gradient(sq: *const SQEM, s: Vec4f) Vec4f {
//     return vec.sub(mat.mulVec(sq.A, s), sq.b);
// }

pub fn eval(sq: *const SQEM, s: Vec4f) f32 {
    return 0.5 * vec.dot(s, mat.mulVec(sq.A, s)) - vec.dot(sq.b, s) + sq.c;
}

pub fn optimalSphere(sq: *SQEM) ?Vec4f {
    // warning: Eigen (via ceigen) uses double precision
    const Ad = mat.cast(f64, sq.A);
    const inv = eigen.computeInverse4d(Ad);
    if (inv) |i| {
        const bd = vec.cast(f64, sq.b);
        const s = mat.mulVec(i, bd);
        return vec.cast(f32, s);
    } else {
        return null;
    }
}
