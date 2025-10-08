const Module = @This();

const std = @import("std");
const assert = std.debug.assert;

const DataGen = @import("../utils/Data.zig").DataGen;

const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;

const PointCloud = @import("../models/point/PointCloud.zig");
const PointCloudStdData = @import("../models/point/PointCloudStdDatas.zig").PointCloudStdData;

const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfaceMeshStdData = @import("../models/surface/SurfaceMeshStdDatas.zig").SurfaceMeshStdData;

name: []const u8,
vtable: *const VTable,

const VTable = struct {
    pointCloudAdded: ?*const fn (m: *Module, point_cloud: *PointCloud) void = null,
    pointCloudStdDataChanged: ?*const fn (m: *Module, point_cloud: *PointCloud, std_data: PointCloudStdData) void = null,
    pointCloudDataUpdated: ?*const fn (m: *Module, point_cloud: *PointCloud, data_gen: *const DataGen) void = null,

    surfaceMeshAdded: ?*const fn (m: *Module, surface_mesh: *SurfaceMesh) void = null,
    surfaceMeshStdDataChanged: ?*const fn (m: *Module, surface_mesh: *SurfaceMesh, std_data: SurfaceMeshStdData) void = null,
    surfaceMeshConnectivityUpdated: ?*const fn (m: *Module, surface_mesh: *SurfaceMesh) void = null,
    surfaceMeshDataUpdated: ?*const fn (m: *Module, surface_mesh: *SurfaceMesh, cell_type: SurfaceMesh.CellType, data_gen: *const DataGen) void = null,

    uiPanel: ?*const fn (m: *Module) void = null,
    menuBar: ?*const fn (m: *Module) void = null,
    rightClickMenu: ?*const fn (m: *Module) void = null,

    draw: ?*const fn (m: *Module, view_matrix: Mat4f, projection_matrix: Mat4f) void = null,
};

pub fn pointCloudAdded(m: *Module, pc: *PointCloud) void {
    if (m.vtable.pointCloudAdded) |func| {
        func(m, pc);
    }
}
pub fn pointCloudStdDataChanged(m: *Module, pc: *PointCloud, data: PointCloudStdData) void {
    if (m.vtable.pointCloudStdDataChanged) |func| {
        func(m, pc, data);
    }
}
pub fn pointCloudDataUpdated(m: *Module, pc: *PointCloud, data_gen: *const DataGen) void {
    if (m.vtable.pointCloudDataUpdated) |func| {
        func(m, pc, data_gen);
    }
}
pub fn surfaceMeshAdded(m: *Module, sm: *SurfaceMesh) void {
    if (m.vtable.surfaceMeshAdded) |func| {
        func(m, sm);
    }
}
pub fn surfaceMeshStdDataChanged(m: *Module, sm: *SurfaceMesh, data: SurfaceMeshStdData) void {
    if (m.vtable.surfaceMeshStdDataChanged) |func| {
        func(m, sm, data);
    }
}
pub fn surfaceMeshConnectivityUpdated(m: *Module, sm: *SurfaceMesh) void {
    if (m.vtable.surfaceMeshConnectivityUpdated) |func| {
        func(m, sm);
    }
}
pub fn surfaceMeshDataUpdated(m: *Module, sm: *SurfaceMesh, cell_type: SurfaceMesh.CellType, data_gen: *const DataGen) void {
    if (m.vtable.surfaceMeshDataUpdated) |func| {
        func(m, sm, cell_type, data_gen);
    }
}
pub fn uiPanel(m: *Module) void {
    if (m.vtable.uiPanel) |func| {
        func(m);
    }
}
pub fn menuBar(m: *Module) void {
    if (m.vtable.menuBar) |func| {
        func(m);
    }
}
pub fn rightClickMenu(m: *Module) void {
    if (m.vtable.rightClickMenu) |func| {
        func(m);
    }
}
pub fn draw(m: *Module, view_matrix: Mat4f, projection_matrix: Mat4f) void {
    if (m.vtable.draw) |func| {
        func(m, view_matrix, projection_matrix);
    }
}
