const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const SurfaceMeshData = SurfaceMesh.SurfaceMeshData;
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

pub fn faceNormal(
    surface_mesh: *SurfaceMesh,
    vertex_position: SurfaceMeshData(.vertex, Vec3),
    face: SurfaceMesh.Cell,
) Vec3 {
    // TODO: try to have a type for the different cell types rather than having to check the type through the Cell active tag
    assert(face.cellType() == .face);
    var dart_it = surface_mesh.cellDartIterator(face);
    var normal = vec.zero3;
    while (dart_it.next()) |dF| {
        var d = dF;
        const p1 = vertex_position.value(.{ .vertex = d });
        d = surface_mesh.phi1(d);
        const p2 = vertex_position.value(.{ .vertex = d });
        d = surface_mesh.phi1(d);
        const p3 = vertex_position.value(.{ .vertex = d });
        normal = vec.add3(normal, vec.cross3(
            vec.sub3(p2, p1),
            vec.sub3(p3, p1),
        ));
        if (surface_mesh.phi1(d) == dF) {
            break;
        }
    }
    return vec.normalized3(normal);
}

pub fn computeFaceNormals(
    surface_mesh: *SurfaceMesh,
    vertex_position: SurfaceMeshData(.vertex, Vec3),
    face_normal: SurfaceMeshData(.face, Vec3),
) !void {
    var face_it = try SurfaceMesh.CellIterator(.face).init(surface_mesh);
    defer face_it.deinit();
    while (face_it.next()) |face| {
        const n = faceNormal(surface_mesh, vertex_position, face);
        face_normal.valuePtr(face).* = n;
    }
}

pub fn vertexNormal(
    surface_mesh: *SurfaceMesh,
    vertex_position: SurfaceMeshData(.vertex, Vec3),
    vertex: SurfaceMesh.Cell,
) Vec3 {
    // TODO: try to have a type for the different cell types rather than having to check the type through the Cell active tag
    assert(vertex.cellType() == .vertex);
    var dart_it = surface_mesh.cellDartIterator(vertex);
    var normal = vec.zero3;
    while (dart_it.next()) |d| {
        if (!surface_mesh.isBoundaryDart(d)) {
            const n = faceNormal(surface_mesh, vertex_position, .{ .face = d });
            normal = vec.add3(normal, n);
        }
    }
    return vec.normalized3(normal);
}

pub fn computeVertexNormals(
    surface_mesh: *SurfaceMesh,
    vertex_position: SurfaceMeshData(.vertex, Vec3),
    vertex_normal: SurfaceMeshData(.vertex, Vec3),
) !void {
    var vertex_it = try SurfaceMesh.CellIterator(.vertex).init(surface_mesh);
    defer vertex_it.deinit();
    while (vertex_it.next()) |vertex| {
        const n = vertexNormal(surface_mesh, vertex_position, vertex);
        vertex_normal.valuePtr(vertex).* = n;
    }
}
