const std = @import("std");

const AppContext = @import("../../main.zig").AppContext;
const PointCloud = @import("PointCloud.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const geometry_utils = @import("../../geometry/utils.zig");

const kdtree = @import("../../geometry/kdtree.zig");

pub fn shrinkingBall(
    pc_kdtree: *kdtree.PointsKDTree,
    p: Vec3f,
    n: Vec3f,
) ?Vec4f {
    var r: f32 = 0.5; // TODO: arbitrary value for the initial radius
    var c = vec.sub3f(p, vec.mulScalar3f(n, r));
    var q = vec.sub3f(p, vec.mulScalar3f(n, 2.0 * r));
    var j: u32 = 0;
    while (true) {
        const q_next = pc_kdtree.nearestNeighbor(c) orelse return null;
        const dist = vec.norm3f(vec.sub3f(q_next, c));
        if (@abs(dist - r) < 1e-4 or vec.norm3f(vec.sub3f(q_next, q)) < 1e-4 or vec.norm3f(vec.sub3f(p, q_next)) < 1e-4) { // TODO: use a better epsilon?
            break;
        }
        const r_next = blk: {
            const qp = vec.sub3f(p, q_next);
            const d = vec.norm3f(qp);
            const cos_theta = geometry_utils.cosAngle(n, qp);
            break :blk d / (2.0 * cos_theta);
        };
        const c_next = vec.sub3f(p, vec.mulScalar3f(n, r_next));
        const sep_angle = geometry_utils.angle(vec.sub3f(p, c_next), vec.sub3f(q_next, c_next));
        if (j > 0 and sep_angle < 35.0 * std.math.pi / 180.0) { // TODO: use a configurable angle threshold?
            break;
        }
        r = r_next;
        c = c_next;
        q = q_next;
        j += 1;
        if (j > 30) {
            std.debug.print("Shrinking ball: too many iterations\n", .{});
            break;
        }
    }
    if (vec.norm3f(vec.sub3f(p, q)) < 1e-4) {
        std.debug.print("Warning: shrinking ball center is too close to the point\n", .{});
    }
    return .{ c[0], c[1], c[2], r };
}

/// Compute the shrinking balls for all points of the given PointCloud
pub fn computePointShrinkingBalls(
    app_ctx: *AppContext,
    pc: *PointCloud,
    pc_kdtree: *kdtree.PointsKDTree,
    point_position: PointCloud.CellData(Vec3f),
    point_normal: PointCloud.CellData(Vec3f),
    point_shrinking_ball: PointCloud.CellData(?Vec4f),
) !void {
    const Task = struct {
        const Task = @This();

        point_cloud: *const PointCloud,
        pc_kdtree: *kdtree.PointsKDTree,
        point_position: PointCloud.CellData(Vec3f),
        point_normal: PointCloud.CellData(Vec3f),
        point_shrinking_ball: PointCloud.CellData(?Vec4f),

        pub fn run(t: *const Task, point: PointCloud.Point) void {
            const n = t.point_normal.value(point);
            t.point_shrinking_ball.valuePtr(point).* = shrinkingBall(
                t.pc_kdtree,
                vec.add3f(t.point_position.value(point), vec.mulScalar3f(n, -1e-4)),
                n,
            );
        }
    };

    var pctr: PointCloud.ParallelPointTaskRunner = try .init(pc);
    defer pctr.deinit();
    try pctr.run(app_ctx, Task{
        .point_cloud = pc,
        .pc_kdtree = pc_kdtree,
        .point_position = point_position,
        .point_normal = point_normal,
        .point_shrinking_ball = point_shrinking_ball,
    });
}
