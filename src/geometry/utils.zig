const std = @import("std");
const Data = @import("../utils/Data.zig").Data;
const vec = @import("../geometry/vec.zig");
const Scalar = vec.Scalar;
const Vec3 = vec.Vec3;

pub fn angle(a: Vec3, b: Vec3) Scalar {
    return std.math.acos(@max(-1.0, @min(1.0, cosAngle(a, b))));
}

pub fn cosAngle(a: Vec3, b: Vec3) Scalar {
    return vec.dot3(vec.normalized3(a), vec.normalized3(b));
}

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

pub fn scale(data: *Data(Vec3), s: Scalar) void {
    var it = data.iterator();
    while (it.next()) |pos| {
        pos.* = vec.mulScalar3(pos.*, s);
    }
}

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

pub fn centerAround(data: *Data(Vec3), v: Vec3) void {
    const c = centroid(data);
    const offset = vec.sub3(v, c);
    var it = data.iterator();
    while (it.next()) |pos| {
        pos.* = vec.add3(pos.*, offset);
    }
}
