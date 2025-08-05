const std = @import("std");
const assert = std.debug.assert;

const ModelsRegistry = @import("../models/ModelsRegistry.zig");
const DataGen = @import("../utils/Data.zig").DataGen;

const mat = @import("../geometry/mat.zig");
const Mat4 = mat.Mat4;

const PointCloud = ModelsRegistry.PointCloud;
const PointCloudStandardData = ModelsRegistry.PointCloudStandardData;
const SurfaceMesh = ModelsRegistry.SurfaceMesh;
const SurfaceMeshStandardData = ModelsRegistry.SurfaceMeshStandardData;

const Self = @This();

ptr: *anyopaque, // pointer to the concrete Module
vtable: *const VTable,

const VTable = struct {
    name: *const fn (ptr: *anyopaque) []const u8,

    pointCloudAdded: *const fn (ptr: *anyopaque, point_cloud: *PointCloud) anyerror!void,
    pointCloudStandardDataChanged: *const fn (ptr: *anyopaque, point_cloud: *PointCloud, std_data: PointCloudStandardData) anyerror!void,

    surfaceMeshAdded: *const fn (ptr: *anyopaque, surface_mesh: *SurfaceMesh) anyerror!void,
    surfaceMeshStandardDataChanged: *const fn (ptr: *anyopaque, surface_mesh: *SurfaceMesh, std_data: SurfaceMeshStandardData) anyerror!void,
    surfaceMeshConnectivityUpdated: *const fn (ptr: *anyopaque, surface_mesh: *SurfaceMesh) anyerror!void,
    surfaceMeshDataUpdated: *const fn (ptr: *anyopaque, surface_mesh: *SurfaceMesh, cell_type: SurfaceMesh.CellType, data_gen: *const DataGen) anyerror!void,

    uiPanel: *const fn (ptr: *anyopaque) void,
    draw: *const fn (ptr: *anyopaque, view_matrix: Mat4, projection_matrix: Mat4) void,
};

pub fn init(ptr: anytype) Self {
    const Ptr = @TypeOf(ptr);
    const ptr_info = @typeInfo(Ptr);
    assert(ptr_info == .pointer); // Must be a pointer
    assert(ptr_info.pointer.size == .one); // Must be a single-item pointer
    assert(@typeInfo(ptr_info.pointer.child) == .@"struct"); // Must point to a struct
    const Module = ptr_info.pointer.child;

    const gen = struct {
        fn name(pointer: *anyopaque) []const u8 {
            if (!@hasDecl(Module, "name")) return "NoName Module";
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            return impl.name();
        }
        fn pointCloudAdded(pointer: *anyopaque, point_cloud: *PointCloud) !void {
            if (!@hasDecl(Module, "pointCloudAdded")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            try impl.pointCloudAdded(point_cloud);
        }
        fn pointCloudStandardDataChanged(pointer: *anyopaque, point_cloud: *PointCloud, std_data: PointCloudStandardData) !void {
            if (!@hasDecl(Module, "pointCloudStandardDataChanged")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            try impl.pointCloudStandardDataChanged(point_cloud, std_data);
        }
        fn surfaceMeshAdded(pointer: *anyopaque, surface_mesh: *SurfaceMesh) !void {
            if (!@hasDecl(Module, "surfaceMeshAdded")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            try impl.surfaceMeshAdded(surface_mesh);
        }
        fn surfaceMeshStandardDataChanged(pointer: *anyopaque, surface_mesh: *SurfaceMesh, std_data: SurfaceMeshStandardData) !void {
            if (!@hasDecl(Module, "surfaceMeshStandardDataChanged")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            try impl.surfaceMeshStandardDataChanged(surface_mesh, std_data);
        }
        fn surfaceMeshConnectivityUpdated(pointer: *anyopaque, surface_mesh: *SurfaceMesh) !void {
            if (!@hasDecl(Module, "surfaceMeshConnectivityUpdated")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            try impl.surfaceMeshConnectivityUpdated(surface_mesh);
        }
        fn surfaceMeshDataUpdated(pointer: *anyopaque, surface_mesh: *SurfaceMesh, cell_type: SurfaceMesh.CellType, data_gen: *const DataGen) !void {
            if (!@hasDecl(Module, "surfaceMeshDataUpdated")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            try impl.surfaceMeshDataUpdated(surface_mesh, cell_type, data_gen);
        }
        fn uiPanel(pointer: *anyopaque) void {
            if (!@hasDecl(Module, "uiPanel")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.uiPanel();
        }
        fn draw(pointer: *anyopaque, view_matrix: Mat4, projection_matrix: Mat4) void {
            if (!@hasDecl(Module, "draw")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.draw(view_matrix, projection_matrix);
        }
    };

    return .{
        .ptr = ptr,
        .vtable = &.{
            .name = gen.name,
            .pointCloudAdded = gen.pointCloudAdded,
            .pointCloudStandardDataChanged = gen.pointCloudStandardDataChanged,
            .surfaceMeshAdded = gen.surfaceMeshAdded,
            .surfaceMeshStandardDataChanged = gen.surfaceMeshStandardDataChanged,
            .surfaceMeshConnectivityUpdated = gen.surfaceMeshConnectivityUpdated,
            .surfaceMeshDataUpdated = gen.surfaceMeshDataUpdated,
            .uiPanel = gen.uiPanel,
            .draw = gen.draw,
        },
    };
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
}

pub fn name(self: *Self) []const u8 {
    return self.vtable.name(self.ptr);
}
pub fn pointCloudAdded(self: *Self, point_cloud: *PointCloud) !void {
    try self.vtable.pointCloudAdded(self.ptr, point_cloud);
}
pub fn pointCloudStandardDataChanged(self: *Self, point_cloud: *PointCloud, data: PointCloudStandardData) !void {
    try self.vtable.pointCloudStandardDataChanged(self.ptr, point_cloud, data);
}
pub fn surfaceMeshAdded(self: *Self, surface_mesh: *SurfaceMesh) !void {
    try self.vtable.surfaceMeshAdded(self.ptr, surface_mesh);
}
pub fn surfaceMeshStandardDataChanged(self: *Self, surface_mesh: *SurfaceMesh, data: SurfaceMeshStandardData) !void {
    try self.vtable.surfaceMeshStandardDataChanged(self.ptr, surface_mesh, data);
}
pub fn surfaceMeshConnectivityUpdated(self: *Self, surface_mesh: *SurfaceMesh) !void {
    try self.vtable.surfaceMeshConnectivityUpdated(self.ptr, surface_mesh);
}
pub fn surfaceMeshDataUpdated(self: *Self, surface_mesh: *SurfaceMesh, cell_type: SurfaceMesh.CellType, data_gen: *const DataGen) !void {
    try self.vtable.surfaceMeshDataUpdated(self.ptr, surface_mesh, cell_type, data_gen);
}
pub fn uiPanel(self: *Self) void {
    self.vtable.uiPanel(self.ptr);
}
pub fn draw(self: *Self, view_matrix: Mat4, projection_matrix: Mat4) void {
    self.vtable.draw(self.ptr, view_matrix, projection_matrix);
}
