const std = @import("std");
const assert = std.debug.assert;

const AppContext = @import("../../main.zig").AppContext;
const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const geometry_utils = @import("../../geometry/utils.zig");

/// Compute and return the angle of the given corner.
pub fn cornerAngle(
    sm: *const SurfaceMesh,
    corner: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
) f32 {
    assert(corner.cellType() == .corner);
    const d = corner.dart();
    const d1 = sm.phi1(d);
    const d_1 = sm.phi_1(d);
    const p1 = vertex_position.value(.{ .vertex = d });
    return geometry_utils.angle(
        vec.sub3f(vertex_position.value(.{ .vertex = d1 }), p1),
        vec.sub3f(vertex_position.value(.{ .vertex = d_1 }), p1),
    );
}

/// Compute the angles of all corners of the given SurfaceMesh
/// and store them in the given corner_angle data.
pub fn computeCornerAngles(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    corner_angle: SurfaceMesh.CellData(.corner, f32),
) !void {
    const Task = struct {
        const Task = @This();

        surface_mesh: *const SurfaceMesh,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        corner_angle: SurfaceMesh.CellData(.corner, f32),

        pub fn run(t: *const Task, corner: SurfaceMesh.Cell) void {
            t.corner_angle.valuePtr(corner).* = cornerAngle(
                t.surface_mesh,
                corner,
                t.vertex_position,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelCellTaskRunner = try .init(sm, .corner);
    defer pctr.deinit();
    try pctr.run(app_ctx, Task{
        .surface_mesh = sm,
        .vertex_position = vertex_position,
        .corner_angle = corner_angle,
    });

    // single-threaded version for the record

    // _ = app_ctx;
    // var corner_it = try SurfaceMesh.CellIterator(.corner).init(sm);
    // defer corner_it.deinit();
    // while (corner_it.next()) |corner| {
    //     corner_angle.valuePtr(corner).* = cornerAngle(sm, corner, vertex_position);
    // }
}

/// Compute and return the angle of the given corner.
/// This version uses intrinsic geometry (edge lengths) instead of extrinsic vertex positions.
pub fn cornerAngleIntrinsic(
    sm: *const SurfaceMesh,
    corner: SurfaceMesh.Cell,
    edge_length: SurfaceMesh.CellData(.edge, f32),
) f32 {
    assert(corner.cellType() == .corner);
    const d = corner.dart();
    const d1 = sm.phi1(d);
    const d_1 = sm.phi_1(d);
    const lOpp = edge_length.value(.{ .edge = d1 });
    const lA = edge_length.value(.{ .edge = d });
    const lB = edge_length.value(.{ .edge = d_1 });
    const q = (lA * lA + lB * lB - lOpp * lOpp) / (2.0 * lA * lB);
    return std.math.acos(@max(-1.0, @min(1.0, q)));
}

/// Compute the angles of all corners of the given SurfaceMesh
/// and store them in the given corner_angle data.
/// This version uses intrinsic geometry (edge lengths) instead of extrinsic vertex positions.
pub fn computeCornerAnglesIntrinsic(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    edge_length: SurfaceMesh.CellData(.edge, f32),
    corner_angle: SurfaceMesh.CellData(.corner, f32),
) !void {
    const Task = struct {
        const Task = @This();

        surface_mesh: *const SurfaceMesh,
        edge_length: SurfaceMesh.CellData(.edge, f32),
        corner_angle: SurfaceMesh.CellData(.corner, f32),

        pub fn run(t: *const Task, corner: SurfaceMesh.Cell) void {
            t.corner_angle.valuePtr(corner).* = cornerAngleIntrinsic(
                t.surface_mesh,
                corner,
                t.edge_length,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelCellTaskRunner = try .init(sm, .corner);
    defer pctr.deinit();
    try pctr.run(app_ctx, Task{
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
    edge: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
) f32 {
    assert(edge.cellType() == .edge);
    if (sm.isIncidentToBoundary(edge)) {
        return 0.0; // Dihedral angle is not defined for boundary edges
    }
    const d = edge.dart();
    const d2 = sm.phi2(d);
    const n1 = face_normal.value(.{ .face = d });
    const n2 = face_normal.value(.{ .face = d2 });
    return std.math.atan2(
        vec.dot3f(
            vec.normalized3f(vec.sub3f(
                vertex_position.value(.{ .vertex = d2 }),
                vertex_position.value(.{ .vertex = d }),
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
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
) !void {
    const Task = struct {
        const Task = @This();

        surface_mesh: *const SurfaceMesh,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),
        edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),

        pub fn run(t: *const Task, edge: SurfaceMesh.Cell) void {
            t.edge_dihedral_angle.valuePtr(edge).* = edgeDihedralAngle(
                t.surface_mesh,
                edge,
                t.vertex_position,
                t.face_normal,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelCellTaskRunner = try .init(sm, .edge);
    defer pctr.deinit();
    try pctr.run(app_ctx, Task{
        .surface_mesh = sm,
        .vertex_position = vertex_position,
        .face_normal = face_normal,
        .edge_dihedral_angle = edge_dihedral_angle,
    });
}
