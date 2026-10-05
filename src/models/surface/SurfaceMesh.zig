//! A SurfaceMesh is a combinatorial map representing a 2-manifold surface mesh.
//! A combinatorial map is a topological data structure based on darts and relations between them
//! (see https://en.wikipedia.org/wiki/Combinatorial_map).
//! Each cell of the mesh is a subset of darts (formally defined as orbits),
//! and each dart belongs to exactly one cell of each dimension (vertex, edge, face in 2D).
//! Consequently, a cell can be represented by any of its darts
//! and a dart can be used as the representative of any of the cells it belongs to.
//!
//! In this implementation, a dart is simply represented by an integer index.
//! A DataContainer (index-based synchronized collection of arrays with empty space management)
//! is used to store the data associated to each dart:
//! - the phi1, phi_1 and phi2 relations that define the combinatorial map,
//! - the indices of the vertex, edge and face cells the dart belongs to.
//! These cell indices refer to entries in dedicated DataContainers that are used to store:
//! - data associated to the vertices, edges and faces of the mesh,
//! - a representative dart of each vertex, edge and face cell (used to iterate over the cells of the mesh).
//! Halfedges and corners do not have their own index & DataContainers: since they are single darts,
//! their index is that of the dart, and their datas are stored in the dart DataContainer.
//!
//! TODO: talk about boundary management

const SurfaceMesh = @This();

const std = @import("std");
const assert = std.debug.assert;

const zgp_log = std.log.scoped(.zgp);

const data = @import("../../utils/data.zig");
const DataContainer = data.DataContainer;
const DataGen = data.DataGen;
const Data = data.Data;
const invalid_index = data.invalid_index;

const BufferPool = @import("../../utils/BufferPool.zig").BufferPool;

// ------------------------------------------------------------------------- //
// Basic types
// ------------------------------------------------------------------------- //

/// A Dart is an index in the dart_data DataContainer of the SurfaceMesh.
pub const Dart = u32;

pub const CellType = enum {
    halfedge,
    corner,
    vertex,
    edge,
    face,
};

/// A Cell is a "typed" index in the DataContainer of the given CellType of the SurfaceMesh.
pub fn Cell(comptime cell_type: CellType) type {
    return struct {
        pub const CellType = cell_type;
        index: u32,
    };
}

// Convenience type aliases for the different Cell types.
pub const Halfedge = Cell(.halfedge);
pub const Corner = Cell(.corner);
pub const Vertex = Cell(.vertex);
pub const Edge = Cell(.edge);
pub const Face = Cell(.face);

// ------------------------------------------------------------------------- //
// Fields
// ------------------------------------------------------------------------- //

allocator: std.mem.Allocator,
index_buffer_pool: *BufferPool(u32), // the BufferPool is shared between SurfaceMeshes (owned by the SurfaceMeshStore)

/// Data containers for darts & the different cell types.
dart_data: DataContainer, // also used to store halfedge & corner data
vertex_data: DataContainer,
edge_data: DataContainer,
face_data: DataContainer,

/// Dart data: connectivity.
dart_phi1: *Data(Dart),
dart_phi_1: *Data(Dart),
dart_phi2: *Data(Dart),

/// Dart data: boundary marker.
dart_boundary_marker: *Data(bool), // true if the dart is a boundary dart (i.e. belongs to a boundary face)
nb_boundary_darts: u32, // number of boundary darts; only updated upon calls to SurfaceMeshStore.surfaceMeshConnectivityUpdated

/// Dart data: a Cell of each type (index in the respective DataContainer) associated with each dart.
dart_vertex: *Data(Vertex),
dart_edge: *Data(Edge),
dart_face: *Data(Face),

/// Cell data: a representative dart for each cell, stored in the respective DataContainer.
/// These representative darts are used to iterate over the cells of the mesh.
vertex_dart: *Data(Dart),
edge_dart: *Data(Dart),
face_dart: *Data(Dart),

/// CellSets for each cell type
vertex_sets: std.StringHashMapUnmanaged(VertexSet),
edge_sets: std.StringHashMapUnmanaged(EdgeSet),
face_sets: std.StringHashMapUnmanaged(FaceSet),

// ------------------------------------------------------------------------- //
// Basic accessors
// ------------------------------------------------------------------------- //

/// Return the dart associated with the given cell.
pub fn dart(sm: *const SurfaceMesh, c: anytype) Dart {
    return switch (@TypeOf(c).CellType) {
        .halfedge, .corner => c.index,
        .vertex => sm.vertex_dart.value(c.index),
        .edge => sm.edge_dart.value(c.index),
        .face => sm.face_dart.value(c.index),
    };
}

/// Return the cell of type cell_type associated with the given dart.
pub fn cell(sm: *const SurfaceMesh, d: Dart, comptime cell_type: CellType) Cell(cell_type) {
    switch (cell_type) {
        .halfedge => return .{ .index = d },
        .corner => return .{ .index = d },
        .vertex => return sm.dart_vertex.value(d),
        .edge => return sm.dart_edge.value(d),
        .face => return sm.dart_face.value(d),
    }
}

// Convenience functions to get the cells associated with the given dart.
pub fn halfedge(_: *const SurfaceMesh, d: Dart) Halfedge {
    return .{ .index = d };
}
pub fn corner(_: *const SurfaceMesh, d: Dart) Corner {
    return .{ .index = d };
}
pub fn vertex(sm: *const SurfaceMesh, d: Dart) Vertex {
    return sm.dart_vertex.value(d);
}
pub fn edge(sm: *const SurfaceMesh, d: Dart) Edge {
    return sm.dart_edge.value(d);
}
pub fn face(sm: *const SurfaceMesh, d: Dart) Face {
    return sm.dart_face.value(d);
}

/// Return a pointer to the data container for the given CellType.
pub fn dataContainerPtr(sm: anytype, comptime cell_type: CellType) if (@typeInfo(@TypeOf(sm)).pointer.is_const) *const DataContainer else *DataContainer {
    return switch (cell_type) {
        .halfedge, .corner => &sm.dart_data,
        .vertex => &sm.vertex_data,
        .edge => &sm.edge_data,
        .face => &sm.face_data,
    };
}

/// Return a pointer to the HashMap of CellSets for the given CellType.
pub fn cellSetContainerPtr(sm: anytype, comptime cell_type: CellType) if (@typeInfo(@TypeOf(sm)).pointer.is_const) *const std.StringHashMapUnmanaged(CellSet(cell_type)) else *std.StringHashMapUnmanaged(CellSet(cell_type)) {
    return switch (cell_type) {
        .vertex => &sm.vertex_sets,
        .edge => &sm.edge_sets,
        .face => &sm.face_sets,
        else => unreachable,
    };
}

// ------------------------------------------------------------------------- //
// Initialization, deinitialization and cloning
// ------------------------------------------------------------------------- //

pub fn init(sm: *SurfaceMesh, allocator: std.mem.Allocator, index_buffer_pool: *BufferPool(u32)) !void {
    sm.allocator = allocator;
    sm.index_buffer_pool = index_buffer_pool;

    try sm.dart_data.init(allocator);
    try sm.vertex_data.init(allocator);
    try sm.edge_data.init(allocator);
    try sm.face_data.init(allocator);

    sm.dart_phi1 = try sm.dart_data.addData(Dart, "phi1");
    sm.dart_phi_1 = try sm.dart_data.addData(Dart, "phi_1");
    sm.dart_phi2 = try sm.dart_data.addData(Dart, "phi2");

    sm.dart_boundary_marker = try sm.dart_data.acquireMarker();
    sm.nb_boundary_darts = 0;

    sm.dart_vertex = try sm.dart_data.addData(Vertex, "vertex");
    sm.dart_edge = try sm.dart_data.addData(Edge, "edge");
    sm.dart_face = try sm.dart_data.addData(Face, "face");

    sm.vertex_dart = try sm.vertex_data.addData(Dart, "dart");
    sm.edge_dart = try sm.edge_data.addData(Dart, "dart");
    sm.face_dart = try sm.face_data.addData(Dart, "dart");

    sm.vertex_sets = .empty;
    sm.edge_sets = .empty;
    sm.face_sets = .empty;
}

pub fn deinit(sm: *SurfaceMesh) void {
    var vertex_sets_it = sm.vertex_sets.iterator();
    while (vertex_sets_it.next()) |entry| {
        const name: [:0]const u8 = @ptrCast(entry.key_ptr.*); // the name is a null-terminated string (dupeSentinel in addCellSet)
        sm.allocator.free(name); // free the name
        entry.value_ptr.deinit();
    }
    var edge_sets_it = sm.edge_sets.iterator();
    while (edge_sets_it.next()) |entry| {
        const name: [:0]const u8 = @ptrCast(entry.key_ptr.*); // the name is a null-terminated string (dupeSentinel in addCellSet)
        sm.allocator.free(name); // free the name
        entry.value_ptr.deinit();
    }
    var face_sets_it = sm.face_sets.iterator();
    while (face_sets_it.next()) |entry| {
        const name: [:0]const u8 = @ptrCast(entry.key_ptr.*); // the name is a null-terminated string (dupeSentinel in addCellSet)
        sm.allocator.free(name); // free the name
        entry.value_ptr.deinit();
    }
    sm.vertex_sets.deinit(sm.allocator);
    sm.edge_sets.deinit(sm.allocator);
    sm.face_sets.deinit(sm.allocator);

    sm.dart_data.deinit();
    sm.vertex_data.deinit();
    sm.edge_data.deinit();
    sm.face_data.deinit();
}

pub fn clearRetainingCapacity(sm: *SurfaceMesh) void {
    var vertex_sets_it = sm.vertex_sets.valueIterator();
    while (vertex_sets_it.next()) |vs| {
        vs.clear();
    }
    var edge_sets_it = sm.edge_sets.valueIterator();
    while (edge_sets_it.next()) |es| {
        es.clear();
    }
    var face_sets_it = sm.face_sets.valueIterator();
    while (face_sets_it.next()) |fs| {
        fs.clear();
    }
    sm.dart_data.clearRetainingCapacity();
    sm.vertex_data.clearRetainingCapacity();
    sm.edge_data.clearRetainingCapacity();
    sm.face_data.clearRetainingCapacity();
}

pub fn clone(sm: *const SurfaceMesh, allocator: std.mem.Allocator) !*SurfaceMesh {
    const cloned_sm = try allocator.create(SurfaceMesh);
    errdefer allocator.destroy(cloned_sm);

    cloned_sm.allocator = allocator;
    cloned_sm.index_buffer_pool = sm.index_buffer_pool;

    // Markers are not copied by ths initFrom function
    try cloned_sm.dart_data.initFrom(&sm.dart_data, true, allocator);
    try cloned_sm.vertex_data.initFrom(&sm.vertex_data, true, allocator);
    try cloned_sm.edge_data.initFrom(&sm.edge_data, true, allocator);
    try cloned_sm.face_data.initFrom(&sm.face_data, true, allocator);

    // recover the topological relations from the copied Dart DataContainer
    cloned_sm.dart_phi1 = cloned_sm.dart_data.getData(Dart, "phi1").?;
    cloned_sm.dart_phi_1 = cloned_sm.dart_data.getData(Dart, "phi_1").?;
    cloned_sm.dart_phi2 = cloned_sm.dart_data.getData(Dart, "phi2").?;

    // create the boundary marker and copy its values from the source SurfaceMesh
    cloned_sm.dart_boundary_marker = try cloned_sm.dart_data.getMarker();
    cloned_sm.dart_boundary_marker.copyFrom(sm.dart_boundary_marker);
    cloned_sm.nb_boundary_darts = sm.nb_boundary_darts;

    // recover the cells from the copied Dart DataContainer
    cloned_sm.dart_vertex = cloned_sm.dart_data.getData(Vertex, "vertex").?;
    cloned_sm.dart_edge = cloned_sm.dart_data.getData(Edge, "edge").?;
    cloned_sm.dart_face = cloned_sm.dart_data.getData(Face, "face").?;

    // recover the representative darts for each cell type from the respective copied DataContainers
    cloned_sm.vertex_dart = cloned_sm.vertex_data.getData(Dart, "dart").?;
    cloned_sm.edge_dart = cloned_sm.edge_data.getData(Dart, "dart").?;
    cloned_sm.face_dart = cloned_sm.face_data.getData(Dart, "dart").?;

    cloned_sm.vertex_sets = .empty;
    cloned_sm.edge_sets = .empty;
    cloned_sm.face_sets = .empty;

    return cloned_sm;
}

pub fn cloneWithoutCellData(sm: *const SurfaceMesh, allocator: std.mem.Allocator) !*SurfaceMesh {
    const cloned_sm = try allocator.create(SurfaceMesh);
    errdefer allocator.destroy(cloned_sm);

    cloned_sm.allocator = allocator;
    cloned_sm.index_buffer_pool = sm.index_buffer_pool;

    // Copy only the structure of the DataContainers (i.e. size, capacity, indices management) but not the CellData
    // Markers are not copied by ths initFrom function
    try cloned_sm.dart_data.initFrom(&sm.dart_data, false, allocator);
    try cloned_sm.vertex_data.initFrom(&sm.vertex_data, false, allocator);
    try cloned_sm.edge_data.initFrom(&sm.edge_data, false, allocator);
    try cloned_sm.face_data.initFrom(&sm.face_data, false, allocator);

    // create the topological relations and copy them from the source Dart DataContainer
    cloned_sm.dart_phi1 = try cloned_sm.dart_data.addData(Dart, "phi1");
    cloned_sm.dart_phi1.copyFrom(sm.dart_phi1);
    cloned_sm.dart_phi_1 = try cloned_sm.dart_data.addData(Dart, "phi_1");
    cloned_sm.dart_phi_1.copyFrom(sm.dart_phi_1);
    cloned_sm.dart_phi2 = try cloned_sm.dart_data.addData(Dart, "phi2");
    cloned_sm.dart_phi2.copyFrom(sm.dart_phi2);

    // create the boundary marker and copy its values from the source SurfaceMesh
    cloned_sm.dart_boundary_marker = try cloned_sm.dart_data.acquireMarker();
    cloned_sm.dart_boundary_marker.copyFrom(sm.dart_boundary_marker);
    cloned_sm.nb_boundary_darts = sm.nb_boundary_darts;

    // create the cells and copy their values from the source SurfaceMesh
    cloned_sm.dart_vertex = try cloned_sm.dart_data.addData(Vertex, "vertex");
    cloned_sm.dart_vertex.copyFrom(sm.dart_vertex);
    cloned_sm.dart_edge = try cloned_sm.dart_data.addData(Edge, "edge");
    cloned_sm.dart_edge.copyFrom(sm.dart_edge);
    cloned_sm.dart_face = try cloned_sm.dart_data.addData(Face, "face");
    cloned_sm.dart_face.copyFrom(sm.dart_face);

    // create the representative darts for each cell type and copy them from the source DataContainers
    cloned_sm.vertex_dart = try cloned_sm.vertex_data.addData(Dart, "dart");
    cloned_sm.vertex_dart.copyFrom(sm.vertex_dart);
    cloned_sm.edge_dart = try cloned_sm.edge_data.addData(Dart, "dart");
    cloned_sm.edge_dart.copyFrom(sm.edge_dart);
    cloned_sm.face_dart = try cloned_sm.face_data.addData(Dart, "dart");
    cloned_sm.face_dart.copyFrom(sm.face_dart);

    cloned_sm.vertex_sets = .empty;
    cloned_sm.edge_sets = .empty;
    cloned_sm.face_sets = .empty;

    return cloned_sm;
}

// ------------------------------------------------------------------------- //
// Iterators
// ------------------------------------------------------------------------- //

/// A DartIterator iterates over all the darts of the SurfaceMesh (including boundary darts).
/// (adds a Dart type over the DataContainer.IndexIterator)
const DartIterator = struct {
    dc_it: DataContainer.IndexIterator,
    pub fn next(it: *DartIterator) ?Dart {
        return it.dc_it.next();
    }
    pub fn nextSafe(it: *DartIterator) ?Dart {
        return it.dc_it.nextSafe();
    }
    pub fn reset(it: *DartIterator) void {
        it.dc_it.reset();
    }
};

/// Return a DartIterator that iterates over all the darts of the SurfaceMesh (including boundary darts).
pub fn dartIterator(sm: *const SurfaceMesh) DartIterator {
    return .{ .dc_it = sm.dart_data.indexIterator() };
}

/// A CellIterator iterates over all the cells of the given type in the SurfaceMesh.
/// (adds a Cell type over the DataContainer.IndexIterator)
pub fn CellIterator(comptime cell_type: CellType) type {
    return struct {
        dc_it: DataContainer.IndexIterator,
        pub fn next(it: *@This()) ?Cell(cell_type) {
            return .{ .index = it.dc_it.next() orelse return null };
        }
        pub fn nextSafe(it: *@This()) ?Cell(cell_type) {
            return .{ .index = it.dc_it.nextSafe() orelse return null };
        }
        pub fn reset(it: *@This()) void {
            it.dc_it.reset();
        }
    };
}

/// Return a CellIterator that iterates over all the cells of the given type in the SurfaceMesh.
pub fn cellIterator(sm: *const SurfaceMesh, comptime cell_type: CellType) CellIterator(cell_type) {
    return .{ .dc_it = sm.dataContainerPtr(cell_type).indexIterator() };
}

// Convenience functions to get the iterators for the different Cell types.
pub fn halfedgeIterator(sm: *const SurfaceMesh) CellIterator(.halfedge) {
    return sm.cellIterator(.halfedge);
}
pub fn cornerIterator(sm: *const SurfaceMesh) CellIterator(.corner) {
    return sm.cellIterator(.corner);
}
pub fn vertexIterator(sm: *const SurfaceMesh) CellIterator(.vertex) {
    return sm.cellIterator(.vertex);
}
pub fn edgeIterator(sm: *const SurfaceMesh) CellIterator(.edge) {
    return sm.cellIterator(.edge);
}
pub fn faceIterator(sm: *const SurfaceMesh) CellIterator(.face) {
    return sm.cellIterator(.face);
}

/// A OrbitDartIterator iterates over all the darts of a cell in the SurfaceMesh.
/// (including the boundary darts that are part of the cell)
pub fn OrbitDartIterator(comptime cell_type: CellType) type {
    return struct {
        surface_mesh: *const SurfaceMesh,
        starting_dart: Dart,
        current_dart: ?Dart,
        pub fn init(sm: *const SurfaceMesh, d: Dart) @This() {
            return .{
                .surface_mesh = sm,
                .starting_dart = d,
                .current_dart = d,
            };
        }
        pub fn next(it: *@This()) ?Dart {
            // prepare current_dart for next iteration
            defer {
                if (it.current_dart) |current_dart| {
                    it.current_dart = switch (cell_type) {
                        .halfedge, .corner => current_dart,
                        .vertex => it.surface_mesh.phi2(it.surface_mesh.phi_1(current_dart)),
                        .edge => it.surface_mesh.phi2(current_dart),
                        .face => it.surface_mesh.phi1(current_dart),
                    };
                    // the next current_dart becomes null when we get back to the starting dart
                    if (it.current_dart == it.starting_dart) {
                        it.current_dart = null;
                    }
                }
            }
            return it.current_dart;
        }
        pub fn reset(it: *@This()) void {
            it.current_dart = it.starting_dart;
        }
    };
}

/// Return an OrbitDartIterator that iterates over all the darts of the given orbit (i.e. a dart and a CellType).
pub fn orbitDartIterator(sm: *const SurfaceMesh, d: Dart, comptime cell_type: CellType) OrbitDartIterator(cell_type) {
    return .init(sm, d);
}

/// Return the first dart of the orbit of d of the given CellType that is not marked as a boundary dart.
/// The only case in which an invalid index can be returned is when called on an orbit that is
/// entirely composed of boundary darts, i.e. boundary face, boundary halfedge, boundary corner.
pub fn orbitNonBoundaryDart(sm: *const SurfaceMesh, d: Dart, comptime cell_type: CellType) Dart {
    var dart_it = sm.orbitDartIterator(d, cell_type);
    return while (dart_it.next()) |cd| {
        if (!sm.isBoundaryDart(cd)) break cd;
    } else invalid_index;
}

/// Return true if the d2 belongs to the orbit of the given CellType of d1.
pub fn dartBelongsToOrbit(sm: *const SurfaceMesh, d1: Dart, d2: Dart, comptime cell_type: CellType) bool {
    var dart_it = sm.orbitDartIterator(d1, cell_type);
    return while (dart_it.next()) |d| {
        if (d == d2) break true;
    } else false;
}

// ------------------------------------------------------------------------- //
// Markers
// ------------------------------------------------------------------------- //

/// A DartMarker stores a boolean for each dart.
/// It can be used for any purpose, using the value/valuePtr/reset functions.
pub const DartMarker = struct {
    surface_mesh: *SurfaceMesh,
    marker: *Data(bool),

    pub fn init(sm: *SurfaceMesh) !DartMarker {
        return .{
            .surface_mesh = sm,
            .marker = try sm.dart_data.acquireMarker(),
        };
    }
    pub fn deinit(dm: *DartMarker) void {
        dm.surface_mesh.dart_data.releaseMarker(dm.marker);
    }

    pub fn mark(dm: *DartMarker, d: Dart) void {
        // assert(!dm.isMarked(d));
        dm.marker.valuePtr(d).* = true;
    }
    pub fn unmark(dm: *DartMarker, d: Dart) void {
        // assert(dm.isMarked(d));
        dm.marker.valuePtr(d).* = false;
    }
    pub fn isMarked(dm: *DartMarker, d: Dart) bool {
        return dm.marker.value(d);
    }

    pub fn markOrbit(dm: *DartMarker, d: Dart, cell_type: CellType) void {
        var dart_it = dm.surface_mesh.orbitDartIterator(d, cell_type);
        while (dart_it.next()) |dd| {
            dm.mark(dd);
        }
    }
    pub fn unmarkOrbit(dm: *DartMarker, d: Dart, cell_type: CellType) void {
        var dart_it = dm.surface_mesh.orbitDartIterator(d, cell_type);
        while (dart_it.next()) |dd| {
            dm.unmark(dd);
        }
    }

    pub fn reset(dm: *DartMarker) void {
        dm.marker.fill(false);
    }
};

/// A CellMarker stores a boolean for each cell of the given CellType.
/// It can be used for any purpose, using the value/valuePtr/reset functions.
pub fn CellMarker(comptime cell_type: CellType) type {
    return struct {
        surface_mesh: *SurfaceMesh,
        marker: *Data(bool),

        pub fn init(sm: *SurfaceMesh) !@This() {
            return .{
                .surface_mesh = sm,
                .marker = try sm.dataContainerPtr(cell_type).acquireMarker(),
            };
        }
        pub fn deinit(cm: *@This()) void {
            cm.surface_mesh.dataContainerPtr(cell_type).releaseMarker(cm.marker);
        }

        pub fn mark(cm: *@This(), c: Cell(cell_type)) void {
            cm.marker.valuePtr(c.index).* = true;
        }
        pub fn unmark(cm: *@This(), c: Cell(cell_type)) void {
            cm.marker.valuePtr(c.index).* = false;
        }
        pub fn isMarked(cm: *@This(), c: Cell(cell_type)) bool {
            return cm.marker.value(c.index);
        }

        pub fn reset(cm: *@This()) void {
            cm.marker.fill(false);
        }
    };
}

// Convenience type aliases for the different CellMarker types.
pub const VertexMarker = CellMarker(.vertex);
pub const EdgeMarker = CellMarker(.edge);
pub const FaceMarker = CellMarker(.face);

// ------------------------------------------------------------------------- //
// Parallel Cell Task Runner
// ------------------------------------------------------------------------- //

/// A ParallelCellTaskRunner allows to run tasks on the cells of the given CellType in parallel.
/// The `run` function takes a Task as an argument which is expected to expose a `run` function that takes a cell of the given CellType as argument.
/// The main thread iterates over the cells and fills buffers, in a double-buffering scheme.
/// Once the first group of buffers is filled, threads are spawned to run the task on these buffers, with a WaitGroup to track the completion of the tasks on this group of buffers.
/// Meanwhile, the main thread continues to iterate over the cells and fills the other group of buffers.
/// Once the second group of buffers is filled, threads are spawned to run the task on these buffers, with a WaitGroup to track the completion of the tasks on this group of buffers.
/// This process is repeated until all cells have been processed.
pub fn ParallelCellTaskRunner(comptime cell_type: CellType) type {
    const IndexBuffer = BufferPool(u32).Buffer;

    return struct {
        surface_mesh: *SurfaceMesh,
        iterator: CellIterator(cell_type),
        // manage two groups of buffers to be able to run tasks on one group while filling the other
        buffers: [2][]IndexBuffer,
        // one Group per group of buffers to be able to wait for the completion of tasks on each group independently
        wg: [2]std.Io.Group,

        pub fn init(sm: *SurfaceMesh) !@This() {
            const cpu_count = try std.Thread.getCpuCount();
            return .{
                .surface_mesh = sm,
                .iterator = sm.cellIterator(cell_type),
                .buffers = .{
                    blk: {
                        // acquire buffers from the pool (one buffer per thread) - first group
                        const buffers: []IndexBuffer = try sm.allocator.alloc(IndexBuffer, cpu_count);
                        for (buffers) |*buffer| {
                            buffer.* = try sm.index_buffer_pool.acquire();
                        }
                        break :blk buffers;
                    },
                    blk: {
                        // acquire buffers from the pool (one buffer per thread) - second group
                        const buffers: []IndexBuffer = try sm.allocator.alloc(IndexBuffer, cpu_count);
                        for (buffers) |*buffer| {
                            buffer.* = try sm.index_buffer_pool.acquire();
                        }
                        break :blk buffers;
                    },
                },
                .wg = .{ .init, .init },
            };
        }

        pub fn deinit(pctr: *@This()) void {
            for (0..2) |i| {
                for (pctr.buffers[i]) |*buffer| {
                    buffer.release();
                }
                pctr.surface_mesh.allocator.free(pctr.buffers[i]);
            }
        }

        pub fn reset(pctr: *@This()) void {
            pctr.iterator.reset();
        }

        fn runTaskOnBufferFunction(Task: type) fn (*Task, []u32) void {
            return struct {
                fn f(task: *Task, buf: []u32) void {
                    for (buf) |idx| task.run(Cell(cell_type){ .index = idx });
                }
            }.f;
        }

        // The `task` must expose a `run(self: *Self, cell: Cell(cell_type)) void` function
        pub fn run(pctr: *@This(), io: std.Io, task: anytype) !void {
            var current_buf_group: usize = 0;
            var current_buf_index: usize = 0;
            var current_index_in_buffer: usize = 0;
            while (pctr.iterator.next()) |c| {
                // add cell to current buffer of current buffer group
                pctr.buffers[current_buf_group][current_buf_index].data[current_index_in_buffer] = c.index;
                current_index_in_buffer += 1;
                // if the current buffer is full, run the task on it and switch to the next buffer of the current buffer group
                if (current_index_in_buffer == pctr.buffers[current_buf_group][current_buf_index].data.len) {
                    pctr.wg[current_buf_group].async(
                        io,
                        runTaskOnBufferFunction(@TypeOf(task)),
                        .{ @constCast(&task), pctr.buffers[current_buf_group][current_buf_index].data },
                    );
                    current_buf_index += 1;
                    current_index_in_buffer = 0;
                }
                // if we have used all the buffers of the current buffer group, switch to the next buffer group
                if (current_buf_index == pctr.buffers[current_buf_group].len) {
                    current_buf_group = (current_buf_group + 1) % 2;
                    // threads working on this buffer group are waited on before we can reuse the buffers of this group
                    try pctr.wg[current_buf_group].await(io);
                    current_buf_index = 0;
                }
            }
            // run the task on the last potentially partially filled buffer and wait for the threads to finish
            if (current_index_in_buffer > 0) {
                pctr.wg[current_buf_group].async(
                    io,
                    runTaskOnBufferFunction(@TypeOf(task)),
                    .{ @constCast(&task), pctr.buffers[current_buf_group][current_buf_index].data[0..current_index_in_buffer] },
                );
            }
            try pctr.wg[0].await(io);
            try pctr.wg[1].await(io);
        }
    };
}

// Convenience type aliases for the different ParallelCellTaskRunner types.
pub const ParallelHalfedgeTaskRunner = ParallelCellTaskRunner(.halfedge);
pub const ParallelCornerTaskRunner = ParallelCellTaskRunner(.corner);
pub const ParallelVertexTaskRunner = ParallelCellTaskRunner(.vertex);
pub const ParallelEdgeTaskRunner = ParallelCellTaskRunner(.edge);
pub const ParallelFaceTaskRunner = ParallelCellTaskRunner(.face);

// ------------------------------------------------------------------------- //
// Cell Data
// ------------------------------------------------------------------------- //

/// A CellData is a handle to a data array of type `T` associated with cells of the given CellType.
/// It provides functions to access the data associated with a given cell.
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
        pub fn valuePtr(cd: anytype, c: Cell(cell_type)) ValuePtrType(@TypeOf(cd)) {
            return cd.data.valuePtr(c.index);
        }
        pub fn value(cd: @This(), c: Cell(cell_type)) T {
            return cd.data.value(c.index);
        }

        pub fn name(cd: @This()) []const u8 {
            return cd.data.data_gen.name;
        }

        pub fn gen(cd: @This()) *DataGen {
            return &cd.data.data_gen;
        }
    };
}

// Convenience type aliases for the different CellData types.
pub fn HalfedgeData(comptime T: type) type {
    return CellData(.halfedge, T);
}
pub fn CornerData(comptime T: type) type {
    return CellData(.corner, T);
}
pub fn VertexData(comptime T: type) type {
    return CellData(.vertex, T);
}
pub fn EdgeData(comptime T: type) type {
    return CellData(.edge, T);
}
pub fn FaceData(comptime T: type) type {
    return CellData(.face, T);
}

/// Create a new data array of the type `T` associated with cells of the given CellType.
/// The `name` must be unique for the given CellType for the creation to succeed.
pub fn addData(sm: *SurfaceMesh, comptime cell_type: CellType, comptime T: type, name: []const u8) !CellData(cell_type, T) {
    return .{ .data = try sm.dataContainerPtr(cell_type).addData(T, name) };
}

/// Create a new data array of the type `T` associated with cells of the given CellType.
/// The `name` is generated by appending a unique random suffix to the given `prefix`, ensuring that the resulting name is unique for the given CellType.
/// The random suffix is generated using the provided random number generator `rng`.
pub fn addDataWithUniqueRandomName(sm: *SurfaceMesh, random: std.Random, comptime cell_type: CellType, comptime T: type, prefix: []const u8) !CellData(cell_type, T) {
    var buf: [64]u8 = undefined;
    while (true) {
        const suffix = random.int(u32);
        const name = try std.fmt.bufPrint(&buf, "{s}_{x:0>8}", .{ prefix, suffix });
        return sm.addData(cell_type, T, name) catch |err| switch (err) {
            error.DataNameAlreadyExists => continue,
            else => return err,
        };
    }
}

/// Return a handle to the data array of the type `T` associated with cells of the given CellType
/// if it exists with the given name, otherwise return null.
pub fn getData(sm: *const SurfaceMesh, comptime cell_type: CellType, comptime T: type, name: []const u8) ?CellData(cell_type, T) {
    if (sm.dataContainerPtr(cell_type).getData(T, name)) |d| {
        return .{ .data = d };
    } else return null;
}

/// Return a handle to the data array of the type `T` associated with cells of the given CellType
/// if it exists with the given name, otherwise create a new data array of the type `T` associated with cells of the given CellType
/// and return a handle to it, along with a boolean indicating whether the data array was newly created (true) or already existed (false).
pub fn getOrAddData(sm: *SurfaceMesh, comptime cell_type: CellType, comptime T: type, name: []const u8) !struct { CellData(cell_type, T), bool } {
    const d, const created = try sm.dataContainerPtr(cell_type).getOrAddData(T, name);
    return .{ .{ .data = d }, created };
}

/// Remove the given CellData.
pub fn removeData(sm: *SurfaceMesh, cell_data: anytype) void {
    sm.dataContainerPtr(@TypeOf(cell_data).CellType).removeData(cell_data.gen());
}

// ------------------------------------------------------------------------- //
// Cell Sets
// ------------------------------------------------------------------------- //

pub const CellSetGen = struct {
    surface_mesh: *SurfaceMesh,
    name: []const u8,
};

/// A CellSet manages a set of cells of a given CellType, using a marker to track the cells.
/// It provides functions to `add` and `remove` cells, `clear` the set, and check for the presence of a cell (`contains`).
/// The cells of the set are directly available in the `cells` array.
/// The `update` function has to be called after the SurfaceMesh has been modified to rebuild the CellSet based on the marker.
/// (this is done automatically in the SurfaceMeshStore.surfaceMeshConnectivityUpdated function)
pub fn CellSet(comptime cell_type: CellType) type {
    return struct {
        pub const CellType = cell_type;

        cell_set_gen: CellSetGen,
        cells: std.ArrayList(Cell(cell_type)),
        marker: CellMarker(cell_type),

        pub fn init(sm: *SurfaceMesh, name: []const u8) !@This() {
            return .{
                .cell_set_gen = .{
                    .surface_mesh = sm,
                    .name = name,
                },
                .cells = .empty,
                .marker = try .init(sm),
            };
        }
        pub fn deinit(cs: *@This()) void {
            cs.marker.deinit();
            cs.cells.deinit(cs.cell_set_gen.surface_mesh.allocator);
        }

        pub fn gen(cs: *const @This()) *const CellSetGen {
            return &cs.cell_set_gen;
        }

        pub fn contains(cs: *@This(), c: Cell(cell_type)) bool {
            return cs.marker.isMarked(c);
        }
        pub fn add(cs: *@This(), c: Cell(cell_type)) !void {
            if (cs.contains(c)) return;
            cs.marker.mark(c);
            try cs.cells.append(cs.cell_set_gen.surface_mesh.allocator, c);
        }
        pub fn remove(cs: *@This(), c: Cell(cell_type)) void {
            if (!cs.contains(c)) return;
            cs.marker.unmark(c);
            for (cs.cells.items, 0..) |cc, i| {
                if (cc.index == c.index) {
                    _ = cs.cells.swapRemove(i);
                    break;
                }
            }
        }
        pub fn clear(cs: *@This()) void {
            cs.marker.reset();
            cs.cells.clearRetainingCapacity();
        }
        pub fn update(cs: *@This()) !void {
            cs.cells.clearRetainingCapacity();
            var it = cs.cell_set_gen.surface_mesh.cellIterator(cell_type);
            while (it.next()) |c| {
                if (cs.marker.isMarked(c)) {
                    try cs.cells.append(cs.cell_set_gen.surface_mesh.allocator, c);
                }
            }
        }
    };
}

// Convenience type aliases for the different CellSet types.
pub const VertexSet = CellSet(.vertex);
pub const EdgeSet = CellSet(.edge);
pub const FaceSet = CellSet(.face);

/// Create a new CellSet for the given CellType.
/// The `name` must be unique for the given CellType for the creation to succeed.
pub fn addCellSet(sm: *SurfaceMesh, comptime cell_type: CellType, name: []const u8) !*CellSet(cell_type) {
    const cell_sets = sm.cellSetContainerPtr(cell_type);
    if (cell_sets.contains(name)) {
        return error.CellSetNameAlreadyExists;
    }

    const owned_name = try sm.allocator.dupeSentinel(u8, name, 0); // duplicate name to own the hashmap key
    errdefer sm.allocator.free(owned_name);

    try cell_sets.put(sm.allocator, owned_name, try .init(sm, owned_name));
    return cell_sets.getPtr(owned_name).?;
}

/// Return a pointer to the CellSet of the given CellType with the given name if it exists, otherwise return null.
pub fn getCellSet(sm: *const SurfaceMesh, comptime cell_type: CellType, name: []const u8) ?*CellSet(cell_type) {
    return sm.cellSetContainerPtr(cell_type).getPtr(name);
}

/// Return a pointer to the CellSet of the given CellType with the given name if it exists,
/// otherwise create a new CellSet with the given name and return a pointer to it.
pub fn getOrAddCellSet(sm: *SurfaceMesh, comptime cell_type: CellType, name: []const u8) !*CellSet(cell_type) {
    if (sm.getCellSet(cell_type, name)) |cs| {
        return cs;
    } else {
        return try sm.addCellSet(cell_type, name);
    }
}

/// Remove the given CellSet (passed by pointer).
pub fn removeCellSet(sm: *SurfaceMesh, cell_set: anytype) void {
    assert(cell_set.surface_mesh == sm);
    cell_set.deinit();
    if (sm.cellSetContainerPtr(@typeInfo(@TypeOf(cell_set)).pointer.child.CellType).remove(cell_set.cell_set_gen.name)) {
        const name: [:0]const u8 = @ptrCast(cell_set.cell_set_gen.name); // the name is a null-terminated string (dupeSentinel in addCellSet)
        sm.allocator.free(name); // free the name
    }
}

// ------------------------------------------------------------------------- //
// Dart Management
// ------------------------------------------------------------------------- //

fn addDart(sm: *SurfaceMesh) !Dart {
    const d = try sm.dart_data.acquireIndex();
    sm.dart_phi1.valuePtr(d).* = d;
    sm.dart_phi_1.valuePtr(d).* = d;
    sm.dart_phi2.valuePtr(d).* = d;
    sm.dart_vertex.valuePtr(d).* = .{ .index = invalid_index };
    sm.dart_edge.valuePtr(d).* = .{ .index = invalid_index };
    sm.dart_face.valuePtr(d).* = .{ .index = invalid_index };
    // boundary marker is already false on a new index
    return d;
}

fn removeDart(sm: *SurfaceMesh, d: Dart) void {
    inline for ([_]CellType{ .vertex, .edge, .face }) |cell_type| {
        const c = sm.cell(d, cell_type);
        if (c.index != invalid_index) {
            sm.dataContainerPtr(cell_type).unrefIndex(c.index);
        }
    }
    sm.dart_data.releaseIndex(d);
}

pub fn phi1(sm: *const SurfaceMesh, d: Dart) Dart {
    return sm.dart_phi1.value(d);
}
pub fn phi_1(sm: *const SurfaceMesh, d: Dart) Dart {
    return sm.dart_phi_1.value(d);
}
pub fn phi2(sm: *const SurfaceMesh, d: Dart) Dart {
    return sm.dart_phi2.value(d);
}

pub fn phi1Sew(sm: *SurfaceMesh, d1: Dart, d2: Dart) void {
    assert(d1 != d2);
    const d3 = sm.phi1(d1);
    const d4 = sm.phi1(d2);
    sm.dart_phi1.valuePtr(d1).* = d4;
    sm.dart_phi1.valuePtr(d2).* = d3;
    sm.dart_phi_1.valuePtr(d4).* = d1;
    sm.dart_phi_1.valuePtr(d3).* = d2;
}

pub fn phi2Sew(sm: *SurfaceMesh, d1: Dart, d2: Dart) void {
    assert(d1 != d2);
    assert(sm.phi2(d1) == d1);
    assert(sm.phi2(d2) == d2);
    sm.dart_phi2.valuePtr(d1).* = d2;
    sm.dart_phi2.valuePtr(d2).* = d1;
}

pub fn phi2Unsew(sm: *SurfaceMesh, d: Dart) void {
    const d2 = sm.phi2(d);
    sm.dart_phi2.valuePtr(d).* = d;
    sm.dart_phi2.valuePtr(d2).* = d2;
}

pub fn isBoundaryDart(sm: *const SurfaceMesh, d: Dart) bool {
    return sm.dart_boundary_marker.value(d);
}

/// Return true if the orbit of the given dart is incident to a boundary face, false otherwise.
pub fn isOrbitIncidentToBoundary(sm: *const SurfaceMesh, d: Dart, comptime cell_type: CellType) bool {
    return switch (cell_type) {
        // a vertex is incident to a boundary face if one of its darts is part of a boundary face
        .vertex => blk: {
            var dart_it = sm.orbitDartIterator(d, cell_type);
            while (dart_it.next()) |dd| {
                if (sm.isBoundaryDart(dd)) {
                    break :blk true;
                }
            }
            break :blk false;
        },
        // an edge is incident to a boundary face if one of its 2 darts is part of a boundary face
        .edge => blk: {
            break :blk sm.isBoundaryDart(d) or sm.isBoundaryDart(sm.phi2(d));
        },
        else => unreachable,
    };
}

// ------------------------------------------------------------------------- //
// Cell Management
// ------------------------------------------------------------------------- //

/// Add a cell of the given CellType.
/// Only vertices, edges and faces can be added (halfedges & corners are their own cells through their unique dart index).
/// The new cell is not associated with any dart of the mesh.
/// This function is only intended for use in SurfaceMesh creation process (import, ...) as the new cell is not
/// in use until it is associated with darts of the mesh.
pub fn addCell(sm: *SurfaceMesh, comptime cell_type: CellType) !Cell(cell_type) {
    assert(cell_type == .vertex or cell_type == .edge or cell_type == .face);
    const c: Cell(cell_type) = .{ .index = try sm.dataContainerPtr(cell_type).acquireIndex() };
    sm.setCellDart(c, invalid_index); // the new cell is not associated with any dart yet
    return c;
}

/// Associate a dart with the given cell.
/// Reference counts of old and new indices are updated accordingly (see DataContainer.refIndex & unrefIndex).
/// Should only be called for vertex, edge and face cell types (halfedges & corners are their own cells through their unique dart index).
pub fn setDartCell(sm: *SurfaceMesh, d: Dart, c: anytype) void {
    assert(c.index != invalid_index);

    const old_index = switch (@TypeOf(c).CellType) {
        .vertex => sm.dart_vertex.value(d).index,
        .edge => sm.dart_edge.value(d).index,
        .face => sm.dart_face.value(d).index,
        else => unreachable,
    };
    if (old_index == c.index) return; // no change

    var data_container = sm.dataContainerPtr(@TypeOf(c).CellType);
    data_container.refIndex(c.index);
    if (old_index != invalid_index) {
        data_container.unrefIndex(old_index);
    }

    switch (@TypeOf(c).CellType) {
        .vertex => sm.dart_vertex.valuePtr(d).* = Vertex{ .index = c.index },
        .edge => sm.dart_edge.valuePtr(d).* = Edge{ .index = c.index },
        .face => sm.dart_face.valuePtr(d).* = Face{ .index = c.index },
        else => unreachable,
    }
}

/// Associate all the darts of the corresponding orbit of dart d with the given cell.
/// Should only be called for vertex, edge and face cell types (halfedges & corners are their own cells through their unique dart index).
fn setOrbitCell(sm: *SurfaceMesh, d: Dart, c: anytype) void {
    var dart_it = sm.orbitDartIterator(d, @TypeOf(c).CellType); // cannot use sm.cellDartIterator(c) because sm.dart(c) is likely not set yet
    while (dart_it.next()) |cd| {
        sm.setDartCell(cd, c);
    }
}

/// Associate a cell with the given representative dart.
/// Should only be called for vertex, edge and face cell types (halfedges & corners are their own cells through their unique dart index).
fn setCellDart(sm: *SurfaceMesh, c: anytype, d: Dart) void {
    switch (@TypeOf(c).CellType) {
        .vertex => sm.vertex_dart.valuePtr(c.index).* = d,
        .edge => sm.edge_dart.valuePtr(c.index).* = d,
        .face => sm.face_dart.valuePtr(c.index).* = d,
        else => unreachable,
    }
}

/// Iterate over the orbits of the given CellType and associate them with a cell if they do not already have one.
/// If part of the darts of an orbit already have a cell, this cell is assigned to all the darts of the orbit.
/// Boundary faces are not associated with a cell.
/// Representative darts of the cells are set along the way (only non-boundary darts are chosen as representative).
pub fn initCells(sm: *SurfaceMesh, comptime cell_type: CellType) !void {
    assert(cell_type == .vertex or cell_type == .edge or cell_type == .face);
    var dm: DartMarker = try .init(sm);
    defer dm.deinit();
    var it = sm.dartIterator();
    while (it.next()) |d| {
        if (dm.isMarked(d)) continue; // skip darts that are part of a cell that have already been processed
        if (sm.isBoundaryDart(d)) continue; // skip boundary darts (boundary faces are not indexed)

        // first check if the orbit is already associated with a cell, even partially
        // (assume that even if only partially associated, all the darts of the orbit have the same cell)
        var c: Cell(cell_type) = .{ .index = invalid_index };
        var dart_it = sm.orbitDartIterator(d, cell_type);
        while (dart_it.next()) |cd| {
            const cd_cell = sm.cell(cd, cell_type);
            if (cd_cell.index != invalid_index) {
                c = cd_cell;
                break;
            }
        }
        // if the orbit is not yet associated with a cell, add a new cell
        if (c.index == invalid_index) {
            c = try sm.addCell(cell_type);
        }
        // associate all the darts of the orbit with the cell and mark them along the way
        dart_it.reset();
        while (dart_it.next()) |cd| {
            sm.setDartCell(cd, c);
            dm.mark(cd);
        }
        // set the representative dart of the cell to the first encountered (non-boundary) dart of the cell
        sm.setCellDart(c, d);
    }
}

/// Return the number of cells of the given CellType.
/// For vertices, edges and faces, the number of cells is simply the number of elements (active indices)
/// in the corresponding DataContainer.
/// For halfedges and corners, the number of cells is the number of non-boundary darts.
pub fn nbCells(sm: *SurfaceMesh, comptime cell_type: CellType) u32 {
    return switch (cell_type) {
        .vertex, .edge, .face => sm.dataContainerPtr(cell_type).nbElements(),
        .halfedge, .corner => sm.dart_data.nbElements() - sm.nb_boundary_darts,
    };
}

/// Return the number of boundary faces in the SurfaceMesh.
pub fn nbBoundaryFaces(sm: *SurfaceMesh) !u32 {
    var count: u32 = 0;
    var dm: DartMarker = try .init(sm);
    defer dm.deinit();
    var it = sm.dartIterator();
    while (it.next()) |d| {
        if (dm.isMarked(d)) continue;
        if (sm.isBoundaryDart(d)) {
            count += 1;
            var dart_it = sm.orbitDartIterator(d, .face);
            while (dart_it.next()) |cd| {
                dm.mark(cd);
            }
        }
    }
    return count;
}

/// Return the degree of the given cell (number of d+1 incident cells).
/// Only vertices and edges have a degree (faces are top-cells and do not have a degree).
pub fn degree(sm: *const SurfaceMesh, c: anytype) u32 {
    return switch (@TypeOf(c).CellType) {
        // nb refs is equal to the number of darts of the vertex which is equal to its degree
        // (no need to iterate through the darts of the vertex)
        .vertex => blk: {
            assert(sm.vertex_data.isActiveIndex(c.index));
            break :blk sm.vertex_data.nb_refs.value(c.index);
        },
        .edge => blk: {
            const d = sm.dart(c);
            break :blk if (sm.isBoundaryDart(d) or sm.isBoundaryDart(sm.phi2(d))) 1 else 2;
        },
        else => unreachable,
    };
}

/// Return the codegree of the given cell (number of d-1 incident cells).
/// Only edges and faces have a codegree (vertices are 0-cells and do not have a codegree).
/// Cannot be called on boundary faces as they are not associated with a cell.
pub fn codegree(sm: *const SurfaceMesh, c: anytype) u32 {
    return switch (@TypeOf(c).CellType) {
        .edge => 2,
        // nb refs is equal to the number of darts of the face which is equal to its codegree
        // (no need to iterate through the darts of the face)
        .face => blk: {
            assert(sm.face_data.isActiveIndex(c.index));
            break :blk sm.face_data.nb_refs.value(c.index);
        },
        else => unreachable,
    };
}

// ------------------------------------------------------------------------- //
// Integrity Check
// ------------------------------------------------------------------------- //

/// Check the integrity of the SurfaceMesh and returns true if it is valid, false otherwise.
pub fn checkIntegrity(sm: *SurfaceMesh) !bool {
    var ok = true;
    var d_it = sm.dartIterator();
    while (d_it.next()) |d| {
        const d2 = sm.phi2(d);
        if (d2 == d) {
            zgp_log.warn("Dart {d} is phi2-linked to itself", .{d});
            ok = false;
        }
        if (sm.phi2(d2) != d) {
            zgp_log.warn("Inconsistent phi2: phi2(phi2({d}) != {d}", .{ d, d });
            ok = false;
        }
        const d1 = sm.phi1(d);
        if (sm.phi_1(d1) != d) {
            zgp_log.warn("Inconsistent phi_1: phi_1(phi1({d}) != {d}", .{ d, d });
            ok = false;
        }
        const d_1 = sm.phi_1(d);
        if (sm.phi1(d_1) != d) {
            zgp_log.warn("Inconsistent phi1: phi1(phi_1({d}) != {d}", .{ d, d });
            ok = false;
        }
        if (sm.isBoundaryDart(d)) {
            if (!sm.isBoundaryDart(d1)) {
                zgp_log.warn("Inconsistent boundary face marking: {d} and {d}", .{ d, d1 });
                ok = false;
            }
            if (sm.isBoundaryDart(d2)) {
                zgp_log.warn("Adjacent boundary faces: {d} and {d}", .{ d, d2 });
                ok = false;
            }
        }
        inline for ([_]CellType{ .vertex, .edge, .face }) |cell_type| {
            const c = sm.cell(d, cell_type);
            if ((cell_type == .face) and sm.isBoundaryDart(d)) {
                if (c.index != invalid_index) {
                    zgp_log.warn("Boundary dart {d} has a valid {s} index", .{ d, @tagName(cell_type) });
                    ok = false;
                }
            } else {
                if (c.index == invalid_index) {
                    zgp_log.warn("Dart {d} has invalid {s} index", .{ d, @tagName(cell_type) });
                    ok = false;
                }
            }
        }
    }

    var d_marker: DartMarker = try .init(sm);
    defer d_marker.deinit();

    inline for ([_]CellType{ .vertex, .edge, .face }) |cell_type| {
        // this data is used to check that each cell in the DataContainer is used by exactly one orbit of darts
        var orbit_count = try sm.addData(cell_type, u32, "orbit_count");
        defer sm.removeData(orbit_count);
        orbit_count.data.fill(0);
        // this data is used to check that the number of darts associated with a cell is consistent with the reference count of the cell in the DataContainer
        var darts_count = try sm.addData(cell_type, u32, "darts_count");
        defer sm.removeData(darts_count);
        darts_count.data.fill(0);

        d_it.reset();
        d_marker.reset();
        while (d_it.next()) |d| {
            if (d_marker.isMarked(d)) continue;
            if (sm.isBoundaryDart(d)) continue; // skip boundary darts (boundary faces have no cell)

            const c = sm.cell(d, cell_type);
            if (c.index != invalid_index) {
                orbit_count.valuePtr(c).* += 1;
            }
            const d_count = darts_count.valuePtr(c);
            const c_dart = sm.dart(c);
            var found_c_dart = false;
            var dart_it = sm.orbitDartIterator(d, cell_type);
            while (dart_it.next()) |cd| {
                d_marker.mark(cd); // mark darts of the orbit on the way
                if (cd == c_dart) {
                    found_c_dart = true;
                }
                const cd_cell = sm.cell(cd, cell_type);
                if (cd_cell.index != c.index) {
                    zgp_log.warn("Inconsistent {s} cell for dart {d}: {d} != {d}", .{ @tagName(cell_type), cd, cd_cell.index, c.index });
                    ok = false;
                }
                d_count.* += 1;
            }
            if (!found_c_dart) {
                zgp_log.warn("Representative dart for {s} cell {d} is not part of the orbit", .{ @tagName(cell_type), c.index });
                ok = false;
            }
            switch (cell_type) {
                .vertex => {
                    if (d_count.* < 2) {
                        zgp_log.warn("Inconsistent vertex darts count for vertex of dart {d}: {d} < 2", .{ d, d_count.* });
                        ok = false;
                    }
                },
                .edge => {
                    if (d_count.* != 2) {
                        zgp_log.warn("Inconsistent edge darts count for edge of dart {d}: {d} != 2", .{ d, d_count.* });
                        ok = false;
                    }
                },
                .face => {
                    if (d_count.* < 3) {
                        zgp_log.warn("Inconsistent face darts count for face of dart {d}: {d} < 3", .{ d, d_count.* });
                        ok = false;
                    }
                },
                else => unreachable,
            }
        }

        var data_container = sm.dataContainerPtr(cell_type);
        var index_it = data_container.indexIterator();
        while (index_it.next()) |idx| {
            const ref_count = data_container.nb_refs.value(idx);
            const d_count = darts_count.data.value(idx);
            if (ref_count != d_count) {
                zgp_log.warn("Inconsistent {s} cell {d}: ref count {d} != actual count {d}", .{ @tagName(cell_type), idx, ref_count, d_count });
                ok = false;
            }
            const o_count = orbit_count.data.value(idx);
            if (o_count == 0) {
                zgp_log.warn("Unused {s} cell {d}", .{ @tagName(cell_type), idx });
                ok = false;
            } else if (o_count > 1) {
                zgp_log.warn("Non-unique {s} cell {d}: used {d} times", .{ @tagName(cell_type), idx, o_count });
                ok = false;
            }
        }
    }

    return ok;
}

// ------------------------------------------------------------------------- //
// Operators
// ------------------------------------------------------------------------- //

/// Create a new face with the given number of vertices.
/// Unbounded means that the face is not linked to any boundary "outer" face (all its darts are phi2-linked to themselves).
/// Return a dart of the new face.
/// WARNING: Cell indices are not managed by this function.
/// This function is only intended for use in SurfaceMesh creation process (import, ...) as the SurfaceMesh is not
/// valid after this function is called.
pub fn addUnboundedFace(sm: *SurfaceMesh, nb_vertices: u32) !Dart {
    const d1 = try sm.addDart();
    for (1..nb_vertices) |_| {
        const d2 = try sm.addDart();
        sm.phi1Sew(d1, d2);
    }
    return d1;
}

/// Remove the given unbounded face from the SurfaceMesh.
/// All the darts of the face are simply removed from the SurfaceMesh, no boundary face is created to close the hole left by the removal of the face.
/// WARNING: Cell indices are not managed by this function.
/// This function is only intended for use in SurfaceMesh creation process (import, ...) as the SurfaceMesh is not
/// valid after this function is called.
pub fn removeFace(sm: *SurfaceMesh, f: Face) void {
    var dart_it = sm.orbitDartIterator(sm.dart(f), .face);
    while (dart_it.next()) |d| {
        sm.phi2Unsew(d);
        sm.removeDart(d);
    }
}

/// Close the hole incident to the given dart by adding a polygonal face.
/// The given dart must be a dart on the boundary of the hole (phi2-linked to itself).
/// Return a dart of the new face (the dart linked to d by phi2).
/// WARNING: Cell indices are not managed by this function.
/// This function is only intended for use in SurfaceMesh creation process (import, ...) as the SurfaceMesh is not
/// valid after this function is called.
pub fn closeHoleWithPolygon(sm: *SurfaceMesh, d: Dart) !Dart {
    assert(sm.phi2(d) == d);
    const b_first = try sm.addDart();
    sm.phi2Sew(d, b_first);

    var d_current = d;
    out: while (true) {
        // find the next dart that is phi2-linked to itself
        while (sm.phi2(d_current) != d_current) {
            d_current = sm.phi2(sm.phi1(d_current));
            if (sm.phi2(d_current) == d) {
                // we are back to the starting dart, so we can stop
                break :out;
            }
        }
        const b_next = try sm.addDart();
        sm.phi2Sew(d_current, b_next);
        sm.phi1Sew(b_first, b_next);
    }

    return b_first;
}

/// Close the SurfaceMesh by adding boundary faces where needed.
/// Open edges (darts phi2-linked to themselves) are detected and boundary faces
/// are created by following the open boundary cycles.
/// WARNING: Cell indices are not managed by this function.
/// This function is only intended for use in SurfaceMesh creation process (import, ...) as the SurfaceMesh is not
/// valid after this function is called.
pub fn close(sm: *SurfaceMesh) !u32 {
    var nb_boundary_faces: u32 = 0;
    var dart_it = sm.dartIterator();
    while (dart_it.next()) |d| {
        if (sm.phi2(d) == d) {
            const f = try closeHoleWithPolygon(sm, d);
            var f_it = sm.orbitDartIterator(f, .face);
            while (f_it.next()) |fd| {
                sm.dart_boundary_marker.valuePtr(fd).* = true;
            }
            nb_boundary_faces += 1;
        }
    }
    return nb_boundary_faces;
}

/// Close the hole incident to the given dart by adding an umbrella.
/// The given dart must be a dart on the boundary of the hole (phi2-linked to itself).
/// WARNING: Cell indices are managed by this function which assumes that the SurfaceMesh was valid just before the hole was created.
pub fn closeHoleWithUmbrella(sm: *SurfaceMesh, d: Dart) !Vertex {
    assert(sm.phi2(d) == d);
    // create the first face of the umbrella
    const f_first = try sm.addUnboundedFace(3);
    sm.phi2Sew(d, f_first);

    var f_current = f_first;
    var d_hole_current = d;
    out: while (true) {
        // find the next dart that is phi2-linked to itself
        while (sm.phi2(d_hole_current) != d_hole_current) {
            d_hole_current = sm.phi2(sm.phi1(d_hole_current));
            if (sm.phi2(d_hole_current) == d) {
                // we are back to the starting dart, so we can stop
                break :out;
            }
        }
        const f_next = try sm.addUnboundedFace(3);
        sm.phi2Sew(d_hole_current, f_next);
        sm.phi2Sew(sm.phi_1(f_current), sm.phi1(f_next));
        f_current = f_next;
    }
    sm.phi2Sew(sm.phi_1(f_current), sm.phi1(f_first)); // finish the umbrella

    const cv_dart = sm.phi_1(f_first); // central vertex dart

    // manage cells
    const cv = try sm.addCell(.vertex); // new cell for central vertex
    sm.setCellDart(cv, cv_dart); // set the representative dart of the central vertex
    var dart_it = sm.orbitDartIterator(cv_dart, .vertex); // turn around central vertex
    while (dart_it.next()) |cvd| {
        sm.setDartCell(cvd, cv);
        const d1 = sm.phi1(cvd);

        // hole vertices
        const hv = sm.vertex(sm.phi1(sm.phi2(d1)));
        sm.setDartCell(d1, hv);
        sm.setDartCell(sm.phi2(cvd), hv);
        sm.setCellDart(hv, d1); // set the representative dart of the hole vertex

        // hole & umbrella edges
        const he = sm.edge(sm.phi2(d1));
        sm.setDartCell(d1, he);
        sm.setCellDart(he, d1); // set the representative dart of the hole edge
        const ue = try sm.addCell(.edge);
        sm.setOrbitCell(cvd, ue);
        sm.setCellDart(ue, cvd); // set the representative dart of the umbrella edge

        // umbrella faces
        const uf = try sm.addCell(.face);
        sm.setOrbitCell(cvd, uf);
        sm.setCellDart(uf, cvd); // set the representative dart of the umbrella face
    }

    return cv;
}

/// Creates a new pyramid whose base is a polygon with `baseSize` vertices.
/// Returns the base face of the pyramid.
pub fn addPyramid(sm: *SurfaceMesh, baseSize: u32) !Face {
    // first create the umbrella forming the pyramid tip
    const first = try sm.addUnboundedFace(3);
    var current_dart = first;
    for (1..baseSize) |_| {
        const next = try sm.addUnboundedFace(3);
        sm.phi2Sew(sm.phi_1(current_dart), sm.phi1(next));
        current_dart = next;
    }
    sm.phi2Sew(sm.phi_1(current_dart), sm.phi1(first)); // finish the umbrella
    // then close the hole to create the base face
    const base_face = try sm.closeHoleWithPolygon(first);

    // manage cells
    var dart_it = sm.orbitDartIterator(base_face, .face);
    while (dart_it.next()) |bfd| {
        // base vertices
        const v = try sm.addCell(.vertex);
        sm.setOrbitCell(bfd, v);
        sm.setCellDart(v, bfd); // set the representative dart of the vertex

        // base & umbrella edges
        const be = try sm.addCell(.edge);
        sm.setOrbitCell(bfd, be);
        sm.setCellDart(be, bfd); // set the representative dart of the edge
        const ue = try sm.addCell(.edge);
        const ue_dart = sm.phi1(sm.phi2(bfd));
        sm.setOrbitCell(ue_dart, ue);
        sm.setCellDart(ue, ue_dart); // set the representative dart of the edge

        // umbrella faces
        const uf = try sm.addCell(.face);
        const uf_dart = sm.phi2(bfd);
        sm.setOrbitCell(uf_dart, uf);
        sm.setCellDart(uf, uf_dart); // set the representative dart of the face
    }
    // tip vertex
    const tv = try sm.addCell(.vertex);
    const tv_dart = sm.phi_1(first);
    sm.setOrbitCell(tv_dart, tv);
    sm.setCellDart(tv, tv_dart); // set the representative dart of the vertex
    // base face
    const bf = try sm.addCell(.face);
    sm.setOrbitCell(base_face, bf);
    sm.setCellDart(bf, base_face); // set the representative dart of the face

    return bf;
}

/// Cuts the given edge by inserting a new vertex.
/// The new vertex is returned: its representative dart is the one that
/// belongs to the same face as the representative dart of the given edge.
/// The edge of the representative dart of the given edge keeps the same edge index
/// (a new edge index is given to the other new edge).
pub fn cutEdge(sm: *SurfaceMesh, e: Edge) !Vertex {
    const d = sm.dart(e);
    const dd = sm.phi2(d);
    sm.phi2Unsew(d);

    const d1 = try sm.addDart();
    sm.phi1Sew(d, d1);
    const dd1 = try sm.addDart();
    sm.phi1Sew(dd, dd1);

    sm.phi2Sew(d, dd1);
    sm.phi2Sew(dd, d1);

    sm.dart_boundary_marker.valuePtr(d1).* = sm.dart_boundary_marker.value(d);
    sm.dart_boundary_marker.valuePtr(dd1).* = sm.dart_boundary_marker.value(dd);

    // Vertex cells
    const v = try sm.addCell(.vertex);
    sm.setDartCell(d1, v);
    sm.setDartCell(dd1, v);
    sm.setCellDart(v, d1); // set the representative dart of the new vertex

    // Edge cells
    // the edge orbit of d keeps the original edge cell
    const original_edge = sm.edge(d);
    sm.setDartCell(dd1, original_edge);
    sm.setCellDart(original_edge, d); // set the representative dart of the original edge
    // the edge orbit of dd gets a new edge cell
    const new_edge = try sm.addCell(.edge);
    sm.setDartCell(dd, new_edge);
    sm.setDartCell(d1, new_edge);
    sm.setCellDart(new_edge, dd); // set the representative dart of the new edge

    // Face cells
    sm.setDartCell(d1, sm.face(d));
    sm.setDartCell(dd1, sm.face(dd));
    // incident faces only gained new darts, so their representative darts remain the same

    return v;
}

/// Flips the given edge (following the orientation of the faces).
/// Should only be called after a call to `canFlipEdge`.
/// TODO: write a more detailed comment
pub fn flipEdge(sm: *SurfaceMesh, e: Edge) void {
    const d = sm.dart(e);
    const dd = sm.phi2(d);
    const d1 = sm.phi1(d);
    const d_1 = sm.phi_1(d);
    const dd1 = sm.phi1(dd);
    const dd_1 = sm.phi_1(dd);

    sm.phi1Sew(d, dd_1);
    sm.phi1Sew(dd, d_1);
    sm.phi1Sew(d, d1);
    sm.phi1Sew(dd, dd1);

    // Vertex cells
    sm.setDartCell(d, sm.vertex(sm.phi1(dd)));
    sm.setDartCell(dd, sm.vertex(sm.phi1(d)));
    // dart d left the vertex of dd1 and dart dd left the vertex of d1
    // as they may have been their representative darts, we need to update the representative darts of these vertices
    sm.setCellDart(sm.vertex(dd1), dd1); // set the representative dart of the vertex of dd1
    sm.setCellDart(sm.vertex(d1), d1); // set the representative dart of the vertex of d1

    // Edge cells
    // no new edges are created & no existing edges are modified

    // Face cells
    const df = sm.face(d);
    const ddf = sm.face(dd);
    sm.setDartCell(dd1, df);
    sm.setDartCell(d1, ddf);
    // dart d1 left the face of d and dart dd1 left the face of dd
    // as they may have been their representative darts, we need to update the representative darts of these faces
    sm.setCellDart(df, d); // set the representative dart of the face of d
    sm.setCellDart(ddf, dd); // set the representative dart of the face of dd
}

/// Check if the given edge can be flipped. Edges that cannot be flipped:
///  1 - boundary edges
///  2 - edges having an incident vertex of degree 2
/// No geometry conditions are checked here.
pub fn canFlipEdge(sm: *SurfaceMesh, e: Edge) bool {
    const d = sm.dart(e);
    const dd = sm.phi2(d);

    // condition 1: do not flip boundary edges
    if (sm.isOrbitIncidentToBoundary(d, .edge)) {
        return false;
    }

    // condition 2: avoid creating degree 1 vertices
    if (sm.degree(sm.vertex(d)) == 2 or sm.degree(sm.vertex(dd)) == 2) {
        return false;
    }

    return true;
}

/// Unflips the given edge (following the inverse orientation of the faces).
/// Should only be called after a call to `canUnflipEdge`.
/// TODO: write a more detailed comment
pub fn unflipEdge(sm: *SurfaceMesh, e: Edge) void {
    const d = sm.dart(e);
    const dd = sm.phi2(d);
    const d1 = sm.phi1(d);
    const d_1 = sm.phi_1(d);
    const d_1_1 = sm.phi_1(d_1);
    const dd1 = sm.phi1(dd);
    const dd_1 = sm.phi_1(dd);
    const dd_1_1 = sm.phi_1(dd_1);

    sm.phi1Sew(d, dd_1);
    sm.phi1Sew(dd, d_1);
    sm.phi1Sew(d, dd_1_1);
    sm.phi1Sew(dd, d_1_1);

    // Vertex cells
    sm.setDartCell(d, sm.vertex(sm.phi1(dd)));
    sm.setDartCell(dd, sm.vertex(sm.phi1(d)));
    // dart d left the vertex of dd1 and dart dd left the vertex of d1
    // as they may have been their representative darts, we need to update the representative darts of these vertices
    sm.setCellDart(sm.vertex(dd1), dd1); // set the representative dart of the vertex of dd1
    sm.setCellDart(sm.vertex(d1), d1); // set the representative dart of the vertex of d1

    // Edge cells
    // no new edges are created & no existing edges are modified

    // Face cells
    const df = sm.face(d);
    const ddf = sm.face(dd);
    sm.setDartCell(dd_1, df);
    sm.setDartCell(d_1, ddf);
    // dart d_1 left the face of d and dart dd_1 left the face of dd
    // as they may have been their representative darts, we need to update the representative darts of these faces
    sm.setCellDart(df, d); // set the representative dart of the face of d
    sm.setCellDart(ddf, dd); // set the representative dart of the face of dd
}

/// Check if the given edge can be unflipped. Edges that cannot be unflipped:
///  1 - boundary edges
///  2 - edges having an incident vertex of degree 2
/// No geometry conditions are checked here.
pub fn canUnflipEdge(sm: *SurfaceMesh, e: Edge) bool {
    const d = sm.dart(e);
    const dd = sm.phi2(d);

    // condition 1: do not flip boundary edges
    if (sm.isOrbitIncidentToBoundary(d, .edge)) {
        return false;
    }

    // condition 2: avoid creating degree 1 vertices
    if (sm.degree(sm.vertex(d)) == 2 or sm.degree(sm.vertex(dd)) == 2) {
        return false;
    }

    return true;
}

/// Collapses the given edge.
/// Should only be called after a call to `canCollapseEdge`.
/// TODO: write a more detailed comment
pub fn collapseEdge(sm: *SurfaceMesh, e: Edge) Vertex {
    const d = sm.dart(e);
    const d1 = sm.phi1(d);
    const d12 = sm.phi2(d1);
    const d_1 = sm.phi_1(d);
    const d_12 = sm.phi2(d_1);
    const dd = sm.phi2(d);
    const dd1 = sm.phi1(dd);
    const dd12 = sm.phi2(dd1);
    const dd_1 = sm.phi_1(dd);
    const dd_12 = sm.phi2(dd_1);

    sm.phi1Sew(d_1, d);
    sm.removeDart(d);
    sm.phi1Sew(dd_1, dd);
    sm.removeDart(dd);

    // remove a potential 2-sided face on the side of d
    if (sm.phi1(d1) == d_1) {
        sm.phi2Unsew(d1);
        sm.phi2Unsew(d_1);
        sm.phi2Sew(d_12, d12);
        sm.removeDart(d1);
        sm.removeDart(d_1);
    }
    // remove a potential 2-sided face on the side of dd
    if (sm.phi1(dd1) == dd_1) {
        sm.phi2Unsew(dd1);
        sm.phi2Unsew(dd_1);
        sm.phi2Sew(dd_12, dd12);
        sm.removeDart(dd1);
        sm.removeDart(dd_1);
    }

    // Vertex cells
    // use the index of the vertex of d for the resulting vertex
    const v = sm.vertex(d_12);
    sm.setOrbitCell(d_12, v);
    sm.setCellDart(v, d_12); // set the representative dart of the resulting vertex
    // if the 2-sided face on the side of d has been removed, then d12 is now the representative dart of the vertex of d12
    if (sm.phi2(d12) == d_12) {
        sm.setCellDart(sm.vertex(d12), d12);
    }
    // if the 2-sided face on the side of dd has been removed, then dd12 is now the representative dart of the vertex of dd12
    if (sm.phi2(dd12) == dd_12) {
        sm.setCellDart(sm.vertex(dd12), dd12);
    }

    // Edge cells
    // these statements are correct wether 2-sided faces have been deleted or not
    sm.setDartCell(d_12, sm.edge(sm.phi2(d_12)));
    sm.setDartCell(dd_12, sm.edge(sm.phi2(dd_12)));
    // if the 2-sided face on the side of d has been removed, then:
    // - use the index of the edge of d12 for the resulting edge
    // - d12 is now the representative dart of this edge
    if (sm.phi2(d12) == d_12) {
        const ee = sm.edge(d12);
        sm.setDartCell(d_12, ee);
        sm.setCellDart(ee, d12);
    }
    // if the 2-sided face on the side of dd has been removed, then:
    // - use the index of the edge of dd12 for the resulting edge
    // - dd12 is now the representative dart of the edge of dd12
    if (sm.phi2(dd12) == dd_12) {
        const ee = sm.edge(dd12);
        sm.setDartCell(dd_12, ee);
        sm.setCellDart(ee, dd12);
    }

    // Face cells
    // if the face on the side of d is still present and is not a boundary face, update its representative dart to d1
    if (sm.phi2(d12) != d_12 and !sm.isBoundaryDart(d1)) {
        sm.setCellDart(sm.face(d1), d1);
    }
    // if the face on the side of dd is still present and is not a boundary face, update its representative dart to dd1
    if (sm.phi2(dd12) != dd_12 and !sm.isBoundaryDart(dd1)) {
        sm.setCellDart(sm.face(dd1), dd1);
    }

    return v;
}

/// Checks if the given edge can be collapsed. Edges that cannot be collapsed:
///  1 - edges whose incident triangle face has the third vertex of degree < 4
///  2 - edges whose incident vertices are both boundary vertices but the edge is not a boundary edge
///  3 - edges whose incident vertices share a common adjacent vertex other than themselves and the third vertex of incident triangle faces
/// No geometry conditions are checked here.
pub fn canCollapseEdge(sm: *const SurfaceMesh, e: Edge) bool {
    const d = sm.dart(e);
    const d12 = sm.phi2(sm.phi1(d));
    const d_1 = sm.phi_1(d);
    const d_12 = sm.phi2(d_1);
    const dd = sm.phi2(d);
    const dd12 = sm.phi2(sm.phi1(dd));
    const dd_1 = sm.phi_1(dd);
    const dd_12 = sm.phi2(dd_1);

    // condition 1: avoid creating vertices of degree 2
    if (!sm.isBoundaryDart(d)) {
        if (sm.codegree(sm.face(d)) == 3 and sm.degree(sm.vertex(d_1)) < 4) {
            return false;
        }
    } else {
        if (sm.phi1(sm.phi1(d)) == d_1) { // avoid collapsing triangular boundary faces
            return false;
        }
    }
    if (!sm.isBoundaryDart(dd)) {
        if (sm.codegree(sm.face(dd)) == 3 and sm.degree(sm.vertex(dd_1)) < 4) {
            return false;
        }
    } else {
        if (sm.phi1(sm.phi1(dd)) == dd_1) { // avoid collapsing triangular boundary faces
            return false;
        }
    }

    // avoid creating vertices of degree > 15 // TODO: seems kind of arbitrary here
    if (sm.degree(sm.vertex(d)) + sm.degree(sm.vertex(dd)) > 15) {
        return false;
    }

    // condition 2: avoid collapsing incident boundary vertices of a non-boundary edge
    if (!sm.isOrbitIncidentToBoundary(d, .edge)) {
        if (sm.isOrbitIncidentToBoundary(d, .vertex) and sm.isOrbitIncidentToBoundary(dd, .vertex)) {
            return false;
        }
    }

    // condition 3: avoid _pinching_ the surface
    // var adjacent_vertices: std.AutoArrayHashMapUnmanaged(u32, void) = .empty;
    // defer adjacent_vertices.deinit(sm.allocator);
    // adjacent_vertices.ensureTotalCapacity(sm.allocator, sm.degree(sm.vertex(d)) + sm.degree(sm.vertex(dd))) catch |err| {
    //     std.debug.print("Error: cannot check edge collapse condition 2: {}\n", .{err});
    // };
    var buf: [64]u32 = undefined; // TODO: arbitrary and dangerous limit of 64 only to avoid dynamic memory allocation here
    var adjacent_vertices: std.ArrayList(u32) = .initBuffer(&buf);
    var d_it = sm.phi_1(d_12);
    while (d_it != dd12) : (d_it = sm.phi_1(sm.phi2(d_it))) {
        // adjacent_vertices.putAssumeCapacity(sm.vertex(d_it).index(), {});
        adjacent_vertices.appendBounded(sm.vertex(d_it).index) catch |err| {
            std.debug.panic("Error: cannot check edge collapse condition 2 because the number of adjacent vertices exceeds {d}: {}\n", .{ buf.len, err });
        };
    }
    d_it = sm.phi_1(dd_12);
    while (d_it != d12) : (d_it = sm.phi_1(sm.phi2(d_it))) {
        // if (adjacent_vertices.contains(sm.vertex(d_it).index())) {
        if (std.mem.findScalar(u32, adjacent_vertices.items, sm.vertex(d_it).index) != null) {
            return false;
        }
    }

    return true;
}

/// Cuts a face by inserting a new edge between the two given darts.
/// The new edge is returned: its representative dart is the one that belongs to the same vertex as d1.
/// The face of d1 keeps the same face cell (a new face cell is created for the other new face).
/// Return the new edge.
pub fn cutFace(sm: *SurfaceMesh, d1: Dart, d2: Dart) !Edge {
    assert(sm.codegree(sm.face(d1)) > 3); // only cut faces with more than 3 edges
    assert(sm.dartBelongsToOrbit(d1, d2, .face)); // check that d2 belongs to the face orbit of d1
    assert(sm.phi1(d1) != d2 and sm.phi_1(d1) != d2); // d1 & d2 should not follow each other

    if (sm.isBoundaryDart(d1)) {
        return error.CuttingBoundaryFaceNotAllowed;
    }

    const d_1 = try sm.addDart();
    sm.phi1Sew(sm.phi_1(d1), d_1);
    const d_2 = try sm.addDart();
    sm.phi1Sew(sm.phi_1(d2), d_2);
    sm.phi1Sew(d_1, d_2);
    sm.phi2Sew(d_1, d_2);

    // Vertex cells
    sm.setDartCell(d_1, sm.vertex(d1));
    sm.setDartCell(d_2, sm.vertex(d2));
    // darts are only added to existing vertices, so their representative darts remain the same

    // Edge cells
    const e = try sm.addCell(.edge);
    sm.setDartCell(d_1, e);
    sm.setDartCell(d_2, e);
    sm.setCellDart(e, d_1); // set the representative dart of the new edge

    // Face cells
    sm.setDartCell(d_2, sm.face(d1));
    const f = try sm.addCell(.face);
    sm.setOrbitCell(d2, f);
    sm.setCellDart(sm.face(d1), d1); // set the representative dart of the original face
    sm.setCellDart(f, d2); // set the representative dart of the new face

    return e;
}

/// Removes the given vertex by merging all its incident faces.
/// TODO: does not handle boundary vertices yet
pub fn removeVertex(sm: *SurfaceMesh, v: Vertex) !void {
    const d = sm.dart(v);
    const d1 = sm.phi1(d);

    var darts: std.ArrayList(Dart) = try .initCapacity(sm.allocator, sm.degree(v) * 2);
    defer darts.deinit(sm.allocator);
    var dart_it = sm.orbitDartIterator(d, .vertex);
    while (dart_it.next()) |it| {
        try darts.appendSlice(sm.allocator, &.{ it, sm.phi2(it) });
        sm.phi1Sew(it, sm.phi_1(sm.phi2(it)));
    }
    for (darts.items) |vd| {
        sm.removeDart(vd);
    }

    // Vertex cells
    // the representative dart of the vertices of the resulting face must be updated, as they may have been removed
    var face_it = sm.orbitDartIterator(d1, .face);
    while (face_it.next()) |fd| {
        sm.setCellDart(sm.vertex(fd), fd);
    }

    // Edge cells
    // edges incident to the removed vertex have been entirely removed

    // Face cells
    const f = sm.face(d1);
    sm.setOrbitCell(d1, f);
    sm.setCellDart(f, d1); // set the representative dart of the resulting face
}
