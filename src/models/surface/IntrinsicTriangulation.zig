const IntrinsicTriangulation = @This();

const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const Cell = SurfaceMesh.Cell;
const SurfacePoint = @import("SurfacePoint.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const geometry_utils = @import("../../geometry/utils.zig");

extrinsic_surface_mesh: *SurfaceMesh,
extrinsic_vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),

intrinsic_triangulation: *SurfaceMesh,
intrinsic_vertex_sp: SurfaceMesh.CellData(.vertex, SurfacePoint),
intrinsic_edge_length: SurfaceMesh.CellData(.edge, f32),

pub fn init(
    extrinsic_surface_mesh: *SurfaceMesh,
    extrinsic_vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    intrinsic_triangulation: *SurfaceMesh,
    intrinsic_vertex_sp: SurfaceMesh.CellData(.vertex, SurfacePoint),
    intrinsic_edge_length: SurfaceMesh.CellData(.edge, f32),
) IntrinsicTriangulation {
    return .{
        .extrinsic_surface_mesh = extrinsic_surface_mesh,
        .extrinsic_vertex_position = extrinsic_vertex_position,
        .intrinsic_triangulation = intrinsic_triangulation,
        .intrinsic_vertex_sp = intrinsic_vertex_sp,
        .intrinsic_edge_length = intrinsic_edge_length,
    };
}
