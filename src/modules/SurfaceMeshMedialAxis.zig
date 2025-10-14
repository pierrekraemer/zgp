const SurfaceMeshMedialAxis = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../utils/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const zgp = @import("../main.zig");
const c = zgp.c;

const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const PointCloud = @import("../models/point/PointCloud.zig");

const eigen = @import("../geometry/eigen.zig");
const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4d = vec.Vec4d;
const SQEM = @import("../geometry/sqem.zig").SQEM;

const sqem = @import("../models/surface/sqem.zig");

const MedialAxisData = struct {
    surface_mesh: *SurfaceMesh,
    vertex_position: ?SurfaceMesh.CellData(.vertex, Vec3f) = null,
    vertex_area: ?SurfaceMesh.CellData(.vertex, f32) = null,
    vertex_sqem: ?SurfaceMesh.CellData(.vertex, SQEM) = null,
    vertex_sphere: ?SurfaceMesh.CellData(.vertex, ?PointCloud.Point) = null,
    face_area: ?SurfaceMesh.CellData(.face, f32) = null,
    face_normal: ?SurfaceMesh.CellData(.face, Vec3f) = null,
    spheres: ?*PointCloud = null,
    sphere_position: ?PointCloud.CellData(Vec3f) = null,
    sphere_radius: ?PointCloud.CellData(f32) = null,
    sphere_color: ?PointCloud.CellData(Vec3f) = null,
    sphere_cluster: ?PointCloud.CellData(std.ArrayList(SurfaceMesh.Cell)) = null,
    initialized: bool = false,

    const lambda: f32 = 0.2; // weight for the euclidean distance in the metric

    pub fn initFromSurfaceMesh(
        mad: *MedialAxisData,
        surface_mesh: *SurfaceMesh,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_area: SurfaceMesh.CellData(.vertex, f32),
        face_area: SurfaceMesh.CellData(.face, f32),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),
    ) !void {
        mad.vertex_position = vertex_position;
        mad.vertex_area = vertex_area;
        if (mad.vertex_sqem == null) {
            mad.vertex_sqem = try surface_mesh.addData(.vertex, SQEM, "__vertex_sqem");
            mad.vertex_sphere = try surface_mesh.addData(.vertex, ?PointCloud.Point, "__vertex_sphere");
        }
        mad.face_area = face_area;
        mad.face_normal = face_normal;
        try sqem.computeVertexSQEMs(
            surface_mesh,
            vertex_position,
            face_area,
            face_normal,
            mad.vertex_sqem.?,
        );
        if (mad.spheres == null) {
            var buf: [64]u8 = undefined;
            const pc_name = std.fmt.bufPrintZ(&buf, "{s}_ma_spheres", .{zgp.surface_mesh_store.surfaceMeshName(surface_mesh).?}) catch "__ma_spheres";
            mad.spheres = try zgp.point_cloud_store.createPointCloud(pc_name);
            mad.sphere_position = try mad.spheres.?.addData(Vec3f, "position");
            mad.sphere_radius = try mad.spheres.?.addData(f32, "radius");
            mad.sphere_color = try mad.spheres.?.addData(Vec3f, "color");
            mad.sphere_cluster = try mad.spheres.?.addData(std.ArrayList(SurfaceMesh.Cell), "cluster");
            zgp.point_cloud_store.setPointCloudStdData(mad.spheres.?, .{ .position = mad.sphere_position.? });
            zgp.point_cloud_store.setPointCloudStdData(mad.spheres.?, .{ .radius = mad.sphere_radius.? });
            // zgp.point_cloud_store.setPointCloudStdData(mad.spheres.?, .{ .color = mad.sphere_color.? });
        } else {
            mad.spheres.?.clearRetainingCapacity();
        }
        const s1 = try mad.spheres.?.addPoint(); // create the first sphere
        mad.sphere_position.?.valuePtr(s1).* = .{ 0.0, 0.0, 0.0 };
        mad.sphere_radius.?.valuePtr(s1).* = 0.01;
        var r = zgp.rng.random();
        mad.sphere_color.?.valuePtr(s1).* = .{ 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32) };
        mad.sphere_cluster.?.valuePtr(s1).* = .empty;
        mad.initialized = true;

        zgp.point_cloud_store.pointCloudConnectivityUpdated(mad.spheres.?);
        zgp.point_cloud_store.pointCloudDataUpdated(mad.spheres.?, Vec3f, mad.sphere_position.?);
        zgp.point_cloud_store.pointCloudDataUpdated(mad.spheres.?, f32, mad.sphere_radius.?);
        zgp.point_cloud_store.pointCloudDataUpdated(mad.spheres.?, Vec3f, mad.sphere_color.?);
    }

    pub fn deinit(mad: *MedialAxisData, surface_mesh: *SurfaceMesh) void {
        if (mad.vertex_sqem) |v_sqem| {
            surface_mesh.removeData(.vertex, v_sqem.gen());
        }
        if (mad.vertex_sphere) |v_sphere| {
            surface_mesh.removeData(.vertex, v_sphere.gen());
        }
        if (mad.spheres) |pc| {
            zgp.point_cloud_store.destroyPointCloud(pc); // PointCloud deinit handles its CellData automatically
        }
    }

    fn computeClusters(mad: *MedialAxisData) !void {
        assert(mad.initialized);
        if (mad.spheres.?.nbPoints() == 0) {
            return;
        }
        // clean up previous clusters
        mad.vertex_sphere.?.data.fill(null);
        var it = mad.sphere_cluster.?.data.iterator();
        while (it.next()) |*cluster| {
            cluster.*.clearRetainingCapacity();
        }
        // compute new clusters
        var v_it = try SurfaceMesh.CellIterator(.vertex).init(mad.surface_mesh);
        defer v_it.deinit();
        while (v_it.next()) |v| {
            const vp = mad.vertex_position.?.value(v);
            const va = mad.vertex_area.?.value(v);
            var min_distance = std.math.floatMax(f32);
            var min_sphere: PointCloud.Point = undefined;
            var s_it = mad.spheres.?.pointIterator();
            while (s_it.next()) |s| {
                const sp = mad.sphere_position.?.value(s);
                const sr = mad.sphere_radius.?.value(s);
                const dist_euclidean = vec.norm3f(vec.sub3f(vp, sp)) - sr;
                const squared_dist_euclidean = dist_euclidean * dist_euclidean * va; // weighted by vertex area
                const dist_sqem = mad.vertex_sqem.?.value(v).eval(.{ sp[0], sp[1], sp[2], sr });
                const dist = dist_sqem + lambda * squared_dist_euclidean;
                if (dist < min_distance) {
                    min_distance = dist;
                    min_sphere = s;
                }
            }
            mad.vertex_sphere.?.valuePtr(v).* = min_sphere;
            try mad.sphere_cluster.?.valuePtr(min_sphere).append(mad.sphere_cluster.?.data.arena(), v);
        }
        // check clusters sizes
        var s_it = mad.spheres.?.pointIterator();
        while (s_it.next()) |s| {
            if (mad.sphere_cluster.?.valuePtr(s).items.len < 4) {
                for (mad.sphere_cluster.?.valuePtr(s).items) |v| {
                    mad.vertex_sphere.?.valuePtr(v).* = null;
                }
                mad.spheres.?.removePoint(s); // it is safe to remove the point while iterating
            }
        }
    }

    pub fn updateSpheres(mad: *MedialAxisData, allocator: std.mem.Allocator) !void {
        assert(mad.initialized);
        try mad.computeClusters();
        var s_it = mad.spheres.?.pointIterator();
        while (s_it.next()) |s| {
            const cluster = mad.sphere_cluster.?.valuePtr(s);
            const sc = mad.sphere_position.?.value(s);
            const sr = mad.sphere_radius.?.value(s);
            var optimized_center: Vec3f = .{ sc[0], sc[1], sc[2] };
            var optimized_radius: f32 = sr;
            var J: eigen.DenseMatrix = .init(@intCast(2 * cluster.items.len), 4);
            defer J.deinit();
            var b = try allocator.alloc(f64, 2 * cluster.items.len);
            defer allocator.free(b);
            var x: [4]f64 = undefined;
            for (0..10) |_| {
                for (cluster.items, 0..) |v, idx| {
                    const vp = mad.vertex_position.?.value(v);
                    var lhs: Vec4d = undefined;
                    var rhs: f64 = undefined;
                    var dart_it = mad.surface_mesh.cellDartIterator(v);
                    while (dart_it.next()) |d| {
                        if (!mad.surface_mesh.isBoundaryDart(d)) {
                            const face: SurfaceMesh.Cell = .{ .face = d };
                            const n = mad.face_normal.?.value(face);
                            const a = mad.face_area.?.value(face) / 3.0;
                            lhs = vec.add4d(lhs, vec.mulScalar4d(Vec4d{ -n[0], -n[1], -n[2], -1.0 }, a));
                            rhs += @floatCast(-1.0 * (vec.dot3f(vec.sub3f(vp, optimized_center), n) - optimized_radius) * a);
                        }
                    }
                    J.setRow(@intCast(idx * 2), &lhs);
                    b[idx * 2] = rhs;
                    const d = vec.sub3f(vp, optimized_center);
                    const l = vec.norm3f(d);
                    const a = std.math.sqrt(mad.vertex_area.?.value(v));
                    lhs = vec.mulScalar4d(Vec4d{ -(d[0] / l), -(d[1] / l), -(d[2] / l), -1.0 }, a * lambda);
                    rhs = @floatCast(-(l - optimized_radius) * a * lambda);
                    J.setRow(@intCast(idx * 2 + 1), &lhs);
                    b[idx * 2 + 1] = rhs;
                }
                J.solveLeastSquares(b, &x);
                optimized_center = vec.add3f(optimized_center, .{ @floatCast(x[0]), @floatCast(x[1]), @floatCast(x[2]) });
                optimized_radius += @floatCast(x[3]);
                if (vec.norm4d(x) < 1e-6) {
                    break;
                }
            }
            mad.sphere_position.?.valuePtr(s).* = optimized_center;
            mad.sphere_radius.?.valuePtr(s).* = optimized_radius;
        }
        zgp.point_cloud_store.pointCloudDataUpdated(mad.spheres.?, Vec3f, mad.sphere_position.?);
        zgp.point_cloud_store.pointCloudDataUpdated(mad.spheres.?, f32, mad.sphere_radius.?);
    }
};

module: Module = .{
    .name = "Surface Mesh Medial Axis",
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .uiPanel = uiPanel,
    },
},

allocator: std.mem.Allocator,
surface_meshes_data: std.AutoHashMap(*SurfaceMesh, MedialAxisData),

pub fn init(allocator: std.mem.Allocator) SurfaceMeshMedialAxis {
    return .{
        .allocator = allocator,
        .surface_meshes_data = std.AutoHashMap(*SurfaceMesh, MedialAxisData).init(allocator),
    };
}

pub fn deinit(smma: *SurfaceMeshMedialAxis) void {
    var it = smma.surface_meshes_data.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit(entry.key_ptr.*);
    }
    smma.surface_meshes_data.deinit();
}

/// Part of the Module interface.
/// Create and store a MedialAxisData for the new SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smma: *SurfaceMeshMedialAxis = @alignCast(@fieldParentPtr("module", m));
    smma.surface_meshes_data.put(surface_mesh, .{
        .surface_mesh = surface_mesh,
    }) catch |err| {
        std.debug.print("Failed to store MedialAxisData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Remove and deinitialize the MedialAxisData for the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smma: *SurfaceMeshMedialAxis = @alignCast(@fieldParentPtr("module", m));
    const ma_data = smma.surface_meshes_data.getPtr(surface_mesh) orelse return;
    ma_data.deinit(surface_mesh);
    _ = smma.surface_meshes_data.remove(surface_mesh);
}

/// Part of the Module interface.
/// Describe the right-click menu interface.
pub fn uiPanel(m: *Module) void {
    const smma: *SurfaceMeshMedialAxis = @alignCast(@fieldParentPtr("module", m));
    const sms = &zgp.surface_mesh_store;

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (zgp.surface_mesh_store.selected_surface_mesh) |sm| {
        const info = sms.surfaceMeshInfo(sm);
        const ma_data = smma.surface_meshes_data.getPtr(sm).?;
        const disabled =
            info.std_data.vertex_position == null or
            info.std_data.vertex_area == null or
            info.std_data.face_area == null or
            info.std_data.face_normal == null;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx(if (ma_data.initialized) "Reinitialize data" else "Initialize data", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            _ = ma_data.initFromSurfaceMesh(
                sm,
                info.std_data.vertex_position.?,
                info.std_data.vertex_area.?,
                info.std_data.face_area.?,
                info.std_data.face_normal.?,
            ) catch |err| {
                std.debug.print("Failed to compute Medial Axis for SurfaceMesh: {}\n", .{err});
            };
        }
        if (disabled) {
            c.ImGui_EndDisabled();
        }
        if (ma_data.initialized) {
            if (c.ImGui_ButtonEx("Update spheres", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                ma_data.updateSpheres(smma.allocator) catch |err| {
                    std.debug.print("Failed to update Medial Axis spheres for SurfaceMesh: {}\n", .{err});
                };
            }
        }
    } else {
        c.ImGui_Text("No SurfaceMesh selected");
    }
}
