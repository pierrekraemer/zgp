const SurfaceMesh = @import("SurfaceMesh.zig");
const Data = @import("../../utils/Data.zig").Data;
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

pub fn edgeLength(
    surface_mesh: *SurfaceMesh,
    vertex_position: *const Data(Vec3),
    edge: SurfaceMesh.Cell,
) f32 {
    const d = SurfaceMesh.dartOf(edge);
    const v1: SurfaceMesh.Cell = .{ .vertex = d };
    const v2: SurfaceMesh.Cell = .{ .vertex = surface_mesh.phi1(d) };
    const p1 = vertex_position.value(surface_mesh.indexOf(v1)).*;
    const p2 = vertex_position.value(surface_mesh.indexOf(v2)).*;
    return vec.norm3(vec.sub3(p2, p1));
}

pub fn computeEdgeLengths(
    surface_mesh: *SurfaceMesh,
    vertex_position: *const Data(Vec3),
    edge_length: *Data(f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.edge).init(surface_mesh);
    defer it.deinit();
    while (it.next()) |edge| {
        edge_length.value(surface_mesh.indexOf(edge)).* = edgeLength(surface_mesh, vertex_position, edge);
    }
}
