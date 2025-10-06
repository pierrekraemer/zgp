//! A VolumeMesh is a combinatorial map representing a 3-manifold volume mesh.
//! A combinatorial map is a topological data structure based on darts and relations between them
//! (see https://en.wikipedia.org/wiki/Combinatorial_map).
//! Each cell of the mesh is a subset of darts (formally defined as orbits),
//! and each dart belongs to exactly one cell of each dimension (vertex, edge, face, volume in 3D).
//! Consequently, a cell can be represented by any of its darts
//! and a dart can be used as the representative of any of the cells it belongs to.
//!
//! In this implementation, a dart is simply represented by an integer index.
//! A DataContainer (index-based synchronized collection of arrays with empty space management)
//! is used to store the data associated to each dart:
//! - the phi1, phi_1, phi2 and phi3 relations that define the combinatorial map,
//! - the indices of the vertex, edge, face and volume cells the dart belongs to.
//! These cell indices refer to entries in other DataContainers that are used to store data
//! associated to the vertices, edges and faces of the mesh.
//! Halfedges and corners do not have their own index & DataContainers: since they are single darts,
//! their index is that of the dart, and their datas are stored in the dart DataContainer).
//!
//! TODO: talk about boundary management

const VolumeMesh = @This();

const std = @import("std");
const assert = std.debug.assert;

const zgp_log = std.log.scoped(.zgp);

const data = @import("../../utils/Data.zig");
const DataContainer = data.DataContainer;
const DataGen = data.DataGen;
const Data = data.Data;

pub const Dart = u32;
const invalid_index = std.math.maxInt(u32);

// TODO: consider what cell types to manage (i.e. 2D cells, ...)

/// A cell is a tagged union containing a dart that belongs to the cell of the current tag.
/// Convenience functions are provided to get the representing dart and the cell type.
pub const Cell = union(enum) {
    halfedge: Dart,
    corner: Dart,
    vertex: Dart,
    edge: Dart,
    face: Dart,
    volume: Dart,

    // boundary volumes are polyhedral volumes composed of boundary darts
    // this cell type is not used to manage data but only to be able to iterate over boundary volumes
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

// TODO: try to have a type for the different cell types rather than having to assert the type through the Cell active tag

allocator: std.mem.Allocator,

/// Data containers for darts & the different cell types.
dart_data: DataContainer, // also used to store corner & halfedge data
vertex_data: DataContainer,
edge_data: DataContainer,
face_data: DataContainer,
volume_data: DataContainer,

/// Dart data: connectivity, cell indices, boundary marker.
dart_phi1: *Data(Dart) = undefined,
dart_phi_1: *Data(Dart) = undefined,
dart_phi2: *Data(Dart) = undefined,
dart_phi3: *Data(Dart) = undefined,
dart_vertex_index: *Data(u32) = undefined, // index of the vertex the dart belongs to
dart_edge_index: *Data(u32) = undefined, // index of the edge the dart belongs to
dart_face_index: *Data(u32) = undefined, // index of the face the dart belongs to
dart_volume_index: *Data(u32) = undefined, // index of the volume the dart belongs to
dart_boundary_marker: *Data(bool) = undefined, // true if the dart is a boundary dart (i.e. belongs to a boundary volume)

pub fn init(allocator: std.mem.Allocator) !VolumeMesh {
    var vm: VolumeMesh = .{
        .allocator = allocator,
        .dart_data = try DataContainer.init(allocator),
        .vertex_data = try DataContainer.init(allocator),
        .edge_data = try DataContainer.init(allocator),
        .face_data = try DataContainer.init(allocator),
        .volume_data = try DataContainer.init(allocator),
    };
    vm.dart_phi1 = try vm.dart_data.addData(Dart, "phi1");
    vm.dart_phi_1 = try vm.dart_data.addData(Dart, "phi_1");
    vm.dart_phi2 = try vm.dart_data.addData(Dart, "phi2");
    vm.dart_phi3 = try vm.dart_data.addData(Dart, "phi3");
    vm.dart_vertex_index = try vm.dart_data.addData(u32, "vertex_index");
    vm.dart_edge_index = try vm.dart_data.addData(u32, "edge_index");
    vm.dart_face_index = try vm.dart_data.addData(u32, "face_index");
    vm.dart_volume_index = try vm.dart_data.addData(u32, "volume_index");
    vm.dart_boundary_marker = try vm.dart_data.getMarker();
    return vm;
}

pub fn deinit(vm: *VolumeMesh) void {
    vm.dart_data.deinit();
    vm.vertex_data.deinit();
    vm.edge_data.deinit();
    vm.face_data.deinit();
    vm.volume_data.deinit();
}

pub fn clearRetainingCapacity(vm: *VolumeMesh) void {
    vm.dart_data.clearRetainingCapacity();
    vm.vertex_data.clearRetainingCapacity();
    vm.edge_data.clearRetainingCapacity();
    vm.face_data.clearRetainingCapacity();
    vm.volume_data.clearRetainingCapacity();
}

/// DartIterator iterates over all the darts of the VolumeMesh.
/// (including boundary darts)
const DartIterator = struct {
    volume_mesh: *const VolumeMesh,
    current_dart: Dart,
    pub fn next(it: *DartIterator) ?Dart {
        if (it.current_dart == it.volume_mesh.dart_data.lastIndex()) {
            return null;
        }
        // prepare current_dart for next iteration
        defer it.current_dart = it.volume_mesh.dart_data.nextIndex(it.current_dart);
        return it.current_dart;
    }
    pub fn reset(it: *DartIterator) void {
        it.current_dart = it.volume_mesh.dart_data.firstIndex();
    }
};

pub fn dartIterator(vm: *const VolumeMesh) DartIterator {
    return .{
        .volume_mesh = vm,
        .current_dart = vm.dart_data.firstIndex(),
    };
}

/// CellDartIterator iterates over all the darts of a cell in the VolumeMesh.
/// (including the boundary darts that are part of the cell)
const CellDartIterator = struct {
    volume_mesh: *const VolumeMesh,
    cell: Cell,
    current_dart: ?Dart,
    pub fn next(it: *CellDartIterator) ?Dart {
        // prepare current_dart for next iteration
        defer {
            if (it.current_dart) |current_dart| {
                it.current_dart = switch (it.cell) {
                    .halfedge, .corner => current_dart,
                    .vertex, .edge, .face, .volume, .boundary => unreachable, // TODO: implement
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

pub fn cellDartIterator(vm: *const VolumeMesh, cell: Cell) CellDartIterator {
    return .{
        .volume_mesh = vm,
        .cell = cell,
        .current_dart = cell.dart(),
    };
}

pub fn dartBelongsToCell(vm: *const VolumeMesh, dart: Dart, cell: Cell) bool {
    var dart_it = vm.cellDartIterator(cell);
    return while (dart_it.next()) |d| {
        if (d == dart) break true;
    } else false;
}

fn firstNonBoundaryDart(vm: *const VolumeMesh) Dart {
    var first = vm.dart_data.firstIndex();
    return while (first != vm.dart_data.lastIndex()) : (first = vm.dart_data.nextIndex(first)) {
        if (!vm.dart_boundary_marker.value(first)) break first;
    } else vm.dart_data.lastIndex();
}

fn nextNonBoundaryDart(vm: *const VolumeMesh, d: Dart) Dart {
    var next = vm.dart_data.nextIndex(d);
    return while (next != vm.dart_data.lastIndex()) : (next = vm.dart_data.nextIndex(next)) {
        if (!vm.dart_boundary_marker.value(next)) break next;
    } else vm.dart_data.lastIndex();
}

fn firstBoundaryDart(vm: *const VolumeMesh) Dart {
    var first = vm.dart_data.firstIndex();
    return while (first != vm.dart_data.lastIndex()) : (first = vm.dart_data.nextIndex(first)) {
        if (vm.dart_boundary_marker.value(first)) break first;
    } else vm.dart_data.lastIndex();
}

fn nextBoundaryDart(vm: *const VolumeMesh, d: Dart) Dart {
    var next = vm.dart_data.nextIndex(d);
    return while (next != vm.dart_data.lastIndex()) : (next = vm.dart_data.nextIndex(next)) {
        if (vm.dart_boundary_marker.value(next)) break next;
    } else vm.dart_data.lastIndex();
}

/// CellIterator iterates over all the cells of the given CellType of the VolumeMesh.
/// Each iterated cell is guaranteed to be represented by a non-boundary dart of the cell.
/// When iterating over halfedges, corners or volumes, boundary halfedges, boundary corners & boundary volumes are not included.
/// This also means that boundary halfedges, boundary corners & boundary volumes have no index and thus do not carry any data.
pub fn CellIterator(comptime cell_type: CellType) type {
    return struct {
        const Self = @This();

        volume_mesh: *VolumeMesh,
        current_dart: Dart,
        marker: ?DartMarker,

        pub fn init(vm: *VolumeMesh) !Self {
            return .{
                .volume_mesh = vm,
                // no marker needed for halfedge/corner iterator (a halfedge/corner is a single dart)
                .marker = if (cell_type != .halfedge and cell_type != .corner) try DartMarker.init(vm) else null,
                .current_dart = if (cell_type == .boundary) vm.firstBoundaryDart() else vm.firstNonBoundaryDart(),
            };
        }
        pub fn deinit(self: *Self) void {
            if (self.marker) |*marker| {
                marker.deinit();
            }
        }
        pub fn next(self: *Self) ?Cell {
            if (self.current_dart == self.volume_mesh.dart_data.lastIndex()) {
                return null;
            }
            // special case for halfedge/corner iterator: a halfedge/corner is a single dart, so there is no need to mark the darts of the cell
            if (cell_type == .halfedge or cell_type == .corner) {
                // prepare current_dart for next iteration
                defer self.current_dart = self.volume_mesh.nextNonBoundaryDart(self.current_dart);
                return @unionInit(Cell, @tagName(cell_type), self.current_dart);
            }
            // other cells: mark the darts of the cell
            const cell = @unionInit(Cell, @tagName(cell_type), self.current_dart);
            var dart_it = self.volume_mesh.cellDartIterator(cell);
            while (dart_it.next()) |d| {
                self.marker.?.valuePtr(d).* = true;
            }
            // prepare current_dart for next iteration
            defer {
                while (true) : ({
                    if (self.current_dart == self.volume_mesh.dart_data.lastIndex() or !self.marker.?.value(self.current_dart))
                        break;
                }) {
                    self.current_dart = if (cell_type == .boundary) self.volume_mesh.nextBoundaryDart(self.current_dart) else self.volume_mesh.nextNonBoundaryDart(self.current_dart);
                }
            }
            return cell;
        }
        pub fn reset(self: *Self) void {
            self.current_dart = if (cell_type == .boundary) self.volume_mesh.firstBoundaryDart() else self.volume_mesh.firstNonBoundaryDart();
            if (self.marker) |*marker| {
                marker.reset();
            }
        }
    };
}

pub fn CellMarker(comptime cell_type: CellType) type {
    return struct {
        const Self = @This();

        volume_mesh: *VolumeMesh,
        marker: *Data(bool),

        pub fn init(vm: *VolumeMesh) !Self {
            return .{
                .volume_mesh = vm,
                .marker = try switch (cell_type) {
                    .halfedge, .corner => vm.dart_data.getMarker(),
                    .vertex => vm.vertex_data.getMarker(),
                    .edge => vm.edge_data.getMarker(),
                    .face => vm.face_data.getMarker(),
                    .volume => vm.volume_data.getMarker(),
                    else => unreachable,
                },
            };
        }
        pub fn deinit(self: *Self) void {
            switch (cell_type) {
                .halfedge, .corner => self.volume_mesh.dart_data.releaseMarker(self.marker),
                .vertex => self.volume_mesh.vertex_data.releaseMarker(self.marker),
                .edge => self.volume_mesh.edge_data.releaseMarker(self.marker),
                .face => self.volume_mesh.face_data.releaseMarker(self.marker),
                .volume => self.volume_mesh.volume_data.releaseMarker(self.marker),
                else => unreachable,
            }
        }

        pub fn value(self: Self, c: Cell) bool {
            assert(c.cellType() == cell_type);
            return self.marker.value(self.volume_mesh.cellIndex(c));
        }
        pub fn valuePtr(self: Self, c: Cell) *bool {
            assert(c.cellType() == cell_type);
            return self.marker.valuePtr(self.volume_mesh.cellIndex(c));
        }
        pub fn reset(self: *Self) void {
            self.marker.fill(false);
        }
    };
}

const DartMarker = struct {
    volume_mesh: *VolumeMesh,
    marker: *Data(bool),

    pub fn init(vm: *VolumeMesh) !DartMarker {
        return .{
            .volume_mesh = vm,
            .marker = try vm.dart_data.getMarker(),
        };
    }
    pub fn deinit(dm: *DartMarker) void {
        dm.volume_mesh.dart_data.releaseMarker(dm.marker);
    }

    pub fn value(dm: DartMarker, d: Dart) bool {
        return dm.marker.value(d);
    }
    pub fn valuePtr(dm: DartMarker, d: Dart) *bool {
        return dm.marker.valuePtr(d);
    }
    pub fn reset(dm: *DartMarker) void {
        dm.marker.fill(false);
    }
};

pub fn CellSet(comptime cell_type: CellType) type {
    return struct {
        const Self = @This();

        volume_mesh: *VolumeMesh,
        marker: CellMarker(cell_type),
        cells: std.ArrayList(Cell),
        indices: std.ArrayList(u32), // useful?

        pub fn init(vm: *VolumeMesh) !Self {
            return .{
                .volume_mesh = vm,
                .marker = try CellMarker(cell_type).init(vm),
                .cells = .empty,
                .indices = .empty,
            };
        }
        pub fn deinit(self: *Self) void {
            self.marker.deinit();
            self.cells.deinit(self.volume_mesh.allocator);
            self.indices.deinit(self.volume_mesh.allocator);
        }

        pub fn contains(self: *Self, c: Cell) bool {
            assert(c.cellType() == cell_type);
            return self.marker.value(c);
        }
        pub fn add(self: *Self, c: Cell) !void {
            assert(c.cellType() == cell_type);
            self.marker.valuePtr(c).* = true;
            try self.cells.append(self.volume_mesh.allocator, c);
            try self.indices.append(self.volume_mesh.allocator, self.volume_mesh.cellIndex(c));
        }
        pub fn remove(self: *Self, c: Cell) void {
            assert(c.cellType() == cell_type);
            self.marker.valuePtr(self.volume_mesh.cellIndex(c)).* = false;
            const c_index = self.volume_mesh.cellIndex(c);
            for (self.cells.indices, 0..) |index, i| {
                if (index == c_index) {
                    self.cells.swapRemove(i);
                    self.indices.swapRemove(i);
                    break;
                }
            }
        }
        pub fn clear(self: *Self) void {
            self.marker.reset();
            self.cells.clearRetainingCapacity();
            self.indices.clearRetainingCapacity();
        }
        pub fn update(self: *Self) !void {
            self.cells.clearRetainingCapacity();
            self.indices.clearRetainingCapacity();
            var it = try CellIterator(cell_type).init(self.volume_mesh);
            defer it.deinit();
            while (it.next()) |c| {
                if (self.contains(c)) {
                    try self.cells.append(self.volume_mesh.allocator, c);
                    try self.indices.append(self.volume_mesh.allocator, self.volume_mesh.cellIndex(c));
                }
            }
        }
    };
}

pub fn CellData(comptime cell_type: CellType, comptime T: type) type {
    return struct {
        const Self = @This();
        pub const CellType = cell_type;
        pub const DataType = T;

        volume_mesh: *const VolumeMesh,
        data: *Data(T),

        pub fn value(self: Self, c: Cell) T {
            assert(c.cellType() == cell_type);
            return self.data.value(self.volume_mesh.cellIndex(c));
        }
        pub fn valuePtr(self: Self, c: Cell) *T {
            assert(c.cellType() == cell_type);
            return self.data.valuePtr(self.volume_mesh.cellIndex(c));
        }
        pub fn name(self: Self) []const u8 {
            return self.data.gen.name;
        }
        pub fn gen(self: Self) *DataGen {
            return &self.data.gen;
        }
    };
}

pub fn addData(vm: *VolumeMesh, comptime cell_type: CellType, comptime T: type, name: []const u8) !CellData(cell_type, T) {
    const d = switch (cell_type) {
        .halfedge, .corner => try vm.dart_data.addData(T, name),
        .vertex => try vm.vertex_data.addData(T, name),
        .edge => try vm.edge_data.addData(T, name),
        .face => try vm.face_data.addData(T, name),
        .volume => try vm.volume_data.addData(T, name),
        else => unreachable,
    };
    return .{ .volume_mesh = vm, .data = d };
}

pub fn getData(vm: *const VolumeMesh, comptime cell_type: CellType, comptime T: type, name: []const u8) ?CellData(cell_type, T) {
    if (switch (cell_type) {
        .halfedge, .corner => vm.dart_data.getData(T, name),
        .vertex => vm.vertex_data.getData(T, name),
        .edge => vm.edge_data.getData(T, name),
        .face => vm.face_data.getData(T, name),
        .volume => vm.volume_data.getData(T, name),
        else => unreachable,
    }) |d| {
        return .{ .volume_mesh = vm, .data = d };
    }
    return null;
}

pub fn removeData(vm: *VolumeMesh, comptime cell_type: CellType, attribute_gen: *DataGen) void {
    switch (cell_type) {
        .halfedge, .corner => vm.dart_data.removeData(attribute_gen),
        .vertex => vm.vertex_data.removeData(attribute_gen),
        .edge => vm.edge_data.removeData(attribute_gen),
        .face => vm.face_data.removeData(attribute_gen),
        .volume => vm.volume_data.removeData(attribute_gen),
        else => unreachable,
    }
}

/// Creates a new index for the given cell type.
/// Only vertices, edges, faces and volumes need indices (halfedges & corners are indexed by their unique dart index).
/// The new index is not associated to any dart of the mesh.
/// This function is only intended for use in VolumeMesh creation process (import, ...) as the new index is not
/// in use until it is associated to the darts of a cell of the mesh (see setCellIndex).
pub fn newDataIndex(vm: *VolumeMesh, cell_type: CellType) !u32 {
    return switch (cell_type) {
        .vertex => vm.vertex_data.newIndex(),
        .edge => vm.edge_data.newIndex(),
        .face => vm.face_data.newIndex(),
        .volume => vm.volume_data.newIndex(),
        else => unreachable,
    };
}

fn addDart(vm: *VolumeMesh) !Dart {
    const d = try vm.dart_data.newIndex();
    vm.dart_phi1.valuePtr(d).* = d;
    vm.dart_phi_1.valuePtr(d).* = d;
    vm.dart_phi2.valuePtr(d).* = d;
    vm.dart_phi3.valuePtr(d).* = d;
    vm.dart_vertex_index.valuePtr(d).* = invalid_index;
    vm.dart_edge_index.valuePtr(d).* = invalid_index;
    vm.dart_face_index.valuePtr(d).* = invalid_index;
    vm.dart_volume_index.valuePtr(d).* = invalid_index;
    // boundary marker is false on a new index
    return d;
}

fn removeDart(vm: *VolumeMesh, d: Dart) void {
    const vertex_index = vm.dart_vertex_index.value(d);
    if (vertex_index != invalid_index) {
        vm.vertex_data.unrefIndex(vertex_index);
    }
    const edge_index = vm.dart_edge_index.value(d);
    if (edge_index != invalid_index) {
        vm.edge_data.unrefIndex(edge_index);
    }
    const face_index = vm.dart_face_index.value(d);
    if (face_index != invalid_index) {
        vm.face_data.unrefIndex(face_index);
    }
    const volume_index = vm.dart_volume_index.value(d);
    if (volume_index != invalid_index) {
        vm.volume_data.unrefIndex(volume_index);
    }
    vm.dart_data.freeIndex(d);
}

pub fn phi1(vm: *const VolumeMesh, dart: Dart) Dart {
    return vm.dart_phi1.value(dart);
}
pub fn phi_1(vm: *const VolumeMesh, dart: Dart) Dart {
    return vm.dart_phi_1.value(dart);
}
pub fn phi2(vm: *const VolumeMesh, dart: Dart) Dart {
    return vm.dart_phi2.value(dart);
}
pub fn phi3(vm: *const VolumeMesh, dart: Dart) Dart {
    return vm.dart_phi3.value(dart);
}

pub fn phi1Sew(vm: *VolumeMesh, d1: Dart, d2: Dart) void {
    assert(d1 != d2);
    const d3 = vm.phi1(d1);
    const d4 = vm.phi1(d2);
    vm.dart_phi1.valuePtr(d1).* = d4;
    vm.dart_phi1.valuePtr(d2).* = d3;
    vm.dart_phi_1.valuePtr(d4).* = d1;
    vm.dart_phi_1.valuePtr(d3).* = d2;
}

pub fn phi2Sew(vm: *VolumeMesh, d1: Dart, d2: Dart) void {
    assert(d1 != d2);
    assert(vm.phi2(d1) == d1);
    assert(vm.phi2(d2) == d2);
    vm.dart_phi2.valuePtr(d1).* = d2;
    vm.dart_phi2.valuePtr(d2).* = d1;
}

pub fn phi2Unsew(vm: *VolumeMesh, d: Dart) void {
    assert(vm.phi2(d) != d);
    const d2 = vm.phi2(d);
    vm.dart_phi2.valuePtr(d).* = d;
    vm.dart_phi2.valuePtr(d2).* = d2;
}

pub fn phi3Sew(vm: *VolumeMesh, d1: Dart, d2: Dart) void {
    assert(d1 != d2);
    assert(vm.phi3(d1) == d1);
    assert(vm.phi3(d2) == d2);
    vm.dart_phi3.valuePtr(d1).* = d2;
    vm.dart_phi3.valuePtr(d2).* = d1;
}

pub fn phi3Unsew(vm: *VolumeMesh, d: Dart) void {
    assert(vm.phi3(d) != d);
    const d3 = vm.phi3(d);
    vm.dart_phi3.valuePtr(d).* = d;
    vm.dart_phi3.valuePtr(d3).* = d3;
}

pub fn isBoundaryDart(vm: *const VolumeMesh, d: Dart) bool {
    return vm.dart_boundary_marker.value(d);
}

pub fn isValidDart(vm: *const VolumeMesh, d: Dart) bool {
    return vm.dart_data.isActiveIndex(d);
}

pub fn isIncidentToBoundary(vm: *const VolumeMesh, cell: Cell) bool {
    return switch (cell.cellType()) {
        .vertex, .edge, .face => blk: {
            var dart_it = vm.cellDartIterator(cell);
            while (dart_it.next()) |d| {
                if (vm.isBoundaryDart(d)) {
                    break :blk true;
                }
            }
            break :blk false;
        },
        else => unreachable,
    };
}

/// Sets the index of the cell of type cell_type the dart d belongs to.
/// Reference counts of old and new indices are updated accordingly (see DataContainer.refIndex & unrefIndex).
/// Should only be called for vertex, edge, face and volume cell types (halfedges & corners are indexed by their unique dart index).
pub fn setDartCellIndex(vm: *VolumeMesh, d: Dart, cell_type: CellType, index: u32) void {
    var index_data = switch (cell_type) {
        .vertex => vm.dart_vertex_index,
        .edge => vm.dart_edge_index,
        .face => vm.dart_face_index,
        .volume => vm.dart_volume_index,
        else => unreachable,
    };
    var data_container = switch (cell_type) {
        .vertex => &vm.vertex_data,
        .edge => &vm.edge_data,
        .face => &vm.face_data,
        .volume => &vm.volume_data,
        else => unreachable,
    };
    const old_index: u32 = index_data.value(d);
    if (index != invalid_index) {
        data_container.refIndex(index);
    }
    if (old_index != invalid_index) {
        data_container.unrefIndex(old_index);
    }
    index_data.valuePtr(d).* = index;
}

pub fn dartCellIndex(vm: *const VolumeMesh, d: Dart, cell_type: CellType) u32 {
    switch (cell_type) {
        .halfedge, .corner => return d,
        .vertex => return vm.dart_vertex_index.value(d),
        .edge => return vm.dart_edge_index.value(d),
        .face => return vm.dart_face_index.value(d),
        .volume => return vm.dart_volume_index.value(d),
        else => unreachable,
    }
}

/// Sets the index of all the darts of the given cell c to the given index.
/// Should only be called for vertices, edges, faces and volumes (halfedges & corners are indexed by their unique dart index).
fn setCellIndex(vm: *VolumeMesh, c: Cell, index: u32) void {
    switch (c) {
        .vertex, .edge, .face, .volume => {
            var dart_it = vm.cellDartIterator(c);
            while (dart_it.next()) |d| {
                vm.setDartCellIndex(d, c.cellType(), index);
            }
        },
        else => unreachable,
    }
}

pub fn cellIndex(vm: *const VolumeMesh, c: Cell) u32 {
    return vm.dartCellIndex(c.dart(), c.cellType());
}

pub fn indexCells(vm: *VolumeMesh, comptime cell_type: CellType) !void {
    assert(cell_type == .vertex or cell_type == .edge or cell_type == .face or cell_type == .volume);
    var it = try CellIterator(cell_type).init(vm);
    defer it.deinit();
    while (it.next()) |cell| {
        if (vm.cellIndex(cell) == invalid_index) {
            const index = try vm.newDataIndex(cell_type);
            vm.setCellIndex(cell, index);
        }
    }
}

pub fn checkIntegrity(vm: *VolumeMesh) !bool {
    var ok = true;
    var d_it = vm.dartIterator();
    while (d_it.next()) |d| {
        const d3 = vm.phi3(d);
        if (d3 == d) {
            zgp_log.warn("Dart {d} is phi3-linked to itself", .{d});
            ok = false;
        }
        if (vm.phi2(d3) != d) {
            zgp_log.warn("Inconsistent phi3: phi3(phi3({d}) != {d}", .{ d, d });
            ok = false;
        }
        const d2 = vm.phi2(d);
        if (d2 == d) {
            zgp_log.warn("Dart {d} is phi2-linked to itself", .{d});
            ok = false;
        }
        if (vm.phi2(d2) != d) {
            zgp_log.warn("Inconsistent phi2: phi2(phi2({d}) != {d}", .{ d, d });
            ok = false;
        }
        // TODO: also check phi3(phi1(d)) is an involution
        const d1 = vm.phi1(d);
        if (vm.phi_1(d1) != d) {
            zgp_log.warn("Inconsistent phi_1: phi_1(phi1({d}) != {d}", .{ d, d });
            ok = false;
        }
        const d_1 = vm.phi_1(d);
        if (vm.phi1(d_1) != d) {
            zgp_log.warn("Inconsistent phi1: phi1(phi_1({d}) != {d}", .{ d, d });
            ok = false;
        }
        if (vm.isBoundaryDart(d)) {
            if (!vm.isBoundaryDart(d1)) {
                zgp_log.warn("Inconsistent boundary volume marking: {d} and {d}", .{ d, d1 });
                ok = false;
            }
            if (!vm.isBoundaryDart(d2)) {
                zgp_log.warn("Inconsistent boundary volume marking: {d} and {d}", .{ d, d2 });
                ok = false;
            }
            if (vm.isBoundaryDart(d3)) {
                zgp_log.warn("Adjacent boundary volumes: {d} and {d}", .{ d, d3 });
                ok = false;
            }
        }
        inline for (.{ .vertex, .edge, .face, .volume }) |cell_type| {
            if (vm.isBoundaryDart(d) and (cell_type == .volume)) {
                // boundary volumes are not indexed
            } else {
                const index = vm.dartCellIndex(d, cell_type);
                if (index == invalid_index) {
                    zgp_log.warn("Dart {d} has invalid {s} index", .{ d, @tagName(cell_type) });
                    ok = false;
                }
            }
        }
    }

    inline for (.{ .vertex, .edge, .face, .volume }) |cell_type| {
        const index_count = try vm.addData(cell_type, u32, "index_count");
        defer vm.removeData(cell_type, index_count.gen());
        index_count.data.fill(0);

        const cell_darts_count = try vm.addData(cell_type, u32, "cell_darts_count");
        defer vm.removeData(cell_type, cell_darts_count.gen());
        cell_darts_count.data.fill(0);

        var cell_it = try CellIterator(cell_type).init(vm);
        defer cell_it.deinit();
        while (cell_it.next()) |cell| {
            index_count.valuePtr(cell).* += 1;
            const idx = vm.cellIndex(cell);
            if (idx == invalid_index) {
                zgp_log.warn("{s} of dart {d} has invalid index", .{ @tagName(cell_type), cell.dart() });
                ok = false;
            }
            const c = cell_darts_count.valuePtr(cell);
            var cell_darts_it = vm.cellDartIterator(cell);
            while (cell_darts_it.next()) |d| {
                const d_idx = vm.dartCellIndex(d, cell_type);
                if (d_idx != idx) {
                    zgp_log.warn("Inconsistent {s} index for dart {d}: {d} != {d}", .{ @tagName(cell_type), d, d_idx, idx });
                    ok = false;
                }
                c.* += 1;
            }
            switch (cell_type) {
                .vertex => {
                    if (c.* < 2) {
                        zgp_log.warn("Inconsistent vertex darts count for vertex {d}: {d} < 2", .{ cell.dart(), c.* });
                        ok = false;
                    }
                },
                .edge => {
                    if (c.* != 2) {
                        zgp_log.warn("Inconsistent edge darts count for edge {d}: {d} != 2", .{ cell.dart(), c.* });
                        ok = false;
                    }
                },
                .face => {
                    if (c.* < 3) {
                        zgp_log.warn("Inconsistent face darts count for face {d}: {d} < 3", .{ cell.dart(), c.* });
                        ok = false;
                    }
                },
                else => unreachable,
            }
        }
        var data_container = switch (cell_type) {
            .vertex => &vm.vertex_data,
            .edge => &vm.edge_data,
            .face => &vm.face_data,
            else => unreachable,
        };
        var idx = data_container.firstIndex();
        while (idx != data_container.lastIndex()) : (idx = data_container.nextIndex(idx)) {
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

/// Returns the number of cells of the given CellType in the given VolumeMesh.
pub fn nbCells(vm: *const VolumeMesh, cell_type: CellType) u32 {
    return switch (cell_type) {
        .halfedge, .corner => vm.dart_data.nbElements(), // TODO: should exclude boundary darts from the count
        .vertex => vm.vertex_data.nbElements(),
        .edge => vm.edge_data.nbElements(),
        .face => vm.face_data.nbElements(),
        .volume => vm.volume_data.nbElements(),
        // TODO: count boundary volumes
        else => unreachable,
    };
}

/// Returns the degree of the given cell (number of d+1 incident cells).
/// Only vertices, edges and faces have a degree (volumes are top-cells and do not have a degree).
pub fn degree(vm: *const VolumeMesh, cell: Cell) u32 {
    return switch (cell.cellType()) {
        .vertex => unreachable, // TODO: implement
        // nb refs is equal to the number of darts of the edge which is equal to the double of its degree
        // (more efficient than iterating through the darts of the edge)
        .edge => vm.edge_data.nb_refs.value(vm.cellIndex(cell)) / 2,
        .face => if (vm.isBoundaryDart(cell.dart()) or vm.isBoundaryDart(vm.phi3(cell.dart()))) 1 else 2,
        else => unreachable,
    };
}

/// Returns the codegree of the given cell (number of d-1 incident cells).
/// Only edges, faces and volumes have a codegree (vertices are 0-cells and do not have a codegree).
pub fn codegree(vm: *const VolumeMesh, cell: Cell) u32 {
    return switch (cell.cellType()) {
        .edge => 2,
        // nb refs is equal to the number of darts of the face which is equal to the double of its codegree
        // (more efficient than iterating through the darts of the face)
        .face => vm.face_data.nb_refs.value(vm.cellIndex(cell)) / 2,
        .volume => unreachable, // TODO: implement
        else => unreachable,
    };
}

/// Closes the given VolumeMesh by adding boundary volumes where needed.
/// TODO: implement
pub fn close(_: *VolumeMesh) !u32 {
    const nb_boundary_volumes: u32 = 0;
    return nb_boundary_volumes;
}
