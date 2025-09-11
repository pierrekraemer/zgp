const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

const geometry_utils = @import("../../geometry/utils.zig");
const normal = @import("normal.zig");

/// Compute and return the angle of the given corner.
pub fn cornerAngle(
    sm: *const SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    corner: SurfaceMesh.Cell,
) f32 {
    assert(corner.cellType() == .corner);
    const d = corner.dart();
    const v1: SurfaceMesh.Cell = .{ .vertex = d };
    const v2: SurfaceMesh.Cell = .{ .vertex = sm.phi1(d) };
    const v3: SurfaceMesh.Cell = .{ .vertex = sm.phi_1(d) };
    return geometry_utils.angle(
        vec.sub3(vertex_position.value(v2), vertex_position.value(v1)),
        vec.sub3(vertex_position.value(v3), vertex_position.value(v1)),
    );
}

/// Compute the angles of all corners of the given SurfaceMesh
/// and store them in the given corner_angle data.
pub fn computeCornerAngles(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    corner_angle: SurfaceMesh.CellData(.corner, f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.corner).init(sm);
    defer it.deinit();
    while (it.next()) |corner| {
        corner_angle.valuePtr(corner).* = cornerAngle(sm, vertex_position, corner);
    }
}

/// Compute and return the dihedral angle of the given edge.
/// Return 0.0 if the edge is a boundary edge.
pub fn edgeDihedralAngle(
    sm: *const SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    edge: SurfaceMesh.Cell,
) f32 {
    assert(edge.cellType() == .edge);
    if (sm.isIncidentToBoundary(edge)) {
        return 0.0; // Dihedral angle is not defined for boundary edges
    }
    const d = edge.dart();
    const d2 = sm.phi2(d);
    const n1 = normal.faceNormal(sm, vertex_position, .{ .face = d });
    const n2 = normal.faceNormal(sm, vertex_position, .{ .face = d2 });
    return std.math.atan2(
        vec.dot3(
            vec.sub3(
                vertex_position.value(.{ .vertex = d2 }),
                vertex_position.value(.{ .vertex = d }),
            ),
            vec.cross3(n1, n2),
        ),
        vec.dot3(n1, n2),
    );
}

/// Compute the dihedral angles of all edges of the given SurfaceMesh
/// and store them in the given edge_dihedral_angle data.
pub fn computeEdgeDihedralAngles(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer it.deinit();
    while (it.next()) |edge| {
        edge_dihedral_angle.valuePtr(edge).* = edgeDihedralAngle(sm, vertex_position, edge);
    }
}
