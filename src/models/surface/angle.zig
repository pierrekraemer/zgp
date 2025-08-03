const SurfaceMesh = @import("SurfaceMesh.zig");
const Data = @import("../../utils/Data.zig").Data;
const vec = @import("../../utils/vec.zig");
const Vec3 = vec.Vec3;

pub fn computeCornerAngles(
    surface_mesh: *SurfaceMesh,
    vertex_position: *const Data(Vec3),
    corner_angle: *Data(f32),
) !void {
    _ = surface_mesh;
    _ = vertex_position;
    _ = corner_angle;
}

pub fn computeEdgeDihedralAngles(
    surface_mesh: *SurfaceMesh,
    vertex_position: *const Data(Vec3),
    edge_dihedral_angle: *Data(f32),
) !void {
    _ = surface_mesh;
    _ = vertex_position;
    _ = edge_dihedral_angle;
}
