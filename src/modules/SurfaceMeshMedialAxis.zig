const SurfaceMeshMedialAxis = @This();

const std = @import("std");

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
    vertex_sqem: ?SurfaceMesh.CellData(.vertex, SQEM) = null,
    spheres: ?*PointCloud = null,
    sphere_position: ?PointCloud.CellData(Vec3f) = null,
    sphere_radius: ?PointCloud.CellData(f32) = null,
    initialized: bool = false,

    pub fn initFromSurfaceMesh(
        self: *MedialAxisData,
        surface_mesh: *SurfaceMesh,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        face_area: SurfaceMesh.CellData(.face, f32),
        face_normal: SurfaceMesh.CellData(.face, Vec3f),
    ) !void {
        if (self.vertex_sqem == null) {
            self.vertex_sqem = try surface_mesh.addData(.vertex, SQEM, "__vertex_sqem");
        }
        try sqem.computeVertexSQEMs(
            surface_mesh,
            vertex_position,
            face_area,
            face_normal,
            self.vertex_sqem.?,
        );
        if (self.spheres == null) {
            self.spheres = try zgp.point_cloud_store.createPointCloud("__medial_axis_spheres");
            self.sphere_position = try self.spheres.?.addData(Vec3f, "position");
            self.sphere_radius = try self.spheres.?.addData(f32, "radius");
        }
        self.spheres.?.clearRetainingCapacity();
        self.initialized = true;
    }

    pub fn deinit(self: *MedialAxisData, surface_mesh: *SurfaceMesh) void {
        if (self.vertex_sqem) |v_sqem| {
            surface_mesh.removeData(.vertex, v_sqem.gen());
        }
        if (self.spheres) |pc| {
            zgp.point_cloud_store.destroyPointCloud(pc); // PointCloud deinit handles its CellData automatically
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
    smma.surface_meshes_data.put(surface_mesh, .{}) catch |err| {
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
        if (ma_data.initialized) {
            c.ImGui_Text("Data initialized");
        } else {
            const disabled =
                info.std_data.vertex_position == null or
                info.std_data.face_area == null or
                info.std_data.face_normal == null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Initialize data", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                _ = ma_data.initFromSurfaceMesh(
                    sm,
                    info.std_data.vertex_position.?,
                    info.std_data.face_area.?,
                    info.std_data.face_normal.?,
                ) catch |err| {
                    std.debug.print("Failed to compute Medial Axis for SurfaceMesh: {}\n", .{err});
                };
            }
            if (disabled) {
                c.ImGui_EndDisabled();
            }
        }
    } else {
        c.ImGui_Text("No SurfaceMesh selected");
    }
}
