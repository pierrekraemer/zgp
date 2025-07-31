const std = @import("std");
const zm = @import("zmath");

const SurfaceMesh = @import("SurfaceMesh.zig");
const Data = @import("../../utils/Data.zig").Data;
const Vec3 = @import("../../numerical/types.zig").Vec3;

pub fn computeFaceNormal(
    surface_mesh: *SurfaceMesh,
    vertex_position: *const Data(Vec3),
    face: SurfaceMesh.Cell,
) !Vec3 {
    // TODO: try to have a type for the different cell types rather than having to check the type through the Cell active tag
    std.debug.assert(SurfaceMesh.typeOf(face) == .face);
    var dart_it = surface_mesh.cellDartIterator(face);
    var normal = zm.f32x4s(0);
    while (dart_it.next()) |dF| {
        var d = dF;
        const p1 = zm.loadArr3(vertex_position.value(surface_mesh.indexOf(.{ .vertex = d })).*);
        d = surface_mesh.phi1(d);
        const p2 = zm.loadArr3(vertex_position.value(surface_mesh.indexOf(.{ .vertex = d })).*);
        d = surface_mesh.phi1(d);
        const p3 = zm.loadArr3(vertex_position.value(surface_mesh.indexOf(.{ .vertex = d })).*);
        const v1 = p2 - p1;
        const v2 = p3 - p1;
        normal += zm.cross3(v1, v2);
        if (surface_mesh.phi1(d) == dF) {
            break;
        }
    }
    var res: Vec3 = .{ 0, 0, 0 };
    zm.storeArr3(&res, zm.normalize3(normal));
    return res;
}

pub fn computeFaceNormals(
    surface_mesh: *SurfaceMesh,
    vertex_position: *const Data(Vec3),
    face_normal: *Data(Vec3),
) !void {
    var face_it = try SurfaceMesh.CellIterator(.face).init(surface_mesh);
    defer face_it.deinit();
    while (face_it.next()) |face| {
        const n = try computeFaceNormal(surface_mesh, vertex_position, face);
        face_normal.value(surface_mesh.indexOf(face)).* = n;
    }
}

pub fn computeVertexNormal(
    surface_mesh: *SurfaceMesh,
    vertex_position: *const Data(Vec3),
    vertex: SurfaceMesh.Cell,
) !Vec3 {
    // TODO: try to have a type for the different cell types rather than having to check the type through the Cell active tag
    std.debug.assert(SurfaceMesh.typeOf(vertex) == .vertex);
    var dart_it = surface_mesh.cellDartIterator(vertex);
    var normal = zm.f32x4s(0);
    while (dart_it.next()) |d| {
        const n = try computeFaceNormal(surface_mesh, vertex_position, .{ .face = d });
        normal += zm.loadArr3(n);
    }
    var res: Vec3 = .{ 0, 0, 0 };
    zm.storeArr3(&res, zm.normalize3(normal));
    return res;
}

pub fn computeVertexNormals(
    surface_mesh: *SurfaceMesh,
    vertex_position: *const Data(Vec3),
    vertex_normal: *Data(Vec3),
) !void {
    var vertex_it = try SurfaceMesh.CellIterator(.vertex).init(surface_mesh);
    defer vertex_it.deinit();
    while (vertex_it.next()) |vertex| {
        const n = try computeVertexNormal(surface_mesh, vertex_position, vertex);
        vertex_normal.value(surface_mesh.indexOf(vertex)).* = n;
    }
}
