const std = @import("std");
const assert = std.debug.assert;

const AppContext = @import("../../main.zig").AppContext;
const PointCloud = @import("PointCloud.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const geometry_utils = @import("../../geometry/utils.zig");

/// Compute the tangent bases of all vertices of the given SurfaceMesh
/// and store them in the given vertex_tangent_basis data.
pub fn computePointTangentBases(
    app_ctx: *AppContext,
    pc: *PointCloud,
    point_normal: PointCloud.CellData(Vec3f),
    point_tangent_basis: PointCloud.CellData([2]Vec3f),
) !void {
    const Task = struct {
        const Task = @This();

        point_cloud: *const PointCloud,
        point_normal: PointCloud.CellData(Vec3f),
        point_tangent_basis: PointCloud.CellData([2]Vec3f),

        pub fn run(t: *const Task, point: PointCloud.Point) void {
            t.point_tangent_basis.valuePtr(point).* = geometry_utils.tangentBasis(t.point_normal.value(point));
        }
    };

    var pctr: PointCloud.ParallelPointTaskRunner = try .init(pc);
    defer pctr.deinit();
    try pctr.run(app_ctx, Task{
        .point_cloud = pc,
        .point_normal = point_normal,
        .point_tangent_basis = point_tangent_basis,
    });
}
