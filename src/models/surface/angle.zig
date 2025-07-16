const zm = @import("zmath");

const SurfaceMesh = @import("SurfaceMesh.zig");
const Data = @import("../../utils/Data.zig").Data;
const Vec3 = @import("../../numerical/types.zig").Vec3;

pub fn computeCornerAngles(
    surface_mesh: *SurfaceMesh,
    vertex_position: *const Data(Vec3),
    corner_angle: *Data(f32),
) !void {
    _ = surface_mesh;
    _ = vertex_position;
    _ = corner_angle;
}
