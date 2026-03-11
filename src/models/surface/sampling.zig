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
    point_surface_point: PointCloud.CellData(SurfacePoint),
    nb_points: usize,
) !void {
    // ensure the inactive indices in the face_area data count
    // for 0 proportion in the subsequent weightedIndex call
    face_area.data.fillInactive(0.0);
    // store a face Cell in the face data container
    // so that an index in the face_area data can be mapped to a face Cell
    var faces = try sm.addData(.face, SurfaceMesh.Cell, "face");
    defer sm.removeData(.face, faces.gen());
    var face_it = try SurfaceMesh.CellIterator(.face).init(sm);
    while (face_it.next()) |f| {
        faces.valuePtr(f).* = f;
    }
    var r = app_ctx.rng.random();
    for (0..nb_points) |_| {
        const p = try pc.addPoint();
        const r1 = r.float(f32);
        const r2 = r.float(f32);
        const sqrt_r1 = @sqrt(r1);
        const bcoords: Vec3f = .{ 1.0 - sqrt_r1, sqrt_r1 * (1.0 - r2), sqrt_r1 * r2 };
        const face_index: u32 = @intCast(r.weightedIndex(f32, face_area.data.data.items));
        const sp: SurfacePoint = .{
            .surface_mesh = sm,
            .type = .{
                .face = .{ .cell = faces.valueByIndex(face_index), .bcoords = bcoords },
            },
        };
        point_surface_point.valuePtr(p).* = sp;
        point_position.valuePtr(p).* = sp.readData(Vec3f, .vertex, vertex_position);
    }
}
