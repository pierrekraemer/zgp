const std = @import("std");
const assert = std.debug.assert;

const AppContext = @import("../../main.zig").AppContext;
const PointCloud = @import("../point/PointCloud.zig");
const SurfaceMesh = @import("../surface/SurfaceMesh.zig");
const SurfacePoint = @import("../surface/SurfacePoint.zig");

const geometry_utils = @import("../../geometry/utils.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const bvh = @import("../../geometry/bvh.zig");

/// Given a SurfaceMesh, fills the given PointCloud with points uniformly sampled on the surface.
/// The given PointCloud is supposed to be empty.
pub fn uniformlySamplePointsOnSurface(
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

pub fn poissonDiskSamplePointsOnSurface(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    sm_bvh: bvh.TrianglesBVH,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    pc: *PointCloud,
    point_position: PointCloud.CellData(Vec3f),
    point_surface_point: PointCloud.CellData(SurfacePoint),
    min_distance: f32,
) !void {
    if (sm.nbCells(.face) == 0) return;

    const bb_min, const bb_max = geometry_utils.boundingBox(vertex_position.data);
    const center = vec.mulScalar3f(vec.add3f(bb_min, bb_max), 0.5);

    const grid_unit_size = min_distance / @sqrt(3.0);
    var grid: std.AutoHashMap([3]i32, Vec3f) = .init(app_ctx.allocator);
    defer grid.deinit();

    var active_points: std.ArrayList(SurfacePoint) = try .initCapacity(app_ctx.allocator, 1024);
    defer active_points.deinit(app_ctx.allocator);

    var face_it = try SurfaceMesh.CellIterator(.face).init(sm);
    {
        const f = face_it.next().?; // get the first face of the SurfaceMesh
        const sp: SurfacePoint = .{ // and init a SurfacePoint at its center
            .surface_mesh = sm,
            .type = .{
                .face = .{ .cell = f, .bcoords = .{ 1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0 } },
            },
        };
        const p = try pc.addPoint(); // add the point to the PointCloud
        point_surface_point.valuePtr(p).* = sp;
        const pos = sp.readData(Vec3f, .vertex, vertex_position);
        point_position.valuePtr(p).* = pos;
        try active_points.append(app_ctx.allocator, sp); // add the SurfacePoint to the active list
        const pos_grid_coord = vec.divScalar3f(vec.sub3f(pos, center), grid_unit_size);
        const grid_idx: [3]i32 = .{
            @intFromFloat(pos_grid_coord[0]),
            @intFromFloat(pos_grid_coord[1]),
            @intFromFloat(pos_grid_coord[2]),
        };
        try grid.put(grid_idx, pos); // add the point in the spatial grid
    }

    var r = app_ctx.rng.random();
    while (active_points.items.len > 0) {
        const idx = r.intRangeLessThan(u32, 0, @intCast(active_points.items.len));
        const sp = active_points.items[idx];
        const f = sp.type.face.cell; // active point are face SurfacePoints
        const f_basis_X: Vec3f = vec.normalized3f(vec.sub3f(
            vertex_position.value(.{ .vertex = f.dart() }),
            vertex_position.value(.{ .vertex = sm.phi1(f.dart()) }),
        ));
        const f_basis_Y: Vec3f = vec.normalized3f(vec.cross3f(face_normal.value(f), f_basis_X));
        const pos = sp.readData(Vec3f, .vertex, vertex_position);
        var new_point_added = false;
        // 30 attempts to find a valid candidate point around the current point
        for (0..30) |_| {
            const angle = r.float(f32) * std.math.pi * 2.0;
            const dist = r.float(f32) * min_distance + min_distance;
            const candidate_pos_tangent = vec.add3f(pos, vec.add3f(
                vec.mulScalar3f(f_basis_X, dist * @cos(angle)),
                vec.mulScalar3f(f_basis_Y, dist * @sin(angle)),
            ));
            const candidate_pos, const candidate_sp = sm_bvh.closestPointWithSurfacePoint(candidate_pos_tangent);
            const candidate_pos_grid_coord = vec.divScalar3f(vec.sub3f(candidate_pos, center), grid_unit_size);
            var candidate_is_valid = true;
            for (0..3) |x| blk: {
                for (0..3) |y| {
                    for (0..3) |z| {
                        const dx: i32 = @as(i32, @intCast(x)) - 1;
                        const dy: i32 = @as(i32, @intCast(y)) - 1;
                        const dz: i32 = @as(i32, @intCast(z)) - 1;
                        const grid_idx: [3]i32 = .{
                            @as(i32, @intFromFloat(candidate_pos_grid_coord[0])) + dx,
                            @as(i32, @intFromFloat(candidate_pos_grid_coord[1])) + dy,
                            @as(i32, @intFromFloat(candidate_pos_grid_coord[2])) + dz,
                        };
                        if (grid.get(grid_idx)) |p| {
                            if (vec.norm3f(vec.sub3f(candidate_pos, p)) < min_distance) {
                                candidate_is_valid = false;
                                break :blk;
                            }
                        }
                    }
                }
            }
            if (candidate_is_valid) {
                const p = try pc.addPoint(); // add the point to the PointCloud
                point_surface_point.valuePtr(p).* = candidate_sp;
                point_position.valuePtr(p).* = candidate_pos;
                try active_points.append(app_ctx.allocator, candidate_sp); // add the SurfacePoint to the active list
                const grid_idx: [3]i32 = .{
                    @intFromFloat(candidate_pos_grid_coord[0]),
                    @intFromFloat(candidate_pos_grid_coord[1]),
                    @intFromFloat(candidate_pos_grid_coord[2]),
                };
                try grid.put(grid_idx, candidate_pos); // add the point in the spatial grid
                new_point_added = true;
                break;
            }
        }
        // or remove the point from the active list
        if (!new_point_added) {
            _ = active_points.swapRemove(idx);
        }
    }
}
