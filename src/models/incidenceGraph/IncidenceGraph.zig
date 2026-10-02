//! TODO: write docs for IncidenceGraph
const IncidenceGraph = @This();

const std = @import("std");
const assert = std.debug.assert;

const data = @import("../../utils/data.zig");
const DataContainer = data.DataContainer;
const DataGen = data.DataGen;
const Data = data.Data;

const BufferPool = @import("../../utils/BufferPool.zig").BufferPool;

// ------------------------------------------------------------------------- //
// Basic types
// ------------------------------------------------------------------------- //

pub const CellIndex = u32;

pub const Cell = union(enum) {
    vertex: CellIndex,
    edge: CellIndex,
    face: CellIndex,

    pub fn cellType(c: Cell) CellType {
        return std.meta.activeTag(c);
    }

    pub fn index(c: Cell) CellIndex {
        return switch (c) {
            inline else => |val| val,
        };
    }
};
pub const CellType = std.meta.Tag(Cell);

// ------------------------------------------------------------------------- //
// Fields
// ------------------------------------------------------------------------- //

allocator: std.mem.Allocator,
cell_buffer_pool: *BufferPool(Cell), // the BufferPool is shared between IncidenceGraphs (owned by the IncidenceGraphStore)

vertex_data: DataContainer,
edge_data: DataContainer,
face_data: DataContainer,

vertex_incident_edges: *Data(std.ArrayList(CellIndex)),
edge_incident_vertices: *Data([2]CellIndex),
edge_incident_faces: *Data(std.ArrayList(CellIndex)),
face_incident_edges: *Data(std.ArrayList(CellIndex)),
face_incident_edges_dir: *Data(std.ArrayList(bool)),

// ------------------------------------------------------------------------- //
// Basic accessors
// ------------------------------------------------------------------------- //

/// Returns the data container associated with the given CellType.
pub fn dataContainerPtr(ig: anytype, cell_type: CellType) if (@typeInfo(@TypeOf(ig)).pointer.is_const) *const DataContainer else *DataContainer {
    return switch (cell_type) {
        .vertex => &ig.vertex_data,
        .edge => &ig.edge_data,
        .face => &ig.face_data,
    };
}

// ------------------------------------------------------------------------- //
// Initialization, deinitialization
// ------------------------------------------------------------------------- //

pub fn init(ig: *IncidenceGraph, allocator: std.mem.Allocator, cell_buffer_pool: *BufferPool(Cell)) !void {
    ig.allocator = allocator;
    ig.cell_buffer_pool = cell_buffer_pool;
    try ig.vertex_data.init(allocator);
    try ig.edge_data.init(allocator);
    try ig.face_data.init(allocator);
    ig.vertex_incident_edges = try ig.vertex_data.addData(std.ArrayList(CellIndex), "vertex_incident_edges");
    ig.edge_incident_vertices = try ig.edge_data.addData([2]CellIndex, "edge_incident_vertices");
    ig.edge_incident_faces = try ig.edge_data.addData(std.ArrayList(CellIndex), "edge_incident_faces");
    ig.face_incident_edges = try ig.face_data.addData(std.ArrayList(CellIndex), "face_incident_edges");
    ig.face_incident_edges_dir = try ig.face_data.addData(std.ArrayList(bool), "face_incident_edges_dir");
}

pub fn deinit(ig: *IncidenceGraph) void {
    var it = ig.vertex_incident_edges.iterator();
    while (it.next()) |elem| {
        elem.value_ptr.deinit(ig.allocator);
    }
    it = ig.edge_incident_faces.iterator();
    while (it.next()) |elem| {
        elem.value_ptr.deinit(ig.allocator);
    }
    it = ig.face_incident_edges.iterator();
    while (it.next()) |elem| {
        elem.value_ptr.deinit(ig.allocator);
    }
    var dir_it = ig.face_incident_edges_dir.iterator();
    while (dir_it.next()) |elem| {
        elem.value_ptr.deinit(ig.allocator);
    }
    ig.vertex_data.deinit();
    ig.edge_data.deinit();
    ig.face_data.deinit();
}

pub fn clearRetainingCapacity(ig: *IncidenceGraph) void {
    var it = ig.vertex_incident_edges.iterator();
    while (it.next()) |elem| {
        elem.value_ptr.deinit(ig.allocator);
    }
    it = ig.edge_incident_faces.iterator();
    while (it.next()) |elem| {
        elem.value_ptr.deinit(ig.allocator);
    }
    it = ig.face_incident_edges.iterator();
    while (it.next()) |elem| {
        elem.value_ptr.deinit(ig.allocator);
    }
    var dir_it = ig.face_incident_edges_dir.iterator();
    while (dir_it.next()) |elem| {
        elem.value_ptr.deinit(ig.allocator);
    }
    ig.vertex_data.clearRetainingCapacity();
    ig.edge_data.clearRetainingCapacity();
    ig.face_data.clearRetainingCapacity();
}

// ------------------------------------------------------------------------- //
// Iterators
// ------------------------------------------------------------------------- //

pub fn CellIterator(comptime cell_type: CellType) type {
    return struct {
        dc_it: DataContainer.IndexIterator,
        pub fn next(it: *@This()) ?Cell {
            return @unionInit(
                Cell,
                @tagName(cell_type),
                it.dc_it.next() orelse return null,
            );
        }
        pub fn nextSafe(it: *@This()) ?Cell {
            return @unionInit(
                Cell,
                @tagName(cell_type),
                it.dc_it.nextSafe() orelse return null,
            );
        }
        pub fn reset(it: *@This()) void {
            it.dc_it.reset();
        }
    };
}

/// Return a CellIterator that iterates over all the cells of the given type in the IncidenceGraph.
pub fn cellIterator(ig: *const IncidenceGraph, comptime cell_type: CellType) CellIterator(cell_type) {
    return .{ .dc_it = ig.dataContainerPtr(cell_type).indexIterator() };
}

// ------------------------------------------------------------------------- //
// Markers
// ------------------------------------------------------------------------- //

/// A CellMarker stores a boolean for each cell of the given CellType.
/// It can be used for any purpose, using the value/valuePtr/reset functions.
pub fn CellMarker(comptime cell_type: CellType) type {
    return struct {
        incidence_graph: *IncidenceGraph,
        marker: *Data(bool),

        pub fn init(ig: *IncidenceGraph) !@This() {
            return .{
                .incidence_graph = ig,
                .marker = try ig.dataContainerPtr(cell_type).acquireMarker(),
            };
        }
        pub fn deinit(cm: *@This()) void {
            cm.incidence_graph.dataContainerPtr(cell_type).releaseMarker(cm.marker);
        }

        pub fn mark(cm: *@This(), c: Cell) void {
            assert(c.cellType() == cell_type);
            cm.marker.valuePtr(c.index()).* = true;
        }
        pub fn unmark(cm: *@This(), c: Cell) void {
            assert(c.cellType() == cell_type);
            cm.marker.valuePtr(c.index()).* = false;
        }
        pub fn isMarked(cm: *@This(), c: Cell) bool {
            assert(c.cellType() == cell_type);
            return cm.marker.value(c.index());
        }

        pub fn reset(cm: *@This()) void {
            cm.marker.fill(false);
        }
    };
}

// ------------------------------------------------------------------------- //
// Cell Data
// ------------------------------------------------------------------------- //

/// A CellData is a handle to a data array of type `T` associated with cells of the given CellType.
/// It provides functions to access the data associated with a given cell or its index.
pub fn CellData(comptime cell_type: CellType, comptime T: type) type {
    return struct {
        pub const CellType = cell_type;
        pub const DataType = T;

        data: *Data(T),

        fn ValuePtrType(comptime SelfType: type) type {
            if (@typeInfo(SelfType).pointer.is_const) {
                return *const T;
            } else {
                return *T;
            }
        }
        pub fn valuePtr(cd: anytype, c: Cell) ValuePtrType(@TypeOf(cd)) {
            assert(c.cellType() == cell_type);
            return cd.data.valuePtr(c.index());
        }
        pub fn value(cd: @This(), c: Cell) T {
            assert(c.cellType() == cell_type);
            return cd.data.value(c.index());
        }

        pub fn name(cd: @This()) []const u8 {
            return cd.data.data_gen.name;
        }

        pub fn gen(cd: @This()) *DataGen {
            return &cd.data.data_gen;
        }
    };
}

/// Creates a new data array of the type `T` associated with cells of the given CellType.
/// The `name` must be unique for the given CellType for the creation to succeed.
pub fn addData(ig: *IncidenceGraph, comptime cell_type: CellType, comptime T: type, name: []const u8) !CellData(cell_type, T) {
    return .{ .data = try ig.dataContainerPtr(cell_type).addData(T, name) };
}

/// Returns a handle to the data array of the type `T` associated with cells of the given CellType
/// if it exists with the given name, otherwise returns null.
pub fn getData(ig: *const IncidenceGraph, comptime cell_type: CellType, comptime T: type, name: []const u8) ?CellData(cell_type, T) {
    if (ig.dataContainerPtr(cell_type).getData(T, name)) |d| {
        return .{ .data = d };
    } else return null;
}

/// Returns a handle to the data array of the type `T` associated with cells of the given CellType
/// if it exists with the given name, otherwise creates a new data array of the type `T` associated with cells of the given CellType
/// and returns a handle to it, along with a boolean indicating whether the data array was newly created (true) or already existed (false).
pub fn getOrAddData(ig: *IncidenceGraph, comptime cell_type: CellType, comptime T: type, name: []const u8) !struct { CellData(cell_type, T), bool } {
    const d, const created = try ig.dataContainerPtr(cell_type).getOrAddData(T, name);
    return .{ .{ .data = d }, created };
}

/// Removes the data array of the type `T` associated with cells of the given CellType.
pub fn removeData(ig: *IncidenceGraph, comptime cell_type: CellType, cell_data: anytype) void {
    ig.dataContainerPtr(cell_type).removeData(cell_data.gen());
}

// ------------------------------------------------------------------------- //
// Cell Management
// ------------------------------------------------------------------------- //

pub fn addVertex(ig: *IncidenceGraph) !Cell {
    const idx = try ig.vertex_data.acquireIndex();
    ig.vertex_incident_edges.valuePtr(idx).* = .empty;
    return .{ .vertex = idx };
}

pub fn addEdge(ig: *IncidenceGraph, v0: Cell, v1: Cell) !Cell {
    assert(v0.cellType() == .vertex);
    assert(v1.cellType() == .vertex);
    const idx = try ig.edge_data.acquireIndex();
    ig.edge_incident_vertices.valuePtr(idx).* = .{ v0.index(), v1.index() };
    ig.edge_incident_faces.valuePtr(idx).* = .empty;
    try ig.vertex_incident_edges.valuePtr(v0.index()).append(ig.allocator, idx);
    try ig.vertex_incident_edges.valuePtr(v1.index()).append(ig.allocator, idx);
    return .{ .edge = idx };
}

pub fn addFace(ig: *IncidenceGraph, edges: []const Cell) !Cell {
    const idx = try ig.face_data.acquireIndex();
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

/// Returns the number of cells of the given CellType in the given IncidenceGraph.
pub fn nbCells(ig: *const IncidenceGraph, cell_type: CellType) u32 {
    return ig.dataContainerPtr(cell_type).nbElements();
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
