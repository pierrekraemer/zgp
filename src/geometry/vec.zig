const std = @import("std");
const assert = std.debug.assert;

/// Vec are n-dimensional vectors represented as fixed-size arrays of scalars.
pub fn Vec(comptime N: usize, comptime Scalar: type) type {
    return [N]Scalar;
}

pub const Vec2f = Vec(2, f32);
pub const Vec3f = Vec(3, f32);
pub const Vec4f = Vec(4, f32);

pub const Vec2d = Vec(2, f64);
pub const Vec3d = Vec(3, f64);
pub const Vec4d = Vec(4, f64);

// Return the dimension of the given Vec type
pub fn dim(comptime V: type) comptime_int {
    const vec_info = @typeInfo(V);
    if (vec_info != .array) {
        @compileError("dim only supports array types");
    }
    return vec_info.array.len;
}

// Return the type of the components of the given Vec type
pub fn ScalarTypeOf(comptime V: type) type {
    const vec_info = @typeInfo(V);
    if (vec_info != .array) {
        @compileError("Scalar only supports array types");
    }
    return vec_info.array.child;
}

// // Return the SIMD representation type corresponding to the given Vec type
// pub fn SIMDVecTypeOf(comptime V: type) type {
//     return @Vector(dim(V), ScalarTypeOf(V));
// }

// Return a vec with each component set to the corresponding component of the given vec, casted to the given Scalar type
// example usage:
// const vf: Vec3f = ...
// const vd: Vec3d = vec.cast(f64, v);
pub fn cast(comptime SDest: type, v: anytype) Vec(dim(@TypeOf(v)), SDest) {
    const V = @TypeOf(v);
    const SSrc = ScalarTypeOf(V);
    if (SSrc == SDest) {
        return v;
    }
    var result: Vec(dim(V), SDest) = undefined;
    for (0..dim(V)) |i| {
        result[i] = switch (@typeInfo(SDest)) {
            .float => switch (@typeInfo(SSrc)) {
                .float => @floatCast(v[i]),
                .int => @floatFromInt(v[i]),
                else => @compileError("only supports array of float/int types"),
            },
            .int => switch (@typeInfo(SSrc)) {
                .float => @intFromFloat(v[i]),
                .int => @intCast(v[i]),
                else => @compileError("only supports array of float/int types"),
            },
            else => @compileError("only supports array of float/int types"),
        };
    }
    return result;
}

// Return a vec composed of the first d components of the given vec
// example usage:
// const v: Vec4f = ...
// const v_truncated: Vec3f = vec.truncate(3, v);
pub fn truncate(comptime d: usize, v: anytype) Vec(d, ScalarTypeOf(@TypeOf(v))) {
    const V = @TypeOf(v);
    assert(d <= dim(V));
    var result: Vec(d, ScalarTypeOf(V)) = undefined;
    for (0..d) |i| {
        result[i] = v[i];
    }
    return result;
}

// Return a vec of the given type with all components set to zero
// example usage: const v = vec.zero(Vec3f);
pub fn zero(comptime V: type) V {
    return @splat(0);
}

// Return a vec of the given type with all components set to the given scalar value
// example usage: const v = vec.splat(Vec3f, 1.0);
pub fn splat(comptime V: type, scalar: ScalarTypeOf(V)) V {
    return @splat(scalar);
}

// Return a vec of the given type with each component set to a random value
// example usage: const v = vec.random(Vec3f, r);
pub fn random(comptime V: type, r: std.Random) V {
    const S = ScalarTypeOf(V);
    var result: V = undefined;
    for (0..dim(V)) |i| {
        result[i] = switch (@typeInfo(S)) {
            .float => r.float(S),
            .int => r.int(S),
            else => @compileError("only supports array of float/int types"),
        };
    }
    return result;
}

// Return the result of the addition of two given vecs
pub fn add(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    // const SIMDVec = SIMDVecTypeOf(@TypeOf(a));
    // const av: SIMDVec = a;
    // const bv: SIMDVec = b;
    // return av + bv;
    const V = @TypeOf(a);
    var result: V = undefined;
    for (0..dim(V)) |i| {
        result[i] = a[i] + b[i];
    }
    return result;
}

// Return the result of the subtraction of two given vecs
pub fn sub(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    // const SIMDVec = SIMDVecTypeOf(@TypeOf(a));
    // const av: SIMDVec = a;
    // const bv: SIMDVec = b;
    // return av - bv;
    const V = @TypeOf(a);
    var result: V = undefined;
    for (0..dim(V)) |i| {
        result[i] = a[i] - b[i];
    }
    return result;
}

// Return the result of the multiplication of the given vec by the given scalar
pub fn mulScalar(v: anytype, s: ScalarTypeOf(@TypeOf(v))) @TypeOf(v) {
    // const SIMDVec = SIMDVecTypeOf(@TypeOf(v));
    // const vv: SIMDVec = v;
    // return vv * splat(SIMDVec, s);
    const V = @TypeOf(v);
    var result: V = undefined;
    for (0..dim(V)) |i| {
        result[i] = v[i] * s;
    }
    return result;
}

// Return the result of the division of the given vec by the given scalar
pub fn divScalar(v: anytype, s: ScalarTypeOf(@TypeOf(v))) @TypeOf(v) {
    // const SIMDVec = SIMDVecTypeOf(@TypeOf(v));
    // const vv: SIMDVec = v;
    // return vv / splat(SIMDVec, s);
    const V = @TypeOf(v);
    var result: V = undefined;
    for (0..dim(V)) |i| {
        result[i] = v[i] / s;
    }
    return result;
}

// Return the result of the component-wise multiplication of two given vecs
pub fn componentwiseMul(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    // const SIMDVec = SIMDVecTypeOf(@TypeOf(a));
    // const av: SIMDVec = a;
    // const bv: SIMDVec = b;
    // return av * bv;
    const V = @TypeOf(a);
    var result: V = undefined;
    for (0..dim(V)) |i| {
        result[i] = a[i] * b[i];
    }
    return result;
}

// Return the result of the component-wise division of two given vecs
pub fn componentwiseDiv(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    // const SIMDVec = SIMDVecTypeOf(@TypeOf(a));
    // const av: SIMDVec = a;
    // const bv: SIMDVec = b;
    // return av / bv;
    const V = @TypeOf(a);
    var result: V = undefined;
    for (0..dim(V)) |i| {
        result[i] = a[i] / b[i];
    }
    return result;
}

// Return the sum of the components of the given vec
pub fn sumComponents(v: anytype) ScalarTypeOf(@TypeOf(v)) {
    // const SIMDVec = SIMDVecTypeOf(@TypeOf(v));
    // const vv: SIMDVec = v;
    // return @reduce(.Add, vv);
    const V = @TypeOf(v);
    var result: ScalarTypeOf(V) = 0;
    for (0..dim(V)) |i| {
        result += v[i];
    }
    return result;
}

// Return the sum of the absolute values of the components of the given vec
pub fn sumComponentsAbs(v: anytype) ScalarTypeOf(@TypeOf(v)) {
    // const SIMDVec = SIMDVecTypeOf(@TypeOf(v));
    // const vv: SIMDVec = v;
    // return @reduce(.Add, vv);
    const V = @TypeOf(v);
    var result: ScalarTypeOf(V) = 0;
    for (0..dim(V)) |i| {
        result += @abs(v[i]);
    }
    return result;
}

// Return the value of the maximum component of the given vec
pub fn maxComponent(v: anytype) ScalarTypeOf(@TypeOf(v)) {
    // const SIMDVec = SIMDVecTypeOf(@TypeOf(v));
    // const vv: SIMDVec = v;
    // return @reduce(.Max, vv);
    const V = @TypeOf(v);
    var result: ScalarTypeOf(V) = v[0];
    for (1..dim(V)) |i| {
        if (v[i] > result) {
            result = v[i];
        }
    }
    return result;
}

// Return the value of the minimum component of the given vec
pub fn minComponent(v: anytype) ScalarTypeOf(@TypeOf(v)) {
    // const SIMDVec = SIMDVecTypeOf(@TypeOf(v));
    // const vv: SIMDVec = v;
    // return @reduce(.Min, vv);
    const V = @TypeOf(v);
    var result: ScalarTypeOf(V) = v[0];
    for (1..dim(V)) |i| {
        if (v[i] < result) {
            result = v[i];
        }
    }
    return result;
}

// Return a vec with each component set to the maximum of the corresponding components of the two given vecs
pub fn componentwiseMax(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    // const SIMDVec = SIMDVecTypeOf(@TypeOf(a));
    // const av: SIMDVec = a;
    // const bv: SIMDVec = b;
    // return @max(av, bv);
    const V = @TypeOf(a);
    var result: V = undefined;
    for (0..dim(V)) |i| {
        result[i] = @max(a[i], b[i]);
    }
    return result;
}

// Return a vec with each component set to the minimum of the corresponding components of the two given vecs
pub fn componentwiseMin(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    // const SIMDVec = SIMDVecTypeOf(@TypeOf(a));
    // const av: SIMDVec = a;
    // const bv: SIMDVec = b;
    // return @min(av, bv);
    const V = @TypeOf(a);
    var result: V = undefined;
    for (0..dim(V)) |i| {
        result[i] = @min(a[i], b[i]);
    }
    return result;
}

// Return the result of the dot product of two given vecs
pub fn dot(a: anytype, b: @TypeOf(a)) ScalarTypeOf(@TypeOf(a)) {
    // const SIMDVec = SIMDVecTypeOf(@TypeOf(a));
    // const av: SIMDVec = a;
    // const bv: SIMDVec = b;
    // return @reduce(.Add, av * bv);
    const V = @TypeOf(a);
    var result: ScalarTypeOf(V) = 0;
    for (0..dim(V)) |i| {
        result += a[i] * b[i];
    }
    return result;
}

// Return the squared norm of the given vec
pub fn squaredNorm(v: anytype) ScalarTypeOf(@TypeOf(v)) {
    return dot(v, v);
}

// Return the norm of the given vec
pub fn norm(v: anytype) ScalarTypeOf(@TypeOf(v)) {
    const S = ScalarTypeOf(@TypeOf(v));
    if (@typeInfo(S) != .float) {
        @compileError("norm only supports float types");
    }
    return @sqrt(squaredNorm(v));
}

// Return a normalized version of the given vec
// If the input vec has norm 0, a zero vec of the same type is returned
pub fn normalized(v: anytype) @TypeOf(v) {
    const n = norm(v);
    if (n == 0) return zero(@TypeOf(v));
    return mulScalar(v, 1 / n);
}

// Return the determinant of two given 2D vecs
pub fn det(a: anytype, b: @TypeOf(a)) ScalarTypeOf(@TypeOf(a)) {
    if (@typeInfo(@TypeOf(a)).array.len != 2) {
        @compileError("det only supports 2D vectors");
    }
    return a[0] * b[1] - a[1] * b[0];
}

// Return the cross product of two given 3D vecs
pub fn cross(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    if (@typeInfo(@TypeOf(a)).array.len != 3) {
        @compileError("cross only supports 3D vectors");
    }
    // const Scalar = ScalarTypeOf(@TypeOf(a));
    // const SIMDVec = SIMDVecTypeOf(@TypeOf(a));
    // const av: SIMDVec = a;
    // const bv: SIMDVec = b;
    // const a_yzx = @shuffle(Scalar, av, undefined, @Vector(3, i32){ 1, 2, 0 });
    // const b_yzx = @shuffle(Scalar, bv, undefined, @Vector(3, i32){ 1, 2, 0 });
    // const a_zxy = @shuffle(Scalar, av, undefined, @Vector(3, i32){ 2, 0, 1 });
    // const b_zxy = @shuffle(Scalar, bv, undefined, @Vector(3, i32){ 2, 0, 1 });
    // return (a_yzx * b_zxy) - (a_zxy * b_yzx);
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}
