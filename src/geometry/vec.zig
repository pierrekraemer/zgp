const std = @import("std");

pub const Vec2f = [2]f32;
pub const Vec3f = [3]f32;
pub const Vec4f = [4]f32;

pub const Vec2d = [2]f64;
pub const Vec3d = [3]f64;
pub const Vec4d = [4]f64;

// pub fn nbComponents(comptime Vec: type) usize {
//     return @typeInfo(Vec).array.len;
// }

pub const zero2f: Vec2f = @splat(0);
pub const zero3f: Vec3f = @splat(0);
pub const zero4f: Vec4f = @splat(0);

pub const zero2d: Vec2d = @splat(0);
pub const zero3d: Vec3d = @splat(0);
pub const zero4d: Vec4d = @splat(0);

pub fn vec4fFromVec4d(v: Vec4d) Vec4f {
    return .{ @floatCast(v[0]), @floatCast(v[1]), @floatCast(v[2]), @floatCast(v[3]) };
}
pub fn vec3fFromVec3d(v: Vec3d) Vec3f {
    return .{ @floatCast(v[0]), @floatCast(v[1]), @floatCast(v[2]) };
}

pub fn splat2f(scalar: f32) Vec2f {
    return @splat(scalar);
}
pub fn splat3f(scalar: f32) Vec3f {
    return @splat(scalar);
}
pub fn splat4f(scalar: f32) Vec4f {
    return @splat(scalar);
}
pub fn splat2d(scalar: f64) Vec2d {
    return @splat(scalar);
}
pub fn splat3d(scalar: f64) Vec3d {
    return @splat(scalar);
}
pub fn splat4d(scalar: f64) Vec4d {
    return @splat(scalar);
}

pub fn random2f(r: std.Random) Vec2f {
    return .{ r.float(f32), r.float(f32) };
}
pub fn random3f(r: std.Random) Vec3f {
    return .{ r.float(f32), r.float(f32), r.float(f32) };
}
pub fn random4f(r: std.Random) Vec4f {
    return .{ r.float(f32), r.float(f32), r.float(f32), r.float(f32) };
}
pub fn random2d(r: std.Random) Vec2d {
    return .{ r.float(f64), r.float(f64) };
}
pub fn random3d(r: std.Random) Vec3d {
    return .{ r.float(f64), r.float(f64), r.float(f64) };
}
pub fn random4d(r: std.Random) Vec4d {
    return .{ r.float(f64), r.float(f64), r.float(f64), r.float(f64) };
}

pub fn add2f(a: Vec2f, b: Vec2f) Vec2f {
    return .{ a[0] + b[0], a[1] + b[1] };
}
pub fn add3f(a: Vec3f, b: Vec3f) Vec3f {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}
pub fn add4f(a: Vec4f, b: Vec4f) Vec4f {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3] };
}
pub fn add2d(a: Vec2d, b: Vec2d) Vec2d {
    return .{ a[0] + b[0], a[1] + b[1] };
}
pub fn add3d(a: Vec3d, b: Vec3d) Vec3d {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}
pub fn add4d(a: Vec4d, b: Vec4d) Vec4d {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3] };
}

pub fn sub2f(a: Vec2f, b: Vec2f) Vec2f {
    return .{ a[0] - b[0], a[1] - b[1] };
}
pub fn sub3f(a: Vec3f, b: Vec3f) Vec3f {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
pub fn sub4f(a: Vec4f, b: Vec4f) Vec4f {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3] };
}
pub fn sub2d(a: Vec2d, b: Vec2d) Vec2d {
    return .{ a[0] - b[0], a[1] - b[1] };
}
pub fn sub3d(a: Vec3d, b: Vec3d) Vec3d {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
pub fn sub4d(a: Vec4d, b: Vec4d) Vec4d {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3] };
}

pub fn mulScalar2f(v: Vec2f, scalar: f32) Vec2f {
    return .{ v[0] * scalar, v[1] * scalar };
}
pub fn mulScalar3f(v: Vec3f, scalar: f32) Vec3f {
    return .{ v[0] * scalar, v[1] * scalar, v[2] * scalar };
}
pub fn mulScalar4f(v: Vec4f, scalar: f32) Vec4f {
    return .{ v[0] * scalar, v[1] * scalar, v[2] * scalar, v[3] * scalar };
}
pub fn mulScalar2d(v: Vec2d, scalar: f64) Vec2d {
    return .{ v[0] * scalar, v[1] * scalar };
}
pub fn mulScalar3d(v: Vec3d, scalar: f64) Vec3d {
    return .{ v[0] * scalar, v[1] * scalar, v[2] * scalar };
}
pub fn mulScalar4d(v: Vec4d, scalar: f64) Vec4d {
    return .{ v[0] * scalar, v[1] * scalar, v[2] * scalar, v[3] * scalar };
}

pub fn divScalar2f(v: Vec2f, scalar: f32) Vec2f {
    return .{ v[0] / scalar, v[1] / scalar };
}
pub fn divScalar3f(v: Vec3f, scalar: f32) Vec3f {
    return .{ v[0] / scalar, v[1] / scalar, v[2] / scalar };
}
pub fn divScalar4f(v: Vec4f, scalar: f32) Vec4f {
    return .{ v[0] / scalar, v[1] / scalar, v[2] / scalar, v[3] / scalar };
}
pub fn divScalar2d(v: Vec2d, scalar: f64) Vec2d {
    return .{ v[0] / scalar, v[1] / scalar };
}
pub fn divScalar3d(v: Vec3d, scalar: f64) Vec3d {
    return .{ v[0] / scalar, v[1] / scalar, v[2] / scalar };
}
pub fn divScalar4d(v: Vec4d, scalar: f64) Vec4d {
    return .{ v[0] / scalar, v[1] / scalar, v[2] / scalar, v[3] / scalar };
}

pub fn componentwiseMul2f(a: Vec2f, b: Vec2f) Vec2f {
    return .{ a[0] * b[0], a[1] * b[1] };
}
pub fn componentwiseMul3f(a: Vec3f, b: Vec3f) Vec3f {
    return .{ a[0] * b[0], a[1] * b[1], a[2] * b[2] };
}
pub fn componentwiseMul4f(a: Vec4f, b: Vec4f) Vec4f {
    return .{ a[0] * b[0], a[1] * b[1], a[2] * b[2], a[3] * b[3] };
}
pub fn componentwiseMul2d(a: Vec2d, b: Vec2d) Vec2d {
    return .{ a[0] * b[0], a[1] * b[1] };
}
pub fn componentwiseMul3d(a: Vec3d, b: Vec3d) Vec3d {
    return .{ a[0] * b[0], a[1] * b[1], a[2] * b[2] };
}
pub fn componentwiseMul4d(a: Vec4d, b: Vec4d) Vec4d {
    return .{ a[0] * b[0], a[1] * b[1], a[2] * b[2], a[3] * b[3] };
}

pub fn componentwiseDiv2f(a: Vec2f, b: Vec2f) Vec2f {
    return .{ a[0] / b[0], a[1] / b[1] };
}
pub fn componentwiseDiv3f(a: Vec3f, b: Vec3f) Vec3f {
    return .{ a[0] / b[0], a[1] / b[1], a[2] / b[2] };
}
pub fn componentwiseDiv4f(a: Vec4f, b: Vec4f) Vec4f {
    return .{ a[0] / b[0], a[1] / b[1], a[2] / b[2], a[3] / b[3] };
}
pub fn componentwiseDiv2d(a: Vec2d, b: Vec2d) Vec2d {
    return .{ a[0] / b[0], a[1] / b[1] };
}
pub fn componentwiseDiv3d(a: Vec3d, b: Vec3d) Vec3d {
    return .{ a[0] / b[0], a[1] / b[1], a[2] / b[2] };
}
pub fn componentwiseDiv4d(a: Vec4d, b: Vec4d) Vec4d {
    return .{ a[0] / b[0], a[1] / b[1], a[2] / b[2], a[3] / b[3] };
}

pub fn maxComponent2f(v: Vec2f) f32 {
    return @max(v[0], v[1]);
}
pub fn maxComponent3f(v: Vec3f) f32 {
    return @max(v[0], v[1], v[2]);
}
pub fn maxComponent4f(v: Vec4f) f32 {
    return @max(v[0], v[1], v[2], v[3]);
}
pub fn maxComponent2d(v: Vec2d) f64 {
    return @max(v[0], v[1]);
}
pub fn maxComponent3d(v: Vec3d) f64 {
    return @max(v[0], v[1], v[2]);
}
pub fn maxComponent4d(v: Vec4d) f64 {
    return @max(v[0], v[1], v[2], v[3]);
}

pub fn minComponent2f(v: Vec2f) f32 {
    return @min(v[0], v[1]);
}
pub fn minComponent3f(v: Vec3f) f32 {
    return @min(v[0], v[1], v[2]);
}
pub fn minComponent4f(v: Vec4f) f32 {
    return @min(v[0], v[1], v[2], v[3]);
}
pub fn minComponent2d(v: Vec2d) f64 {
    return @min(v[0], v[1]);
}
pub fn minComponent3d(v: Vec3d) f64 {
    return @min(v[0], v[1], v[2]);
}
pub fn minComponent4d(v: Vec4d) f64 {
    return @min(v[0], v[1], v[2], v[3]);
}

pub fn componentwiseMax2f(a: Vec2f, b: Vec2f) Vec2f {
    return .{ @max(a[0], b[0]), @max(a[1], b[1]) };
}
pub fn componentwiseMax3f(a: Vec3f, b: Vec3f) Vec3f {
    return .{ @max(a[0], b[0]), @max(a[1], b[1]), @max(a[2], b[2]) };
}
pub fn componentwiseMax4f(a: Vec4f, b: Vec4f) Vec4f {
    return .{ @max(a[0], b[0]), @max(a[1], b[1]), @max(a[2], b[2]), @max(a[3], b[3]) };
}
pub fn componentwiseMax2d(a: Vec2d, b: Vec2d) Vec2d {
    return .{ @max(a[0], b[0]), @max(a[1], b[1]) };
}
pub fn componentwiseMax3d(a: Vec3d, b: Vec3d) Vec3d {
    return .{ @max(a[0], b[0]), @max(a[1], b[1]), @max(a[2], b[2]) };
}
pub fn componentwiseMax4d(a: Vec4d, b: Vec4d) Vec4d {
    return .{ @max(a[0], b[0]), @max(a[1], b[1]), @max(a[2], b[2]), @max(a[3], b[3]) };
}

pub fn componentwiseMin2f(a: Vec2f, b: Vec2f) Vec2f {
    return .{ @min(a[0], b[0]), @min(a[1], b[1]) };
}
pub fn componentwiseMin3f(a: Vec3f, b: Vec3f) Vec3f {
    return .{ @min(a[0], b[0]), @min(a[1], b[1]), @min(a[2], b[2]) };
}
pub fn componentwiseMin4f(a: Vec4f, b: Vec4f) Vec4f {
    return .{ @min(a[0], b[0]), @min(a[1], b[1]), @min(a[2], b[2]), @min(a[3], b[3]) };
}
pub fn componentwiseMin2d(a: Vec2d, b: Vec2d) Vec2d {
    return .{ @min(a[0], b[0]), @min(a[1], b[1]) };
}
pub fn componentwiseMin3d(a: Vec3d, b: Vec3d) Vec3d {
    return .{ @min(a[0], b[0]), @min(a[1], b[1]), @min(a[2], b[2]) };
}
pub fn componentwiseMin4d(a: Vec4d, b: Vec4d) Vec4d {
    return .{ @min(a[0], b[0]), @min(a[1], b[1]), @min(a[2], b[2]), @min(a[3], b[3]) };
}

pub fn dot2f(a: Vec2f, b: Vec2f) f32 {
    return a[0] * b[0] + a[1] * b[1];
}
pub fn dot3f(a: Vec3f, b: Vec3f) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
pub fn dot4f(a: Vec4f, b: Vec4f) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
}
pub fn dot2d(a: Vec2d, b: Vec2d) f64 {
    return a[0] * b[0] + a[1] * b[1];
}
pub fn dot3d(a: Vec3d, b: Vec3d) f64 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
pub fn dot4d(a: Vec4d, b: Vec4d) f64 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
}

pub fn squaredNorm2f(v: Vec2f) f32 {
    return dot2f(v, v);
}
pub fn squaredNorm3f(v: Vec3f) f32 {
    return dot3f(v, v);
}
pub fn squaredNorm4f(v: Vec4f) f32 {
    return dot4f(v, v);
}
pub fn squaredNorm2d(v: Vec2d) f64 {
    return dot2d(v, v);
}
pub fn squaredNorm3d(v: Vec3d) f64 {
    return dot3d(v, v);
}
pub fn squaredNorm4d(v: Vec4d) f64 {
    return dot4d(v, v);
}

pub fn norm2f(v: Vec2f) f32 {
    return @sqrt(squaredNorm2f(v));
}
pub fn norm3f(v: Vec3f) f32 {
    return @sqrt(squaredNorm3f(v));
}
pub fn norm4f(v: Vec4f) f32 {
    return @sqrt(squaredNorm4f(v));
}
pub fn norm2d(v: Vec2d) f64 {
    return @sqrt(squaredNorm2d(v));
}
pub fn norm3d(v: Vec3d) f64 {
    return @sqrt(squaredNorm3d(v));
}
pub fn norm4d(v: Vec4d) f64 {
    return @sqrt(squaredNorm4d(v));
}

pub fn normalized2f(v: Vec2f) Vec2f {
    const n = norm2f(v);
    if (n == 0) return zero2f;
    return mulScalar2f(v, 1 / n);
}
pub fn normalized3f(v: Vec3f) Vec3f {
    const n = norm3f(v);
    if (n == 0) return zero3f;
    return mulScalar3f(v, 1 / n);
}
pub fn normalized4f(v: Vec4f) Vec4f {
    const n = norm4f(v);
    if (n == 0) return zero4f;
    return mulScalar4f(v, 1 / n);
}
pub fn normalized2d(v: Vec2d) Vec2d {
    const n = norm2d(v);
    if (n == 0) return zero2d;
    return mulScalar2d(v, 1 / n);
}
pub fn normalized3d(v: Vec3d) Vec3d {
    const n = norm3d(v);
    if (n == 0) return zero3d;
    return mulScalar3d(v, 1 / n);
}
pub fn normalized4d(v: Vec4d) Vec4d {
    const n = norm4d(v);
    if (n == 0) return zero4d;
    return mulScalar4d(v, 1 / n);
}

pub fn cross3f(a: Vec3f, b: Vec3f) Vec3f {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}
pub fn cross3d(a: Vec3d, b: Vec3d) Vec3d {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}
