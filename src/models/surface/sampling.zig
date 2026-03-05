const std = @import("std");
const assert = std.debug.assert;

const AppContext = @import("../../main.zig").AppContext;
const PointCloud = @import("../point/PointCloud.zig");
const SurfaceMesh = @import("../surface/SurfaceMesh.zig");
const SurfacePoint = @import("../surface/SurfacePoint.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const geometry_utils = @import("../../geometry/utils.zig");

/// Given a SurfaceMesh, fills the given PointCloud with points uniformly sampled on the surface.
/// The given PointCloud is supposed to be empty.
pub fn samplePointsOnSurface(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    pc: *PointCloud,
    point_position: PointCloud.CellData(Vec3f),
    sampling_density: f32,
) !void {
    _ = face_area;
    _ = sampling_density;
    var r = app_ctx.rng.random();
    var face_it = try SurfaceMesh.CellIterator(.face).init(sm);
    defer face_it.deinit();
    while (face_it.next()) |f| {
        // const area = face_area.value(f);
        // const nb_points: usize = @intFromFloat(area * sampling_density);
        // for (0..nb_points) |_| {
        const r1 = r.float(f32);
        const r2 = r.float(f32);
        const bcoords: Vec3f = .{ 1.0 - @sqrt(r1), @sqrt(r1) * (1.0 - r2), @sqrt(r1) * r2 };
        const sp: SurfacePoint = .{
            .surface_mesh = sm,
            .type = .{
                .face = .{ .cell = f, .bcoords = bcoords },
            },
        };
        const pos = sp.interpolate(Vec3f, vertex_position);
        const p = try pc.addPoint();
        point_position.valuePtr(p).* = pos;
        // }
    }
}
