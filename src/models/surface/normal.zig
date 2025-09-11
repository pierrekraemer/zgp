const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

const angle = @import("angle.zig");

/// Compute and return the normal of the given face.
/// The normal of a polygonal face is computed as the normalized sum of successive edges cross products.
pub fn faceNormal(
    sm: *const SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face: SurfaceMesh.Cell,
) Vec3 {
    // TODO: try to have a type for the different cell types rather than having to check the type through the Cell active tag
    assert(face.cellType() == .face);
    var dart_it = sm.cellDartIterator(face);
    var normal = vec.zero3;
    while (dart_it.next()) |dF| {
        var d = dF;
        const p1 = vertex_position.value(.{ .vertex = d });
        d = sm.phi1(d);
        const p2 = vertex_position.value(.{ .vertex = d });
        d = sm.phi1(d);
        const p3 = vertex_position.value(.{ .vertex = d });
        normal = vec.add3(normal, vec.cross3(
            vec.sub3(p2, p1),
            vec.sub3(p3, p1),
        ));
        if (sm.phi1(d) == dF) {
            break;
        }
    }
    return vec.normalized3(normal);
}

/// Compute the normals of all faces of the given SurfaceMesh
/// and store them in the given face_normal data.
pub fn computeFaceNormals(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
) !void {
    var face_it = try SurfaceMesh.CellIterator(.face).init(sm);
    defer face_it.deinit();
    while (face_it.next()) |face| {
        const n = faceNormal(sm, vertex_position, face);
        face_normal.valuePtr(face).* = n;
    }
}

/// Compute and return the normal of the given vertex.
/// The normal of a vertex is computed as the average of the normals of its incident faces,
/// weighted by the angle of the corresponding corners.
pub fn vertexNormal(
    sm: *const SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    vertex: SurfaceMesh.Cell,
) Vec3 {
    // TODO: try to have a type for the different cell types rather than having to check the type through the Cell active tag
    assert(vertex.cellType() == .vertex);
    var normal = vec.zero3;
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (!sm.isBoundaryDart(d)) {
            const n = faceNormal(sm, vertex_position, .{ .face = d });
            normal = vec.add3(
                normal,
                vec.mulScalar3(
                    n,
                    angle.cornerAngle(sm, vertex_position, .{ .corner = d }),
                ),
            );
        }
    }
    return vec.normalized3(normal);
}

/// Compute the normals of all vertices of the given SurfaceMesh
/// and store them in the given vertex_normal data.
pub fn computeVertexNormals(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3),
) !void {
    var vertex_it = try SurfaceMesh.CellIterator(.vertex).init(sm);
    defer vertex_it.deinit();
    while (vertex_it.next()) |vertex| {
        const n = vertexNormal(sm, vertex_position, vertex);
        vertex_normal.valuePtr(vertex).* = n;
    }
}
