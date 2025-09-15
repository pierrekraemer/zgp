const Module = @This();

const std = @import("std");
const assert = std.debug.assert;

const ModelsRegistry = @import("../models/ModelsRegistry.zig");
const DataGen = @import("../utils/Data.zig").DataGen;

const mat = @import("../geometry/mat.zig");
const Mat4 = mat.Mat4;

const PointCloud = ModelsRegistry.PointCloud;
const PointCloudStdData = ModelsRegistry.PointCloudStdData;
const SurfaceMesh = ModelsRegistry.SurfaceMesh;
const SurfaceMeshStdData = ModelsRegistry.SurfaceMeshStdData;

ptr: *anyopaque, // pointer to the concrete Module
vtable: *const VTable,

const VTable = struct {
    name: *const fn (ptr: *anyopaque) []const u8,

    pointCloudAdded: *const fn (ptr: *anyopaque, point_cloud: *PointCloud) void,
    pointCloudStdDataChanged: *const fn (ptr: *anyopaque, point_cloud: *PointCloud, std_data: PointCloudStdData) void,
    pointCloudDataUpdated: *const fn (ptr: *anyopaque, point_cloud: *PointCloud, data_gen: *const DataGen) void,

    surfaceMeshAdded: *const fn (ptr: *anyopaque, surface_mesh: *SurfaceMesh) void,
    surfaceMeshStdDataChanged: *const fn (ptr: *anyopaque, surface_mesh: *SurfaceMesh, std_data: SurfaceMeshStdData) void,
    surfaceMeshConnectivityUpdated: *const fn (ptr: *anyopaque, surface_mesh: *SurfaceMesh) void,
    surfaceMeshDataUpdated: *const fn (ptr: *anyopaque, surface_mesh: *SurfaceMesh, cell_type: SurfaceMesh.CellType, data_gen: *const DataGen) void,

    uiPanel: *const fn (ptr: *anyopaque) void,
    menuBar: *const fn (ptr: *anyopaque) void,
    draw: *const fn (ptr: *anyopaque, view_matrix: Mat4, projection_matrix: Mat4) void,
};

pub fn init(ptr: anytype) Module {
    const Ptr = @TypeOf(ptr);
    const ptr_info = @typeInfo(Ptr);
    assert(ptr_info == .pointer); // Must be a pointer
    assert(ptr_info.pointer.size == .one); // Must be a single-item pointer
    assert(@typeInfo(ptr_info.pointer.child) == .@"struct"); // Must point to a struct
    const ModuleType = ptr_info.pointer.child;

    const gen = struct {
        fn name(pointer: *anyopaque) []const u8 {
            if (!@hasDecl(ModuleType, "name")) return "NoName Module";
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            return impl.name();
        }
        fn pointCloudAdded(pointer: *anyopaque, point_cloud: *PointCloud) void {
            if (!@hasDecl(ModuleType, "pointCloudAdded")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.pointCloudAdded(point_cloud);
        }
        fn pointCloudStdDataChanged(pointer: *anyopaque, point_cloud: *PointCloud, std_data: PointCloudStdData) void {
            if (!@hasDecl(ModuleType, "pointCloudStdDataChanged")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.pointCloudStdDataChanged(point_cloud, std_data);
        }
        fn pointCloudDataUpdated(pointer: *anyopaque, point_cloud: *PointCloud, data_gen: *const DataGen) void {
            if (!@hasDecl(ModuleType, "pointCloudDataUpdated")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.pointCloudDataUpdated(point_cloud, data_gen);
        }
        fn surfaceMeshAdded(pointer: *anyopaque, surface_mesh: *SurfaceMesh) void {
            if (!@hasDecl(ModuleType, "surfaceMeshAdded")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.surfaceMeshAdded(surface_mesh);
        }
        fn surfaceMeshStdDataChanged(pointer: *anyopaque, surface_mesh: *SurfaceMesh, std_data: SurfaceMeshStdData) void {
            if (!@hasDecl(ModuleType, "surfaceMeshStdDataChanged")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.surfaceMeshStdDataChanged(surface_mesh, std_data);
        }
        fn surfaceMeshConnectivityUpdated(pointer: *anyopaque, surface_mesh: *SurfaceMesh) void {
            if (!@hasDecl(ModuleType, "surfaceMeshConnectivityUpdated")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.surfaceMeshConnectivityUpdated(surface_mesh);
        }
        fn surfaceMeshDataUpdated(pointer: *anyopaque, surface_mesh: *SurfaceMesh, cell_type: SurfaceMesh.CellType, data_gen: *const DataGen) void {
            if (!@hasDecl(ModuleType, "surfaceMeshDataUpdated")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.surfaceMeshDataUpdated(surface_mesh, cell_type, data_gen);
        }
        fn uiPanel(pointer: *anyopaque) void {
            if (!@hasDecl(ModuleType, "uiPanel")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.uiPanel();
        }
        fn menuBar(pointer: *anyopaque) void {
            if (!@hasDecl(ModuleType, "menuBar")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.menuBar();
        }
        fn draw(pointer: *anyopaque, view_matrix: Mat4, projection_matrix: Mat4) void {
            if (!@hasDecl(ModuleType, "draw")) return;
            const impl: Ptr = @ptrCast(@alignCast(pointer));
            impl.draw(view_matrix, projection_matrix);
        }
    };

    return .{
        .ptr = ptr,
        .vtable = comptime &.{
            .name = gen.name,
            .pointCloudAdded = gen.pointCloudAdded,
            .pointCloudStdDataChanged = gen.pointCloudStdDataChanged,
            .pointCloudDataUpdated = gen.pointCloudDataUpdated,
            .surfaceMeshAdded = gen.surfaceMeshAdded,
            .surfaceMeshStdDataChanged = gen.surfaceMeshStdDataChanged,
            .surfaceMeshConnectivityUpdated = gen.surfaceMeshConnectivityUpdated,
            .surfaceMeshDataUpdated = gen.surfaceMeshDataUpdated,
            .uiPanel = gen.uiPanel,
            .menuBar = gen.menuBar,
            .draw = gen.draw,
        },
    };
}

pub fn deinit(m: *Module) void {
    m.arena.deinit();
}

pub fn name(m: *Module) []const u8 {
    return m.vtable.name(m.ptr);
}
pub fn pointCloudAdded(m: *Module, pc: *PointCloud) void {
    m.vtable.pointCloudAdded(m.ptr, pc);
}
pub fn pointCloudStdDataChanged(m: *Module, pc: *PointCloud, data: PointCloudStdData) void {
    m.vtable.pointCloudStdDataChanged(m.ptr, pc, data);
}
pub fn pointCloudDataUpdated(m: *Module, pc: *PointCloud, data_gen: *const DataGen) void {
    m.vtable.pointCloudDataUpdated(m.ptr, pc, data_gen);
}
pub fn surfaceMeshAdded(m: *Module, sm: *SurfaceMesh) void {
    m.vtable.surfaceMeshAdded(m.ptr, sm);
}
pub fn surfaceMeshStdDataChanged(m: *Module, sm: *SurfaceMesh, data: SurfaceMeshStdData) void {
    m.vtable.surfaceMeshStdDataChanged(m.ptr, sm, data);
}
pub fn surfaceMeshConnectivityUpdated(m: *Module, sm: *SurfaceMesh) void {
    m.vtable.surfaceMeshConnectivityUpdated(m.ptr, sm);
}
pub fn surfaceMeshDataUpdated(m: *Module, sm: *SurfaceMesh, cell_type: SurfaceMesh.CellType, data_gen: *const DataGen) void {
    m.vtable.surfaceMeshDataUpdated(m.ptr, sm, cell_type, data_gen);
}
pub fn uiPanel(m: *Module) void {
    m.vtable.uiPanel(m.ptr);
}
pub fn menuBar(m: *Module) void {
    m.vtable.menuBar(m.ptr);
}
pub fn draw(m: *Module, view_matrix: Mat4, projection_matrix: Mat4) void {
    m.vtable.draw(m.ptr, view_matrix, projection_matrix);
}
