const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const geometry_utils = @import("../../geometry/utils.zig");

/// Compute and return the area of the given face.
/// TODO: should perform ear-triangulation on polygonal faces instead of just a triangle fan.
pub fn faceArea(
    sm: *const SurfaceMesh,
    face: SurfaceMesh.Face,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
) f32 {
    var area: f32 = 0.0;
    const d_start = sm.dart(face);
    const p1 = vertex_position.value(sm.vertex(d_start));
    var d_next = sm.phi1(d_start);
    if (d_next == d_start) return 0.0; // 1-sided face
    var d_prev = d_next;
    d_next = sm.phi1(d_next);
    if (d_next == d_start) return 0.0; // 2-sided face
    var p2 = vertex_position.value(sm.vertex(d_prev));
    while (d_next != d_start) : (d_next = sm.phi1(d_next)) {
        const p3 = vertex_position.value(sm.vertex(d_next));
        area += geometry_utils.triangleArea(p1, p2, p3);
        d_prev = d_next;
        p2 = p3;
    }
    return area;
}

/// Compute the areas of all faces of the given SurfaceMesh
/// and store them in the given face_area data.
pub fn computeFaceAreas(
    io: std.Io,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    face_area: *SurfaceMesh.FaceData(f32),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        vertex_position: SurfaceMesh.VertexData(Vec3f),
        face_area: *SurfaceMesh.FaceData(f32),

        pub fn run(t: *const @This(), face: SurfaceMesh.Face) void {
            t.face_area.valuePtr(face).* = faceArea(
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
        .face_area = face_area,
    });
}

/// Compute and return the area of the given face.
/// This version uses intrinsic geometry (edge lengths) instead of extrinsic vertex positions.
pub fn faceAreaIntrinsic(
    sm: *const SurfaceMesh,
    face: SurfaceMesh.Face,
    edge_length: SurfaceMesh.EdgeData(f32),
) f32 {
    const d = sm.dart(face);
    return geometry_utils.triangleAreaIntrinsic(
        edge_length.value(sm.edge(d)),
        edge_length.value(sm.edge(sm.phi1(d))),
        edge_length.value(sm.edge(sm.phi_1(d))),
    );
}

/// Compute the areas of all faces of the given SurfaceMesh
/// and store them in the given face_area data.
/// This version uses intrinsic geometry (edge lengths) instead of extrinsic vertex positions.
pub fn computeFaceAreasIntrinsic(
    io: std.Io,
    sm: *SurfaceMesh,
    edge_length: SurfaceMesh.EdgeData(f32),
    face_area: *SurfaceMesh.FaceData(f32),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        edge_length: SurfaceMesh.EdgeData(f32),
        face_area: *SurfaceMesh.FaceData(f32),

        pub fn run(t: *const @This(), face: SurfaceMesh.Face) void {
            t.face_area.valuePtr(face).* = faceAreaIntrinsic(
                t.surface_mesh,
                face,
                t.edge_length,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelFaceTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .edge_length = edge_length,
        .face_area = face_area,
    });
}

/// Compute and return the area of the given vertex.
/// The area of a vertex is defined as a sum of contributions from its incident faces.
/// Each incident face f contributes 1/codegree(f) of its area to the area of the vertex.
pub fn vertexArea(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Vertex,
    face_area: SurfaceMesh.FaceData(f32),
) f32 {
    var area: f32 = 0.0;
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (sm.isBoundaryDart(d)) continue; // skip boundary faces
        const f = sm.face(d);
        const cd: f32 = @floatFromInt(sm.codegree(f));
        area += face_area.value(f) / cd;
    }
    return area;
}

/// Compute the areas of all vertices of the given SurfaceMesh
/// and store them in the given vertex_area data.
/// The area of a vertex is defined as a sum of contributions from its incident faces.
/// Each face f contributes 1/codegree(f) of its area to the area of its incident vertices.
/// Executed here in a face-centric manner => nice but do not allow for parallelization (TODO: measure performance)
pub fn computeVertexAreas(
    sm: *SurfaceMesh,
    face_area: SurfaceMesh.FaceData(f32),
    vertex_area: *SurfaceMesh.VertexData(f32),
) !void {
    vertex_area.data.fill(0.0);
    var it = sm.faceIterator();
    while (it.next()) |f| {
        const cd: f32 = @floatFromInt(sm.codegree(f));
        const a = face_area.value(f) / cd;
        var dart_it = sm.orbitDartIterator(sm.dart(f), .face);
        while (dart_it.next()) |d| {
            vertex_area.valuePtr(sm.vertex(d)).* += a;
        }
    }
}
