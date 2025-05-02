const std = @import("std");

const Self = @This();

pub const PointCloud = @import("point/PointCloud.zig");
pub const SurfaceMesh = @import("surface/SurfaceMesh.zig");

allocator: std.mem.Allocator,

point_clouds: std.StringHashMap(*PointCloud),
surface_meshes: std.StringHashMap(*SurfaceMesh),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
        .point_clouds = std.StringHashMap(*PointCloud).init(allocator),
        .surface_meshes = std.StringHashMap(*SurfaceMesh).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var pc_it = self.point_clouds.iterator();
    while (pc_it.next()) |entry| {
        const pc = entry.value_ptr.*;
        pc.deinit();
        self.allocator.destroy(pc);
    }
    self.point_clouds.deinit();
    var sm_it = self.surface_meshes.iterator();
    while (sm_it.next()) |entry| {
        const sm = entry.value_ptr.*;
        sm.deinit();
        self.allocator.destroy(sm);
    }
    self.surface_meshes.deinit();
}

pub fn createPointCloud(self: *Self, name: []const u8) !*PointCloud {
    const maybe_point_cloud = self.point_clouds.get(name);
    if (maybe_point_cloud) |_| {
        return error.ModelNameAlreadyExists;
    }
    const pc = try self.allocator.create(PointCloud);
    pc.* = try PointCloud.init(self.allocator);
    try self.point_clouds.put(name, pc);
    return pc;
}

pub fn loadPointCloudFromFile(self: *Self, filename: []const u8) !*PointCloud {
    const pc = try self.createPointCloud(filename);
    // read the file and fill the point cloud
    return pc;
}

pub fn createSurfaceMesh(self: *Self, name: []const u8) !*SurfaceMesh {
    const maybe_surface_mesh = self.surface_meshes.get(name);
    if (maybe_surface_mesh) |_| {
        return error.ModelNameAlreadyExists;
    }
    const sm = try self.allocator.create(SurfaceMesh);
    sm.* = try SurfaceMesh.init(self.allocator);
    try self.surface_meshes.put(name, sm);
    return sm;
}

pub fn loadSurfaceMeshFromFile(self: *Self, filename: []const u8) !*SurfaceMesh {
    const sm = try self.createSurfaceMesh(filename);
    // read the file and fill the surface mesh
    return sm;
}
