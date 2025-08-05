const std = @import("std");

pub const Scalar = f32;

fn Vec(comptime N: usize) type {
    return [N]Scalar;
}

pub const Vec2 = Vec(2);
pub const Vec3 = Vec(3);
pub const Vec4 = Vec(4);

// pub fn nbComponents(comptime Vec: type) usize {
//     return @typeInfo(Vec).array.len;
// }

pub const zero2: Vec2 = @splat(0);
pub const zero3: Vec3 = @splat(0);
pub const zero4: Vec4 = @splat(0);

pub fn splat2(scalar: Scalar) Vec2 {
    return @splat(scalar);
}
pub fn splat3(scalar: Scalar) Vec3 {
    return @splat(scalar);
}
pub fn splat4(scalar: Scalar) Vec4 {
    return @splat(scalar);
}

pub fn random2(r: std.Random) Vec2 {
    return .{ r.float(Scalar), r.float(Scalar) };
}
pub fn random3(r: std.Random) Vec3 {
    return .{ r.float(Scalar), r.float(Scalar), r.float(Scalar) };
}
pub fn random4(r: std.Random) Vec4 {
    return .{ r.float(Scalar), r.float(Scalar), r.float(Scalar), r.float(Scalar) };
}

pub fn add2(a: Vec2, b: Vec2) Vec2 {
    return .{ a[0] + b[0], a[1] + b[1] };
}
pub fn add3(a: Vec3, b: Vec3) Vec3 {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}
pub fn add4(a: Vec4, b: Vec4) Vec4 {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3] };
}

pub fn sub2(a: Vec2, b: Vec2) Vec2 {
    return .{ a[0] - b[0], a[1] - b[1] };
}
pub fn sub3(a: Vec3, b: Vec3) Vec3 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
pub fn sub4(a: Vec4, b: Vec4) Vec4 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3] };
}

pub fn mulScalar2(v: Vec2, scalar: Scalar) Vec2 {
    return .{ v[0] * scalar, v[1] * scalar };
}
pub fn mulScalar3(v: Vec3, scalar: Scalar) Vec3 {
    return .{ v[0] * scalar, v[1] * scalar, v[2] * scalar };
}
pub fn mulScalar4(v: Vec4, scalar: Scalar) Vec4 {
    return .{ v[0] * scalar, v[1] * scalar, v[2] * scalar, v[3] * scalar };
}

pub fn divScalar2(v: Vec2, scalar: Scalar) Vec2 {
    return .{ v[0] / scalar, v[1] / scalar };
}
pub fn divScalar3(v: Vec3, scalar: Scalar) Vec3 {
    return .{ v[0] / scalar, v[1] / scalar, v[2] / scalar };
}
pub fn divScalar4(v: Vec4, scalar: Scalar) Vec4 {
    return .{ v[0] / scalar, v[1] / scalar, v[2] / scalar, v[3] / scalar };
}

pub fn componentwiseMul2(a: Vec2, b: Vec2) Vec2 {
    return .{ a[0] * b[0], a[1] * b[1] };
}
pub fn componentwiseMul3(a: Vec3, b: Vec3) Vec3 {
    return .{ a[0] * b[0], a[1] * b[1], a[2] * b[2] };
}
pub fn componentwiseMul4(a: Vec4, b: Vec4) Vec4 {
    return .{ a[0] * b[0], a[1] * b[1], a[2] * b[2], a[3] * b[3] };
}

pub fn componentwiseDiv2(a: Vec2, b: Vec2) Vec2 {
    return .{ a[0] / b[0], a[1] / b[1] };
}
pub fn componentwiseDiv3(a: Vec3, b: Vec3) Vec3 {
    return .{ a[0] / b[0], a[1] / b[1], a[2] / b[2] };
}
pub fn componentwiseDiv4(a: Vec4, b: Vec4) Vec4 {
    return .{ a[0] / b[0], a[1] / b[1], a[2] / b[2], a[3] / b[3] };
}

pub fn maxComponent2(v: Vec2) Scalar {
    return @max(v[0], v[1]);
}
pub fn maxComponent3(v: Vec3) Scalar {
    return @max(v[0], v[1], v[2]);
}
pub fn maxComponent4(v: Vec4) Scalar {
    return @max(v[0], v[1], v[2], v[3]);
}

pub fn minComponent2(v: Vec2) Scalar {
    return @min(v[0], v[1]);
}
pub fn minComponent3(v: Vec3) Scalar {
    return @min(v[0], v[1], v[2]);
}
pub fn minComponent4(v: Vec4) Scalar {
    return @min(v[0], v[1], v[2], v[3]);
}

pub fn componentwiseMax2(a: Vec2, b: Vec2) Vec2 {
    return .{ @max(a[0], b[0]), @max(a[1], b[1]) };
}
pub fn componentwiseMax3(a: Vec3, b: Vec3) Vec3 {
    return .{ @max(a[0], b[0]), @max(a[1], b[1]), @max(a[2], b[2]) };
}
pub fn componentwiseMax4(a: Vec4, b: Vec4) Vec4 {
    return .{ @max(a[0], b[0]), @max(a[1], b[1]), @max(a[2], b[2]), @max(a[3], b[3]) };
}

pub fn componentwiseMin2(a: Vec2, b: Vec2) Vec2 {
    return .{ @min(a[0], b[0]), @min(a[1], b[1]) };
}
pub fn componentwiseMin3(a: Vec3, b: Vec3) Vec3 {
    return .{ @min(a[0], b[0]), @min(a[1], b[1]), @min(a[2], b[2]) };
}
pub fn componentwiseMin4(a: Vec4, b: Vec4) Vec4 {
    return .{ @min(a[0], b[0]), @min(a[1], b[1]), @min(a[2], b[2]), @min(a[3], b[3]) };
}

pub fn dot2(a: Vec2, b: Vec2) Scalar {
    return a[0] * b[0] + a[1] * b[1];
}
pub fn dot3(a: Vec3, b: Vec3) Scalar {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
pub fn dot4(a: Vec4, b: Vec4) Scalar {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
}

pub fn squaredNorm2(v: Vec2) Scalar {
    return dot2(v, v);
}
pub fn squaredNorm3(v: Vec3) Scalar {
    return dot3(v, v);
}
pub fn squaredNorm4(v: Vec4) Scalar {
    return dot4(v, v);
}

pub fn norm2(v: Vec2) Scalar {
    return @sqrt(squaredNorm2(v));
}
pub fn norm3(v: Vec3) Scalar {
    return @sqrt(squaredNorm3(v));
}
pub fn norm4(v: Vec4) Scalar {
    return @sqrt(squaredNorm4(v));
}

pub fn normalized2(v: Vec2) Vec2 {
    const n = norm2(v);
    if (n == 0) return zero2;
    return mulScalar2(v, 1 / n);
}
pub fn normalized3(v: Vec3) Vec3 {
    const n = norm3(v);
    if (n == 0) return zero3;
    return mulScalar3(v, 1 / n);
}
pub fn normalized4(v: Vec4) Vec4 {
    const n = norm4(v);
    if (n == 0) return zero4;
    return mulScalar4(v, 1 / n);
}

pub fn cross3(a: Vec3, b: Vec3) Vec3 {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}
