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

intrinsic_surface_mesh: *SurfaceMesh = undefined,
intrinsic_vertex_sp: SurfaceMesh.CellData(.vertex, SurfacePoint) = undefined,
intrinsic_edge_length: SurfaceMesh.CellData(.edge, f32) = undefined,

pub fn init(
    extrinsic_surface_mesh: *SurfaceMesh,
    extrinsic_vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
) !IntrinsicTriangulation {
    var it = .{
        .extrinsic_surface_mesh = extrinsic_surface_mesh,
        .extrinsic_vertex_position = extrinsic_vertex_position,
    };

    var ism = try extrinsic_surface_mesh.allocator.create(SurfaceMesh);
    errdefer extrinsic_surface_mesh.allocator.destroy(ism);
    ism.* = try .init(extrinsic_surface_mesh.allocator, extrinsic_surface_mesh.cell_buffer_pool);
    errdefer ism.deinit();

    ism.copyConnectivity(extrinsic_surface_mesh);

    const edge_length = try ism.addData(.edge, f32, "length");

    it.intrinsic_edge_length = edge_length;
    it.intrinsic_surface_mesh = ism;
    return it;
}
