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

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const SQEM = @import("../geometry/sqem.zig").SQEM;

const sqem = @import("../models/surface/sqem.zig");

const MedialAxisData = struct {
    surface_mesh: *const SurfaceMesh,
    vertex_position: ?SurfaceMesh.CellData(.vertex, Vec3f) = null,
    vertex_area: ?SurfaceMesh.CellData(.vertex, f32) = null,
    vertex_sqem: ?SurfaceMesh.CellData(.vertex, SQEM) = null,
    vertex_sphere: ?SurfaceMesh.CellData(.vertex, ?PointCloud.Point) = null,
    spheres: ?*PointCloud = null,
    sphere_position: ?PointCloud.CellData(Vec3f) = null,
    sphere_radius: ?PointCloud.CellData(f32) = null,
    sphere_color: ?PointCloud.CellData(Vec3f) = null,
    sphere_cluster: ?PointCloud.CellData(std.ArrayList(SurfaceMesh.Cell)) = null,
    initialized: bool = false,

    const lambda: f32 = 0.2; // weight for the euclidean distance in the metric

    pub fn initFromSurfaceMesh(
        self: *MedialAxisData,
        surface_mesh: *SurfaceMesh,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        vertex_area: SurfaceMesh.CellData(.vertex, f32),
        face_area: SurfaceMesh.CellData(.face, f32),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),
    ) !void {
        self.vertex_position = vertex_position;
        self.vertex_area = vertex_area;
        if (self.vertex_sqem == null) {
            self.vertex_sqem = try surface_mesh.addData(.vertex, SQEM, "__vertex_sqem");
            self.vertex_sphere = try surface_mesh.addData(.vertex, ?PointCloud.Point, "__vertex_sphere");
        }
        try sqem.computeVertexSQEMs(
            surface_mesh,
            vertex_position,
            face_area,
            face_normal,
            self.vertex_sqem.?,
        );
        if (self.spheres == null) {
            var buf: [64]u8 = undefined;
            const pc_name = std.fmt.bufPrintZ(&buf, "{s}_ma_spheres", .{zgp.surface_mesh_store.surfaceMeshName(surface_mesh).?}) catch "__ma_spheres";
            self.spheres = try zgp.point_cloud_store.createPointCloud(pc_name);
            self.sphere_position = try self.spheres.?.addData(Vec3f, "position");
            self.sphere_radius = try self.spheres.?.addData(f32, "radius");
            self.sphere_color = try self.spheres.?.addData(Vec3f, "color");
            self.sphere_cluster = try self.spheres.?.addData(std.ArrayList(SurfaceMesh.Cell), "cluster");
            zgp.point_cloud_store.setPointCloudStdData(self.spheres.?, .{ .position = self.sphere_position.? });
            zgp.point_cloud_store.setPointCloudStdData(self.spheres.?, .{ .radius = self.sphere_radius.? });
            zgp.point_cloud_store.setPointCloudStdData(self.spheres.?, .{ .color = self.sphere_color.? });
        } else {
            self.spheres.?.clearRetainingCapacity();
        }
        const s1 = try self.spheres.?.addPoint(); // create the first sphere
        self.sphere_position.?.valuePtr(s1).* = .{ 0.0, 0.0, 0.0 };
        self.sphere_radius.?.valuePtr(s1).* = 1.0;
        var r = zgp.rng.random();
        self.sphere_color.?.valuePtr(s1).* = .{ 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32), 0.5 + 0.5 * r.float(f32) };
        self.sphere_cluster.?.valuePtr(s1).* = .empty;
        self.initialized = true;

        zgp.point_cloud_store.pointCloudConnectivityUpdated(self.spheres.?);
        zgp.point_cloud_store.pointCloudDataUpdated(self.spheres.?, Vec3f, self.sphere_position.?);
        zgp.point_cloud_store.pointCloudDataUpdated(self.spheres.?, f32, self.sphere_radius.?);
        zgp.point_cloud_store.pointCloudDataUpdated(self.spheres.?, Vec3f, self.sphere_color.?);
    }

    pub fn deinit(self: *MedialAxisData, surface_mesh: *SurfaceMesh) void {
        if (self.vertex_sqem) |v_sqem| {
            surface_mesh.removeData(.vertex, v_sqem.gen());
        }
        if (self.vertex_sphere) |v_sphere| {
            surface_mesh.removeData(.vertex, v_sphere.gen());
        }
        if (self.spheres) |pc| {
            zgp.point_cloud_store.destroyPointCloud(pc); // PointCloud deinit handles its CellData automatically
        }
    }

    pub fn computeClusters(self: *MedialAxisData) !void {
        assert(self.initialized);
        if (self.spheres.?.nbPoints() == 0) {
            return;
        }
        // clean up previous clusters
        self.vertex_sphere.?.data.fill(null);
        var it = self.sphere_cluster.?.data.iterator();
        while (it.next()) |*cluster| {
            cluster.*.clearRetainingCapacity();
        }
        // compute new clusters
        var v_it = SurfaceMesh.CellIterator(.vertex).init(self.surface_mesh);
        defer v_it.deinit();
        while (v_it.next()) |v| {
            const vp = self.vertex_position.?.value(v);
            const va = self.vertex_area.?.value(v);
            var min_distance = std.math.floatMax(f32);
            var min_sphere: PointCloud.Point = undefined;
            var s_it = self.spheres.?.pointIterator();
            while (s_it.next()) |s| {
                const sp = self.sphere_position.?.value(s);
                const sr = self.sphere_radius.?.value(s);
                const dist_euclidean = vec.norm3f(vec.sub3f(vp, sp)) - sr;
                const squared_dist_euclidean = dist_euclidean * dist_euclidean * va; // weighted by vertex area
                const dist_sqem = self.vertex_sqem.?.value(v).eval(.{ sp[0], sp[1], sp[2], sr });
                const dist = dist_sqem + lambda * squared_dist_euclidean;
                if (dist < min_distance) {
                    min_distance = dist;
                    min_sphere = s;
                }
            }
            self.vertex_sphere.?.valuePtr(v).* = min_sphere;
            try self.sphere_cluster.?.valuePtr(min_sphere).append(self.sphere_cluster.?.data.arena(), v);
        }
        // check clusters sizes
        var s_it = self.spheres.?.pointIterator();
        while (s_it.next()) |s| {
            if (self.sphere_cluster.?.valuePtr(s).items.len < 4) {
                for (self.sphere_cluster.?.value(s)) |v| {
                    self.vertex_sphere.?.valuePtr(v).* = null;
                }
                self.spheres.?.removePoint(s); // it is safe to remove the point while iterating
            }
        }
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

surface_meshes_data: std.AutoHashMap(*SurfaceMesh, MedialAxisData),

pub fn init(allocator: std.mem.Allocator) SurfaceMeshMedialAxis {
    return .{
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
    } else {
        c.ImGui_Text("No SurfaceMesh selected");
    }
}
