const std = @import("std");

const Data = @import("../utils/Data.zig").Data;

const vec = @import("../geometry/vec.zig");
const Scalar = vec.Scalar;
const Vec3 = vec.Vec3;

/// Compute and return the angle between two vectors.
pub fn angle(a: Vec3, b: Vec3) Scalar {
    return std.math.acos(@max(-1.0, @min(1.0, cosAngle(a, b))));
}

/// Compute and return the cosine of the angle between two vectors.
pub fn cosAngle(a: Vec3, b: Vec3) Scalar {
    return vec.dot3(
        vec.normalized3(a),
        vec.normalized3(b),
    );
}

/// Compute and return the area of the triangle defined by the given three points.
pub fn triangleArea(a: Vec3, b: Vec3, c: Vec3) Scalar {
    return 0.5 * vec.norm3(vec.cross3(
        vec.sub3(b, a),
        vec.sub3(c, a),
    ));
}

/// Compute and return the _unnormalized_ normal vector of the triangle defined by the given three points.
pub fn triangleNormal(a: Vec3, b: Vec3, c: Vec3) Vec3 {
    return vec.cross3(
        vec.sub3(b, a),
        vec.sub3(c, a),
    );
}

/// Compute and return the axis-aligned bounding box of the given data points
/// as a pair of minimum and maximum corners.
pub fn boundingBox(data: *const Data(Vec3)) struct { Vec3, Vec3 } {
    var it = data.constIterator();
    var bb_min = vec.splat3(std.math.floatMax(Scalar));
    var bb_max = vec.splat3(std.math.floatMin(Scalar));
    while (it.next()) |pos| {
        bb_min = vec.componentwiseMin3(bb_min, pos.*);
        bb_max = vec.componentwiseMax3(bb_max, pos.*);
    }
    return .{ bb_min, bb_max };
}

/// Scale the given data points by the given scalar factor.
pub fn scale(data: *Data(Vec3), s: Scalar) void {
    var it = data.iterator();
    while (it.next()) |pos| {
        pos.* = vec.mulScalar3(pos.*, s);
    }
}

/// Compute and return the centroid of the given data points.
pub fn centroid(data: *const Data(Vec3)) Vec3 {
    var c = vec.zero3;
    var it = data.constIterator();
    while (it.next()) |pos| {
        c = vec.add3(c, pos.*);
    }
    const nb_elements = data.nbElements();
    if (nb_elements == 0) {
        return c; // return zero vector if no elements
    }
    const nb_elements_f: Scalar = @floatFromInt(nb_elements);
    return vec.mulScalar3(c, 1.0 / nb_elements_f);
}

/// Translate the given data points to center around the given point.
pub fn centerAround(data: *Data(Vec3), v: Vec3) void {
    const c = centroid(data);
    const offset = vec.sub3(v, c);
    var it = data.iterator();
    while (it.next()) |pos| {
        pos.* = vec.add3(pos.*, offset);
    }
}
