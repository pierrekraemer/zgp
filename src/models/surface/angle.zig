const std = @import("std");
const assert = std.debug.assert;

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
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    corner_angle: SurfaceMesh.CellData(.corner, f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.corner).init(sm);
    defer it.deinit();
    while (it.next()) |corner| {
        corner_angle.valuePtr(corner).* = cornerAngle(
            sm,
            corner,
            vertex_position,
        );
    }
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
            vec.sub3f(
                vertex_position.value(.{ .vertex = d2 }),
                vertex_position.value(.{ .vertex = d }),
            ),
            vec.cross3f(n1, n2),
        ),
        vec.dot3f(n1, n2),
    );
}

/// Compute the dihedral angles of all edges of the given SurfaceMesh
/// and store them in the given edge_dihedral_angle data.
/// Face normals are assumed to be normalized.
pub fn computeEdgeDihedralAngles(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer it.deinit();
    while (it.next()) |edge| {
        edge_dihedral_angle.valuePtr(edge).* = edgeDihedralAngle(
            sm,
            edge,
            vertex_position,
            face_normal,
        );
    }
}
