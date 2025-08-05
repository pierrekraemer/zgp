const std = @import("std");

const SurfaceMesh = @import("SurfaceMesh.zig");
const Data = @import("../../utils/Data.zig").Data;
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

const geometry_utils = @import("../../geometry/utils.zig");
const normal = @import("normal.zig");

pub fn cornerAngle(
    surface_mesh: *SurfaceMesh,
    vertex_position: *const Data(Vec3),
    corner: SurfaceMesh.Cell,
) f32 {
    const d = SurfaceMesh.dartOf(corner);
    const v1: SurfaceMesh.Cell = .{ .vertex = d };
    const v2: SurfaceMesh.Cell = .{ .vertex = surface_mesh.phi1(d) };
    const v3: SurfaceMesh.Cell = .{ .vertex = surface_mesh.phi_1(d) };
    const p1 = vertex_position.value(surface_mesh.indexOf(v1)).*;
    const p2 = vertex_position.value(surface_mesh.indexOf(v2)).*;
    const p3 = vertex_position.value(surface_mesh.indexOf(v3)).*;
    return geometry_utils.angle(vec.sub3(p2, p1), vec.sub3(p3, p1));
}

pub fn computeCornerAngles(
    surface_mesh: *SurfaceMesh,
    vertex_position: *const Data(Vec3),
    corner_angle: *Data(f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.corner).init(surface_mesh);
    defer it.deinit();
    while (it.next()) |corner| {
        corner_angle.value(surface_mesh.indexOf(corner)).* = cornerAngle(surface_mesh, vertex_position, corner);
    }
}

pub fn edgeDihedralAngle(
    surface_mesh: *SurfaceMesh,
    vertex_position: *const Data(Vec3),
    edge: SurfaceMesh.Cell,
) f32 {
    const d = SurfaceMesh.dartOf(edge);
    const d2 = surface_mesh.phi2(d); // TODO: check boundary condition
    const v1: SurfaceMesh.Cell = .{ .vertex = d };
    const v2: SurfaceMesh.Cell = .{ .vertex = d2 };
    const p1 = vertex_position.value(surface_mesh.indexOf(v1)).*;
    const p2 = vertex_position.value(surface_mesh.indexOf(v2)).*;
    const f1: SurfaceMesh.Cell = .{ .face = d };
    const f2: SurfaceMesh.Cell = .{ .face = d2 };
    const n1 = normal.faceNormal(surface_mesh, vertex_position, f1);
    const n2 = normal.faceNormal(surface_mesh, vertex_position, f2);
    return std.math.atan2(
        vec.dot3(vec.sub3(p2, p1), vec.cross3(n1, n2)),
        vec.dot3(n1, n2),
    );
}

pub fn computeEdgeDihedralAngles(
    surface_mesh: *SurfaceMesh,
    vertex_position: *const Data(Vec3),
    edge_dihedral_angle: *Data(f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.edge).init(surface_mesh);
    defer it.deinit();
    while (it.next()) |edge| {
        edge_dihedral_angle.value(surface_mesh.indexOf(edge)).* = edgeDihedralAngle(surface_mesh, vertex_position, edge);
    }
}
