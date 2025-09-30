//! A SurfaceMesh is a combinatorial map representing a 2-manifold surface mesh.
//! A combinatorial map is a topological data structure based on darts and relations between them
//! (see https://en.wikipedia.org/wiki/Combinatorial_map).
//! Each cell of the mesh is a subset of darts (formally defined as orbits),
//! and each dart belongs to exactly one cell of each dimension (vertex, edge, face in 2D).
//! Consequently, a cell can be represented by any of its darts
//! and a dart can be interpreted as the representative of any of the cells it belongs to.
//!
//! In this implementation, a dart is simply represented by an integer index.
//! A DataContainer (index-based synchronized collection of arrays with empty space management)
//! is used to store the data associated to each dart:
//! - the phi1, phi_1 and phi2 relations that define the combinatorial map,
//! - the indices of the corner, vertex, edge and face cells the dart belongs to,
//! These cell indices refer to entries in other DataContainers that are used to store data
//! associated to halfedges, corners, vertices, edges and faces.
//!
//! TODO: talk about boundary management

const SurfaceMesh = @This();

const std = @import("std");
const assert = std.debug.assert;

const zgp_log = std.log.scoped(.zgp);

const data = @import("../../utils/Data.zig");
const DataContainer = data.DataContainer;
const DataGen = data.DataGen;
const Data = data.Data;

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

// TODO: try to have a type for the different cell types rather than having to assert the type through the Cell active tag

const invalid_index = std.math.maxInt(u32);

allocator: std.mem.Allocator,

/// Data containers for darts & the different cell types.
dart_data: DataContainer, // also used to store corner & halfedge data
vertex_data: DataContainer,
edge_data: DataContainer,
face_data: DataContainer,

/// Dart data: connectivity, cell indices, boundary marker.
dart_phi1: *Data(Dart) = undefined,
dart_phi_1: *Data(Dart) = undefined,
dart_phi2: *Data(Dart) = undefined,
dart_vertex_index: *Data(u32) = undefined, // index of the vertex the dart belongs to
dart_edge_index: *Data(u32) = undefined, // index of the edge the dart belongs to
dart_face_index: *Data(u32) = undefined, // index of the face the dart belongs to
dart_boundary_marker: *Data(bool) = undefined, // true if the dart is a boundary dart (i.e. belongs to a boundary face)

pub fn init(allocator: std.mem.Allocator) !SurfaceMesh {
    var sm: SurfaceMesh = .{
        .allocator = allocator,
        .dart_data = try DataContainer.init(allocator),
        .vertex_data = try DataContainer.init(allocator),
        .edge_data = try DataContainer.init(allocator),
        .face_data = try DataContainer.init(allocator),
    };
    sm.dart_phi1 = try sm.dart_data.addData(Dart, "phi1");
    sm.dart_phi_1 = try sm.dart_data.addData(Dart, "phi_1");
    sm.dart_phi2 = try sm.dart_data.addData(Dart, "phi2");
    sm.dart_vertex_index = try sm.dart_data.addData(u32, "vertex_index");
    sm.dart_edge_index = try sm.dart_data.addData(u32, "edge_index");
    sm.dart_face_index = try sm.dart_data.addData(u32, "face_index");
    sm.dart_boundary_marker = try sm.dart_data.getMarker();
    return sm;
}

pub fn deinit(sm: *SurfaceMesh) void {
    sm.dart_data.deinit();
    sm.vertex_data.deinit();
    sm.edge_data.deinit();
    sm.face_data.deinit();
}

pub fn clearRetainingCapacity(sm: *SurfaceMesh) void {
    sm.dart_data.clearRetainingCapacity();
    sm.vertex_data.clearRetainingCapacity();
    sm.edge_data.clearRetainingCapacity();
    sm.face_data.clearRetainingCapacity();
}

/// DartIterator iterates over all the darts of the SurfaceMesh.
/// (including boundary darts)
const DartIterator = struct {
    surface_mesh: *const SurfaceMesh,
    current_dart: Dart,
    pub fn next(it: *DartIterator) ?Dart {
        if (it.current_dart == it.surface_mesh.dart_data.lastIndex()) {
            return null;
        }
        // prepare current_dart for next iteration
        defer it.current_dart = it.surface_mesh.dart_data.nextIndex(it.current_dart);
        return it.current_dart;
    }
    pub fn reset(it: *DartIterator) void {
        it.current_dart = it.surface_mesh.dart_data.firstIndex();
    }
};

pub fn dartIterator(sm: *const SurfaceMesh) DartIterator {
    return .{
        .surface_mesh = sm,
        .current_dart = sm.dart_data.firstIndex(),
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

pub fn cellDartIterator(sm: *const SurfaceMesh, cell: Cell) CellDartIterator {
    return .{
        .surface_mesh = sm,
        .cell = cell,
        .current_dart = cell.dart(),
    };
}

pub fn dartBelongsToCell(sm: *const SurfaceMesh, dart: Dart, cell: Cell) bool {
    var dart_it = sm.cellDartIterator(cell);
    return while (dart_it.next()) |d| {
        if (d == dart) break true;
    } else false;
}

fn firstNonBoundaryDart(sm: *const SurfaceMesh) Dart {
    var first = sm.dart_data.firstIndex();
    return while (first != sm.dart_data.lastIndex()) : (first = sm.dart_data.nextIndex(first)) {
        if (!sm.dart_boundary_marker.value(first)) break first;
    } else sm.dart_data.lastIndex();
}

fn nextNonBoundaryDart(sm: *const SurfaceMesh, d: Dart) Dart {
    var next = sm.dart_data.nextIndex(d);
    return while (next != sm.dart_data.lastIndex()) : (next = sm.dart_data.nextIndex(next)) {
        if (!sm.dart_boundary_marker.value(next)) break next;
    } else sm.dart_data.lastIndex();
}

fn firstBoundaryDart(sm: *const SurfaceMesh) Dart {
    var first = sm.dart_data.firstIndex();
    return while (first != sm.dart_data.lastIndex()) : (first = sm.dart_data.nextIndex(first)) {
        if (sm.dart_boundary_marker.value(first)) break first;
    } else sm.dart_data.lastIndex();
}

fn nextBoundaryDart(sm: *const SurfaceMesh, d: Dart) Dart {
    var next = sm.dart_data.nextIndex(d);
    return while (next != sm.dart_data.lastIndex()) : (next = sm.dart_data.nextIndex(next)) {
        if (sm.dart_boundary_marker.value(next)) break next;
    } else sm.dart_data.lastIndex();
}

/// CellIterator iterates over all the cells of the given CellType of the SurfaceMesh.
/// Each iterated cell is guaranteed to be represented by a non-boundary dart of the cell.
/// When iterating over halfedges, corners or faces, boundary halfedges, boundary corners & boundary faces are not included.
/// This also means that boundary halfedges, boundary corners & boundary faces have no index and thus do not carry any data.
pub fn CellIterator(comptime cell_type: CellType) type {
    return struct {
        const Self = @This();

        surface_mesh: *SurfaceMesh,
        current_dart: Dart,
        marker: ?DartMarker,

        pub fn init(sm: *SurfaceMesh) !Self {
            return .{
                .surface_mesh = sm,
                // no marker needed for halfedge/corner iterator (a halfedge/corner is a single dart)
                .marker = if (cell_type != .halfedge and cell_type != .corner) try DartMarker.init(sm) else null,
                .current_dart = if (cell_type == .boundary) sm.firstBoundaryDart() else sm.firstNonBoundaryDart(),
            };
        }
        pub fn deinit(self: *Self) void {
            if (self.marker) |*marker| {
                marker.deinit();
            }
        }
        pub fn next(self: *Self) ?Cell {
            if (self.current_dart == self.surface_mesh.dart_data.lastIndex()) {
                return null;
            }
            // special case for halfedge/corner iterator: a halfedge/corner is a single dart, so there is no need to mark the darts of the cell
            if (cell_type == .halfedge or cell_type == .corner) {
                // prepare current_dart for next iteration
                defer self.current_dart = self.surface_mesh.nextNonBoundaryDart(self.current_dart);
                return @unionInit(Cell, @tagName(cell_type), self.current_dart);
            }
            // other cells: mark the darts of the cell
            const cell = @unionInit(Cell, @tagName(cell_type), self.current_dart);
            var dart_it = self.surface_mesh.cellDartIterator(cell);
            while (dart_it.next()) |d| {
                self.marker.?.valuePtr(d).* = true;
            }
            // prepare current_dart for next iteration
            defer {
                while (true) : ({
                    if (self.current_dart == self.surface_mesh.dart_data.lastIndex() or !self.marker.?.value(self.current_dart))
                        break;
                }) {
                    self.current_dart = if (cell_type == .boundary) self.surface_mesh.nextBoundaryDart(self.current_dart) else self.surface_mesh.nextNonBoundaryDart(self.current_dart);
                }
            }
            return cell;
        }
        pub fn reset(self: *Self) void {
            self.current_dart = if (cell_type == .boundary) self.surface_mesh.firstBoundaryDart() else self.surface_mesh.firstNonBoundaryDart();
            if (self.marker) |*marker| {
                marker.reset();
            }
        }
    };
}

pub fn CellMarker(comptime cell_type: CellType) type {
    return struct {
        const Self = @This();

        surface_mesh: *SurfaceMesh,
        marker: *Data(bool),

        pub fn init(sm: *SurfaceMesh) !Self {
            return .{
                .surface_mesh = sm,
                .marker = try switch (cell_type) {
                    .halfedge, .corner => sm.dart_data.getMarker(),
                    .vertex => sm.vertex_data.getMarker(),
                    .edge => sm.edge_data.getMarker(),
                    .face => sm.face_data.getMarker(),
                    else => unreachable,
                },
            };
        }
        pub fn deinit(self: *Self) void {
            switch (cell_type) {
                .halfedge, .corner => self.surface_mesh.dart_data.releaseMarker(self.marker),
                .vertex => self.surface_mesh.vertex_data.releaseMarker(self.marker),
                .edge => self.surface_mesh.edge_data.releaseMarker(self.marker),
                .face => self.surface_mesh.face_data.releaseMarker(self.marker),
                else => unreachable,
            }
        }

        pub fn value(self: Self, c: Cell) bool {
            assert(c.cellType() == cell_type);
            return self.marker.value(self.surface_mesh.cellIndex(c));
        }
        pub fn valuePtr(self: Self, c: Cell) *bool {
            assert(c.cellType() == cell_type);
            return self.marker.valuePtr(self.surface_mesh.cellIndex(c));
        }
        pub fn reset(self: *Self) void {
            self.marker.fill(false);
        }
    };
}

const DartMarker = struct {
    surface_mesh: *SurfaceMesh,
    marker: *Data(bool),

    pub fn init(sm: *SurfaceMesh) !DartMarker {
        return .{
            .surface_mesh = sm,
            .marker = try sm.dart_data.getMarker(),
        };
    }
    pub fn deinit(dm: *DartMarker) void {
        dm.surface_mesh.dart_data.releaseMarker(dm.marker);
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

        surface_mesh: *SurfaceMesh,
        marker: CellMarker(cell_type),
        cells: std.ArrayList(Cell),
        indices: std.ArrayList(u32), // useful?

        pub fn init(sm: *SurfaceMesh) !Self {
            return .{
                .surface_mesh = sm,
                .marker = try CellMarker(cell_type).init(sm),
                .cells = .empty,
                .indices = .empty,
            };
        }
        pub fn deinit(self: *Self) void {
            self.marker.deinit();
            self.cells.deinit(self.surface_mesh.allocator);
            self.indices.deinit(self.surface_mesh.allocator);
        }

        pub fn contains(self: *Self, c: Cell) bool {
            assert(c.cellType() == cell_type);
            return self.marker.value(c);
        }
        pub fn add(self: *Self, c: Cell) !void {
            assert(c.cellType() == cell_type);
            self.marker.valuePtr(c).* = true;
            try self.cells.append(self.surface_mesh.allocator, c);
            try self.indices.append(self.surface_mesh.allocator, self.surface_mesh.cellIndex(c));
        }
        pub fn remove(self: *Self, c: Cell) void {
            assert(c.cellType() == cell_type);
            self.marker.valuePtr(self.surface_mesh.cellIndex(c)).* = false;
            const c_index = self.surface_mesh.cellIndex(c);
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
            var it = try CellIterator(cell_type).init(self.surface_mesh);
            defer it.deinit();
            while (it.next()) |c| {
                if (self.contains(c)) {
                    try self.cells.append(self.surface_mesh.allocator, c);
                    try self.indices.append(self.surface_mesh.allocator, self.surface_mesh.cellIndex(c));
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

        surface_mesh: *const SurfaceMesh,
        data: *Data(T),

        pub fn value(self: Self, c: Cell) T {
            assert(c.cellType() == cell_type);
            return self.data.value(self.surface_mesh.cellIndex(c));
        }
        pub fn valuePtr(self: Self, c: Cell) *T {
            assert(c.cellType() == cell_type);
            return self.data.valuePtr(self.surface_mesh.cellIndex(c));
        }
        pub fn name(self: Self) []const u8 {
            return self.data.gen.name;
        }
        pub fn gen(self: Self) *DataGen {
            return &self.data.gen;
        }
    };
}

pub fn addData(sm: *SurfaceMesh, comptime cell_type: CellType, comptime T: type, name: []const u8) !CellData(cell_type, T) {
    const d = switch (cell_type) {
        .halfedge, .corner => try sm.dart_data.addData(T, name),
        .vertex => try sm.vertex_data.addData(T, name),
        .edge => try sm.edge_data.addData(T, name),
        .face => try sm.face_data.addData(T, name),
        else => unreachable,
    };
    return .{ .surface_mesh = sm, .data = d };
}

pub fn getData(sm: *const SurfaceMesh, comptime cell_type: CellType, comptime T: type, name: []const u8) ?CellData(cell_type, T) {
    if (switch (cell_type) {
        .halfedge, .corner => sm.dart_data.getData(T, name),
        .vertex => sm.vertex_data.getData(T, name),
        .edge => sm.edge_data.getData(T, name),
        .face => sm.face_data.getData(T, name),
        else => unreachable,
    }) |d| {
        return .{ .surface_mesh = sm, .data = d };
    }
    return null;
}

pub fn removeData(sm: *SurfaceMesh, comptime cell_type: CellType, attribute_gen: *DataGen) void {
    switch (cell_type) {
        .halfedge, .corner => sm.dart_data.removeData(attribute_gen),
        .vertex => sm.vertex_data.removeData(attribute_gen),
        .edge => sm.edge_data.removeData(attribute_gen),
        .face => sm.face_data.removeData(attribute_gen),
        else => unreachable,
    }
}

/// Creates a new index for the given cell type.
/// Only vertices, edges and faces need indices (halfedges & corners are indexed by their unique dart index).
/// The new index is not associated to any dart of the mesh.
/// This function is only intended for use in SurfaceMesh creation process (import, ...) as the new index is not
/// in use until it is associated to the darts of a cell of the mesh (see setCellIndex).
pub fn newDataIndex(sm: *SurfaceMesh, cell_type: CellType) !u32 {
    return switch (cell_type) {
        .vertex => sm.vertex_data.newIndex(),
        .edge => sm.edge_data.newIndex(),
        .face => sm.face_data.newIndex(),
        else => unreachable,
    };
}

fn addDart(sm: *SurfaceMesh) !Dart {
    const d = try sm.dart_data.newIndex();
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
    sm.dart_data.freeIndex(d);
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
    assert(sm.phi2(d) != d);
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
pub fn setDartCellIndex(sm: *SurfaceMesh, d: Dart, cell_type: CellType, index: u32) void {
    var index_data = switch (cell_type) {
        .vertex => sm.dart_vertex_index,
        .edge => sm.dart_edge_index,
        .face => sm.dart_face_index,
        else => unreachable,
    };
    var data_container = switch (cell_type) {
        .vertex => &sm.vertex_data,
        .edge => &sm.edge_data,
        .face => &sm.face_data,
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
        .edge => {
            const d = c.dart();
            sm.setDartCellIndex(d, .edge, index);
            sm.setDartCellIndex(sm.phi2(d), .edge, index);
        },
        .vertex, .face => {
            var dart_it = sm.cellDartIterator(c);
            while (dart_it.next()) |d| {
                sm.setDartCellIndex(d, c.cellType(), index);
            }
        },
        else => unreachable,
    }
}

pub fn cellIndex(sm: *const SurfaceMesh, c: Cell) u32 {
    return sm.dartCellIndex(c.dart(), c.cellType());
}

pub fn indexCells(sm: *SurfaceMesh, comptime cell_type: CellType) !void {
    assert(cell_type == .vertex or cell_type == .edge or cell_type == .face);
    var it = try CellIterator(cell_type).init(sm);
    defer it.deinit();
    while (it.next()) |cell| {
        if (sm.cellIndex(cell) == invalid_index) {
            const index = try sm.newDataIndex(cell_type);
            sm.setCellIndex(cell, index);
        }
    }
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
        inline for (.{ .vertex, .edge, .face }) |cell_type| {
            if (sm.isBoundaryDart(d) and (cell_type == .face)) {
                // boundary faces are not indexed
            } else {
                const index = sm.dartCellIndex(d, cell_type);
                if (index == invalid_index) {
                    zgp_log.warn("Dart {d} has invalid {s} index", .{ d, @tagName(cell_type) });
                    ok = false;
                }
            }
        }
    }

    inline for (.{ .vertex, .edge, .face }) |cell_type| {
        const index_count = try sm.addData(cell_type, u32, "index_count");
        defer sm.removeData(cell_type, index_count.gen());
        index_count.data.fill(0);

        const cell_darts_count = try sm.addData(cell_type, u32, "cell_darts_count");
        defer sm.removeData(cell_type, cell_darts_count.gen());
        cell_darts_count.data.fill(0);

        var cell_it = try CellIterator(cell_type).init(sm);
        defer cell_it.deinit();
        while (cell_it.next()) |cell| {
            index_count.valuePtr(cell).* += 1;
            const idx = sm.cellIndex(cell);
            if (idx == invalid_index) {
                zgp_log.warn("{s} of dart {d} has invalid index", .{ @tagName(cell_type), cell.dart() });
                ok = false;
            }
            const c = cell_darts_count.valuePtr(cell);
            var cell_darts_it = sm.cellDartIterator(cell);
            while (cell_darts_it.next()) |d| {
                const d_idx = sm.dartCellIndex(d, cell_type);
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
            .vertex => &sm.vertex_data,
            .edge => &sm.edge_data,
            .face => &sm.face_data,
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

/// Returns the number of cells of the given CellType in the given SurfaceMesh.
pub fn nbCells(sm: *const SurfaceMesh, cell_type: CellType) u32 {
    return switch (cell_type) {
        .halfedge, .corner => sm.dart_data.nbElements(), // TODO: should exclude boundary darts from the count
        .vertex => sm.vertex_data.nbElements(),
        .edge => sm.edge_data.nbElements(),
        .face => sm.face_data.nbElements(),
        // TODO: count boundary faces
        else => unreachable,
    };
}

/// Returns the degree of the given cell (number of d+1 incident cells).
/// Only vertices and edges have a degree (faces are top-cells and do not have a degree).
pub fn degree(sm: *const SurfaceMesh, cell: Cell) u32 {
    return switch (cell.cellType()) {
        // nb refs is equal to the number of darts of the vertex which is equal to its degree
        // (more efficient than iterating through the darts of the vertex)
        .vertex => sm.vertex_data.nb_refs.value(sm.cellIndex(cell)),
        .edge => if (sm.isBoundaryDart(cell.dart()) or sm.isBoundaryDart(sm.phi2(cell.dart()))) 1 else 2,
        else => unreachable,
    };
}

/// Returns the codegree of the given cell (number of d-1 incident cells).
/// Only edges and faces have a codegree (vertices are 0-cells and do not have a codegree).
pub fn codegree(sm: *const SurfaceMesh, cell: Cell) u32 {
    return switch (cell.cellType()) {
        .edge => 2,
        // nb refs is equal to the number of darts of the face which is equal to its codegree
        // (more efficient than iterating through the darts of the face)
        .face => blk: {
            // boundary faces are not indexed and thus do not have an associated index with a ref count
            if (sm.isBoundaryDart(cell.dart())) {
                var res: u32 = 0;
                var dart_it = sm.cellDartIterator(cell);
                while (dart_it.next()) |_| : (res += 1) {}
                break :blk res;
            } else break :blk sm.face_data.nb_refs.value(sm.cellIndex(cell));
        },
        else => unreachable,
    };
}

/// Creates a new face with the given number of vertices.
/// Unbounded means that the face is not linked to any boundary "outer" face (all its darts are phi2-linked to themselves).
/// None of the face darts are associated to halfedge/corner/vertex/edge/face indices and the face is not closed by a boundary face.
/// This function is only intended for use in SurfaceMesh creation process (import, ...) as the SurfaceMesh is not
/// valid after this function is called.
pub fn addUnboundedFace(sm: *SurfaceMesh, nb_vertices: u32) !Cell {
    const d1 = try sm.addDart();
    for (1..nb_vertices) |_| {
        const d2 = try sm.addDart();
        sm.phi1Sew(d1, d2);
    }
    var it = d1;
    while (true) {
        it = sm.phi1(it);
        if (it == d1) {
            break;
        }
    }
    return .{ .face = d1 };
}

/// Closes the given SurfaceMesh by adding boundary faces where needed.
/// Open edges (darts phi2-linked to themselves) are detected and boundary faces
/// are created by following the open boundary cycles.
/// This function is meant to be called after a construction process of a SurfaceMesh
/// such as importing from files (see ModelsRegistry.loadSurfaceMeshFromFile)
pub fn close(sm: *SurfaceMesh) !u32 {
    var nb_boundary_faces: u32 = 0;
    var dart_it = sm.dartIterator();
    while (dart_it.next()) |d| {
        if (sm.phi2(d) == d) {
            const b_first = try sm.addDart();
            sm.dart_boundary_marker.valuePtr(b_first).* = true;
            sm.phi2Sew(d, b_first);
            sm.setDartCellIndex(b_first, .vertex, sm.dartCellIndex(sm.phi1(d), .vertex));
            sm.setDartCellIndex(b_first, .edge, sm.dartCellIndex(d, .edge));
            // boundary darts do not represent a valid face, thus they do not have a face index

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
                sm.dart_boundary_marker.valuePtr(b_next).* = true;
                sm.phi2Sew(d_current, b_next);
                sm.phi1Sew(b_first, b_next);
                sm.setDartCellIndex(b_next, .vertex, sm.dartCellIndex(sm.phi1(d_current), .vertex));
                sm.setDartCellIndex(b_next, .edge, sm.dartCellIndex(d_current, .edge));
                // boundary darts do not represent a valid face, thus they do not have a face index
            }

            nb_boundary_faces += 1;
        }
    }
    return nb_boundary_faces;
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
        const index = try sm.newDataIndex(.vertex);
        sm.setDartCellIndex(d1, .vertex, index);
        sm.setDartCellIndex(dd1, .vertex, index);
    }
    {
        // Edge indices.
        // The edge of d keeps the index of the original edge.
        sm.setDartCellIndex(dd1, .edge, sm.dartCellIndex(d, .edge));
        // The edge of dd gets a new index.
        const index = try sm.newDataIndex(.edge);
        sm.setDartCellIndex(dd, .edge, index);
        sm.setDartCellIndex(d1, .edge, index);
    }
    {
        // Face indices.
        sm.setDartCellIndex(d1, .face, sm.dartCellIndex(d, .face));
        sm.setDartCellIndex(dd1, .face, sm.dartCellIndex(dd, .face));
    }

    return .{ .vertex = d1 };
}

/// Flips the given edge.
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
    }
    {
        // Edge indices.
        // no new edges are created & no existing edges are modified
    }
    {
        // Face indices.
        sm.setDartCellIndex(sm.phi_1(d), .face, sm.dartCellIndex(d, .face));
        sm.setDartCellIndex(sm.phi_1(dd), .face, sm.dartCellIndex(dd, .face));
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

/// Collapses the given edge.
/// Should only be called after a call to `canCollapseEdge`.
/// TODO: write a more detailed comment
pub fn collapseEdge(sm: *SurfaceMesh, edge: Cell) Cell {
    assert(edge.cellType() == .edge);

    const d = edge.dart();
    const d1 = sm.phi1(d);
    const d_1 = sm.phi_1(d);
    const d_12 = sm.phi2(d_1);
    const dd = sm.phi2(d);
    const dd1 = sm.phi1(dd);
    const dd_1 = sm.phi_1(dd);
    const dd_12 = sm.phi2(dd_1);

    sm.phi1Sew(d_1, d);
    sm.removeDart(d);
    sm.phi1Sew(dd_1, dd);
    sm.removeDart(dd);

    // remove a potential 2-sided face on the side of d
    if (sm.phi1(d1) == d_1) {
        const d12 = sm.phi2(d1);
        sm.phi2Unsew(d1);
        sm.phi2Unsew(d_1);
        sm.phi2Sew(d_12, d12);
        sm.removeDart(d1);
        sm.removeDart(d_1);
    }
    // remove a potential 2-sided face on the side of dd
    if (sm.phi1(dd1) == dd_1) {
        const dd12 = sm.phi2(dd1);
        sm.phi2Unsew(dd1);
        sm.phi2Unsew(dd_1);
        sm.phi2Sew(dd_12, dd12);
        sm.removeDart(dd1);
        sm.removeDart(dd_1);
    }

    {
        // Vertex indices.
        // use the index of the vertex of d for the resulting vertex
        sm.setCellIndex(.{ .vertex = d_12 }, sm.dartCellIndex(d_12, .vertex));
    }
    {
        // Edge indices.
        // these statements are correct wether 2-sided faces have been deleted or not
        sm.setDartCellIndex(d_12, .edge, sm.dartCellIndex(sm.phi2(d_12), .edge));
        sm.setDartCellIndex(dd_12, .edge, sm.dartCellIndex(sm.phi2(dd_12), .edge));
    }
    {
        // Face indices.
        // faces have been either removed or reduced
    }

    return .{ .vertex = d_12 };
}

/// Checks if the given edge can be collapsed. Edges that cannot be collapsed:
///  1 - edges whose incident triangle face has the third vertex of degree < 4
///  2 - edges whose incident vertices share a common adjacent vertex other than themselves and the third vertex of incident triangle faces
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

    // condition 2: avoid creating vertices of degree > 14
    if (sm.degree(.{ .vertex = d }) + sm.degree(.{ .vertex = dd }) > 14) {
        return false;
    }

    // condition 3: avoid _pinching_ the surface
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
        if (std.mem.indexOfScalar(u32, adjacentVertices.items, sm.dartCellIndex(d_it, .vertex)) != null) {
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
    }
    {
        // Edge indices.
        const index = try sm.newDataIndex(.edge);
        sm.setDartCellIndex(d_1, .edge, index);
        sm.setDartCellIndex(d_2, .edge, index);
    }
    {
        // Face indices.
        sm.setDartCellIndex(d_2, .face, sm.dartCellIndex(d1, .face));
        const index = try sm.newDataIndex(.face);
        sm.setCellIndex(.{ .face = d2 }, index);
    }

    return .{ .edge = d_1 };
}
