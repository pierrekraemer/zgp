const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const geometry_utils = @import("../../geometry/utils.zig");

/// Compute and return the angle of the given corner.
pub fn cornerAngle(
    sm: *const SurfaceMesh,
    corner: SurfaceMesh.Corner,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
) f32 {
    const d = sm.dart(corner);
    const p1 = vertex_position.value(sm.vertex(d));
    return geometry_utils.angle(
        vec.sub3f(vertex_position.value(sm.vertex(sm.phi1(d))), p1),
        vec.sub3f(vertex_position.value(sm.vertex(sm.phi_1(d))), p1),
    );
}

/// Compute the angles of all corners of the given SurfaceMesh
/// and store them in the given corner_angle data.
pub fn computeCornerAngles(
    io: std.Io,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    corner_angle: *SurfaceMesh.CornerData(f32),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        vertex_position: SurfaceMesh.VertexData(Vec3f),
        corner_angle: *SurfaceMesh.CornerData(f32),

        pub fn run(t: *const @This(), corner: SurfaceMesh.Corner) void {
            t.corner_angle.valuePtr(corner).* = cornerAngle(
                t.surface_mesh,
                corner,
                t.vertex_position,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelCornerTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .vertex_position = vertex_position,
        .corner_angle = corner_angle,
    });
}

/// Compute and return the angle of the given corner.
/// This version uses intrinsic geometry (edge lengths) instead of extrinsic vertex positions.
pub fn cornerAngleIntrinsic(
    sm: *const SurfaceMesh,
    corner: SurfaceMesh.Corner,
    edge_length: SurfaceMesh.EdgeData(f32),
) f32 {
    const d = sm.dart(corner);
    const lOpp = edge_length.value(sm.edge(sm.phi1(d)));
    const lA = edge_length.value(sm.edge(d));
    const lB = edge_length.value(sm.edge(sm.phi_1(d)));
    const q = (lA * lA + lB * lB - lOpp * lOpp) / (2.0 * lA * lB);
    return std.math.acos(@max(-1.0, @min(1.0, q)));
}

/// Compute the angles of all corners of the given SurfaceMesh
/// and store them in the given corner_angle data.
/// This version uses intrinsic geometry (edge lengths) instead of extrinsic vertex positions.
pub fn computeCornerAnglesIntrinsic(
    io: std.Io,
    sm: *SurfaceMesh,
    edge_length: SurfaceMesh.EdgeData(f32),
    corner_angle: *SurfaceMesh.CornerData(f32),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        edge_length: SurfaceMesh.EdgeData(f32),
        corner_angle: *SurfaceMesh.CornerData(f32),

        pub fn run(t: *const @This(), corner: SurfaceMesh.Corner) void {
            t.corner_angle.valuePtr(corner).* = cornerAngleIntrinsic(
                t.surface_mesh,
                corner,
                t.edge_length,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelCornerTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .edge_length = edge_length,
        .corner_angle = corner_angle,
    });
}

/// Compute and return the dihedral angle of the given edge.
/// Return 0.0 if the edge is a boundary edge.
/// Face normals are assumed to be normalized.
pub fn edgeDihedralAngle(
    sm: *const SurfaceMesh,
    edge: SurfaceMesh.Edge,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    face_normal: SurfaceMesh.FaceData(Vec3f),
) f32 {
    const d = sm.dart(edge);
    if (sm.isOrbitIncidentToBoundary(d, .edge)) {
        return 0.0; // Dihedral angle is not defined for boundary edges
    }
    const d2 = sm.phi2(d);
    const n1 = face_normal.value(sm.face(d));
    const n2 = face_normal.value(sm.face(d2));
    return std.math.atan2(
        vec.dot3f(
            vec.normalized3f(vec.sub3f(
                vertex_position.value(sm.vertex(d2)),
                vertex_position.value(sm.vertex(d)),
            )),
            vec.cross3f(n1, n2),
        ),
        vec.dot3f(n1, n2),
    );
}

/// Compute the dihedral angles of all edges of the given SurfaceMesh
/// and store them in the given edge_dihedral_angle data.
/// Face normals are assumed to be normalized.
pub fn computeEdgeDihedralAngles(
    io: std.Io,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    face_normal: SurfaceMesh.FaceData(Vec3f),
    edge_dihedral_angle: *SurfaceMesh.EdgeData(f32),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        vertex_position: SurfaceMesh.VertexData(Vec3f),
        face_normal: SurfaceMesh.FaceData(Vec3f),
        edge_dihedral_angle: *SurfaceMesh.EdgeData(f32),

        pub fn run(t: *const @This(), edge: SurfaceMesh.Edge) void {
            t.edge_dihedral_angle.valuePtr(edge).* = edgeDihedralAngle(
                t.surface_mesh,
                edge,
                t.vertex_position,
                t.face_normal,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelEdgeTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .vertex_position = vertex_position,
        .face_normal = face_normal,
        .edge_dihedral_angle = edge_dihedral_angle,
    });
}
