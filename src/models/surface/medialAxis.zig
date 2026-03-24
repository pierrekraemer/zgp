const std = @import("std");

const AppContext = @import("../../main.zig").AppContext;
const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const geometry_utils = @import("../../geometry/utils.zig");

const bvh = @import("../../geometry/bvh.zig");

pub fn shrinkingBall(
    sm_bvh: bvh.TrianglesBVH,
    p: Vec3f,
    n: Vec3f,
) ?Vec4f {
    var r = if (sm_bvh.intersectedSurfacePoint(.{ .origin = p, .direction = vec.mulScalar3f(n, -1.0) })) |sp| blk: {
        const ip = sp.readData(Vec3f, .vertex, sm_bvh.vertex_position);
        break :blk vec.norm3f(vec.sub3f(p, ip)) * 0.75;
    } else {
        return null;
    };
    var c = vec.sub3f(p, vec.mulScalar3f(n, r));
    var q = vec.sub3f(p, vec.mulScalar3f(n, 2.0 * r));
    var j: u32 = 0;
    while (true) {
        const q_next = sm_bvh.closestPoint(c);
        const dist = vec.norm3f(vec.sub3f(q_next, c));
        if (@abs(dist - r) < 1e-4 or vec.norm3f(vec.sub3f(q_next, q)) < 1e-4) { // TODO: use a better epsilon?
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
        if (j > 0 and sep_angle < 20.0 * std.math.pi / 180.0) { // TODO: use a better angle?
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
    return .{ c[0], c[1], c[2], r };
}

/// Compute the
pub fn computeVertexShrinkingBalls(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    sm_bvh: bvh.TrianglesBVH,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_shrinking_ball: SurfaceMesh.CellData(.vertex, ?Vec4f),
) !void {
    const Task = struct {
        const Task = @This();

        surface_mesh: *const SurfaceMesh,
        sm_bvh: bvh.TrianglesBVH,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_shrinking_ball: SurfaceMesh.CellData(.vertex, ?Vec4f),

        pub inline fn run(t: *const Task, vertex: SurfaceMesh.Cell) void {
            const n = t.vertex_normal.value(vertex);
            t.vertex_shrinking_ball.valuePtr(vertex).* = shrinkingBall(
                t.sm_bvh,
                vec.add3f(t.vertex_position.value(vertex), vec.mulScalar3f(n, -1e-4)),
                n,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelCellTaskRunner = try .init(sm, .vertex);
    defer pctr.deinit();
    try pctr.run(app_ctx, Task{
        .surface_mesh = sm,
        .sm_bvh = sm_bvh,
        .vertex_position = vertex_position,
        .vertex_normal = vertex_normal,
        .vertex_shrinking_ball = vertex_shrinking_ball,
    });
}
