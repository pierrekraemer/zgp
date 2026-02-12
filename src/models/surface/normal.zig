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
    face: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
) Vec3f {
    assert(face.cellType() == .face);
    var dart_it = sm.cellDartIterator(face);
    var normal = vec.zero3f;
    while (dart_it.next()) |dF| {
        var d = dF;
        const p1 = vertex_position.value(.{ .vertex = d });
        d = sm.phi1(d);
        const p2 = vertex_position.value(.{ .vertex = d });
        d = sm.phi1(d);
        const p3 = vertex_position.value(.{ .vertex = d });
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
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
) !void {
    const Task = struct {
        const Task = @This();

        surface_mesh: *const SurfaceMesh,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),

        pub inline fn run(t: *const Task, face: SurfaceMesh.Cell) void {
            t.face_normal.valuePtr(face).* = faceNormal(
                t.surface_mesh,
                face,
                t.vertex_position,
            );
        }
    };

    var pctr = try SurfaceMesh.ParallelCellTaskRunner(.face).init(sm);
    defer pctr.deinit();
    try pctr.run(Task{
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
    vertex: SurfaceMesh.Cell,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
) Vec3f {
    assert(vertex.cellType() == .vertex);
    var normal = vec.zero3f;
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (!sm.isBoundaryDart(d)) {
            normal = vec.add3f(
                normal,
                vec.mulScalar3f(
                    face_normal.value(.{ .face = d }),
                    corner_angle.value(.{ .corner = d }),
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
    sm: *SurfaceMesh,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
) !void {
    vertex_normal.data.fill(vec.zero3f);
    var face_it = try SurfaceMesh.CellIterator(.face).init(sm);
    defer face_it.deinit();
    while (face_it.next()) |face| {
        const n = face_normal.value(face);
        var dart_it = sm.cellDartIterator(face);
        while (dart_it.next()) |d| {
            const v: SurfaceMesh.Cell = .{ .vertex = d };
            vertex_normal.valuePtr(v).* = vec.add3f(
                vertex_normal.value(v),
                vec.mulScalar3f(
                    n,
                    corner_angle.value(.{ .corner = d }),
                ),
            );
        }
    }
    var it = vertex_normal.data.iterator();
    while (it.next()) |n| {
        n.* = vec.normalized3f(n.*);
    }

    // const Task = struct {
    //     const Task = @This();

    //     surface_mesh: *const SurfaceMesh,
    //     corner_angle: SurfaceMesh.CellData(.corner, f32),
    //     face_normal: SurfaceMesh.CellData(.face, Vec3f),
    //     vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),

    //     pub inline fn run(t: *const Task, vertex: SurfaceMesh.Cell) void {
    //         t.vertex_normal.valuePtr(vertex).* = vertexNormal(
    //             t.surface_mesh,
    //             vertex,
    //             t.corner_angle,
    //             t.face_normal,
    //         );
    //     }
    // };

    // var pctr = try SurfaceMesh.ParallelCellTaskRunner(.vertex).init(sm);
    // defer pctr.deinit();
    // try pctr.run(Task{
    //     .surface_mesh = sm,
    //     .corner_angle = corner_angle,
    //     .face_normal = face_normal,
    //     .vertex_normal = vertex_normal,
    // });
}
