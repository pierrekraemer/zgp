const std = @import("std");
const PointCloud = @import("point/PointCloud.zig");
const SurfaceMesh = @import("surface/SurfaceMesh.zig");

const Self = @This();

point_clouds: std.StringHashMap(*PointCloud),
surface_meshes: std.StringHashMap(*SurfaceMesh),

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .point_clouds = try std.StringHashMap(*PointCloud).init(allocator),
        .surface_meshes = try std.StringHashMap(*SurfaceMesh).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.point_clouds.deinit();
    self.surface_meshes.deinit();
}

pub fn register_point_cloud(self: *Self, name: []const u8, point_cloud: *PointCloud) !void {
    try self.point_clouds.put(name, point_cloud);
}

pub fn load_point_cloud_from_file(self: *Self, filename: []const u8) !*PointCloud {
    _ = self;
    _ = filename;
    return error.NotImplemented;
}

pub fn register_surface_mesh(self: *Self, name: []const u8, surface_mesh: *SurfaceMesh) !void {
    try self.surface_meshes.put(name, surface_mesh);
}

pub fn load_surface_mesh_from_file(self: *Self, filename: []const u8) !*SurfaceMesh {
    _ = self;
    _ = filename;
    return error.NotImplemented;
}
