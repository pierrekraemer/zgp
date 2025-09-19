const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const vec = @import("vec.zig");
const Vec3 = vec.Vec3;
const Vec4 = vec.Vec4;
const Scalar = vec.Scalar;

/// 4x4 matrix
/// All operations consider the matrix to be in column-major order.
pub const Mat3 = [3]Vec3;
pub const Mat4 = [4]Vec4;

pub const identity3: Mat3 = .{
    .{ 1.0, 0.0, 0.0 },
    .{ 0.0, 1.0, 0.0 },
    .{ 0.0, 0.0, 1.0 },
};

pub const identity4: Mat4 = .{
    .{ 1.0, 0.0, 0.0, 0.0 },
    .{ 0.0, 1.0, 0.0, 0.0 },
    .{ 0.0, 0.0, 1.0, 0.0 },
    .{ 0.0, 0.0, 0.0, 1.0 },
};

pub const zero3: Mat3 = .{ vec.zero3, vec.zero3, vec.zero3 };

pub const zero4: Mat4 = .{ vec.zero4, vec.zero4, vec.zero4, vec.zero4 };

pub fn mul3(a: Mat3, b: Mat3) Mat3 {
    var result: Mat3 = undefined;
    for (0..2) |i| {
        for (0..2) |j| {
            result[i][j] = a[0][j] * b[i][0] + a[1][j] * b[i][1] + a[2][j] * b[i][2];
        }
    }
    return result;
}

pub fn mul4(a: Mat4, b: Mat4) Mat4 {
    var result: Mat4 = undefined;
    for (0..3) |i| {
        for (0..3) |j| {
            result[i][j] = a[0][j] * b[i][0] + a[1][j] * b[i][1] + a[2][j] * b[i][2] + a[3][j] * b[i][3];
        }
    }
    return result;
}

pub fn preMulVec3(v: Vec3, m: Mat3) Vec3 {
    return .{
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2],
    };
}

pub fn mulVec3(m: Mat3, v: Vec3) Vec3 {
    return .{
        m[0][0] * v[0] + m[1][0] * v[1] + m[2][0] * v[2],
        m[0][1] * v[0] + m[1][1] * v[1] + m[2][1] * v[2],
        m[0][2] * v[0] + m[1][2] * v[1] + m[2][2] * v[2],
    };
}

pub fn preMulVec4(v: Vec4, m: Mat4) Vec4 {
    return .{
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2] + m[0][3] * v[3],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2] + m[1][3] * v[3],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2] + m[2][3] * v[3],
        m[3][0] * v[0] + m[3][1] * v[1] + m[3][2] * v[2] + m[3][3] * v[3],
    };
}

pub fn mulVec4(m: Mat4, v: Vec4) Vec4 {
    return .{
        m[0][0] * v[0] + m[1][0] * v[1] + m[2][0] * v[2] + m[3][0] * v[3],
        m[0][1] * v[0] + m[1][1] * v[1] + m[2][1] * v[2] + m[3][1] * v[3],
        m[0][2] * v[0] + m[1][2] * v[1] + m[2][2] * v[2] + m[3][2] * v[3],
        m[0][3] * v[0] + m[1][3] * v[1] + m[2][3] * v[2] + m[3][3] * v[3],
    };
}

pub fn outerProduct3(v1: Vec3, v2: Vec3) Mat3 {
    return .{
        .{ v1[0] * v2[0], v1[0] * v2[1], v1[0] * v2[2] },
        .{ v1[1] * v2[0], v1[1] * v2[1], v1[1] * v2[2] },
        .{ v1[2] * v2[0], v1[2] * v2[1], v1[2] * v2[2] },
    };
}

pub fn outerProduct4(v1: Vec4, v2: Vec4) Mat4 {
    return .{
        .{ v1[0] * v2[0], v1[0] * v2[1], v1[0] * v2[2], v1[0] * v2[3] },
        .{ v1[1] * v2[0], v1[1] * v2[1], v1[1] * v2[2], v1[1] * v2[3] },
        .{ v1[2] * v2[0], v1[2] * v2[1], v1[2] * v2[2], v1[2] * v2[3] },
        .{ v1[3] * v2[0], v1[3] * v2[1], v1[3] * v2[2], v1[3] * v2[3] },
    };
}

pub fn add3(a: Mat3, b: Mat3) Mat3 {
    return .{
        .{ a[0][0] + b[0][0], a[0][1] + b[0][1], a[0][2] + b[0][2] },
        .{ a[1][0] + b[1][0], a[1][1] + b[1][1], a[1][2] + b[1][2] },
        .{ a[2][0] + b[2][0], a[2][1] + b[2][1], a[2][2] + b[2][2] },
    };
}

pub fn add4(a: Mat4, b: Mat4) Mat4 {
    return .{
        .{ a[0][0] + b[0][0], a[0][1] + b[0][1], a[0][2] + b[0][2], a[0][3] + b[0][3] },
        .{ a[1][0] + b[1][0], a[1][1] + b[1][1], a[1][2] + b[1][2], a[1][3] + b[1][3] },
        .{ a[2][0] + b[2][0], a[2][1] + b[2][1], a[2][2] + b[2][2], a[2][3] + b[2][3] },
        .{ a[3][0] + b[3][0], a[3][1] + b[3][1], a[3][2] + b[3][2], a[3][3] + b[3][3] },
    };
}

pub fn lookAt(eyepos: Vec3, eyedir: Vec3, updir: Vec3) Mat4 {
    // const eyedir = vec.sub3(eyepos, focuspos);
    const dir = vec.mulScalar3(eyedir, -1.0);
    const az = vec.normalized3(dir);
    const ax = vec.normalized3(vec.cross3(updir, az));
    const ay = vec.normalized3(vec.cross3(az, ax));
    return .{
        .{ ax[0], ay[0], az[0], 0 },
        .{ ax[1], ay[1], az[1], 0 },
        .{ ax[2], ay[2], az[2], 0 },
        .{ -vec.dot3(ax, eyepos), -vec.dot3(ay, eyepos), -vec.dot3(az, eyepos), 1.0 },
    };
}

pub fn perspective(fov: Scalar, aspect: Scalar, near: Scalar, far: Scalar) Mat4 {
    const c = @cos(fov / 2);
    const s = @sin(fov / 2);

    assert(near > 0.0 and far > 0.0);
    assert(!math.approxEqAbs(Scalar, s, 0.0, 0.001));
    assert(!math.approxEqAbs(Scalar, far, near, 0.001));
    assert(!math.approxEqAbs(Scalar, aspect, 0.0, 0.01));

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

pub fn orthographic(w: Scalar, h: Scalar, near: Scalar, far: Scalar) Mat4 {
    assert(!math.approxEqAbs(Scalar, w, 0.0, 0.001));
    assert(!math.approxEqAbs(Scalar, h, 0.0, 0.001));
    assert(!math.approxEqAbs(Scalar, far, near, 0.001));

    return .{
        .{ 2 / w, 0.0, 0.0, 0.0 },
        .{ 0.0, 2 / h, 0.0, 0.0 },
        .{ 0.0, 0.0, 2 / (near - far), 0.0 },
        .{ 0.0, 0.0, (near + far) / (near - far), 1.0 },
    };
}

pub fn rotMat3FromNormalizedAxisAndAngle(axis: Vec3, angle: Scalar) Mat3 {
    const c = @cos(angle);
    const s = @sin(angle);
    const t = 1 - c;

    return .{
        .{ t * axis[0] * axis[0] + c, t * axis[0] * axis[1] + s * axis[2], t * axis[0] * axis[2] - s * axis[1] },
        .{ t * axis[0] * axis[1] - s * axis[2], t * axis[1] * axis[1] + c, t * axis[1] * axis[2] + s * axis[0] },
        .{ t * axis[0] * axis[2] + s * axis[1], t * axis[1] * axis[2] - s * axis[0], t * axis[2] * axis[2] + c },
    };
}

pub fn rotMat3FromAxisAndAngle(axis: Vec3, angle: Scalar) Mat3 {
    return rotMat3FromNormalizedAxisAndAngle(vec.normalized3(axis), angle);
}

pub fn rotMat4FromNormalizedAxisAndAngle(axis: Vec3, angle: Scalar) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    const t = 1 - c;

    return .{
        .{ t * axis[0] * axis[0] + c, t * axis[0] * axis[1] + s * axis[2], t * axis[0] * axis[2] - s * axis[1], 0 },
        .{ t * axis[0] * axis[1] - s * axis[2], t * axis[1] * axis[1] + c, t * axis[1] * axis[2] + s * axis[0], 0 },
        .{ t * axis[0] * axis[2] + s * axis[1], t * axis[1] * axis[2] - s * axis[0], t * axis[2] * axis[2] + c, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn rotMat4FromAxisAndAngle(axis: Vec3, angle: Scalar) Mat4 {
    return rotMat4FromNormalizedAxisAndAngle(vec.normalized3(axis), angle);
}
