const std = @import("std");

const Data = @import("../utils/Data.zig").Data;

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

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

/// Compute and return the axis-aligned bounding box of the given data points
/// as a pair of minimum and maximum corners.
pub fn boundingBox(data: *const Data(Vec3f)) struct { Vec3f, Vec3f } {
    var it = data.constIterator();
    var bb_min = vec.splat3f(std.math.floatMax(f32));
    var bb_max = vec.splat3f(std.math.floatMin(f32));
    while (it.next()) |pos| {
        bb_min = vec.componentwiseMin3f(bb_min, pos.*);
        bb_max = vec.componentwiseMax3f(bb_max, pos.*);
    }
    return .{ bb_min, bb_max };
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
