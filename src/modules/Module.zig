const Module = @This();

const c = @import("c");

const DataGen = @import("../utils/data.zig").DataGen;

const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;

const PointCloud = @import("../models/point/PointCloud.zig");
const PointCloudStdData = @import("../models/PointCloudStore.zig").PointCloudStdData;

const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfaceMeshStdData = @import("../models/SurfaceMeshStore.zig").SurfaceMeshStdData;

const IncidenceGraph = @import("../models/incidenceGraph/IncidenceGraph.zig");
const IncidenceGraphStdData = @import("../models/IncidenceGraphStore.zig").IncidenceGraphStdData;

pub const SupportedModels = struct {
    point_cloud: bool = false,
    surface_mesh: bool = false,
    incidence_graph: bool = false,
};

name: []const u8,
supported_models: SupportedModels = .{},
vtable: *const VTable,

const VTable = struct {
    // PointCloudStore events
    pointCloudCreated: *const fn (m: *Module, point_cloud: *PointCloud) void = defaultPointCloudCreated,
    pointCloudDestroyed: *const fn (m: *Module, point_cloud: *PointCloud) void = defaultPointCloudDestroyed,
    pointCloudConnectivityUpdated: *const fn (m: *Module, point_cloud: *PointCloud) void = defaultPointCloudConnectivityUpdated,
    pointCloudStdDataChanged: *const fn (m: *Module, point_cloud: *PointCloud, std_data: PointCloudStdData) void = defaultPointCloudStdDataChanged,
    pointCloudDataUpdated: *const fn (m: *Module, point_cloud: *PointCloud, data_gen: *const DataGen) void = defaultPointCloudDataUpdated,

    // SurfaceMeshStore events
    surfaceMeshCreated: *const fn (m: *Module, surface_mesh: *SurfaceMesh) void = defaultSurfaceMeshCreated,
    surfaceMeshDestroyed: *const fn (m: *Module, surface_mesh: *SurfaceMesh) void = defaultSurfaceMeshDestroyed,
    surfaceMeshConnectivityUpdated: *const fn (m: *Module, surface_mesh: *SurfaceMesh) void = defaultSurfaceMeshConnectivityUpdated,
    surfaceMeshStdDataChanged: *const fn (m: *Module, surface_mesh: *SurfaceMesh, std_data: SurfaceMeshStdData) void = defaultSurfaceMeshStdDataChanged,
    surfaceMeshDataUpdated: *const fn (m: *Module, surface_mesh: *SurfaceMesh, cell_type: SurfaceMesh.CellType, data_gen: *const DataGen) void = defaultSurfaceMeshDataUpdated,
    surfaceMeshCellSetUpdated: *const fn (m: *Module, surface_mesh: *SurfaceMesh, cell_set: *const SurfaceMesh.CellSet) void = defaultSurfaceMeshCellSetUpdated,

    // IncidenceGraphStore events
    incidenceGraphCreated: *const fn (m: *Module, incidence_graph: *IncidenceGraph) void = defaultIncidenceGraphCreated,
    incidenceGraphDestroyed: *const fn (m: *Module, incidence_graph: *IncidenceGraph) void = defaultIncidenceGraphDestroyed,
    incidenceGraphConnectivityUpdated: *const fn (m: *Module, incidence_graph: *IncidenceGraph) void = defaultIncidenceGraphConnectivityUpdated,
    incidenceGraphStdDataChanged: *const fn (m: *Module, incidence_graph: *IncidenceGraph, std_data: IncidenceGraphStdData) void = defaultIncidenceGraphStdDataChanged,
    incidenceGraphDataUpdated: *const fn (m: *Module, incidence_graph: *IncidenceGraph, cell_type: IncidenceGraph.CellType, data_gen: *const DataGen) void = defaultIncidenceGraphDataUpdated,

    // UI events
    leftPanel: *const fn (m: *Module) void = defaultLeftPanel,
    rightPanel: *const fn (m: *Module) void = defaultRightPanel,
    menuBar: *const fn (m: *Module) void = defaultMenuBar,
    rightClickMenu: *const fn (m: *Module) void = defaultRightClickMenu,

    // App events
    selectedModelChanged: *const fn (m: *Module) void = defaultSelectedModelChanged,

    // View events
    draw: *const fn (m: *Module, view_matrix: Mat4f, projection_matrix: Mat4f) void = defaultDraw,

    // Window events
    sdlEvent: *const fn (m: *Module, event: *const c.SDL_Event) bool = defaultSdlEvent, // returns true if the event was handled and should not be processed by other modules
};

pub fn defaultPointCloudCreated(_: *Module, _: *PointCloud) void {}
pub fn pointCloudCreated(m: *Module, pc: *PointCloud) void {
    m.vtable.pointCloudCreated(m, pc);
}
pub fn defaultPointCloudDestroyed(_: *Module, _: *PointCloud) void {}
pub fn pointCloudDestroyed(m: *Module, pc: *PointCloud) void {
    m.vtable.pointCloudDestroyed(m, pc);
}
pub fn defaultPointCloudConnectivityUpdated(_: *Module, _: *PointCloud) void {}
pub fn pointCloudConnectivityUpdated(m: *Module, pc: *PointCloud) void {
    m.vtable.pointCloudConnectivityUpdated(m, pc);
}
pub fn defaultPointCloudStdDataChanged(_: *Module, _: *PointCloud, _: PointCloudStdData) void {}
pub fn pointCloudStdDataChanged(m: *Module, pc: *PointCloud, data: PointCloudStdData) void {
    m.vtable.pointCloudStdDataChanged(m, pc, data);
}
pub fn defaultPointCloudDataUpdated(_: *Module, _: *PointCloud, _: *const DataGen) void {}
pub fn pointCloudDataUpdated(m: *Module, pc: *PointCloud, data_gen: *const DataGen) void {
    m.vtable.pointCloudDataUpdated(m, pc, data_gen);
}

pub fn defaultSurfaceMeshCreated(_: *Module, _: *SurfaceMesh) void {}
pub fn surfaceMeshCreated(m: *Module, sm: *SurfaceMesh) void {
    m.vtable.surfaceMeshCreated(m, sm);
}
pub fn defaultSurfaceMeshDestroyed(_: *Module, _: *SurfaceMesh) void {}
pub fn surfaceMeshDestroyed(m: *Module, sm: *SurfaceMesh) void {
    m.vtable.surfaceMeshDestroyed(m, sm);
}
pub fn defaultSurfaceMeshConnectivityUpdated(_: *Module, _: *SurfaceMesh) void {}
pub fn surfaceMeshConnectivityUpdated(m: *Module, sm: *SurfaceMesh) void {
    m.vtable.surfaceMeshConnectivityUpdated(m, sm);
}
pub fn defaultSurfaceMeshStdDataChanged(_: *Module, _: *SurfaceMesh, _: SurfaceMeshStdData) void {}
pub fn surfaceMeshStdDataChanged(m: *Module, sm: *SurfaceMesh, data: SurfaceMeshStdData) void {
    m.vtable.surfaceMeshStdDataChanged(m, sm, data);
}
pub fn defaultSurfaceMeshDataUpdated(_: *Module, _: *SurfaceMesh, _: SurfaceMesh.CellType, _: *const DataGen) void {}
pub fn surfaceMeshDataUpdated(m: *Module, sm: *SurfaceMesh, cell_type: SurfaceMesh.CellType, data_gen: *const DataGen) void {
    m.vtable.surfaceMeshDataUpdated(m, sm, cell_type, data_gen);
}
pub fn defaultSurfaceMeshCellSetUpdated(_: *Module, _: *SurfaceMesh, _: *const SurfaceMesh.CellSet) void {}
pub fn surfaceMeshCellSetUpdated(m: *Module, sm: *SurfaceMesh, cell_set: *const SurfaceMesh.CellSet) void {
    m.vtable.surfaceMeshCellSetUpdated(m, sm, cell_set);
}

pub fn defaultIncidenceGraphCreated(_: *Module, _: *IncidenceGraph) void {}
pub fn incidenceGraphCreated(m: *Module, ig: *IncidenceGraph) void {
    m.vtable.incidenceGraphCreated(m, ig);
}
pub fn defaultIncidenceGraphDestroyed(_: *Module, _: *IncidenceGraph) void {}
pub fn incidenceGraphDestroyed(m: *Module, ig: *IncidenceGraph) void {
    m.vtable.incidenceGraphDestroyed(m, ig);
}
pub fn defaultIncidenceGraphConnectivityUpdated(_: *Module, _: *IncidenceGraph) void {}
pub fn incidenceGraphConnectivityUpdated(m: *Module, ig: *IncidenceGraph) void {
    m.vtable.incidenceGraphConnectivityUpdated(m, ig);
}
pub fn defaultIncidenceGraphStdDataChanged(_: *Module, _: *IncidenceGraph, _: IncidenceGraphStdData) void {}
pub fn incidenceGraphStdDataChanged(m: *Module, ig: *IncidenceGraph, data: IncidenceGraphStdData) void {
    m.vtable.incidenceGraphStdDataChanged(m, ig, data);
}
pub fn defaultIncidenceGraphDataUpdated(_: *Module, _: *IncidenceGraph, _: IncidenceGraph.CellType, _: *const DataGen) void {}
pub fn incidenceGraphDataUpdated(m: *Module, ig: *IncidenceGraph, cell_type: IncidenceGraph.CellType, data_gen: *const DataGen) void {
    m.vtable.incidenceGraphDataUpdated(m, ig, cell_type, data_gen);
}

pub fn defaultLeftPanel(_: *Module) void {}
pub fn leftPanel(m: *Module) void {
    m.vtable.leftPanel(m);
}
pub fn defaultRightPanel(_: *Module) void {}
pub fn rightPanel(m: *Module) void {
    m.vtable.rightPanel(m);
}
pub fn defaultMenuBar(_: *Module) void {}
pub fn menuBar(m: *Module) void {
    m.vtable.menuBar(m);
}
pub fn defaultRightClickMenu(_: *Module) void {}
pub fn rightClickMenu(m: *Module) void {
    m.vtable.rightClickMenu(m);
}

pub fn defaultSelectedModelChanged(_: *Module) void {}
pub fn selectedModelChanged(m: *Module) void {
    m.vtable.selectedModelChanged(m);
}

pub fn defaultDraw(_: *Module, _: Mat4f, _: Mat4f) void {}
pub fn draw(m: *Module, view_matrix: Mat4f, projection_matrix: Mat4f) void {
    m.vtable.draw(m, view_matrix, projection_matrix);
}

pub fn defaultSdlEvent(_: *Module, _: *const c.SDL_Event) bool {
    return false;
}
pub fn sdlEvent(m: *Module, event: *const c.SDL_Event) bool {
    return m.vtable.sdlEvent(m, event);
}
