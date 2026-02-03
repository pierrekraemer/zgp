const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const vec = @import("vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec3d = vec.Vec3d;
const Vec4d = vec.Vec4d;

/// 4x4 matrix
/// All operations consider the matrix to be in column-major order.
pub const Mat3f = [3]Vec3f;
pub const Mat4f = [4]Vec4f;
pub const Mat3d = [3]Vec3d;
pub const Mat4d = [4]Vec4d;

pub const identity3f: Mat3f = .{
    .{ 1.0, 0.0, 0.0 },
    .{ 0.0, 1.0, 0.0 },
    .{ 0.0, 0.0, 1.0 },
};
pub const identity3d: Mat3d = .{
    .{ 1.0, 0.0, 0.0 },
    .{ 0.0, 1.0, 0.0 },
    .{ 0.0, 0.0, 1.0 },
};

pub const identity4f: Mat4f = .{
    .{ 1.0, 0.0, 0.0, 0.0 },
    .{ 0.0, 1.0, 0.0, 0.0 },
    .{ 0.0, 0.0, 1.0, 0.0 },
    .{ 0.0, 0.0, 0.0, 1.0 },
};
pub const identity4d: Mat4d = .{
    .{ 1.0, 0.0, 0.0, 0.0 },
    .{ 0.0, 1.0, 0.0, 0.0 },
    .{ 0.0, 0.0, 1.0, 0.0 },
    .{ 0.0, 0.0, 0.0, 1.0 },
};

pub const zero3f: Mat3f = .{ vec.zero3f, vec.zero3f, vec.zero3f };
pub const zero4f: Mat4f = .{ vec.zero4f, vec.zero4f, vec.zero4f, vec.zero4f };
pub const zero3d: Mat3d = .{ vec.zero3d, vec.zero3d, vec.zero3d };
pub const zero4d: Mat4d = .{ vec.zero4d, vec.zero4d, vec.zero4d, vec.zero4d };

pub fn mat3fFromMat3d(m: Mat3d) Mat3f {
    return .{
        vec.vec3fFromVec3d(m[0]),
        vec.vec3fFromVec3d(m[1]),
        vec.vec3fFromVec3d(m[2]),
    };
}
pub fn mat3dFromMat3f(m: Mat3f) Mat3d {
    return .{
        vec.vec3dFromVec3f(m[0]),
        vec.vec3dFromVec3f(m[1]),
        vec.vec3dFromVec3f(m[2]),
    };
}
pub fn mat4fFromMat4d(m: Mat4d) Mat4f {
    return .{
        vec.vec4fFromVec4d(m[0]),
        vec.vec4fFromVec4d(m[1]),
        vec.vec4fFromVec4d(m[2]),
        vec.vec4fFromVec4d(m[3]),
    };
}
pub fn mat4dFromMat4f(m: Mat4f) Mat4d {
    return .{
        vec.vec4dFromVec4f(m[0]),
        vec.vec4dFromVec4f(m[1]),
        vec.vec4dFromVec4f(m[2]),
        vec.vec4dFromVec4f(m[3]),
    };
}

pub fn mul3f(a: Mat3f, b: Mat3f) Mat3f {
    var result: Mat3f = undefined;
    for (0..2) |i| {
        for (0..2) |j| {
            result[i][j] = a[0][j] * b[i][0] + a[1][j] * b[i][1] + a[2][j] * b[i][2];
        }
    }
    return result;
}
pub fn mul3d(a: Mat3d, b: Mat3d) Mat3d {
    var result: Mat3d = undefined;
    for (0..2) |i| {
        for (0..2) |j| {
            result[i][j] = a[0][j] * b[i][0] + a[1][j] * b[i][1] + a[2][j] * b[i][2];
        }
    }
    return result;
}

pub fn mul4f(a: Mat4f, b: Mat4f) Mat4f {
    var result: Mat4f = undefined;
    for (0..3) |i| {
        for (0..3) |j| {
            result[i][j] = a[0][j] * b[i][0] + a[1][j] * b[i][1] + a[2][j] * b[i][2] + a[3][j] * b[i][3];
        }
    }
    return result;
}
pub fn mul4d(a: Mat4d, b: Mat4d) Mat4d {
    var result: Mat4d = undefined;
    for (0..3) |i| {
        for (0..3) |j| {
            result[i][j] = a[0][j] * b[i][0] + a[1][j] * b[i][1] + a[2][j] * b[i][2] + a[3][j] * b[i][3];
        }
    }
    return result;
}

pub fn mulVec3f(m: Mat3f, v: Vec3f) Vec3f {
    return .{
        m[0][0] * v[0] + m[1][0] * v[1] + m[2][0] * v[2],
        m[0][1] * v[0] + m[1][1] * v[1] + m[2][1] * v[2],
        m[0][2] * v[0] + m[1][2] * v[1] + m[2][2] * v[2],
    };
}
pub fn mulVec3d(m: Mat3d, v: Vec3d) Vec3d {
    return .{
        m[0][0] * v[0] + m[1][0] * v[1] + m[2][0] * v[2],
        m[0][1] * v[0] + m[1][1] * v[1] + m[2][1] * v[2],
        m[0][2] * v[0] + m[1][2] * v[1] + m[2][2] * v[2],
    };
}

pub fn mulVec4f(m: Mat4f, v: Vec4f) Vec4f {
    return .{
        m[0][0] * v[0] + m[1][0] * v[1] + m[2][0] * v[2] + m[3][0] * v[3],
        m[0][1] * v[0] + m[1][1] * v[1] + m[2][1] * v[2] + m[3][1] * v[3],
        m[0][2] * v[0] + m[1][2] * v[1] + m[2][2] * v[2] + m[3][2] * v[3],
        m[0][3] * v[0] + m[1][3] * v[1] + m[2][3] * v[2] + m[3][3] * v[3],
    };
}
pub fn mulVec4d(m: Mat4d, v: Vec4d) Vec4d {
    return .{
        m[0][0] * v[0] + m[1][0] * v[1] + m[2][0] * v[2] + m[3][0] * v[3],
        m[0][1] * v[0] + m[1][1] * v[1] + m[2][1] * v[2] + m[3][1] * v[3],
        m[0][2] * v[0] + m[1][2] * v[1] + m[2][2] * v[2] + m[3][2] * v[3],
        m[0][3] * v[0] + m[1][3] * v[1] + m[2][3] * v[2] + m[3][3] * v[3],
    };
}

pub fn preMulVec3f(v: Vec3f, m: Mat3f) Vec3f {
    return .{
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2],
    };
}
pub fn preMulVec3d(v: Vec3d, m: Mat3d) Vec3d {
    return .{
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2],
    };
}

pub fn preMulVec4f(v: Vec4f, m: Mat4f) Vec4f {
    return .{
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2] + m[0][3] * v[3],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2] + m[1][3] * v[3],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2] + m[2][3] * v[3],
        m[3][0] * v[0] + m[3][1] * v[1] + m[3][2] * v[2] + m[3][3] * v[3],
    };
}
pub fn preMulVec4d(v: Vec4d, m: Mat4d) Vec4d {
    return .{
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2] + m[0][3] * v[3],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2] + m[1][3] * v[3],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2] + m[2][3] * v[3],
        m[3][0] * v[0] + m[3][1] * v[1] + m[3][2] * v[2] + m[3][3] * v[3],
    };
}

pub fn mulScalar3f(m: Mat3f, s: f32) Mat3f {
    return .{
        vec.mulScalar3f(m[0], s),
        vec.mulScalar3f(m[1], s),
        vec.mulScalar3f(m[2], s),
    };
}
pub fn mulScalar3d(m: Mat3d, s: f64) Mat3d {
    return .{
        vec.mulScalar3d(m[0], s),
        vec.mulScalar3d(m[1], s),
        vec.mulScalar3d(m[2], s),
    };
}

pub fn mulScalar4f(m: Mat4f, s: f32) Mat4f {
    return .{
        vec.mulScalar4f(m[0], s),
        vec.mulScalar4f(m[1], s),
        vec.mulScalar4f(m[2], s),
        vec.mulScalar4f(m[3], s),
    };
}
pub fn mulScalar4d(m: Mat4d, s: f64) Mat4d {
    return .{
        vec.mulScalar4d(m[0], s),
        vec.mulScalar4d(m[1], s),
        vec.mulScalar4d(m[2], s),
        vec.mulScalar4d(m[3], s),
    };
}

pub fn outerProduct3f(v1: Vec3f, v2: Vec3f) Mat3f {
    return .{
        .{ v1[0] * v2[0], v1[1] * v2[0], v1[2] * v2[0] },
        .{ v1[0] * v2[1], v1[1] * v2[1], v1[2] * v2[1] },
        .{ v1[0] * v2[2], v1[1] * v2[2], v1[2] * v2[2] },
    };
}
pub fn outerProduct3d(v1: Vec3d, v2: Vec3d) Mat3d {
    return .{
        .{ v1[0] * v2[0], v1[1] * v2[0], v1[2] * v2[0] },
        .{ v1[0] * v2[1], v1[1] * v2[1], v1[2] * v2[1] },
        .{ v1[0] * v2[2], v1[1] * v2[2], v1[2] * v2[2] },
    };
}

pub fn outerProduct4f(v1: Vec4f, v2: Vec4f) Mat4f {
    return .{
        .{ v1[0] * v2[0], v1[1] * v2[0], v1[2] * v2[0], v1[3] * v2[0] },
        .{ v1[0] * v2[1], v1[1] * v2[1], v1[2] * v2[1], v1[3] * v2[1] },
        .{ v1[0] * v2[2], v1[1] * v2[2], v1[2] * v2[2], v1[3] * v2[2] },
        .{ v1[0] * v2[3], v1[1] * v2[3], v1[2] * v2[3], v1[3] * v2[3] },
    };
}
pub fn outerProduct4d(v1: Vec4d, v2: Vec4d) Mat4d {
    return .{
        .{ v1[0] * v2[0], v1[1] * v2[0], v1[2] * v2[0], v1[3] * v2[0] },
        .{ v1[0] * v2[1], v1[1] * v2[1], v1[2] * v2[1], v1[3] * v2[1] },
        .{ v1[0] * v2[2], v1[1] * v2[2], v1[2] * v2[2], v1[3] * v2[2] },
        .{ v1[0] * v2[3], v1[1] * v2[3], v1[2] * v2[3], v1[3] * v2[3] },
    };
}

pub fn add3f(a: Mat3f, b: Mat3f) Mat3f {
    return .{
        .{ a[0][0] + b[0][0], a[0][1] + b[0][1], a[0][2] + b[0][2] },
        .{ a[1][0] + b[1][0], a[1][1] + b[1][1], a[1][2] + b[1][2] },
        .{ a[2][0] + b[2][0], a[2][1] + b[2][1], a[2][2] + b[2][2] },
    };
}
pub fn add3d(a: Mat3d, b: Mat3d) Mat3d {
    return .{
        .{ a[0][0] + b[0][0], a[0][1] + b[0][1], a[0][2] + b[0][2] },
        .{ a[1][0] + b[1][0], a[1][1] + b[1][1], a[1][2] + b[1][2] },
        .{ a[2][0] + b[2][0], a[2][1] + b[2][1], a[2][2] + b[2][2] },
    };
}

pub fn add4f(a: Mat4f, b: Mat4f) Mat4f {
    return .{
        .{ a[0][0] + b[0][0], a[0][1] + b[0][1], a[0][2] + b[0][2], a[0][3] + b[0][3] },
        .{ a[1][0] + b[1][0], a[1][1] + b[1][1], a[1][2] + b[1][2], a[1][3] + b[1][3] },
        .{ a[2][0] + b[2][0], a[2][1] + b[2][1], a[2][2] + b[2][2], a[2][3] + b[2][3] },
        .{ a[3][0] + b[3][0], a[3][1] + b[3][1], a[3][2] + b[3][2], a[3][3] + b[3][3] },
    };
}
pub fn add4d(a: Mat4d, b: Mat4d) Mat4d {
    return .{
        .{ a[0][0] + b[0][0], a[0][1] + b[0][1], a[0][2] + b[0][2], a[0][3] + b[0][3] },
        .{ a[1][0] + b[1][0], a[1][1] + b[1][1], a[1][2] + b[1][2], a[1][3] + b[1][3] },
        .{ a[2][0] + b[2][0], a[2][1] + b[2][1], a[2][2] + b[2][2], a[2][3] + b[2][3] },
        .{ a[3][0] + b[3][0], a[3][1] + b[3][1], a[3][2] + b[3][2], a[3][3] + b[3][3] },
    };
}

pub fn sub3f(a: Mat3f, b: Mat3f) Mat3f {
    return .{
        .{ a[0][0] - b[0][0], a[0][1] - b[0][1], a[0][2] - b[0][2] },
        .{ a[1][0] - b[1][0], a[1][1] - b[1][1], a[1][2] - b[1][2] },
        .{ a[2][0] - b[2][0], a[2][1] - b[2][1], a[2][2] - b[2][2] },
    };
}
pub fn sub3d(a: Mat3d, b: Mat3d) Mat3d {
    return .{
        .{ a[0][0] - b[0][0], a[0][1] - b[0][1], a[0][2] - b[0][2] },
        .{ a[1][0] - b[1][0], a[1][1] - b[1][1], a[1][2] - b[1][2] },
        .{ a[2][0] - b[2][0], a[2][1] - b[2][1], a[2][2] - b[2][2] },
    };
}

pub fn sub4f(a: Mat4f, b: Mat4f) Mat4f {
    return .{
        .{ a[0][0] - b[0][0], a[0][1] - b[0][1], a[0][2] - b[0][2], a[0][3] - b[0][3] },
        .{ a[1][0] - b[1][0], a[1][1] - b[1][1], a[1][2] - b[1][2], a[1][3] - b[1][3] },
        .{ a[2][0] - b[2][0], a[2][1] - b[2][1], a[2][2] - b[2][2], a[2][3] - b[2][3] },
        .{ a[3][0] - b[3][0], a[3][1] - b[3][1], a[3][2] - b[3][2], a[3][3] - b[3][3] },
    };
}
pub fn sub4d(a: Mat4d, b: Mat4d) Mat4d {
    return .{
        .{ a[0][0] - b[0][0], a[0][1] - b[0][1], a[0][2] - b[0][2], a[0][3] - b[0][3] },
        .{ a[1][0] - b[1][0], a[1][1] - b[1][1], a[1][2] - b[1][2], a[1][3] - b[1][3] },
        .{ a[2][0] - b[2][0], a[2][1] - b[2][1], a[2][2] - b[2][2], a[2][3] - b[2][3] },
        .{ a[3][0] - b[3][0], a[3][1] - b[3][1], a[3][2] - b[3][2], a[3][3] - b[3][3] },
    };
}

pub fn lookAt(eyepos: Vec3f, eyedir: Vec3f, updir: Vec3f) Mat4f {
    // const eyedir = vec.sub3f(eyepos, focuspos);
    const dir = vec.mulScalar3f(eyedir, -1.0);
    const az = vec.normalized3f(dir);
    const ax = vec.normalized3f(vec.cross3f(updir, az));
    const ay = vec.normalized3f(vec.cross3f(az, ax));
    return .{
        .{ ax[0], ay[0], az[0], 0 },
        .{ ax[1], ay[1], az[1], 0 },
        .{ ax[2], ay[2], az[2], 0 },
        .{ -vec.dot3f(ax, eyepos), -vec.dot3f(ay, eyepos), -vec.dot3f(az, eyepos), 1.0 },
    };
}

pub fn perspective(fov: f32, aspect: f32, near: f32, far: f32) Mat4f {
    const c = @cos(fov / 2);
    const s = @sin(fov / 2);

    assert(near > 0.0 and far > 0.0);
    assert(!math.approxEqAbs(f32, s, 0.0, 0.001));
    assert(!math.approxEqAbs(f32, far, near, 0.001));
    assert(!math.approxEqAbs(f32, aspect, 0.0, 0.01));

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

pub fn orthographic(w: f32, h: f32, near: f32, far: f32) Mat4f {
    assert(!math.approxEqAbs(f32, w, 0.0, 0.001));
    assert(!math.approxEqAbs(f32, h, 0.0, 0.001));
    assert(!math.approxEqAbs(f32, far, near, 0.001));

    return .{
        .{ 2 / w, 0.0, 0.0, 0.0 },
        .{ 0.0, 2 / h, 0.0, 0.0 },
        .{ 0.0, 0.0, 2 / (near - far), 0.0 },
        .{ 0.0, 0.0, (near + far) / (near - far), 1.0 },
    };
}

pub fn rotMat3FromNormalizedAxisAndAngle(axis: Vec3f, angle: f32) Mat3f {
    const c = @cos(angle);
    const s = @sin(angle);
    const t = 1 - c;

    return .{
        .{ t * axis[0] * axis[0] + c, t * axis[0] * axis[1] + s * axis[2], t * axis[0] * axis[2] - s * axis[1] },
        .{ t * axis[0] * axis[1] - s * axis[2], t * axis[1] * axis[1] + c, t * axis[1] * axis[2] + s * axis[0] },
        .{ t * axis[0] * axis[2] + s * axis[1], t * axis[1] * axis[2] - s * axis[0], t * axis[2] * axis[2] + c },
    };
}

pub fn rotMat3FromAxisAndAngle(axis: Vec3f, angle: f32) Mat3f {
    return rotMat3FromNormalizedAxisAndAngle(vec.normalized3f(axis), angle);
}

pub fn rotMat4FromNormalizedAxisAndAngle(axis: Vec3f, angle: f32) Mat4f {
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

pub fn rotMat4FromAxisAndAngle(axis: Vec3f, angle: f32) Mat4f {
    return rotMat4FromNormalizedAxisAndAngle(vec.normalized3f(axis), angle);
}
