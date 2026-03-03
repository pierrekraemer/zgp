const std = @import("std");

const Data = @import("../utils/Data.zig").Data;

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

pub const epsilon: f32 = 1e-5;

/// Compute and return the angle between two vectors.
pub fn angle(a: Vec3f, b: Vec3f) f32 {
    return std.math.acos(@max(-1.0, @min(1.0, cosAngle(a, b))));
}

/// Compute and return the cosine of the angle between two vectors.
pub fn cosAngle(a: Vec3f, b: Vec3f) f32 {
    return vec.dot3f(
        vec.normalized3f(a),
        vec.normalized3f(b),
    );
}

/// Compute and return the area of the triangle defined by the given three points.
pub fn triangleArea(a: Vec3f, b: Vec3f, c: Vec3f) f32 {
    return 0.5 * vec.norm3f(vec.cross3f(
        vec.sub3f(b, a),
        vec.sub3f(c, a),
    ));
}

/// Compute and return the _unnormalized_ normal vector of the triangle defined by the given three points.
pub fn triangleNormal(a: Vec3f, b: Vec3f, c: Vec3f) Vec3f {
    return vec.cross3f(
        vec.sub3f(b, a),
        vec.sub3f(c, a),
    );
}

// Compute the squared distance between the given point p and the line defined by the given two points a and b.
pub fn squaredDistanceLinePoint(a: Vec3f, b: Vec3f, p: Vec3f) f32 {
    const ab = vec.normalized3f(vec.sub3f(b, a));
    const ap = vec.sub3f(p, a);
    return vec.squaredNorm3f(vec.cross3f(ap, ab));
}

/// Compute the signed distance between the given point p and the plane defined by the given three points a, b, c.
pub fn signedDistancePlanePoint(a: Vec3f, b: Vec3f, c: Vec3f, p: Vec3f) f32 {
    const n = vec.normalized3f(triangleNormal(a, b, c));
    const d = vec.dot3f(n, a);
    return vec.dot3f(n, p) - d;
}

/// Compute the distance between the given point p and the plane defined by the given three points a, b, c.
pub fn distancePlanePoint(a: Vec3f, b: Vec3f, c: Vec3f, p: Vec3f) f32 {
    return @abs(signedDistancePlanePoint(a, b, c, p));
}

pub const PlaneOrientation = enum {
    on,
    under,
    over,
};

/// Compute and return the orientation of the given point with respect to the plane defined by the given three points.
pub fn planeOrientation(a: Vec3f, b: Vec3f, c: Vec3f, p: Vec3f) PlaneOrientation {
    const dist = signedDistancePlanePoint(a, b, c, p);
    if (@abs(dist) <= epsilon) {
        return .on;
    } else if (dist < 0.0) {
        return .under;
    } else {
        return .over;
    }
}

/// Return a vector where the component of v along unitDir has been removed.
/// As the name suggests, unitDir must be a unit vector.
pub fn removeComponent(v: Vec3f, unitDir: Vec3f) Vec3f {
    return vec.sub3f(
        v,
        vec.mulScalar3f(
            unitDir,
            vec.dot3f(v, unitDir),
        ),
    );
}

/// Compute and return the axis-aligned bounding box of the given data points
/// as a pair of minimum and maximum corners.
pub fn boundingBox(data: *const Data(Vec3f)) struct { Vec3f, Vec3f } {
    var bb_min = vec.splat3f(std.math.floatMax(f32));
    var bb_max = vec.splat3f(std.math.floatMin(f32));
    var it = data.constIterator();
    while (it.next()) |pos| {
        bb_min = vec.componentwiseMin3f(bb_min, pos.*);
        bb_max = vec.componentwiseMax3f(bb_max, pos.*);
    }
    return .{ bb_min, bb_max };
}

/// Compute and return the 6 points that contribute to the axis-aligned bounding box of the given data points
/// in the following order: xmin, xmin, ymin ymax, zmin, zmax
/// (a point can be present multiple times)
pub fn extremePoints(data: *const Data(Vec3f)) [6]Vec3f {
    var bb_min = vec.splat3f(std.math.floatMax(f32));
    var bb_max = vec.splat3f(std.math.floatMin(f32));
    var result: [6]Vec3f = undefined;
    var it = data.constIterator();
    while (it.next()) |pos| {
        if (pos[0] < bb_min[0]) {
            bb_min[0] = pos[0];
            result[0] = pos.*;
        }
        if (pos[0] > bb_max[0]) {
            bb_max[0] = pos[0];
            result[1] = pos.*;
        }
        if (pos[1] < bb_min[1]) {
            bb_min[1] = pos[1];
            result[2] = pos.*;
        }
        if (pos[1] > bb_max[1]) {
            bb_max[1] = pos[1];
            result[3] = pos.*;
        }
        if (pos[2] < bb_min[2]) {
            bb_min[2] = pos[2];
            result[4] = pos.*;
        }
        if (pos[2] > bb_max[2]) {
            bb_max[2] = pos[2];
            result[5] = pos.*;
        }
    }
    return result;
}

/// Scale the given data points by the given scalar factor.
pub fn scale(data: *Data(Vec3f), s: f32) void {
    var it = data.iterator();
    while (it.next()) |pos| {
        pos.* = vec.mulScalar3f(pos.*, s);
    }
}

/// Compute and return the mean value of the given data.
/// Supports float, int, or array of float/int types.
pub fn meanValue(comptime T: type, data: *const Data(T)) T {
    var sum: T = switch (@typeInfo(T)) {
        .float, .int => 0,
        .array => blk: {
            const elem_info = @typeInfo(@typeInfo(T).array.child);
            if (elem_info != .float and elem_info != .int) {
                @compileError("meanValue only supports float, int, or array of float/int types");
            }
            break :blk @splat(0);
        },
        else => @compileError("meanValue only supports float, int, or array of float/int types"),
    };
    const nb_elements: usize = data.nbElements();
    if (nb_elements == 0) {
        return sum; // return zero if no elements
    }
    var it = data.constIterator();
    while (it.next()) |v| {
        switch (@typeInfo(T)) {
            .float, .int => sum += v.*,
            .array => {
                inline for (0..@typeInfo(T).array.len) |i| {
                    sum[i] += v.*[i];
                }
            },
            else => unreachable,
        }
    }
    return switch (@typeInfo(T)) {
        .float => sum / @as(T, @floatFromInt(nb_elements)),
        .int => sum / @as(T, @intCast(nb_elements)),
        .array => blk: {
            inline for (0..@typeInfo(T).array.len) |i| {
                sum[i] = sum[i] / @as(@TypeOf(sum[i]), @floatFromInt(nb_elements));
            }
            break :blk sum;
        },
        else => unreachable,
    };
}

/// Translate the given data points to center around the given point.
pub fn centerAround(data: *Data(Vec3f), v: Vec3f) void {
    const c = meanValue(Vec3f, data);
    const offset = vec.sub3f(v, c);
    var it = data.iterator();
    while (it.next()) |pos| {
        pos.* = vec.add3f(pos.*, offset);
    }
}
