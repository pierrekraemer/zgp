const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

const geometry_utils = @import("../../geometry/utils.zig");

/// Compute and return the normal of the given face.
/// The normal of a polygonal face is computed as the normalized sum of successive edges cross products.
pub fn faceNormal(
    sm: *const SurfaceMesh,
    face: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
) Vec3 {
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
        normal = vec.add3(
            normal,
            geometry_utils.triangleNormal(p1, p2, p3),
        );
        // early stop for triangle faces
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
        face_normal.valuePtr(face).* = faceNormal(
            sm,
            face,
            vertex_position,
        );
    }
}

/// Compute and return the normal of the given vertex.
/// The normal of a vertex is computed as the average of the normals of its incident faces
/// weighted by the angle of the corresponding corners.
/// Face normals are assumed to be normalized.
pub fn vertexNormal(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
) Vec3 {
    assert(vertex.cellType() == .vertex);
    var normal = vec.zero3;
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (!sm.isBoundaryDart(d)) {
            normal = vec.add3(
                normal,
                vec.mulScalar3(
                    face_normal.value(.{ .face = d }),
                    corner_angle.value(.{ .corner = d }),
                ),
            );
        }
    }
    return vec.normalized3(normal);
}

/// Compute the normals of all vertices of the given SurfaceMesh
/// and store them in the given vertex_normal data.
/// Face normals are assumed to be normalized.
pub fn computeVertexNormals(
    sm: *SurfaceMesh,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3),
) !void {
    var vertex_it = try SurfaceMesh.CellIterator(.vertex).init(sm);
    defer vertex_it.deinit();
    while (vertex_it.next()) |vertex| {
        vertex_normal.valuePtr(vertex).* = vertexNormal(
            sm,
            vertex,
            corner_angle,
            face_normal,
        );
    }
}
