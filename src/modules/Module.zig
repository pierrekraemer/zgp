const std = @import("std");
const zm = @import("zmath");
const assert = std.debug.assert;

const ModelsRegistry = @import("../models/ModelsRegistry.zig");

const PointCloud = ModelsRegistry.PointCloud;
const PointCloudStandardData = ModelsRegistry.PointCloudStandardData;
const SurfaceMesh = ModelsRegistry.SurfaceMesh;
const SurfaceMeshStandardData = ModelsRegistry.SurfaceMeshStandardData;

const Self = @This();

ptr: *anyopaque, // pointer to the concrete Module
vtable: *const VTable,

const VTable = struct {
    pointCloudAdded: *const fn (ptr: *anyopaque, point_cloud: *PointCloud) anyerror!void,
    pointCloudStandardDataChanged: *const fn (ptr: *anyopaque, point_cloud: *PointCloud, data: PointCloudStandardData) void,

    surfaceMeshAdded: *const fn (ptr: *anyopaque, surface_mesh: *SurfaceMesh) anyerror!void,
    surfaceMeshStandardDataChanged: *const fn (ptr: *anyopaque, surface_mesh: *SurfaceMesh, data: SurfaceMeshStandardData) void,

    uiPanel: *const fn (ptr: *anyopaque) void,
    draw: *const fn (ptr: *anyopaque, view_matrix: zm.Mat, projection_matrix: zm.Mat) void,
};

pub fn init(ptr: anytype) Self {
    const Ptr = @TypeOf(ptr);
    const ptr_info = @typeInfo(Ptr);
    assert(ptr_info == .pointer); // Must be a pointer
    assert(ptr_info.pointer.size == .one); // Must be a single-item pointer
    assert(@typeInfo(ptr_info.pointer.child) == .@"struct"); // Must point to a struct
    const Module = ptr_info.pointer.child;

    const gen = struct {
        fn pointCloudAdded(pointer: *anyopaque, point_cloud: *PointCloud) !void {
            if (!@hasDecl(Module, "pointCloudAdded")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            try impl.pointCloudAdded(point_cloud);
        }
        fn pointCloudStandardDataChanged(pointer: *anyopaque, point_cloud: *PointCloud, data: PointCloudStandardData) void {
            if (!@hasDecl(Module, "pointCloudStandardDataChanged")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.pointCloudStandardDataChanged(point_cloud, data);
        }
        fn surfaceMeshAdded(pointer: *anyopaque, surface_mesh: *SurfaceMesh) !void {
            if (!@hasDecl(Module, "surfaceMeshAdded")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            try impl.surfaceMeshAdded(surface_mesh);
        }
        fn surfaceMeshStandardDataChanged(pointer: *anyopaque, surface_mesh: *SurfaceMesh, data: SurfaceMeshStandardData) void {
            if (!@hasDecl(Module, "surfaceMeshStandardDataChanged")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.surfaceMeshStandardDataChanged(surface_mesh, data);
        }
        fn uiPanel(pointer: *anyopaque) void {
            if (!@hasDecl(Module, "uiPanel")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.uiPanel();
        }
        fn draw(pointer: *anyopaque, view_matrix: zm.Mat, projection_matrix: zm.Mat) void {
            if (!@hasDecl(Module, "draw")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.draw(view_matrix, projection_matrix);
        }
    };

    return .{
        .ptr = ptr,
        .vtable = &.{
            .pointCloudAdded = gen.pointCloudAdded,
            .pointCloudStandardDataChanged = gen.pointCloudStandardDataChanged,
            .surfaceMeshAdded = gen.surfaceMeshAdded,
            .surfaceMeshStandardDataChanged = gen.surfaceMeshStandardDataChanged,
            .uiPanel = gen.uiPanel,
            .draw = gen.draw,
        },
    };
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
}

pub fn pointCloudAdded(self: *Self, point_cloud: *PointCloud) !void {
    try self.vtable.pointCloudAdded(self.ptr, point_cloud);
}
pub fn pointCloudStandardDataChanged(self: *Self, point_cloud: *PointCloud, data: PointCloudStandardData) void {
    self.vtable.pointCloudStandardDataChanged(self.ptr, point_cloud, data);
}
pub fn surfaceMeshAdded(self: *Self, surface_mesh: *SurfaceMesh) !void {
    try self.vtable.surfaceMeshAdded(self.ptr, surface_mesh);
}
pub fn surfaceMeshStandardDataChanged(self: *Self, surface_mesh: *SurfaceMesh, data: SurfaceMeshStandardData) void {
    self.vtable.surfaceMeshStandardDataChanged(self.ptr, surface_mesh, data);
}
pub fn uiPanel(self: *Self) void {
    self.vtable.uiPanel(self.ptr);
}
pub fn draw(self: *Self, view_matrix: zm.Mat, projection_matrix: zm.Mat) void {
    self.vtable.draw(self.ptr, view_matrix, projection_matrix);
}
