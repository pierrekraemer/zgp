//! TODO: write docs for IncidenceGraph
const IncidenceGraph = @This();

const std = @import("std");
const assert = std.debug.assert;

const data = @import("../../utils/data.zig");
const DataContainer = data.DataContainer;
const DataGen = data.DataGen;
const Data = data.Data;

const BufferPool = @import("../../utils/BufferPool.zig").BufferPool;

pub const CellIndex = u32;

pub const Cell = union(enum) {
    vertex: CellIndex,
    edge: CellIndex,
    face: CellIndex,

    pub fn index(c: Cell) CellIndex {
        const idx, _ = switch (c) {
            inline else => |val, tag| .{ val, tag },
        };
        return idx;
    }

    pub fn cellType(c: Cell) CellType {
        return std.meta.activeTag(c);
    }
};
pub const CellType = std.meta.Tag(Cell);

allocator: std.mem.Allocator,
cell_buffer_pool: *BufferPool(Cell),

vertex_data: *DataContainer,
edge_data: *DataContainer,
face_data: *DataContainer,

vertex_incident_edges: *Data(std.ArrayList(CellIndex)) = undefined,
edge_incident_vertices: *Data([2]CellIndex) = undefined,
edge_incident_faces: *Data(std.ArrayList(CellIndex)) = undefined,
face_incident_edges: *Data(std.ArrayList(CellIndex)) = undefined,
face_incident_edges_dir: *Data(std.ArrayList(bool)) = undefined,

pub fn init(allocator: std.mem.Allocator, cell_buffer_pool: *BufferPool(Cell)) !IncidenceGraph {
    var ig: IncidenceGraph = .{
        .allocator = allocator,
        .cell_buffer_pool = cell_buffer_pool,
        .vertex_data = try .init(allocator),
        .edge_data = try .init(allocator),
        .face_data = try .init(allocator),
    };
    ig.vertex_incident_edges = try ig.vertex_data.addData(std.ArrayList(CellIndex), "vertex_incident_edges");
    ig.edge_incident_vertices = try ig.edge_data.addData([2]CellIndex, "edge_incident_vertices");
    ig.edge_incident_faces = try ig.edge_data.addData(std.ArrayList(CellIndex), "edge_incident_faces");
    ig.face_incident_edges = try ig.face_data.addData(std.ArrayList(CellIndex), "face_incident_edges");
    ig.face_incident_edges_dir = try ig.face_data.addData(std.ArrayList(bool), "face_incident_edges_dir");
    return ig;
}

pub fn deinit(ig: *IncidenceGraph) void {
    var it = ig.vertex_incident_edges.iterator();
    while (it.next()) |entry| {
        entry.deinit(ig.allocator);
    }
    it = ig.edge_incident_faces.iterator();
    while (it.next()) |entry| {
        entry.deinit(ig.allocator);
    }
    it = ig.face_incident_edges.iterator();
    while (it.next()) |entry| {
        entry.deinit(ig.allocator);
    }
    var dir_it = ig.face_incident_edges_dir.iterator();
    while (dir_it.next()) |entry| {
        entry.deinit(ig.allocator);
    }
    ig.vertex_data.deinit();
    ig.edge_data.deinit();
    ig.face_data.deinit();
}

pub fn clearRetainingCapacity(ig: *IncidenceGraph) void {
    var it = ig.vertex_incident_edges.iterator();
    while (it.next()) |entry| {
        entry.deinit(ig.allocator);
    }
    it = ig.edge_incident_faces.iterator();
    while (it.next()) |entry| {
        entry.deinit(ig.allocator);
    }
    it = ig.face_incident_edges.iterator();
    while (it.next()) |entry| {
        entry.deinit(ig.allocator);
    }
    var dir_it = ig.face_incident_edges_dir.iterator();
    while (dir_it.next()) |entry| {
        entry.deinit(ig.allocator);
    }
    ig.vertex_data.clearRetainingCapacity();
    ig.edge_data.clearRetainingCapacity();
    ig.face_data.clearRetainingCapacity();
}

/// A CellMarker stores a boolean for each cell of the given CellType.
/// It can be used for any purpose, using the value/valuePtr/reset functions.
pub const CellMarker = struct {
    incidence_graph: *IncidenceGraph,
    cell_type: CellType,
    marker: *Data(bool),

    pub fn init(ig: *IncidenceGraph, cell_type: CellType) !CellMarker {
        return .{
            .incidence_graph = ig,
            .cell_type = cell_type,
            .marker = try switch (cell_type) {
                .vertex => ig.vertex_data.getMarker(),
                .edge => ig.edge_data.getMarker(),
                .face => ig.face_data.getMarker(),
                else => unreachable,
            },
        };
    }
    pub fn deinit(cm: *CellMarker) void {
        switch (cm.cell_type) {
            .vertex => cm.incidence_graph.vertex_data.releaseMarker(cm.marker),
            .edge => cm.incidence_graph.edge_data.releaseMarker(cm.marker),
            .face => cm.incidence_graph.face_data.releaseMarker(cm.marker),
            else => unreachable,
        }
    }

    pub fn mark(cm: *CellMarker, c: Cell) void {
        assert(c.cellType() == cm.cell_type);
        assert(!cm.isMarked(c));
        cm.marker.valuePtr(c.index()).* = true;
    }
    pub fn unmark(cm: *CellMarker, c: Cell) void {
        assert(c.cellType() == cm.cell_type);
        assert(cm.isMarked(c));
        cm.marker.valuePtr(c.index()).* = false;
    }
    pub fn isMarked(cm: *CellMarker, c: Cell) bool {
        assert(c.cellType() == cm.cell_type);
        return cm.marker.value(c.index());
    }
    pub fn reset(cm: *CellMarker) void {
        cm.marker.fill(false);
    }
};

/// CellIterator iterates over all the cells of the given CellType of the IncidenceGraph.
const CellIterator = struct {
    incidence_graph: *IncidenceGraph,
    cell_type: CellType,
    cell_container: *DataContainer,
    current_index: CellIndex = undefined,

    pub fn next(ci: *CellIterator) ?Cell {
        if (ci.current_index == ci.cell_container.lastIndex()) {
            return null;
        }
        // prepare current_index for next iteration
        defer ci.current_index = ci.cell_container.nextIndex(ci.current_index);
        return switch (ci.cell_type) {
            .vertex => .{ .vertex = ci.current_index },
            .edge => .{ .edge = ci.current_index },
            .face => .{ .face = ci.current_index },
        };
    }
    pub fn reset(ci: *CellIterator) void {
        ci.current_index = ci.cell_container.firstIndex();
    }
};

pub fn cellIterator(ig: *IncidenceGraph, cell_type: CellType) CellIterator {
    var ci: CellIterator = .{
        .incidence_graph = ig,
        .cell_type = cell_type,
        .cell_container = ig.dataContainer(cell_type),
    };
    ci.reset();
    return ci;
}

/// A CellData is a handle to a data array of type `T` associated with cells of the given CellType.
/// It provides functions to access the data associated with a given cell or its index.
pub fn CellData(comptime cell_type: CellType, comptime T: type) type {
    return struct {
        const Self = @This();
        pub const CellType = cell_type;
        pub const DataType = T;

        incidence_graph: *const IncidenceGraph,
        data: *Data(T),

        pub fn value(self: Self, c: Cell) T {
            assert(c.cellType() == cell_type);
            return self.data.value(c.index());
        }

        pub fn valuePtr(self: Self, c: Cell) *T {
            assert(c.cellType() == cell_type);
            return self.data.valuePtr(c.index());
        }

        pub fn name(self: Self) []const u8 {
            return self.data.data_gen.name;
        }

        pub fn gen(self: Self) *DataGen {
            return &self.data.data_gen;
        }
    };
}

/// Returns the data container associated with the given CellType.
pub fn dataContainer(ig: *const IncidenceGraph, cell_type: CellType) *DataContainer {
    return switch (cell_type) {
        .vertex => ig.vertex_data,
        .edge => ig.edge_data,
        .face => ig.face_data,
    };
}

/// Creates a new data array of the type `T` associated with cells of the given CellType.
/// The `name` must be unique for the given CellType for the creation to succeed.
pub fn addData(ig: *IncidenceGraph, comptime cell_type: CellType, comptime T: type, name: []const u8) !CellData(cell_type, T) {
    return .{
        .incidence_graph = ig,
        .data = try ig.dataContainer(cell_type).addData(T, name),
    };
}

/// Returns a handle to the data array of the type `T` associated with cells of the given CellType
/// if it exists with the given name, otherwise returns null.
pub fn getData(ig: *const IncidenceGraph, comptime cell_type: CellType, comptime T: type, name: []const u8) ?CellData(cell_type, T) {
    if (ig.dataContainer(cell_type).getData(T, name)) |d| {
        return .{
            .incidence_graph = ig,
            .data = d,
        };
    } else return null;
}

/// Returns a handle to the data array of the type `T` associated with cells of the given CellType
/// if it exists with the given name, otherwise creates a new data array of the type `T` associated with cells of the given CellType
/// and returns a handle to it.
pub fn getOrAddData(ig: *IncidenceGraph, comptime cell_type: CellType, comptime T: type, name: []const u8) !CellData(cell_type, T) {
    return .{
        .incidence_graph = ig,
        .data = try ig.dataContainer(cell_type).getOrAddData(T, name),
    };
}

/// Removes the data array of the type `T` associated with cells of the given CellType.
pub fn removeData(ig: *IncidenceGraph, comptime cell_type: CellType, comptime T: type, cellData: CellData(cell_type, T)) void {
    assert(cellData.incidence_graph == ig);
    ig.dataContainer(cell_type).removeData(&cellData.data.data_gen);
}

/// Returns the number of cells of the given CellType in the given IncidenceGraph.
pub fn nbCells(ig: *const IncidenceGraph, cell_type: CellType) u32 {
    return ig.dataContainer(cell_type).nbElements();
}

/// Returns the degree of the given cell (number of d+1 incident cells).
/// Only vertices and edges have a degree (faces are top-cells and do not have a degree).
pub fn degree(ig: *const IncidenceGraph, cell: Cell) u32 {
    return switch (cell) {
        .vertex => ig.vertex_incident_edges.value(cell).items.len,
        .edge => ig.edge_incident_faces.value(cell).items.len,
        else => unreachable,
    };
}

/// Returns the codegree of the given cell (number of d-1 incident cells).
/// Only edges and faces have a codegree (vertices are 0-cells and do not have a codegree).
pub fn codegree(ig: *const IncidenceGraph, cell: Cell) u32 {
    return switch (cell) {
        .edge => 2,
        .face => ig.face_incident_edges.value(cell).items.len,
        else => unreachable,
    };
}

pub fn addVertex(ig: *IncidenceGraph) !Cell {
    const idx = try ig.vertex_data.getIndex();
    ig.vertex_incident_edges.valuePtr(idx).* = .empty;
    return .{ .vertex = idx };
}

pub fn addEdge(ig: *IncidenceGraph, v0: Cell, v1: Cell) !Cell {
    assert(v0.cellType() == .vertex);
    assert(v1.cellType() == .vertex);
    const idx = try ig.edge_data.getIndex();
    ig.edge_incident_vertices.valuePtr(idx).* = .{ v0.index(), v1.index() };
    ig.edge_incident_faces.valuePtr(idx).* = .empty;
    try ig.vertex_incident_edges.valuePtr(v0.index()).append(ig.allocator, idx);
    try ig.vertex_incident_edges.valuePtr(v1.index()).append(ig.allocator, idx);
    return .{ .edge = idx };
}

pub fn addFace(ig: *IncidenceGraph, edges: []const Cell) !Cell {
    const idx = try ig.face_data.getIndex();
    var fie: *std.ArrayList(CellIndex) = ig.face_incident_edges.valuePtr(idx);
    var fied: *std.ArrayList(bool) = ig.face_incident_edges_dir.valuePtr(idx);
    fie.* = .empty;
    fied.* = .empty;
    // TODO: order the edges of the face and set directions accordingly
    for (edges) |e| {
        try fie.append(ig.allocator, e.index());
        try fied.append(ig.allocator, true);
        try ig.edge_incident_faces.valuePtr(e.index()).append(ig.allocator, idx);
    }
    return .{ .face = idx };
}
