const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const geometry_utils = @import("../../geometry/utils.zig");

/// Compute and return the normal of the given face.
/// The normal of a polygonal face is computed as the normalized sum of successive edges cross products.
pub fn faceNormal(
    sm: *const SurfaceMesh,
    face: SurfaceMesh.Face,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
) Vec3f {
    var dart_it = sm.orbitDartIterator(sm.dart(face), .face);
    var normal = vec.zero3f;
    while (dart_it.next()) |dF| {
        var d = dF;
        const p1 = vertex_position.value(sm.vertex(d));
        d = sm.phi1(d);
        const p2 = vertex_position.value(sm.vertex(d));
        d = sm.phi1(d);
        const p3 = vertex_position.value(sm.vertex(d));
        normal = vec.add3f(
            normal,
            geometry_utils.triangleNormal(p1, p2, p3),
        );
        // early stop for triangle faces
        if (sm.phi1(d) == dF) {
            break;
        }
    }
    return vec.normalized3f(normal);
}

/// Compute the normals of all faces of the given SurfaceMesh
/// and store them in the given face_normal data.
pub fn computeFaceNormals(
    io: std.Io,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    face_normal: *SurfaceMesh.FaceData(Vec3f),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        vertex_position: SurfaceMesh.VertexData(Vec3f),
        face_normal: *SurfaceMesh.FaceData(Vec3f),

        pub fn run(t: *const @This(), face: SurfaceMesh.Face) void {
            t.face_normal.valuePtr(face).* = faceNormal(
                t.surface_mesh,
                face,
                t.vertex_position,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelFaceTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .vertex_position = vertex_position,
        .face_normal = face_normal,
    });
}

/// Compute and return the normal of the given vertex.
/// The normal of a vertex is computed as the average of the normals of its incident faces
/// weighted by the angle of the corresponding corners.
/// Face normals are assumed to be normalized.
pub fn vertexNormal(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Vertex,
    corner_angle: SurfaceMesh.CornerData(f32),
    face_normal: SurfaceMesh.FaceData(Vec3f),
) Vec3f {
    var normal = vec.zero3f;
    var dart_it = sm.orbitDartIterator(sm.dart(vertex), .vertex);
    while (dart_it.next()) |d| {
        if (!sm.isBoundaryDart(d)) {
            normal = vec.add3f(
                normal,
                vec.mulScalar3f(
                    face_normal.value(sm.face(d)),
                    corner_angle.value(sm.corner(d)),
                ),
            );
        }
    }
    return vec.normalized3f(normal);
}

/// Compute the normals of all vertices of the given SurfaceMesh
/// and store them in the given vertex_normal data.
/// Face normals are assumed to be normalized.
/// Executed here in a face-centric manner => nice but do not allow for parallelization (TODO: measure performance)
pub fn computeVertexNormals(
    io: std.Io,
    sm: *SurfaceMesh,
    corner_angle: SurfaceMesh.CornerData(f32),
    face_normal: SurfaceMesh.FaceData(Vec3f),
    vertex_normal: *SurfaceMesh.VertexData(Vec3f),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        corner_angle: SurfaceMesh.CornerData(f32),
        face_normal: SurfaceMesh.FaceData(Vec3f),
        vertex_normal: *SurfaceMesh.VertexData(Vec3f),

        pub fn run(t: *const @This(), vertex: SurfaceMesh.Vertex) void {
            t.vertex_normal.valuePtr(vertex).* = vertexNormal(
                t.surface_mesh,
                vertex,
                t.corner_angle,
                t.face_normal,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelVertexTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .corner_angle = corner_angle,
        .face_normal = face_normal,
        .vertex_normal = vertex_normal,
    });
}
