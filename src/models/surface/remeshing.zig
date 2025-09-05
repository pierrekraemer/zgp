const std = @import("std");
const assert = std.debug.assert;

const zgp = @import("../../main.zig");

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

pub fn pliantRemeshing(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
) !void {
    _ = sm;
    _ = vertex_position;
}
