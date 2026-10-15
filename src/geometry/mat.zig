const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const vec = @import("vec.zig");

/// Mat are n-dimensional square matrices, represented as fixed-size arrays of Vec.
/// All operations consider matrices to be in column-major order.
pub fn Mat(comptime N: usize, comptime Scalar: type) type {
    return [N]vec.Vec(N, Scalar);
}

pub const Mat2f = Mat(2, f32);
pub const Mat3f = Mat(3, f32);
pub const Mat4f = Mat(4, f32);

pub const Mat2d = Mat(2, f64);
pub const Mat3d = Mat(3, f64);
pub const Mat4d = Mat(4, f64);

// Return the dimension of the given Mat type
// (and check that it is a square matrix)
pub fn dim(comptime M: type) comptime_int {
    const mat_info = @typeInfo(M);
    if (mat_info != .array) {
        @compileError("dim only supports array types");
    }
    if (vec.dim(VectorTypeOf(M)) != mat_info.array.len) {
        @compileError("dim only supports square matrices");
    }
    return mat_info.array.len;
}

// Return the type of the vectors that compose the given Mat type
pub fn VectorTypeOf(comptime M: type) type {
    const mat_info = @typeInfo(M);
    if (mat_info != .array) {
        @compileError("VectorTypeOf only supports array types");
    }
    const vec_info = @typeInfo(mat_info.array.child);
    if (vec_info != .array) {
        @compileError("VectorTypeOf only supports array of array types");
    }
    return mat_info.array.child;
}

// Return the type of the components of the given Mat type
pub fn ScalarTypeOf(comptime M: type) type {
    return vec.ScalarTypeOf(VectorTypeOf(M));
}

// Return a matrix with each coeff set to the corresponding coeff of the given matrix, casted to the given Scalar type
pub fn cast(comptime S: type, m: anytype) Mat(dim(@TypeOf(m)), S) {
    const M = @TypeOf(m);
    if (ScalarTypeOf(M) == S) {
        return m;
    }
    var result: Mat(dim(M), S) = undefined;
    for (0..dim(M)) |i| {
        result[i] = vec.cast(S, m[i]);
    }
    return result;
}

// Return an identity matrix of the given type
pub fn identity(comptime M: type) M {
    const V = VectorTypeOf(M);
    var result: M = undefined;
    for (0..dim(M)) |i| {
        result[i] = vec.zero(V);
        result[i][i] = 1.0;
    }
    return result;
}

// Return a zero matrix of the given type
pub fn zero(comptime M: type) M {
    const V = VectorTypeOf(M);
    var result: M = undefined;
    for (0..dim(M)) |i| {
        result[i] = vec.zero(V);
    }
    return result;
}

// Return the result of the multiplication of two given matrices
pub fn mul(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    const M = @TypeOf(a);
    const d = dim(M);
    var result: M = undefined;
    for (0..d) |i| {
        result[i] = vec.zero(VectorTypeOf(M));
        for (0..d) |j| {
            result[i] = vec.add(result[i], vec.mulScalar(a[j], b[i][j]));
        }
    }
    return result;
}

// Return the result of the multiplication of the given matrix and vector (M * v)
pub fn mulVec(a: anytype, v: VectorTypeOf(@TypeOf(a))) VectorTypeOf(@TypeOf(a)) {
    const M = @TypeOf(a);
    const d = dim(M);
    var result = vec.zero(VectorTypeOf(M));
    for (0..d) |i| {
        for (0..d) |j| {
            result[i] += a[j][i] * v[j];
        }
    }
    return result;
}

// Return the result of the multiplication of the given transposed vector and matrix (v^T * M)
pub fn preMulVec(a: anytype, v: VectorTypeOf(@TypeOf(a))) VectorTypeOf(@TypeOf(a)) {
    const M = @TypeOf(a);
    const d = dim(M);
    var result = vec.zero(VectorTypeOf(M));
    for (0..d) |i| {
        for (0..d) |j| {
            result[i] += a[i][j] * v[j];
        }
    }
    return result;
}

// Return the result of the multiplication of the given matrix by the given scalar
pub fn mulScalar(m: anytype, s: ScalarTypeOf(@TypeOf(m))) @TypeOf(m) {
    const M = @TypeOf(m);
    var result: M = undefined;
    for (0..dim(M)) |i| {
        result[i] = vec.mulScalar(m[i], s);
    }
    return result;
}

// Return the result of the outer product of the given two vectors (v1 * v2^T)
pub fn outerProduct(v1: anytype, v2: @TypeOf(v1)) Mat(vec.dim(@TypeOf(v1)), vec.ScalarTypeOf(@TypeOf(v1))) {
    const V = @TypeOf(v1);
    var result: Mat(vec.dim(V), vec.ScalarTypeOf(V)) = undefined;
    for (0..vec.dim(V)) |i| {
        result[i] = vec.mulScalar(v1, v2[i]);
    }
    return result;
}

// Return the result of the addition of two given matrices
pub fn add(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    const M = @TypeOf(a);
    var result: M = undefined;
    for (0..dim(M)) |i| {
        result[i] = vec.add(a[i], b[i]);
    }
    return result;
}

// Return the result of the subtraction of two given matrices
pub fn sub(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    const M = @TypeOf(a);
    var result: M = undefined;
    for (0..dim(M)) |i| {
        result[i] = vec.sub(a[i], b[i]);
    }
    return result;
}

// Return the result of the transposition of the given matrix
pub fn transpose(m: anytype) @TypeOf(m) {
    const M = @TypeOf(m);
    var result: M = undefined;
    for (0..dim(M)) |i| {
        for (0..dim(M)) |j| {
            result[i][j] = m[j][i];
        }
    }
    return result;
}

pub fn lookAt(
    eyepos: anytype,
    eyedir: @TypeOf(eyepos),
    updir: @TypeOf(eyepos),
) Mat(4, vec.ScalarTypeOf(@TypeOf(eyepos))) {
    const V = @TypeOf(eyepos);
    if (vec.dim(V) != 3) {
        @compileError("lookAt only supports 3D vectors");
    }
    const S = vec.ScalarTypeOf(V);
    if (@typeInfo(S) != .float) {
        @compileError("lookAt only supports float types");
    }

    // const eyedir = vec.sub(eyepos, focuspos);
    const dir = vec.mulScalar(eyedir, -1.0);
    const az = vec.normalized(dir);
    const ax = vec.normalized(vec.cross(updir, az));
    const ay = vec.normalized(vec.cross(az, ax));
    return .{
        .{ ax[0], ay[0], az[0], 0 },
        .{ ax[1], ay[1], az[1], 0 },
        .{ ax[2], ay[2], az[2], 0 },
        .{ -vec.dot(ax, eyepos), -vec.dot(ay, eyepos), -vec.dot(az, eyepos), 1.0 },
    };
}

pub fn perspective(
    fov: anytype,
    aspect: @TypeOf(fov),
    near: @TypeOf(fov),
    far: @TypeOf(fov),
) Mat(4, @TypeOf(fov)) {
    const S = @TypeOf(fov);
    if (@typeInfo(S) != .float) {
        @compileError("perspective only supports float types");
    }

    const c = @cos(fov / 2);
    const s = @sin(fov / 2);

    assert(near > 0.0 and far > 0.0);
    assert(!math.approxEqAbs(S, s, 0.0, 0.001));
    assert(!math.approxEqAbs(S, far, near, 0.001));
    assert(!math.approxEqAbs(S, aspect, 0.0, 0.01));

    const h = c / s;
    const w = h / aspect;
    const r = near - far;

    return .{
        .{ w, 0.0, 0.0, 0.0 },
        .{ 0.0, h, 0.0, 0.0 },
        .{ 0.0, 0.0, (near + far) / r, -1.0 },
        .{ 0.0, 0.0, 2.0 * near * far / r, 0.0 },
    };
}

pub fn orthographic(
    w: anytype,
    h: @TypeOf(w),
    near: @TypeOf(w),
    far: @TypeOf(w),
) Mat(4, @TypeOf(w)) {
    const S = @TypeOf(w);
    if (@typeInfo(S) != .float) {
        @compileError("orthographic only supports float types");
    }

    assert(!math.approxEqAbs(S, w, 0.0, 0.001));
    assert(!math.approxEqAbs(S, h, 0.0, 0.001));
    assert(!math.approxEqAbs(S, far, near, 0.001));
    assert(near > 0.0 and far > 0.0 and far > near);

    return .{
        .{ 2 / w, 0.0, 0.0, 0.0 },
        .{ 0.0, 2 / h, 0.0, 0.0 },
        .{ 0.0, 0.0, 2 / (near - far), 0.0 },
        .{ 0.0, 0.0, (near + far) / (near - far), 1.0 },
    };
}

pub fn rotMat3FromNormalizedAxisAndAngle(
    axis: anytype,
    angle: vec.ScalarTypeOf(@TypeOf(axis)),
) Mat(3, vec.ScalarTypeOf(@TypeOf(axis))) {
    const V = @TypeOf(axis);
    if (vec.dim(V) != 3) {
        @compileError("rotMat3FromNormalizedAxisAndAngle only supports 3D vectors");
    }
    const S = vec.ScalarTypeOf(V);
    if (@typeInfo(S) != .float) {
        @compileError("rotMat3FromNormalizedAxisAndAngle only supports float types");
    }

    const c = @cos(angle);
    const s = @sin(angle);
    const t = 1 - c;

    return .{
        .{ t * axis[0] * axis[0] + c, t * axis[0] * axis[1] + s * axis[2], t * axis[0] * axis[2] - s * axis[1] },
        .{ t * axis[0] * axis[1] - s * axis[2], t * axis[1] * axis[1] + c, t * axis[1] * axis[2] + s * axis[0] },
        .{ t * axis[0] * axis[2] + s * axis[1], t * axis[1] * axis[2] - s * axis[0], t * axis[2] * axis[2] + c },
    };
}

pub fn rotMat3FromAxisAndAngle(
    axis: anytype,
    angle: vec.ScalarTypeOf(@TypeOf(axis)),
) Mat(3, vec.ScalarTypeOf(@TypeOf(axis))) {
    return rotMat3FromNormalizedAxisAndAngle(
        vec.normalized(axis),
        angle,
    );
}
