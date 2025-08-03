const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const vec = @import("vec.zig");
const Vec3 = vec.Vec3;
const Vec4 = vec.Vec4;
const Scalar = vec.Scalar;

/// 4x4 matrix
/// All operations consider the matrix to be in column-major order.
pub const Mat4 = [4]Vec4;

pub const identity4 = .{
    .{ 1, 0, 0, 0 },
    .{ 0, 1, 0, 0 },
    .{ 0, 0, 1, 0 },
    .{ 0, 0, 0, 1 },
};

pub fn mul4(a: Mat4, b: Mat4) Mat4 {
    var result: Mat4 = undefined;
    for (0..3) |i| {
        for (0..3) |j| {
            result[i][j] = a[0][j] * b[i][0] + a[1][j] * b[i][1] + a[2][j] * b[i][2] + a[3][j] * b[i][3];
        }
    }
    return result;
}

pub fn mulVec4(m: Mat4, v: Vec4) Vec4 {
    return .{
        m[0][0] * v[0] + m[1][0] * v[1] + m[2][0] * v[2] + m[3][0] * v[3],
        m[0][1] * v[0] + m[1][1] * v[1] + m[2][1] * v[2] + m[3][1] * v[3],
        m[0][2] * v[0] + m[1][2] * v[1] + m[2][2] * v[2] + m[3][2] * v[3],
        m[0][3] * v[0] + m[1][3] * v[1] + m[2][3] * v[2] + m[3][3] * v[3],
    };
}

pub fn flat4(m: Mat4) [16]Scalar {
    return .{
        m[0][0], m[0][1], m[0][2], m[0][3],
        m[1][0], m[1][1], m[1][2], m[1][3],
        m[2][0], m[2][1], m[2][2], m[2][3],
        m[3][0], m[3][1], m[3][2], m[3][3],
    };
}

// TODO: Keep only the right-handed versions

pub fn lookToLh(eyepos: Vec3, eyedir: Vec3, updir: Vec3) Mat4 {
    const az = vec.normalized3(eyedir);
    const ax = vec.normalized3(vec.cross3(updir, az));
    const ay = vec.normalized3(vec.cross3(az, ax));
    return .{
        .{ ax[0], ay[0], az[0], 0 },
        .{ ax[1], ay[1], az[1], 0 },
        .{ ax[2], ay[2], az[2], 0 },
        .{ -vec.dot3(ax, eyepos), -vec.dot3(ay, eyepos), -vec.dot3(az, eyepos), 1.0 },
    };
}
pub fn lookToRh(eyepos: Vec3, eyedir: Vec3, updir: Vec3) Mat4 {
    return lookToLh(eyepos, vec.mulScalar3(eyedir, -1.0), updir);
}
pub fn lookAtLh(eyepos: Vec3, focuspos: Vec3, updir: Vec3) Mat4 {
    return lookToLh(eyepos, vec.sub3(focuspos, eyepos), updir);
}
pub fn lookAtRh(eyepos: Vec3, focuspos: Vec3, updir: Vec3) Mat4 {
    return lookToLh(eyepos, vec.sub3(eyepos, focuspos), updir);
}

pub fn perspectiveFovRh(fov: Scalar, aspect: Scalar, near: Scalar, far: Scalar) Mat4 {
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

pub fn orthographicRh(w: Scalar, h: Scalar, near: Scalar, far: Scalar) Mat4 {
    assert(!math.approxEqAbs(Scalar, w, 0.0, 0.001));
    assert(!math.approxEqAbs(Scalar, h, 0.0, 0.001));
    assert(!math.approxEqAbs(Scalar, far, near, 0.001));

    const r = near - far;
    return .{
        .{ 2 / w, 0.0, 0.0, 0.0 },
        .{ 0.0, 2 / h, 0.0, 0.0 },
        .{ 0.0, 0.0, 2 / r, 0.0 },
        .{ 0.0, 0.0, (near + far) / r, 1.0 },
    };
}

pub fn rotMatFromNormalizedAxisAndAngle(axis: Vec3, angle: Scalar) Mat4 {
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

pub fn rotMatFromAxisAndAngle(axis: Vec3, angle: Scalar) Mat4 {
    return rotMatFromNormalizedAxisAndAngle(vec.normalized3(axis), angle);
}
