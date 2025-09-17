const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

/// Compute and return the Gaussian curvature of the given vertex
/// computed as the angle defect.
pub fn vertexGaussianCurvature(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
) f32 {
    assert(vertex.cellType() == .vertex);
    if (sm.isIncidentToBoundary(vertex)) {
        return 0.0;
    }
    var angle_sum: f32 = 0.0;
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        angle_sum += corner_angle.value(.{ .corner = d });
    }
    return 2.0 * std.math.pi - angle_sum;
}

/// Compute the Gaussian curvatures of all vertices of the given SurfaceMesh
/// and store the results in the given vertex_gaussian_curvature data.
pub fn computeVertexGaussianCurvatures(
    sm: *SurfaceMesh,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    vertex_gaussian_curvature: SurfaceMesh.CellData(.vertex, f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.vertex).init(sm);
    defer it.deinit();
    while (it.next()) |vertex| {
        vertex_gaussian_curvature.valuePtr(vertex).* = vertexGaussianCurvature(
            sm,
            vertex,
            corner_angle,
        );
    }
}

/// Compute and return the mean curvature of the given vertex
/// using the edge-based discrete mean curvature formula.
pub fn vertexMeanCurvature(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    edge_length: SurfaceMesh.CellData(.edge, f32),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
) f32 {
    assert(vertex.cellType() == .vertex);
    var mc: f32 = 0.0;
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        const e: SurfaceMesh.Cell = .{ .edge = d };
        mc += edge_dihedral_angle.value(e) * edge_length.value(e) * 0.5;
    }
    return mc * 0.5;
}

/// Compute the mean curvatures of all vertices of the given SurfaceMesh
/// and store the results in the given vertex_mean_curvature data.
pub fn computeVertexMeanCurvatures(
    sm: *SurfaceMesh,
    edge_length: SurfaceMesh.CellData(.edge, f32),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
    vertex_mean_curvature: SurfaceMesh.CellData(.vertex, f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.vertex).init(sm);
    defer it.deinit();
    while (it.next()) |vertex| {
        vertex_mean_curvature.valuePtr(vertex).* = vertexMeanCurvature(
            sm,
            vertex,
            edge_length,
            edge_dihedral_angle,
        );
    }
}
