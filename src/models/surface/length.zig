const SurfaceMesh = @import("SurfaceMesh.zig");
const Data = @import("../../utils/Data.zig").Data;
const vec = @import("../../utils/vec.zig");
const Vec3 = vec.Vec3;

pub fn computeEdgeLengths(
    surface_mesh: *SurfaceMesh,
    vertex_position: *const Data(Vec3),
    edge_length: *Data(f32),
) !void {
    var it = try surface_mesh.CellIterator(.edge).init();
    defer it.deinit();
    while (it.next()) |edge| {
        const d = SurfaceMesh.dartOf(edge);
        const v1: SurfaceMesh.Cell = .{ .vertex = d };
        const v2: SurfaceMesh.Cell = .{ .vertex = surface_mesh.phi1(d) };
        const p1 = vertex_position.value(surface_mesh.indexOf(v1)).*;
        const p2 = vertex_position.value(surface_mesh.indexOf(v2)).*;
        edge_length.value(surface_mesh.indexOf(edge)).* = vec.norm3(vec.sub3(p2, p1));
    }
}
