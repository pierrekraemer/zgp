const std = @import("std");
const assert = std.debug.assert;

const AppContext = @import("../../main.zig").AppContext;
const PointCloud = @import("PointCloud.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const SQEM = @import("../../geometry/SQEM.zig");

/// Compute and return the SQEM of the given point.
pub fn pointSQEM(
    point: PointCloud.Point,
    point_position: PointCloud.CellData(Vec3f),
    point_normal: PointCloud.CellData(Vec3f),
    // point_area: PointCloud.CellData(f32),
    point_tangent_basis: PointCloud.CellData([2]Vec3f),
    line_quadric_epsilon: f32,
) SQEM {
    var vsq = SQEM.zero;
    const p = point_position.value(point);
    const n = point_normal.value(point);

    var fsq: SQEM = .initSpherePlaneDistance(p, n, 1.0); // point_area.value(point));
    vsq.add(&fsq);

    const tb = point_tangent_basis.value(point);
    const reg1: SQEM = .initCenterPlaneDistance(p, tb[0], line_quadric_epsilon * 1.0); // point_area.value(point));
    const reg2: SQEM = .initCenterPlaneDistance(p, tb[1], line_quadric_epsilon * 1.0); // point_area.value(point));
    vsq.add(&reg1);
    vsq.add(&reg2);
    return vsq;
}

/// Compute the SQEMs of all points of the given PointCloud
/// and store them in the given point_sqem data.
pub fn computePointSQEMs(
    app_ctx: *AppContext,
    pc: *PointCloud,
    point_position: PointCloud.CellData(Vec3f),
    point_normal: PointCloud.CellData(Vec3f),
    // point_area: PointCloud.CellData(f32),
    point_tangent_basis: PointCloud.CellData([2]Vec3f),
    line_quadric_epsilon: f32,
    point_sqem: PointCloud.CellData(SQEM),
) !void {
    const Task = struct {
        const Task = @This();

        point_position: PointCloud.CellData(Vec3f),
        point_normal: PointCloud.CellData(Vec3f),
        // point_area: PointCloud.CellData(f32),
        point_tangent_basis: PointCloud.CellData([2]Vec3f),
        line_quadric_epsilon: f32,
        point_sqem: PointCloud.CellData(SQEM),

        pub fn run(t: *const Task, point: PointCloud.Point) void {
            t.point_sqem.valuePtr(point).* = pointSQEM(
                point,
                t.point_position,
                t.point_normal,
                // t.point_area,
                t.point_tangent_basis,
                t.line_quadric_epsilon,
            );
        }
    };

    var pctr: PointCloud.ParallelPointTaskRunner = try .init(pc);
    defer pctr.deinit();
    try pctr.run(app_ctx, Task{
        .point_position = point_position,
        .point_normal = point_normal,
        // .point_area = point_area,
        .point_tangent_basis = point_tangent_basis,
        .line_quadric_epsilon = line_quadric_epsilon,
        .point_sqem = point_sqem,
    });
}
