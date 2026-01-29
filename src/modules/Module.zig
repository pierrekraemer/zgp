const Module = @This();

const zgp = @import("../main.zig");
const c = zgp.c;

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
    pointCloudCreated: ?*const fn (m: *Module, point_cloud: *PointCloud) void = null,
    pointCloudDestroyed: ?*const fn (m: *Module, point_cloud: *PointCloud) void = null,
    pointCloudConnectivityUpdated: ?*const fn (m: *Module, point_cloud: *PointCloud) void = null,
    pointCloudStdDataChanged: ?*const fn (m: *Module, point_cloud: *PointCloud, std_data: PointCloudStdData) void = null,
    pointCloudDataUpdated: ?*const fn (m: *Module, point_cloud: *PointCloud, data_gen: *const DataGen) void = null,

    surfaceMeshCreated: ?*const fn (m: *Module, surface_mesh: *SurfaceMesh) void = null,
    surfaceMeshDestroyed: ?*const fn (m: *Module, surface_mesh: *SurfaceMesh) void = null,
    surfaceMeshConnectivityUpdated: ?*const fn (m: *Module, surface_mesh: *SurfaceMesh) void = null,
    surfaceMeshStdDataChanged: ?*const fn (m: *Module, surface_mesh: *SurfaceMesh, std_data: SurfaceMeshStdData) void = null,
    surfaceMeshDataUpdated: ?*const fn (m: *Module, surface_mesh: *SurfaceMesh, cell_type: SurfaceMesh.CellType, data_gen: *const DataGen) void = null,
    surfaceMeshCellSetUpdated: ?*const fn (m: *Module, surface_mesh: *SurfaceMesh, cell_type: SurfaceMesh.CellType) void = null,

    uiPanel: ?*const fn (m: *Module) void = null,
    menuBar: ?*const fn (m: *Module) void = null,
    rightClickMenu: ?*const fn (m: *Module) void = null,

    draw: ?*const fn (m: *Module, view_matrix: Mat4f, projection_matrix: Mat4f) void = null,

    sdlEvent: ?*const fn (m: *Module, event: *const c.SDL_Event) void = null,
};

pub inline fn pointCloudCreated(m: *Module, pc: *PointCloud) void {
    if (m.vtable.pointCloudCreated) |func| {
        func(m, pc);
    }
}
pub inline fn pointCloudDestroyed(m: *Module, pc: *PointCloud) void {
    if (m.vtable.pointCloudDestroyed) |func| {
        func(m, pc);
    }
}
pub inline fn pointCloudConnectivityUpdated(m: *Module, pc: *PointCloud) void {
    if (m.vtable.pointCloudConnectivityUpdated) |func| {
        func(m, pc);
    }
}
pub inline fn pointCloudStdDataChanged(m: *Module, pc: *PointCloud, data: PointCloudStdData) void {
    if (m.vtable.pointCloudStdDataChanged) |func| {
        func(m, pc, data);
    }
}
pub inline fn pointCloudDataUpdated(m: *Module, pc: *PointCloud, data_gen: *const DataGen) void {
    if (m.vtable.pointCloudDataUpdated) |func| {
        func(m, pc, data_gen);
    }
}
pub inline fn surfaceMeshCreated(m: *Module, sm: *SurfaceMesh) void {
    if (m.vtable.surfaceMeshCreated) |func| {
        func(m, sm);
    }
}
pub inline fn surfaceMeshDestroyed(m: *Module, sm: *SurfaceMesh) void {
    if (m.vtable.surfaceMeshDestroyed) |func| {
        func(m, sm);
    }
}
pub inline fn surfaceMeshConnectivityUpdated(m: *Module, sm: *SurfaceMesh) void {
    if (m.vtable.surfaceMeshConnectivityUpdated) |func| {
        func(m, sm);
    }
}
pub inline fn surfaceMeshStdDataChanged(m: *Module, sm: *SurfaceMesh, data: SurfaceMeshStdData) void {
    if (m.vtable.surfaceMeshStdDataChanged) |func| {
        func(m, sm, data);
    }
}
pub inline fn surfaceMeshDataUpdated(m: *Module, sm: *SurfaceMesh, cell_type: SurfaceMesh.CellType, data_gen: *const DataGen) void {
    if (m.vtable.surfaceMeshDataUpdated) |func| {
        func(m, sm, cell_type, data_gen);
    }
}
pub inline fn surfaceMeshCellSetUpdated(m: *Module, sm: *SurfaceMesh, cell_type: SurfaceMesh.CellType) void {
    if (m.vtable.surfaceMeshCellSetUpdated) |func| {
        func(m, sm, cell_type);
    }
}
pub inline fn uiPanel(m: *Module) void {
    if (m.vtable.uiPanel) |func| {
        func(m);
    }
}
pub inline fn menuBar(m: *Module) void {
    if (m.vtable.menuBar) |func| {
        func(m);
    }
}
pub inline fn rightClickMenu(m: *Module) void {
    if (m.vtable.rightClickMenu) |func| {
        func(m);
    }
}
pub inline fn draw(m: *Module, view_matrix: Mat4f, projection_matrix: Mat4f) void {
    if (m.vtable.draw) |func| {
        func(m, view_matrix, projection_matrix);
    }
}
pub inline fn sdlEvent(m: *Module, event: *const c.SDL_Event) void {
    if (m.vtable.sdlEvent) |func| {
        func(m, event);
    }
}
