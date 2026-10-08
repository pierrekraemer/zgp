//! Application Context:
//! - io instance
//! - allocator instance
//! - model stores
//! - current selected model
//! - random number generator
//! - window
//! - view

const AppContext = @This();

const std = @import("std");

const PointCloud = @import("models/point/PointCloud.zig");
const PointCloudStore = @import("models/PointCloudStore.zig");
const SurfaceMesh = @import("models/surface/SurfaceMesh.zig");
const SurfaceMeshStore = @import("models/SurfaceMeshStore.zig");
const IncidenceGraph = @import("models/incidenceGraph/IncidenceGraph.zig");
const IncidenceGraphStore = @import("models/IncidenceGraphStore.zig");

const Window = @import("ui/Window.zig");
const View = @import("rendering/View.zig");

io: std.Io,
allocator: std.mem.Allocator,
point_cloud_store: PointCloudStore,
surface_mesh_store: SurfaceMeshStore,
incidence_graph_store: IncidenceGraphStore,
selected_model: ModelSelection = .none,
rng: std.Random.DefaultPrng,
window: Window,
view: View,

pub fn init(io: std.Io, allocator: std.mem.Allocator) !AppContext {
    var seed: u64 = undefined;
    io.random(std.mem.asBytes(&seed));
    return .{
        .io = io,
        .allocator = allocator,
        .point_cloud_store = try .init(io, allocator),
        .surface_mesh_store = try .init(io, allocator),
        .incidence_graph_store = try .init(io, allocator),
        .rng = .init(seed),
        .window = try .init(),
        .view = .init(),
    };
}

pub fn wireUp(self: *AppContext) void {
    self.point_cloud_store.selected_model = &self.selected_model;
    self.surface_mesh_store.selected_model = &self.selected_model;
    self.incidence_graph_store.selected_model = &self.selected_model;
}

pub fn deinit(self: *AppContext) void {
    self.point_cloud_store.deinit();
    self.surface_mesh_store.deinit();
    self.incidence_graph_store.deinit();
    self.view.deinit();
    self.window.deinit();
}

pub fn requestRedraw(self: *AppContext) void {
    self.view.needs_redraw = true;
}

pub const ModelSelection = union(enum) {
    none,
    surface_mesh: *SurfaceMesh,
    point_cloud: *PointCloud,
    incidence_graph: *IncidenceGraph,

    pub fn modelType(self: ModelSelection) ModelType {
        return std.meta.activeTag(self);
    }
};
pub const ModelType = std.meta.Tag(ModelSelection);
