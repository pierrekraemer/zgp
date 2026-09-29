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
//! These cell indices refer to entries in other DataContainers that are used to store data
//! associated to the vertices, edges and faces of the mesh.
//! Halfedges and corners do not have their own index & DataContainers: since they are single darts,
//! their index is that of the dart, and their datas are stored in the dart DataContainer).
//!
//! TODO: talk about boundary management

const SurfaceMesh = @This();

const std = @import("std");
const assert = std.debug.assert;

const zgp_log = std.log.scoped(.zgp);

const AppContext = @import("../../main.zig").AppContext;

const data = @import("../../utils/data.zig");
const DataContainer = data.DataContainer;
const DataGen = data.DataGen;
const Data = data.Data;
const invalid_index = data.invalid_index;

const BufferPool = @import("../../utils/BufferPool.zig").BufferPool;

pub const Dart = u32;

/// A cell is a tagged union containing a dart that belongs to the cell of the current tag.
/// Convenience functions are provided to get the representing dart and the cell type.
pub const Cell = union(enum) {
    halfedge: Dart,
    corner: Dart,
    vertex: Dart,
    edge: Dart,
    face: Dart,

    // boundary faces are polygonal faces composed of boundary darts
    // this cell type is not used to manage data but only to be able to iterate over boundary faces
    boundary: Dart,

    pub fn dart(c: Cell) Dart {
        const d, _ = switch (c) {
            inline else => |val, tag| .{ val, tag },
        };
        return d;
    }

    pub fn cellType(c: Cell) CellType {
        return std.meta.activeTag(c);
    }
};
pub const CellType = std.meta.Tag(Cell);

allocator: std.mem.Allocator,
cell_buffer_pool: *BufferPool(Cell), // the BufferPool is shared between SurfaceMeshes (owned by the SurfaceMeshStore)

/// Data containers for darts & the different cell types.
dart_data: DataContainer, // also used to store corner & halfedge data
vertex_data: DataContainer,
edge_data: DataContainer,
face_data: DataContainer,

/// Dart data: connectivity, cell indices, boundary marker.
dart_phi1: *Data(Dart),
dart_phi_1: *Data(Dart),
dart_phi2: *Data(Dart),
dart_vertex_index: *Data(u32), // index of the vertex the dart belongs to
dart_edge_index: *Data(u32), // index of the edge the dart belongs to
dart_face_index: *Data(u32), // index of the face the dart belongs to
dart_boundary_marker: *Data(bool), // true if the dart is a boundary dart (i.e. belongs to a boundary face)

/// A representative dart for each cell, stored in Data containers for each cell type.
/// These representative darts are used to iterate over the cells of the mesh.
vertex_dart: *Data(Dart),
edge_dart: *Data(Dart),
face_dart: *Data(Dart),

nb_boundary_darts: u32, // number of boundary darts; only updated upon calls to SurfaceMeshStore.surfaceMeshConnectivityUpdated

/// CellSets for each cell type
vertex_sets: std.StringHashMapUnmanaged(CellSet(.vertex)),
edge_sets: std.StringHashMapUnmanaged(CellSet(.edge)),
face_sets: std.StringHashMapUnmanaged(CellSet(.face)),

pub fn init(sm: *SurfaceMesh, allocator: std.mem.Allocator, cell_buffer_pool: *BufferPool(Cell)) !void {
    sm.allocator = allocator;
    sm.cell_buffer_pool = cell_buffer_pool;

    try sm.dart_data.init(allocator);
    try sm.vertex_data.init(allocator);
    try sm.edge_data.init(allocator);
    try sm.face_data.init(allocator);

    sm.dart_phi1 = try sm.dart_data.addData(Dart, "phi1");
    sm.dart_phi_1 = try sm.dart_data.addData(Dart, "phi_1");
    sm.dart_phi2 = try sm.dart_data.addData(Dart, "phi2");
    sm.dart_vertex_index = try sm.dart_data.addData(u32, "vertex_index");
    sm.dart_edge_index = try sm.dart_data.addData(u32, "edge_index");
    sm.dart_face_index = try sm.dart_data.addData(u32, "face_index");

    sm.vertex_dart = try sm.vertex_data.addData(Dart, "dart");
    sm.edge_dart = try sm.edge_data.addData(Dart, "dart");
    sm.face_dart = try sm.face_data.addData(Dart, "dart");

    sm.dart_boundary_marker = try sm.dart_data.acquireMarker();
    sm.nb_boundary_darts = 0;

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
    var vertex_sets_it = sm.vertex_sets.iterator();
    while (vertex_sets_it.next()) |entry| {
        entry.value_ptr.clear();
    }
    var edge_sets_it = sm.edge_sets.iterator();
    while (edge_sets_it.next()) |entry| {
        entry.value_ptr.clear();
    }
    var face_sets_it = sm.face_sets.iterator();
    while (face_sets_it.next()) |entry| {
        entry.value_ptr.clear();
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
    cloned_sm.cell_buffer_pool = sm.cell_buffer_pool;

    // Markers are not copied by ths initFrom function
    try cloned_sm.dart_data.initFrom(&sm.dart_data, true, allocator);
    try cloned_sm.vertex_data.initFrom(&sm.vertex_data, true, allocator);
    try cloned_sm.edge_data.initFrom(&sm.edge_data, true, allocator);
    try cloned_sm.face_data.initFrom(&sm.face_data, true, allocator);

    // recover the topological relations & cell indices from the copied Dart DataContainer
    cloned_sm.dart_phi1 = cloned_sm.dart_data.getData(Dart, "phi1").?;
    cloned_sm.dart_phi_1 = cloned_sm.dart_data.getData(Dart, "phi_1").?;
    cloned_sm.dart_phi2 = cloned_sm.dart_data.getData(Dart, "phi2").?;
    cloned_sm.dart_vertex_index = cloned_sm.dart_data.getData(u32, "vertex_index").?;
    cloned_sm.dart_edge_index = cloned_sm.dart_data.getData(u32, "edge_index").?;
    cloned_sm.dart_face_index = cloned_sm.dart_data.getData(u32, "face_index").?;

    // recover the representative darts for each cell type from the copied DataContainers
    cloned_sm.vertex_dart = cloned_sm.vertex_data.getData(Dart, "dart").?;
    cloned_sm.edge_dart = cloned_sm.edge_data.getData(Dart, "dart").?;
    cloned_sm.face_dart = cloned_sm.face_data.getData(Dart, "dart").?;

    // create the boundary marker and copy its values from the source SurfaceMesh
    cloned_sm.dart_boundary_marker = try cloned_sm.dart_data.getMarker();
    cloned_sm.dart_boundary_marker.copyFrom(sm.dart_boundary_marker);
    cloned_sm.nb_boundary_darts = sm.nb_boundary_darts;

    cloned_sm.vertex_sets = .empty;
    cloned_sm.edge_sets = .empty;
    cloned_sm.face_sets = .empty;

    return cloned_sm;
}

pub fn cloneWithoutCellData(sm: *const SurfaceMesh, allocator: std.mem.Allocator) !*SurfaceMesh {
    const cloned_sm = try allocator.create(SurfaceMesh);
    errdefer allocator.destroy(cloned_sm);

    cloned_sm.allocator = allocator;
    cloned_sm.cell_buffer_pool = sm.cell_buffer_pool;

    // Copy only the structure of the DataContainers (i.e. size, capacity, indices management) but not the CellData
    // Markers are not copied by ths initFrom function
    try cloned_sm.dart_data.initFrom(&sm.dart_data, false, allocator);
    try cloned_sm.vertex_data.initFrom(&sm.vertex_data, false, allocator);
    try cloned_sm.edge_data.initFrom(&sm.edge_data, false, allocator);
    try cloned_sm.face_data.initFrom(&sm.face_data, false, allocator);

    // create the topological relations & cell indices and copy them from the source Dart DataContainer
    cloned_sm.dart_phi1 = try cloned_sm.dart_data.addData(Dart, "phi1");
    cloned_sm.dart_phi1.copyFrom(sm.dart_phi1);
    cloned_sm.dart_phi_1 = try cloned_sm.dart_data.addData(Dart, "phi_1");
    cloned_sm.dart_phi_1.copyFrom(sm.dart_phi_1);
    cloned_sm.dart_phi2 = try cloned_sm.dart_data.addData(Dart, "phi2");
    cloned_sm.dart_phi2.copyFrom(sm.dart_phi2);
    cloned_sm.dart_vertex_index = try cloned_sm.dart_data.addData(u32, "vertex_index");
    cloned_sm.dart_vertex_index.copyFrom(sm.dart_vertex_index);
    cloned_sm.dart_edge_index = try cloned_sm.dart_data.addData(u32, "edge_index");
    cloned_sm.dart_edge_index.copyFrom(sm.dart_edge_index);
    cloned_sm.dart_face_index = try cloned_sm.dart_data.addData(u32, "face_index");
    cloned_sm.dart_face_index.copyFrom(sm.dart_face_index);

    // create the representative darts for each cell type and copy them from the source DataContainers
    cloned_sm.vertex_dart = try cloned_sm.vertex_data.addData(Dart, "dart");
    cloned_sm.vertex_dart.copyFrom(sm.vertex_dart);
    cloned_sm.edge_dart = try cloned_sm.edge_data.addData(Dart, "dart");
    cloned_sm.edge_dart.copyFrom(sm.edge_dart);
    cloned_sm.face_dart = try cloned_sm.face_data.addData(Dart, "dart");
    cloned_sm.face_dart.copyFrom(sm.face_dart);

    // create the boundary marker and copy its values from the source SurfaceMesh
    cloned_sm.dart_boundary_marker = try cloned_sm.dart_data.acquireMarker();
    cloned_sm.dart_boundary_marker.copyFrom(sm.dart_boundary_marker);
    cloned_sm.nb_boundary_darts = sm.nb_boundary_darts;

    cloned_sm.vertex_sets = .empty;
    cloned_sm.edge_sets = .empty;
    cloned_sm.face_sets = .empty;

    return cloned_sm;
}

/// Returns the data container associated with the given CellType.
pub fn dataContainerPtr(sm: anytype, comptime cell_type: CellType) if (@typeInfo(@TypeOf(sm)).pointer.is_const) *const DataContainer else *DataContainer {
    return switch (cell_type) {
        .halfedge, .corner => &sm.dart_data,
        .vertex => &sm.vertex_data,
        .edge => &sm.edge_data,
        .face => &sm.face_data,
        else => unreachable,
    };
}

/// Returns a pointer to the HashMap of CellSets for the given CellType.
pub fn cellSetContainerPtr(sm: anytype, comptime cell_type: CellType) if (@typeInfo(@TypeOf(sm)).pointer.is_const) *const std.StringHashMapUnmanaged(CellSet(cell_type)) else *std.StringHashMapUnmanaged(CellSet(cell_type)) {
    return switch (cell_type) {
        .vertex => &sm.vertex_sets,
        .edge => &sm.edge_sets,
        .face => &sm.face_sets,
        else => unreachable,
    };
}

/// DartIterator iterates over all the darts of the SurfaceMesh (including boundary darts).
const DartIterator = struct {
    surface_mesh: *const SurfaceMesh,
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

/// Returns a DartIterator that iterates over all the darts of the SurfaceMesh (including boundary darts).
pub fn dartIterator(sm: *const SurfaceMesh) DartIterator {
    return .{
        .surface_mesh = sm,
        .dc_it = sm.dart_data.indexIterator(),
    };
}

/// CellIterator iterates over all the cells of the given type in the SurfaceMesh.
pub fn CellIterator(comptime cell_type: CellType) type {
    return struct {
        surface_mesh: *const SurfaceMesh,
        dc_it: DataContainer.IndexIterator,
        pub fn next(it: *@This()) ?Cell {
            return if (it.dc_it.next()) |idx|
                switch (cell_type) {
                    .halfedge => .{ .halfedge = idx },
                    .corner => .{ .corner = idx },
                    .vertex => .{ .vertex = it.surface_mesh.vertex_dart.value(idx) },
                    .edge => .{ .edge = it.surface_mesh.edge_dart.value(idx) },
                    .face => .{ .face = it.surface_mesh.face_dart.value(idx) },
                    else => unreachable,
                }
            else
                null;
        }
        pub fn nextSafe(it: *@This()) ?Cell {
            return if (it.dc_it.nextSafe()) |idx|
                switch (cell_type) {
                    .halfedge => .{ .halfedge = idx },
                    .corner => .{ .corner = idx },
                    .vertex => .{ .vertex = it.surface_mesh.vertex_dart.value(idx) },
                    .edge => .{ .edge = it.surface_mesh.edge_dart.value(idx) },
                    .face => .{ .face = it.surface_mesh.face_dart.value(idx) },
                    else => unreachable,
                }
            else
                null;
        }
        pub fn reset(it: *@This()) void {
            it.dc_it.reset();
        }
    };
}

/// Returns a CellIterator that iterates over all the cells of the given type in the SurfaceMesh.
pub fn cellIterator(sm: *const SurfaceMesh, comptime cell_type: CellType) CellIterator(cell_type) {
    return .{
        .surface_mesh = sm,
        .dc_it = sm.dataContainerPtr(cell_type).indexIterator(),
    };
}

/// CellDartIterator iterates over all the darts of a cell in the SurfaceMesh.
/// (including the boundary darts that are part of the cell)
const CellDartIterator = struct {
    surface_mesh: *const SurfaceMesh,
    cell: Cell,
    current_dart: ?Dart,
    pub fn next(it: *CellDartIterator) ?Dart {
        // prepare current_dart for next iteration
        defer {
            if (it.current_dart) |current_dart| {
                it.current_dart = switch (it.cell) {
                    .halfedge, .corner => current_dart,
                    .vertex => it.surface_mesh.phi2(it.surface_mesh.phi_1(current_dart)),
                    .edge => it.surface_mesh.phi2(current_dart),
                    .face => it.surface_mesh.phi1(current_dart),
                    .boundary => it.surface_mesh.phi1(current_dart),
                };
                // the next current_dart becomes null when we get back to the starting dart
                if (it.current_dart == it.cell.dart()) {
                    it.current_dart = null;
                }
            }
        }
        return it.current_dart;
    }
    pub fn reset(it: *CellDartIterator) void {
        it.current_dart = it.cell.dart();
    }
};

// Returns a CellDartIterator that iterates over all the darts of the given cell.
pub fn cellDartIterator(sm: *const SurfaceMesh, cell: Cell) CellDartIterator {
    return .{
        .surface_mesh = sm,
        .cell = cell,
        .current_dart = cell.dart(),
    };
}

// Returns the first dart of the cell that is not marked as a boundary dart.
// The only case in which an invalid index can be returned is when called on a cell that is
// entirely composed of boundary darts, i.e. boundary face, boundary halfedge, boundary corner
pub fn cellNonBoundaryDart(sm: *const SurfaceMesh, cell: Cell) Dart {
    var dart_it = sm.cellDartIterator(cell);
    return while (dart_it.next()) |d| {
        if (!sm.dart_boundary_marker.value(d)) break d;
    } else invalid_index;
}

// Returns true if the given dart belongs to the given cell, false otherwise.
pub fn dartBelongsToCell(sm: *const SurfaceMesh, dart: Dart, cell: Cell) bool {
    var dart_it = sm.cellDartIterator(cell);
    return while (dart_it.next()) |d| {
        if (d == dart) break true;
    } else false;
}

// // Returns the first dart that is not marked as a boundary dart.
// fn firstNonBoundaryDart(sm: *const SurfaceMesh) Dart {
//     var first = sm.dart_data.firstIndex();
//     return while (first != sm.dart_data.lastIndex()) : (first = sm.dart_data.nextIndex(first)) {
//         if (!sm.dart_boundary_marker.value(first)) break first;
//     } else sm.dart_data.lastIndex();
// }

// // Returns the next dart after the given dart that is not marked as a boundary dart.
// fn nextNonBoundaryDart(sm: *const SurfaceMesh, d: Dart) Dart {
//     var next = sm.dart_data.nextIndex(d);
//     return while (next != sm.dart_data.lastIndex()) : (next = sm.dart_data.nextIndex(next)) {
//         if (!sm.dart_boundary_marker.value(next)) break next;
//     } else sm.dart_data.lastIndex();
// }

// // Returns the first dart that is marked as a boundary dart.
// fn firstBoundaryDart(sm: *const SurfaceMesh) Dart {
//     var first = sm.dart_data.firstIndex();
//     return while (first != sm.dart_data.lastIndex()) : (first = sm.dart_data.nextIndex(first)) {
//         if (sm.dart_boundary_marker.value(first)) break first;
//     } else sm.dart_data.lastIndex();
// }

// // Returns the next dart after the given dart that is marked as a boundary dart.
// fn nextBoundaryDart(sm: *const SurfaceMesh, d: Dart) Dart {
//     var next = sm.dart_data.nextIndex(d);
//     return while (next != sm.dart_data.lastIndex()) : (next = sm.dart_data.nextIndex(next)) {
//         if (sm.dart_boundary_marker.value(next)) break next;
//     } else sm.dart_data.lastIndex();
// }

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

    pub fn markCell(dm: *DartMarker, cell: Cell) void {
        var dart_it = dm.surface_mesh.cellDartIterator(cell);
        while (dart_it.next()) |d| {
            dm.mark(d);
        }
    }
    pub fn unmarkCell(dm: *DartMarker, cell: Cell) void {
        var dart_it = dm.surface_mesh.cellDartIterator(cell);
        while (dart_it.next()) |d| {
            dm.unmark(d);
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
                .marker = try switch (cell_type) {
                    .halfedge, .corner => sm.dart_data.acquireMarker(),
                    .vertex => sm.vertex_data.acquireMarker(),
                    .edge => sm.edge_data.acquireMarker(),
                    .face => sm.face_data.acquireMarker(),
                    else => unreachable,
                },
            };
        }
        pub fn deinit(cm: *@This()) void {
            switch (cell_type) {
                .halfedge, .corner => cm.surface_mesh.dart_data.releaseMarker(cm.marker),
                .vertex => cm.surface_mesh.vertex_data.releaseMarker(cm.marker),
                .edge => cm.surface_mesh.edge_data.releaseMarker(cm.marker),
                .face => cm.surface_mesh.face_data.releaseMarker(cm.marker),
                else => unreachable,
            }
        }

        pub fn mark(cm: *@This(), c: Cell) void {
            assert(c.cellType() == cell_type);
            cm.marker.valuePtr(cm.surface_mesh.cellIndex(c)).* = true;
        }
        pub fn markByIndex(cm: *@This(), index: u32) void {
            cm.marker.valuePtr(index).* = true;
        }
        pub fn unmark(cm: *@This(), c: Cell) void {
            assert(c.cellType() == cell_type);
            cm.marker.valuePtr(cm.surface_mesh.cellIndex(c)).* = false;
        }
        pub fn unmarkByIndex(cm: *@This(), index: u32) void {
            cm.marker.valuePtr(index).* = false;
        }
        pub fn isMarked(cm: *@This(), c: Cell) bool {
            assert(c.cellType() == cell_type);
            return cm.marker.value(cm.surface_mesh.cellIndex(c));
        }
        pub fn isMarkedByIndex(cm: *@This(), index: u32) bool {
            return cm.marker.value(index);
        }
        pub fn reset(cm: *@This()) void {
            cm.marker.fill(false);
        }
    };
}

/// A ParallelCellTaskRunner allows to run tasks on the cells of the given CellType in parallel.
/// The `run` function takes a Task as an argument which is expected to expose a `run` function that takes a cell of the given CellType as argument.
/// The main thread iterates over the cells and fills buffers, in a double-buffering scheme.
/// Once the first group of buffers is filled, threads are spawned to run the task on these buffers, with a WaitGroup to track the completion of the tasks on this group of buffers.
/// Meanwhile, the main thread continues to iterate over the cells and fills the other group of buffers.
/// Once the second group of buffers is filled, threads are spawned to run the task on these buffers, with a WaitGroup to track the completion of the tasks on this group of buffers.
/// This process is repeated until all cells have been processed.
pub fn ParallelCellTaskRunner(comptime cell_type: CellType) type {
    const CellBuffer = BufferPool(Cell).Buffer;

    return struct {
        surface_mesh: *SurfaceMesh,
        iterator: CellIterator(cell_type),
        // manage two groups of buffers to be able to run tasks on one group while filling the other
        buffers: [2][]CellBuffer,
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
                        const buffers: []CellBuffer = try sm.allocator.alloc(CellBuffer, cpu_count);
                        for (buffers) |*buffer| {
                            buffer.* = try sm.cell_buffer_pool.acquire();
                        }
                        break :blk buffers;
                    },
                    blk: {
                        // acquire buffers from the pool (one buffer per thread) - second group
                        const buffers: []CellBuffer = try sm.allocator.alloc(CellBuffer, cpu_count);
                        for (buffers) |*buffer| {
                            buffer.* = try sm.cell_buffer_pool.acquire();
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

        fn runTaskOnBufferFunction(Task: type) fn (*Task, []Cell) void {
            return struct {
                fn f(task: *Task, buf: []Cell) void {
                    for (buf) |cell| task.run(cell);
                }
            }.f;
        }

        // The `task` must expose a `run(self: *Self, cell: Cell) void` function
        pub fn run(pctr: *@This(), io: std.Io, task: anytype) !void {
            var current_buf_group: usize = 0;
            var current_buf_index: usize = 0;
            var current_index_in_buffer: usize = 0;
            while (pctr.iterator.next()) |cell| {
                // add cell to current buffer of current buffer group
                pctr.buffers[current_buf_group][current_buf_index].data[current_index_in_buffer] = cell;
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

/// A CellSet manages a set of cells of a given CellType, using a marker to track the cells.
/// It provides functions to `add` and `remove` cells, `clear` the set, and check for the presence of a cell (`contains`).
/// The cells of the set are directly available in the `cells` array, and their indices in the SurfaceMesh are available in the `indices` array.
/// The `update` function has to be called after the SurfaceMesh has been modified to rebuild the CellSet based on the marker.
pub const CellSetGen = struct {
    surface_mesh: *SurfaceMesh,
    cells: std.ArrayList(Cell),
    indices: std.ArrayList(u32),
    name: []const u8,
};

pub fn CellSet(comptime cell_type: CellType) type {
    return struct {
        cell_set_gen: CellSetGen,
        marker: CellMarker(cell_type),

        pub fn init(sm: *SurfaceMesh, name: []const u8) !@This() {
            return .{
                .cell_set_gen = .{
                    .surface_mesh = sm,
                    .cells = .empty,
                    .indices = .empty,
                    .name = name,
                },
                .marker = try .init(sm),
            };
        }
        pub fn deinit(cs: *@This()) void {
            cs.marker.deinit();
            cs.cell_set_gen.cells.deinit(cs.cell_set_gen.surface_mesh.allocator);
            cs.cell_set_gen.indices.deinit(cs.cell_set_gen.surface_mesh.allocator);
        }

        pub fn gen(cs: *const @This()) *const CellSetGen {
            return &cs.cell_set_gen;
        }

        pub fn contains(cs: *@This(), c: Cell) bool {
            return cs.marker.isMarked(c);
        }
        pub fn add(cs: *@This(), c: Cell) !void {
            if (cs.contains(c)) return;
            cs.marker.mark(c);
            try cs.cell_set_gen.cells.append(cs.cell_set_gen.surface_mesh.allocator, c);
            try cs.cell_set_gen.indices.append(cs.cell_set_gen.surface_mesh.allocator, cs.cell_set_gen.surface_mesh.cellIndex(c));
        }
        pub fn remove(cs: *@This(), c: Cell) void {
            if (!cs.contains(c)) return;
            const c_index = cs.cell_set_gen.surface_mesh.cellIndex(c);
            cs.marker.unmark(c);
            for (cs.cell_set_gen.indices.items, 0..) |index, i| {
                if (index == c_index) {
                    _ = cs.cell_set_gen.cells.swapRemove(i);
                    _ = cs.cell_set_gen.indices.swapRemove(i);
                    break;
                }
            }
        }
        pub fn clear(cs: *@This()) void {
            cs.marker.reset();
            cs.cell_set_gen.cells.clearRetainingCapacity();
            cs.cell_set_gen.indices.clearRetainingCapacity();
        }
        pub fn update(cs: *@This()) !void {
            cs.cell_set_gen.cells.clearRetainingCapacity();
            cs.cell_set_gen.indices.clearRetainingCapacity();
            var it = cs.cell_set_gen.surface_mesh.cellIterator(cell_type);
            while (it.next()) |c| {
                if (cs.contains(c)) {
                    try cs.cell_set_gen.cells.append(cs.cell_set_gen.surface_mesh.allocator, c);
                    try cs.cell_set_gen.indices.append(cs.cell_set_gen.surface_mesh.allocator, cs.cell_set_gen.surface_mesh.cellIndex(c));
                }
            }
        }
    };
}

/// A CellData is a handle to a data array of type `T` associated with cells of the given CellType.
/// It provides functions to access the data associated with a given cell or its index.
pub fn CellData(comptime cell_type: CellType, comptime T: type) type {
    return struct {
        pub const CellType = cell_type;
        pub const DataType = T;

        surface_mesh: *const SurfaceMesh,
        data: *Data(T),

        pub fn value(cd: @This(), c: Cell) T {
            assert(c.cellType() == cell_type);
            return cd.data.value(cd.surface_mesh.cellIndex(c));
        }
        pub fn valueByIndex(cd: @This(), index: u32) T {
            return cd.data.value(index);
        }

        pub fn valuePtr(cd: @This(), c: Cell) *T {
            assert(c.cellType() == cell_type);
            return cd.data.valuePtr(cd.surface_mesh.cellIndex(c));
        }
        pub fn valuePtrByIndex(cd: @This(), index: u32) *T {
            return cd.data.valuePtr(index);
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
pub fn addData(sm: *SurfaceMesh, comptime cell_type: CellType, comptime T: type, name: []const u8) !CellData(cell_type, T) {
    return .{
        .surface_mesh = sm,
        .data = try sm.dataContainerPtr(cell_type).addData(T, name),
    };
}

/// Creates a new data array of the type `T` associated with cells of the given CellType.
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

/// Returns a handle to the data array of the type `T` associated with cells of the given CellType
/// if it exists with the given name, otherwise returns null.
pub fn getData(sm: *const SurfaceMesh, comptime cell_type: CellType, comptime T: type, name: []const u8) ?CellData(cell_type, T) {
    if (sm.dataContainerPtr(cell_type).getData(T, name)) |d| {
        return .{
            .surface_mesh = sm,
            .data = d,
        };
    } else return null;
}

/// Returns a handle to the data array of the type `T` associated with cells of the given CellType
/// if it exists with the given name, otherwise creates a new data array of the type `T` associated with cells of the given CellType
/// and returns a handle to it, along with a boolean indicating whether the data array was newly created (true) or already existed (false).
pub fn getOrAddData(sm: *SurfaceMesh, comptime cell_type: CellType, comptime T: type, name: []const u8) !struct { CellData(cell_type, T), bool } {
    const d, const created = try sm.dataContainerPtr(cell_type).getOrAddData(T, name);
    return .{
        .{
            .surface_mesh = sm,
            .data = d,
        },
        created,
    };
}

/// Removes the data array of the type `T` associated with cells of the given CellType.
pub fn removeData(sm: *SurfaceMesh, comptime cell_type: CellType, comptime T: type, cellData: CellData(cell_type, T)) void {
    assert(cellData.surface_mesh == sm);
    sm.dataContainerPtr(cell_type).removeData(&cellData.data.data_gen);
}

/// Acquire a new index for the given cell type.
/// Only vertices, edges and faces need indices (halfedges & corners are indexed by their unique dart index).
/// The new index is not associated to any dart of the mesh.
/// This function is only intended for use in SurfaceMesh creation process (import, ...) as the new index is not
/// in use until it is associated to the darts of a cell of the mesh (see setCellIndex).
pub fn acquireCellIndex(sm: *SurfaceMesh, cell_type: CellType) !u32 {
    return sw: switch (cell_type) {
        .vertex => {
            const idx = try sm.vertex_data.acquireIndex();
            sm.vertex_dart.valuePtr(idx).* = invalid_index; // the new index is not associated to any dart yet
            break :sw idx;
        },
        .edge => {
            const idx = try sm.edge_data.acquireIndex();
            sm.edge_dart.valuePtr(idx).* = invalid_index; // the new index is not associated to any dart yet
            break :sw idx;
        },
        .face => {
            const idx = try sm.face_data.acquireIndex();
            sm.face_dart.valuePtr(idx).* = invalid_index; // the new index is not associated to any dart yet
            break :sw idx;
        },
        else => unreachable,
    };
}

/// Creates a new cell set for the given CellType.
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

/// Returns a pointer to the cell set of the given CellType with the given name if it exists, otherwise returns null.
pub fn getCellSet(sm: *const SurfaceMesh, comptime cell_type: CellType, name: []const u8) ?*CellSet(cell_type) {
    return sm.cellSetContainerPtr(cell_type).getPtr(name);
}

/// Returns a pointer to the cell set of the given CellType with the given name if it exists,
/// otherwise creates a new cell set with the given name and returns a pointer to it.
pub fn getOrAddCellSet(sm: *SurfaceMesh, comptime cell_type: CellType, name: []const u8) !*CellSet(cell_type) {
    if (sm.getCellSet(cell_type, name)) |cs| {
        return cs;
    } else {
        return try sm.addCellSet(cell_type, name);
    }
}

/// Removes the cell set of the given CellType.
pub fn removeCellSet(sm: *SurfaceMesh, comptime cell_type: CellType, cell_set: *CellSet(cell_type)) void {
    assert(cell_set.surface_mesh == sm);
    cell_set.deinit();
    if (sm.cellSetContainerPtr(cell_type).remove(cell_set.cell_set_gen.name)) {
        const name: [:0]const u8 = @ptrCast(cell_set.cell_set_gen.name); // the name is a null-terminated string (dupeSentinel in addCellSet)
        sm.allocator.free(name); // free the name
    }
}

fn addDart(sm: *SurfaceMesh) !Dart {
    const d = try sm.dart_data.acquireIndex();
    sm.dart_phi1.valuePtr(d).* = d;
    sm.dart_phi_1.valuePtr(d).* = d;
    sm.dart_phi2.valuePtr(d).* = d;
    sm.dart_vertex_index.valuePtr(d).* = invalid_index;
    sm.dart_edge_index.valuePtr(d).* = invalid_index;
    sm.dart_face_index.valuePtr(d).* = invalid_index;
    // boundary marker is false on a new index
    return d;
}

fn removeDart(sm: *SurfaceMesh, d: Dart) void {
    const vertex_index = sm.dart_vertex_index.value(d);
    if (vertex_index != invalid_index) {
        sm.vertex_data.unrefIndex(vertex_index);
    }
    const edge_index = sm.dart_edge_index.value(d);
    if (edge_index != invalid_index) {
        sm.edge_data.unrefIndex(edge_index);
    }
    const face_index = sm.dart_face_index.value(d);
    if (face_index != invalid_index) {
        sm.face_data.unrefIndex(face_index);
    }
    sm.dart_data.releaseIndex(d);
}

pub fn phi1(sm: *const SurfaceMesh, dart: Dart) Dart {
    return sm.dart_phi1.value(dart);
}
pub fn phi_1(sm: *const SurfaceMesh, dart: Dart) Dart {
    return sm.dart_phi_1.value(dart);
}
pub fn phi2(sm: *const SurfaceMesh, dart: Dart) Dart {
    return sm.dart_phi2.value(dart);
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

pub fn isValidDart(sm: *const SurfaceMesh, d: Dart) bool {
    return sm.dart_data.isActiveIndex(d);
}

pub fn isIncidentToBoundary(sm: *const SurfaceMesh, cell: Cell) bool {
    return switch (cell.cellType()) {
        // a vertex is incident to a boundary face if one of its darts is part of a boundary face
        .vertex => blk: {
            var dart_it = sm.cellDartIterator(cell);
            while (dart_it.next()) |d| {
                if (sm.isBoundaryDart(d)) {
                    break :blk true;
                }
            }
            break :blk false;
        },
        // an edge is incident to a boundary face if one of its 2 darts is part of a boundary face
        .edge => sm.isBoundaryDart(cell.dart()) or sm.isBoundaryDart(sm.phi2(cell.dart())),
        else => unreachable,
    };
}

/// Sets the index of the cell of type cell_type the dart d belongs to.
/// Reference counts of old and new indices are updated accordingly (see DataContainer.refIndex & unrefIndex).
/// Should only be called for vertex, edge and face cell types (halfedges & corners are indexed by their unique dart index).
pub fn setDartCellIndex(sm: *SurfaceMesh, d: Dart, comptime cell_type: CellType, index: u32) void {
    var index_data = switch (cell_type) {
        .vertex => sm.dart_vertex_index,
        .edge => sm.dart_edge_index,
        .face => sm.dart_face_index,
        else => unreachable,
    };
    var data_container = sm.dataContainerPtr(cell_type);
    const old_index: u32 = index_data.value(d);
    if (old_index == index) return; // no change
    if (index != invalid_index) {
        data_container.refIndex(index);
    }
    if (old_index != invalid_index) {
        data_container.unrefIndex(old_index);
    }
    index_data.valuePtr(d).* = index;
}

/// Returns the index of the cell of type cell_type the dart d belongs to.
pub fn dartCellIndex(sm: *const SurfaceMesh, d: Dart, cell_type: CellType) u32 {
    switch (cell_type) {
        .halfedge, .corner => return d,
        .vertex => return sm.dart_vertex_index.value(d),
        .edge => return sm.dart_edge_index.value(d),
        .face => return sm.dart_face_index.value(d),
        else => unreachable,
    }
}

/// Sets the index of all the darts of the given cell c to the given index.
/// Should only be called for vertices, edges and faces (halfedges & corners are indexed by their unique dart index).
fn setCellIndex(sm: *SurfaceMesh, c: Cell, index: u32) void {
    switch (c) {
        .vertex => {
            var dart_it = sm.cellDartIterator(c);
            while (dart_it.next()) |d| {
                sm.setDartCellIndex(d, .vertex, index);
            }
        },
        .edge => {
            const d = c.dart();
            sm.setDartCellIndex(d, .edge, index);
            sm.setDartCellIndex(sm.phi2(d), .edge, index);
        },
        .face => {
            var dart_it = sm.cellDartIterator(c);
            while (dart_it.next()) |d| {
                sm.setDartCellIndex(d, .face, index);
            }
        },
        else => unreachable,
    }
}

/// Returns the index of the given cell.
pub fn cellIndex(sm: *const SurfaceMesh, c: Cell) u32 {
    return sm.dartCellIndex(c.dart(), c.cellType());
}

/// Iterates over the cells of the given cell type and assigns them an index if they don't have one yet
/// (i.e. if their index is invalid_index).
/// If part of the darts of a cell already have an index, this index is assigned to all the darts of the cell.
/// Boundary faces are not indexed.
/// Representative darts of the indexed cells are set along the way (only non-boundary darts are chosen as representative).
pub fn indexCells(sm: *SurfaceMesh, comptime cell_type: CellType) !void {
    assert(cell_type == .vertex or cell_type == .edge or cell_type == .face);
    var dm: DartMarker = try .init(sm);
    defer dm.deinit();
    var it = sm.dartIterator();
    while (it.next()) |d| {
        if (dm.isMarked(d)) continue; // skip darts that are part of a cell that have already been processed
        if (sm.isBoundaryDart(d)) continue; // skip boundary darts (boundary faces are not indexed)

        // first check if the cell is already indexed, even partially
        // (assume that even if only partially indexed, all the darts of the cell have the same index)
        var index: u32 = invalid_index;
        const cell = @unionInit(SurfaceMesh.Cell, @tagName(cell_type), d);
        var dart_it = sm.cellDartIterator(cell);
        while (dart_it.next()) |cd| {
            const cd_index = sm.dartCellIndex(cd, cell_type);
            if (cd_index != invalid_index) {
                index = cd_index;
                break;
            }
        }
        // if the cell is not indexed yet, acquire a new index for it
        if (index == invalid_index) {
            index = try sm.acquireCellIndex(cell_type);
        }
        // set the index to all the darts of the cell and mark them along the way
        dart_it.reset();
        while (dart_it.next()) |cd| {
            sm.setDartCellIndex(cd, cell_type, index);
            dm.mark(cd);
        }
        // set the representative dart of the cell to the first encountered non-boundary dart of the cell
        switch (cell_type) {
            .vertex => sm.vertex_dart.valuePtr(index).* = d,
            .edge => sm.edge_dart.valuePtr(index).* = d,
            .face => sm.face_dart.valuePtr(index).* = d,
            else => unreachable,
        }
    }
}

/// Returns the number of cells of the given CellType in the given SurfaceMesh.
/// For vertices, edges and faces, the number of cells is simply the number of elements (active indices)
/// in the corresponding DataContainer.
/// For halfedges and corners, the number of cells is the number of non-boundary darts (each halfedge/corner
/// is represented by a single non-boundary dart).
/// For boundary faces, as there is no index and no data container, an explicit Darts traversal with marking is needed.
pub fn nbCells(sm: *SurfaceMesh, comptime cell_type: CellType) u32 {
    return switch (cell_type) {
        .vertex, .edge, .face => sm.dataContainerPtr(cell_type).nbElements(),
        .halfedge, .corner => sm.dart_data.nbElements() - sm.nb_boundary_darts,
        .boundary => blk: {
            var count: u32 = 0;
            var dm = DartMarker.init(sm) catch {
                break :blk 0; // if the marker cannot be created, return 0
            };
            defer dm.deinit();
            var it = sm.dartIterator();
            while (it.next()) |d| {
                if (sm.isBoundaryDart(d) and !dm.isMarked(d)) {
                    dm.markCell(.{ .face = d });
                }
                count += 1;
            }
            break :blk count;
        },
    };
}

/// Returns the degree of the given cell (number of d+1 incident cells).
/// Only vertices and edges have a degree (faces are top-cells and do not have a degree).
pub fn degree(sm: *const SurfaceMesh, cell: Cell) u32 {
    return switch (cell) {
        // nb refs is equal to the number of darts of the vertex which is equal to its degree
        // (no need to iterate through the darts of the vertex)
        .vertex => blk: {
            const index = sm.cellIndex(cell);
            assert(sm.vertex_data.isActiveIndex(index));
            break :blk sm.vertex_data.nb_refs.value(index);
        },
        .edge => if (sm.isBoundaryDart(cell.dart()) or sm.isBoundaryDart(sm.phi2(cell.dart()))) 1 else 2,
        else => unreachable,
    };
}

/// Returns the codegree of the given cell (number of d-1 incident cells).
/// Only edges and faces have a codegree (vertices are 0-cells and do not have a codegree).
pub fn codegree(sm: *const SurfaceMesh, cell: Cell) u32 {
    return switch (cell) {
        .edge => 2,
        // nb refs is equal to the number of darts of the face which is equal to its codegree
        // (no need to iterate through the darts of the face)
        .face => blk: {
            // boundary faces are not indexed and thus do not have an associated index with a ref count
            if (sm.isBoundaryDart(cell.dart())) {
                var res: u32 = 0;
                var dart_it = sm.cellDartIterator(cell);
                while (dart_it.next()) |_| : (res += 1) {}
                break :blk res;
            } else {
                const index = sm.cellIndex(cell);
                assert(sm.face_data.isActiveIndex(index));
                break :blk sm.face_data.nb_refs.value(index);
            }
        },
        else => unreachable,
    };
}

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
        for ([_]CellType{ .vertex, .edge, .face }) |cell_type| {
            const index = sm.dartCellIndex(d, cell_type);
            if ((cell_type == .face) and sm.isBoundaryDart(d)) {
                if (index != invalid_index) {
                    zgp_log.warn("Boundary dart {d} has a valid {s} index", .{ d, @tagName(cell_type) });
                    ok = false;
                }
            } else {
                if (index == invalid_index) {
                    zgp_log.warn("Dart {d} has invalid {s} index", .{ d, @tagName(cell_type) });
                    ok = false;
                }
            }
        }
    }

    var d_marker: DartMarker = try .init(sm);
    defer d_marker.deinit();

    inline for ([_]CellType{ .vertex, .edge, .face }) |cell_type| {
        const index_count = try sm.addData(cell_type, u32, "index_count");
        defer sm.removeData(cell_type, u32, index_count);
        index_count.data.fill(0);

        const cell_darts_count = try sm.addData(cell_type, u32, "cell_darts_count");
        defer sm.removeData(cell_type, u32, cell_darts_count);
        cell_darts_count.data.fill(0);

        d_it.reset();
        d_marker.reset();
        while (d_it.next()) |d| {
            if (d_marker.isMarked(d)) continue;
            if (sm.isBoundaryDart(d)) continue; // skip boundary darts (boundary faces are not indexed)

            const cell = @unionInit(SurfaceMesh.Cell, @tagName(cell_type), d);
            d_marker.markCell(cell);

            const idx = sm.cellIndex(cell);
            if (idx == invalid_index) {
                zgp_log.warn("{s} of dart {d} has invalid index", .{ @tagName(cell_type), cell.dart() });
                ok = false;
            }

            const cell_representative_dart = switch (cell_type) {
                .vertex => sm.vertex_dart.value(idx),
                .edge => sm.edge_dart.value(idx),
                .face => sm.face_dart.value(idx),
                else => unreachable,
            };
            var found_representative_dart = false;

            index_count.valuePtrByIndex(idx).* += 1;
            const c = cell_darts_count.valuePtrByIndex(idx);
            var cell_darts_it = sm.cellDartIterator(cell);
            while (cell_darts_it.next()) |cd| {
                if (cd == cell_representative_dart) {
                    found_representative_dart = true;
                }
                const cd_idx = sm.dartCellIndex(cd, cell_type);
                if (cd_idx != idx) {
                    zgp_log.warn("Inconsistent {s} index for dart {d}: {d} != {d}", .{ @tagName(cell_type), cd, cd_idx, idx });
                    ok = false;
                }
                c.* += 1;
            }
            if (!found_representative_dart) {
                zgp_log.warn("Representative dart for {s} index {d} is not part of the cell", .{ @tagName(cell_type), idx });
                ok = false;
            }
            switch (cell_type) {
                .vertex => {
                    if (c.* < 2) {
                        zgp_log.warn("Inconsistent vertex darts count for vertex of dart {d}: {d} < 2", .{ cell.dart(), c.* });
                        ok = false;
                    }
                },
                .edge => {
                    if (c.* != 2) {
                        zgp_log.warn("Inconsistent edge darts count for edge of dart {d}: {d} != 2", .{ cell.dart(), c.* });
                        ok = false;
                    }
                },
                .face => {
                    if (c.* < 3) {
                        zgp_log.warn("Inconsistent face darts count for face of dart {d}: {d} < 3", .{ cell.dart(), c.* });
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
            const darts_count = cell_darts_count.data.value(idx);
            if (ref_count != darts_count) {
                zgp_log.warn("Inconsistent {s} index {d}: ref count {d} != actual count {d}", .{ @tagName(cell_type), idx, ref_count, darts_count });
                ok = false;
            }
            const count = index_count.data.value(idx);
            if (count == 0) {
                zgp_log.warn("Unused {s} index {d}", .{ @tagName(cell_type), idx });
                ok = false;
            } else if (count > 1) {
                zgp_log.warn("Non-unique {s} index {d}: used {d} times", .{ @tagName(cell_type), idx, count });
                ok = false;
            }
        }
    }

    return ok;
}

/// Creates a new face with the given number of vertices.
/// Unbounded means that the face is not linked to any boundary "outer" face (all its darts are phi2-linked to themselves).
/// WARNING: Cell indices are not managed by this function.
/// This function is only intended for use in SurfaceMesh creation process (import, ...) as the SurfaceMesh is not
/// valid after this function is called.
pub fn addUnboundedFace(sm: *SurfaceMesh, nb_vertices: u32) !Cell {
    const d1 = try sm.addDart();
    for (1..nb_vertices) |_| {
        const d2 = try sm.addDart();
        sm.phi1Sew(d1, d2);
    }
    return .{ .face = d1 };
}

/// Removes the given unbounded face from the SurfaceMesh.
/// All the darts of the face are simply removed from the SurfaceMesh, no boundary face is created to close the hole left by the removal of the face.
/// WARNING: Cell indices are not managed by this function.
/// This function is only intended for use in SurfaceMesh creation process (import, ...) as the SurfaceMesh is not
/// valid after this function is called.
pub fn removeFace(sm: *SurfaceMesh, face: Cell) void {
    assert(face.cellType() == .face);
    var dart_it = sm.cellDartIterator(face);
    while (dart_it.next()) |d| {
        sm.phi2Unsew(d);
        sm.removeDart(d);
    }
}

/// Closes the hole incident to the given dart by adding a polygonal face.
/// The given dart must be a dart on the boundary of the hole (phi2-linked to itself).
/// The new face is returned, represented by the dart sewn to d by phi2.
/// WARNING: Cell indices are not managed by this function.
/// This function is only intended for use in SurfaceMesh creation process (import, ...) as the SurfaceMesh is not
/// valid after this function is called.
pub fn closeHoleWithPolygon(sm: *SurfaceMesh, d: Dart) !Cell {
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

    return .{ .face = b_first };
}

/// Closes the given SurfaceMesh by adding boundary faces where needed.
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
            var f_it = sm.cellDartIterator(f);
            while (f_it.next()) |fd| {
                sm.dart_boundary_marker.valuePtr(fd).* = true;
            }
            nb_boundary_faces += 1;
        }
    }
    return nb_boundary_faces;
}

/// Closes the hole incident to the given dart by adding an umbrella.
/// The given dart must be a dart on the boundary of the hole (phi2-linked to itself).
/// WARNING: Cell indices are managed by this function which assumes that the SurfaceMesh was valid just before the hole was created.
pub fn closeHoleWithUmbrella(sm: *SurfaceMesh, d: Dart) !Cell {
    assert(sm.phi2(d) == d);
    // create the first face of the umbrella
    var f_first = try sm.addUnboundedFace(3);
    sm.phi2Sew(d, f_first.dart());

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
        sm.phi2Sew(d_hole_current, f_next.dart());
        sm.phi2Sew(sm.phi_1(f_current.dart()), sm.phi1(f_next.dart()));
        f_current = f_next;
    }
    sm.phi2Sew(sm.phi_1(f_current.dart()), sm.phi1(f_first.dart())); // finish the umbrella

    const cv_dart = sm.phi_1(f_first.dart()); // central vertex dart

    // set the indices for the cells
    const cv_index = try sm.acquireCellIndex(.vertex); // new index for central vertex
    sm.vertex_dart.valuePtr(cv_index).* = cv_dart; // set the representative dart of the central vertex
    var dart_it = sm.cellDartIterator(.{ .vertex = cv_dart }); // turn around central vertex
    while (dart_it.next()) |dart| {
        sm.setDartCellIndex(dart, .vertex, cv_index);
        const d1 = sm.phi1(dart);
        {
            // hole vertices
            const h_index = sm.dartCellIndex(sm.phi1(sm.phi2(d1)), .vertex);
            sm.setDartCellIndex(d1, .vertex, h_index);
            sm.setDartCellIndex(sm.phi2(dart), .vertex, h_index);
            sm.vertex_dart.valuePtr(h_index).* = d1; // set the representative dart of the hole vertex
        }
        {
            // hole & umbrella edges
            const h_index = sm.dartCellIndex(sm.phi2(d1), .edge);
            sm.setDartCellIndex(d1, .edge, h_index);
            sm.edge_dart.valuePtr(h_index).* = d1; // set the representative dart of the hole edge
            const u_index = try sm.acquireCellIndex(.edge);
            sm.setCellIndex(.{ .edge = dart }, u_index);
            sm.edge_dart.valuePtr(u_index).* = dart; // set the representative dart of the umbrella edge
        }
        {
            // umbrella faces
            const u_index = try sm.acquireCellIndex(.face);
            sm.setCellIndex(.{ .face = dart }, u_index);
            sm.face_dart.valuePtr(u_index).* = dart; // set the representative dart of the umbrella face
        }
    }

    return .{ .vertex = cv_dart };
}

/// Creates a new pyramid whose base is a polygon with `baseSize` vertices.
/// Returns the base face of the pyramid.
pub fn addPyramid(sm: *SurfaceMesh, baseSize: u32) !Cell {
    // first create the umbrella forming the pyramid tip
    const first = try sm.addUnboundedFace(3);
    var current_dart = first.dart();
    for (1..baseSize) |_| {
        const next = try sm.addUnboundedFace(3);
        sm.phi2Sew(sm.phi_1(current_dart), sm.phi1(next.dart()));
        current_dart = next.dart();
    }
    sm.phi2Sew(sm.phi_1(current_dart), sm.phi1(first.dart())); // finish the umbrella
    // then close the hole to create the base face
    const base_face = try sm.closeHoleWithPolygon(first.dart());

    // set the indices for the cells
    var dart_it = sm.cellDartIterator(base_face);
    while (dart_it.next()) |d| {
        {
            // base vertices
            const index = try sm.acquireCellIndex(.vertex);
            sm.setCellIndex(.{ .vertex = d }, index);
            sm.vertex_dart.valuePtr(index).* = d; // set the representative dart of the vertex
        }
        {
            // base & umbrella edges
            const b_index = try sm.acquireCellIndex(.edge);
            sm.setCellIndex(.{ .edge = d }, b_index);
            sm.edge_dart.valuePtr(b_index).* = d; // set the representative dart of the edge
            const u_index = try sm.acquireCellIndex(.edge);
            const u_edge_dart = sm.phi1(sm.phi2(d));
            sm.setCellIndex(.{ .edge = u_edge_dart }, u_index);
            sm.edge_dart.valuePtr(u_index).* = u_edge_dart; // set the representative dart of the edge
        }
        {
            // umbrella faces
            const index = try sm.acquireCellIndex(.face);
            const u_face_dart = sm.phi2(d);
            sm.setCellIndex(.{ .face = u_face_dart }, index);
            sm.face_dart.valuePtr(index).* = u_face_dart; // set the representative dart of the face
        }
    }
    {
        // tip vertex
        const index = try sm.acquireCellIndex(.vertex);
        const tip_vertex_dart = sm.phi_1(first.dart());
        sm.setCellIndex(.{ .vertex = tip_vertex_dart }, index);
        sm.vertex_dart.valuePtr(index).* = tip_vertex_dart; // set the representative dart of the vertex
    }
    {
        // base face
        const index = try sm.acquireCellIndex(.face);
        sm.setCellIndex(base_face, index);
        sm.face_dart.valuePtr(index).* = base_face.dart(); // set the representative dart of the face
    }

    return base_face;
}

/// Cuts the given edge by inserting a new vertex.
/// The new vertex is returned: its representative dart is the one that
/// belongs to the same face as the representative dart of the given edge.
/// The edge of the representative dart of the given edge keeps the same edge index
/// (a new edge index is given to the other new edge).
pub fn cutEdge(sm: *SurfaceMesh, edge: Cell) !Cell {
    assert(edge.cellType() == .edge);

    const d = edge.dart();
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

    {
        // Vertex indices.
        const index = try sm.acquireCellIndex(.vertex);
        sm.setDartCellIndex(d1, .vertex, index);
        sm.setDartCellIndex(dd1, .vertex, index);
        sm.vertex_dart.valuePtr(index).* = d1; // set the representative dart of the new vertex
    }
    {
        // Edge indices.
        // The edge of d keeps the index of the original edge.
        const original_edge_index = sm.dartCellIndex(d, .edge);
        sm.setDartCellIndex(dd1, .edge, original_edge_index);
        sm.edge_dart.valuePtr(original_edge_index).* = d; // set the representative dart of the original edge
        // The edge of dd gets a new index.
        const index = try sm.acquireCellIndex(.edge);
        sm.setDartCellIndex(dd, .edge, index);
        sm.setDartCellIndex(d1, .edge, index);
        sm.edge_dart.valuePtr(index).* = dd; // set the representative dart of the new edge
    }
    {
        // Face indices.
        sm.setDartCellIndex(d1, .face, sm.dartCellIndex(d, .face));
        sm.setDartCellIndex(dd1, .face, sm.dartCellIndex(dd, .face));
        // incident faces only gained new darts, so their representative darts remain the same
    }

    return .{ .vertex = d1 };
}

/// Flips the given edge (following the orientation of the faces).
/// Should only be called after a call to `canFlipEdge`.
/// TODO: write a more detailed comment
pub fn flipEdge(sm: *SurfaceMesh, edge: Cell) void {
    assert(edge.cellType() == .edge);

    const d = edge.dart();
    const dd = sm.phi2(d);
    const d1 = sm.phi1(d);
    const d_1 = sm.phi_1(d);
    const dd1 = sm.phi1(dd);
    const dd_1 = sm.phi_1(dd);

    sm.phi1Sew(d, dd_1);
    sm.phi1Sew(dd, d_1);
    sm.phi1Sew(d, d1);
    sm.phi1Sew(dd, dd1);

    {
        // Vertex indices.
        sm.setDartCellIndex(d, .vertex, sm.dartCellIndex(sm.phi1(dd), .vertex));
        sm.setDartCellIndex(dd, .vertex, sm.dartCellIndex(sm.phi1(d), .vertex));
        // dart d left the vertex of dd1 and dart dd left the vertex of d1
        // as they may have been their representative darts, we need to update the representative darts of these vertices
        sm.vertex_dart.valuePtr(sm.dartCellIndex(dd1, .vertex)).* = dd1; // set the representative dart of the vertex of dd1
        sm.vertex_dart.valuePtr(sm.dartCellIndex(d1, .vertex)).* = d1; // set the representative dart of the vertex of d1
    }
    {
        // Edge indices.
        // no new edges are created & no existing edges are modified
    }
    {
        // Face indices.
        const df_idx = sm.dartCellIndex(d, .face);
        const ddf_idx = sm.dartCellIndex(dd, .face);
        // sm.setDartCellIndex(sm.phi_1(d), .face, sm.dartCellIndex(d, .face));
        // sm.setDartCellIndex(sm.phi_1(dd), .face, sm.dartCellIndex(dd, .face));
        sm.setDartCellIndex(dd1, .face, df_idx);
        sm.setDartCellIndex(d1, .face, ddf_idx);
        // dart d1 left the face of d and dart dd1 left the face of dd
        // as they may have been their representative darts, we need to update the representative darts of these faces
        sm.face_dart.valuePtr(df_idx).* = d; // set the representative dart of the face of d
        sm.face_dart.valuePtr(ddf_idx).* = dd; // set the representative dart of the face of dd
    }
}

/// Check if the given edge can be flipped. Edges that cannot be flipped:
///  1 - boundary edges
///  2 - edges having an incident vertex of degree 2
/// No geometry conditions are checked here.
pub fn canFlipEdge(sm: *SurfaceMesh, edge: Cell) bool {
    assert(edge.cellType() == .edge);

    const d = edge.dart();
    const dd = sm.phi2(d);

    // condition 1: do not flip boundary edges
    if (sm.isIncidentToBoundary(edge)) {
        return false;
    }

    // condition 2: avoid creating degree 1 vertices
    if (sm.degree(.{ .vertex = d }) == 2 or sm.degree(.{ .vertex = dd }) == 2) {
        return false;
    }

    return true;
}

/// Unflips the given edge (following the inverse orientation of the faces).
/// Should only be called after a call to `canUnflipEdge`.
/// TODO: write a more detailed comment
pub fn unflipEdge(sm: *SurfaceMesh, edge: Cell) void {
    assert(edge.cellType() == .edge);

    const d = edge.dart();
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

    {
        // Vertex indices.
        sm.setDartCellIndex(d, .vertex, sm.dartCellIndex(sm.phi1(dd), .vertex));
        sm.setDartCellIndex(dd, .vertex, sm.dartCellIndex(sm.phi1(d), .vertex));
        // dart d left the vertex of dd1 and dart dd left the vertex of d1
        // as they may have been their representative darts, we need to update the representative darts of these vertices
        sm.vertex_dart.valuePtr(sm.dartCellIndex(dd1, .vertex)).* = dd1; // set the representative dart of the vertex of dd1
        sm.vertex_dart.valuePtr(sm.dartCellIndex(d1, .vertex)).* = d1; // set the representative dart of the vertex of d1
    }
    {
        // Edge indices.
        // no new edges are created & no existing edges are modified
    }
    {
        // Face indices.
        const df_idx = sm.dartCellIndex(d, .face);
        const ddf_idx = sm.dartCellIndex(dd, .face);
        sm.setDartCellIndex(dd_1, .face, df_idx);
        sm.setDartCellIndex(d_1, .face, ddf_idx);
        // dart d_1 left the face of d and dart dd_1 left the face of dd
        // as they may have been their representative darts, we need to update the representative darts of these faces
        sm.face_dart.valuePtr(df_idx).* = d; // set the representative dart of the face of d
        sm.face_dart.valuePtr(ddf_idx).* = dd; // set the representative dart of the face of dd
    }
}

/// Check if the given edge can be unflipped. Edges that cannot be unflipped:
///  1 - boundary edges
///  2 - edges having an incident vertex of degree 2
/// No geometry conditions are checked here.
pub fn canUnflipEdge(sm: *SurfaceMesh, edge: Cell) bool {
    assert(edge.cellType() == .edge);

    const d = edge.dart();
    const dd = sm.phi2(d);

    // condition 1: do not flip boundary edges
    if (sm.isIncidentToBoundary(edge)) {
        return false;
    }

    // condition 2: avoid creating degree 1 vertices
    if (sm.degree(.{ .vertex = d }) == 2 or sm.degree(.{ .vertex = dd }) == 2) {
        return false;
    }

    return true;
}

/// Collapses the given edge.
/// Should only be called after a call to `canCollapseEdge`.
/// TODO: write a more detailed comment
pub fn collapseEdge(sm: *SurfaceMesh, edge: Cell) Cell {
    assert(edge.cellType() == .edge);

    const d = edge.dart();
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

    {
        // Vertex indices.
        // use the index of the vertex of d for the resulting vertex
        const v_idx = sm.dartCellIndex(d_12, .vertex);
        sm.setCellIndex(.{ .vertex = d_12 }, v_idx);
        sm.vertex_dart.valuePtr(v_idx).* = d_12; // set the representative dart of the resulting vertex
        // if the 2-sided face on the side of d has been removed, then d12 is now the representative dart of the vertex of d12
        if (sm.phi2(d12) == d_12) {
            sm.vertex_dart.valuePtr(sm.dartCellIndex(d12, .vertex)).* = d12;
        }
        // if the 2-sided face on the side of dd has been removed, then dd12 is now the representative dart of the vertex of dd12
        if (sm.phi2(dd12) == dd_12) {
            sm.vertex_dart.valuePtr(sm.dartCellIndex(dd12, .vertex)).* = dd12;
        }
    }
    {
        // Edge indices.
        // these statements are correct wether 2-sided faces have been deleted or not
        sm.setDartCellIndex(d_12, .edge, sm.dartCellIndex(sm.phi2(d_12), .edge));
        sm.setDartCellIndex(dd_12, .edge, sm.dartCellIndex(sm.phi2(dd_12), .edge));
        // if the 2-sided face on the side of d has been removed, then:
        // - use the index of the edge of d12 for the resulting edge
        // - d12 is now the representative dart of this edge
        if (sm.phi2(d12) == d_12) {
            const e_idx = sm.dartCellIndex(d12, .edge);
            sm.setDartCellIndex(d_12, .edge, e_idx);
            sm.edge_dart.valuePtr(e_idx).* = d12;
        }
        // if the 2-sided face on the side of dd has been removed, then:
        // - use the index of the edge of dd12 for the resulting edge
        // - dd12 is now the representative dart of the edge of dd12
        if (sm.phi2(dd12) == dd_12) {
            const e_idx = sm.dartCellIndex(dd12, .edge);
            sm.setDartCellIndex(dd_12, .edge, e_idx);
            sm.edge_dart.valuePtr(e_idx).* = dd12;
        }
    }
    {
        // Face indices.
        // if the face on the side of d is still present and is not a boundary face, update its representative dart to d1
        if (sm.phi2(d12) != d_12 and !sm.isBoundaryDart(d1)) {
            sm.face_dart.valuePtr(sm.dartCellIndex(d1, .face)).* = d1;
        }
        // if the face on the side of dd is still present and is not a boundary face, update its representative dart to dd1
        if (sm.phi2(dd12) != dd_12 and !sm.isBoundaryDart(dd1)) {
            sm.face_dart.valuePtr(sm.dartCellIndex(dd1, .face)).* = dd1;
        }
    }

    return .{ .vertex = d_12 };
}

/// Checks if the given edge can be collapsed. Edges that cannot be collapsed:
///  1 - edges whose incident triangle face has the third vertex of degree < 4
///  2 - edges whose incident vertices are both boundary vertices but the edge is not a boundary edge
///  3 - edges whose incident vertices share a common adjacent vertex other than themselves and the third vertex of incident triangle faces
/// No geometry conditions are checked here.
pub fn canCollapseEdge(sm: *const SurfaceMesh, edge: Cell) bool {
    assert(edge.cellType() == .edge);

    const d = edge.dart();
    const d12 = sm.phi2(sm.phi1(d));
    const d_1 = sm.phi_1(d);
    const d_12 = sm.phi2(d_1);
    const dd = sm.phi2(d);
    const dd12 = sm.phi2(sm.phi1(dd));
    const dd_1 = sm.phi_1(dd);
    const dd_12 = sm.phi2(dd_1);

    // condition 1: avoid creating vertices of degree 2
    if (sm.codegree(.{ .face = d }) == 3 and sm.degree(.{ .vertex = d_1 }) < 4) {
        return false;
    }
    if (sm.codegree(.{ .face = dd }) == 3 and sm.degree(.{ .vertex = dd_1 }) < 4) {
        return false;
    }

    // condition 2: avoid creating vertices of degree > 15 // TODO: seems kind of arbitrary here
    if (sm.degree(.{ .vertex = d }) + sm.degree(.{ .vertex = dd }) > 15) {
        return false;
    }

    // condition 2: avoid collapsing incident boundary vertices of a non-boundary edge
    if (!sm.isIncidentToBoundary(edge)) {
        if (sm.isIncidentToBoundary(.{ .vertex = d }) and sm.isIncidentToBoundary(.{ .vertex = dd })) {
            return false;
        }
    }

    // condition 3: avoid _pinching_ the surface
    // TODO: could implement this with a set (HashMap(u32, void))
    var buf: [64]u32 = undefined; // TODO: arbitrary limit of 64 only to avoid dynamic memory allocation here
    var adjacentVertices = std.ArrayList(u32).initBuffer(&buf);
    var d_it = sm.phi_1(d_12);
    while (d_it != dd12) : (d_it = sm.phi_1(sm.phi2(d_it))) {
        adjacentVertices.appendBounded(sm.dartCellIndex(d_it, .vertex)) catch |err| {
            std.debug.panic("Error: cannot check edge collapse condition 2 because the number of adjacent vertices exceeds {d}: {}\n", .{ buf.len, err });
        };
    }
    d_it = sm.phi_1(dd_12);
    while (d_it != d12) : (d_it = sm.phi_1(sm.phi2(d_it))) {
        if (std.mem.findScalar(u32, adjacentVertices.items, sm.dartCellIndex(d_it, .vertex)) != null) {
            return false;
        }
    }

    return true;
}

/// Cuts a face by inserting a new edge between the two given darts.
/// The new edge is returned: its representative dart is the one that belongs to the same vertex as d1.
/// The face of d1 keeps the same face index (a new face index is given to the other new face).
pub fn cutFace(sm: *SurfaceMesh, d1: Dart, d2: Dart) !Cell {
    assert(sm.codegree(.{ .face = d1 }) > 3); // only cut faces with more than 3 edges
    assert(sm.dartBelongsToCell(d2, .{ .face = d1 })); // check that d1 & d2 belong to the same face
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

    {
        // Vertex indices.
        sm.setDartCellIndex(d_1, .vertex, sm.dartCellIndex(d1, .vertex));
        sm.setDartCellIndex(d_2, .vertex, sm.dartCellIndex(d2, .vertex));
        // darts are only added to existing vertices, so their representative darts remain the same
    }
    {
        // Edge indices.
        const index = try sm.acquireCellIndex(.edge);
        sm.setDartCellIndex(d_1, .edge, index);
        sm.setDartCellIndex(d_2, .edge, index);
        sm.edge_dart.valuePtr(index).* = d_1; // set the representative dart of the new edge
    }
    {
        // Face indices.
        sm.setDartCellIndex(d_2, .face, sm.dartCellIndex(d1, .face));
        const index = try sm.acquireCellIndex(.face);
        sm.setCellIndex(.{ .face = d2 }, index);
        sm.face_dart.valuePtr(sm.dartCellIndex(d1, .face)).* = d1; // set the representative dart of the original face
        sm.face_dart.valuePtr(index).* = d2; // set the representative dart of the new face
    }

    return .{ .edge = d_1 };
}

/// Removes the given vertex by merging all its incident faces.
/// TODO: does not handle boundary vertices yet
pub fn removeVertex(sm: *SurfaceMesh, vertex: Cell) void {
    assert(vertex.cellType() == .vertex);
    const d = vertex.dart();
    const d1 = sm.phi1(d);
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |it| {
        sm.phi1Sew(it, sm.phi_1(sm.phi2(it)));
    }
    sm.removeFace(.{ .face = d });

    {
        // Vertex indices.
        // the representative dart of the vertices of the resulting face must be updated, as they may have been removed
        var face_it = sm.cellDartIterator(.{ .face = d });
        while (face_it.next()) |fd| {
            sm.vertex_dart.valuePtr(sm.dartCellIndex(fd, .vertex)).* = fd;
        }
    }
    {
        // Edge indices.
        // edges incident to the removed vertex have been entirely removed
    }
    {
        // Face indices.
        const f_idx = sm.dartCellIndex(d1, .face);
        sm.setCellIndex(.{ .face = d1 }, f_idx);
        sm.face_dart.valuePtr(f_idx).* = d1; // set the representative dart of the resulting face
    }
}
