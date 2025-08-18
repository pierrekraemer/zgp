const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @This();

const data = @import("../../utils/Data.zig");
const DataContainer = data.DataContainer;
const DataGen = data.DataGen;
const Data = data.Data;

pub const Dart = u32;

pub const Cell = union(enum) {
    corner: Dart,
    vertex: Dart,
    // orientedEdge: Dart, // TODO: consider adding orientedEdge as a cell type
    edge: Dart,
    face: Dart,

    pub fn dart(self: Cell) Dart {
        const d, _ = switch (self) {
            inline else => |val, tag| .{ val, tag },
        };
        return d;
    }

    pub fn cellType(self: Cell) CellType {
        return std.meta.activeTag(self);
    }
};

pub const CellType = std.meta.Tag(Cell);

const invalid_index = std.math.maxInt(u32);

/// Data containers for darts & the different cell types.
dart_data: DataContainer,
corner_data: DataContainer,
vertex_data: DataContainer,
edge_data: DataContainer,
face_data: DataContainer,

/// Dart data: connectivity & cell indices.
dart_phi1: *Data(Dart) = undefined,
dart_phi_1: *Data(Dart) = undefined,
dart_phi2: *Data(Dart) = undefined,
dart_corner_index: *Data(u32) = undefined,
dart_vertex_index: *Data(u32) = undefined,
dart_edge_index: *Data(u32) = undefined,
dart_face_index: *Data(u32) = undefined,
dart_boundary_marker: *Data(bool) = undefined, // boundary marker

const DartIterator = struct {
    surface_mesh: *const SurfaceMesh,
    current_dart: Dart,
    pub fn next(self: *DartIterator) ?Dart {
        if (self.current_dart == self.surface_mesh.dart_data.lastIndex()) {
            return null;
        }
        // prepare current_dart for next iteration
        defer self.current_dart = self.surface_mesh.dart_data.nextIndex(self.current_dart);
        return self.current_dart;
    }
    pub fn reset(self: *DartIterator) void {
        self.current_dart = self.surface_mesh.dart_data.firstIndex();
    }
};

const CellDartIterator = struct {
    surface_mesh: *const SurfaceMesh,
    cell: Cell,
    current_dart: ?Dart,
    pub fn next(self: *CellDartIterator) ?Dart {
        // prepare current_dart for next iteration
        defer {
            if (self.current_dart) |current_dart| {
                self.current_dart = switch (self.cell) {
                    .corner => current_dart,
                    .vertex => self.surface_mesh.phi2(self.surface_mesh.phi_1(current_dart)),
                    .edge => self.surface_mesh.phi2(current_dart),
                    .face => self.surface_mesh.phi1(current_dart),
                };
                // the next current_dart becomes null when we get back to the starting dart
                if (self.current_dart == self.cell.dart()) {
                    self.current_dart = null;
                }
            }
        }
        return self.current_dart;
    }
};

fn firstNonBoundaryDart(self: *const SurfaceMesh) Dart {
    var first = self.dart_data.firstIndex();
    return while (first != self.dart_data.lastIndex()) : (first = self.dart_data.nextIndex(first)) {
        if (!self.dart_boundary_marker.value(first).*) {
            break first;
        }
    } else self.dart_data.lastIndex();
}

fn nextNonBoundaryDart(self: *const SurfaceMesh, d: Dart) Dart {
    var next = self.dart_data.nextIndex(d);
    return while (next != self.dart_data.lastIndex()) : (next = self.dart_data.nextIndex(next)) {
        if (!self.dart_boundary_marker.value(next).*) {
            break next;
        }
    } else self.dart_data.lastIndex();
}

// TODO: write BoundaryIterator

pub fn CellIterator(comptime cell_type: CellType) type {
    return struct {
        surface_mesh: *SurfaceMesh,
        current_dart: Dart,
        marker: ?*Data(bool),
        pub fn init(surface_mesh: *SurfaceMesh) !@This() {
            return .{
                .surface_mesh = surface_mesh,
                // no marker needed for corner iterator (a corner is a single dart)
                .marker = if (cell_type != .corner) try surface_mesh.dart_data.getMarker() else null,
                .current_dart = surface_mesh.firstNonBoundaryDart(),
            };
        }
        pub fn deinit(self: *@This()) void {
            if (self.marker) |marker| {
                self.surface_mesh.dart_data.releaseMarker(marker);
            }
        }
        pub fn next(self: *@This()) ?Cell {
            if (self.current_dart == self.surface_mesh.dart_data.lastIndex()) {
                return null;
            }
            // special case for corner iterator: a corner is a single dart, so there is no need to mark the darts of the cell
            if (cell_type == .corner) {
                // prepare current_dart for next iteration
                defer self.current_dart = self.surface_mesh.nextNonBoundaryDart(self.current_dart);
                return .{ .corner = self.current_dart };
            }
            // other cells: mark the darts of the cell
            const cell = @unionInit(Cell, @tagName(cell_type), self.current_dart);
            var dart_it = self.surface_mesh.cellDartIterator(cell);
            while (dart_it.next()) |d| {
                self.marker.?.value(d).* = true;
            }
            // prepare current_dart for next iteration
            defer {
                // TODO: rewrite more readable & efficient version
                while (true) : ({
                    if (self.current_dart == self.surface_mesh.dart_data.lastIndex() or
                        !self.marker.?.value(self.current_dart).*)
                    {
                        break;
                    }
                }) {
                    self.current_dart = self.surface_mesh.nextNonBoundaryDart(self.current_dart);
                }
            }
            return cell;
        }
        pub fn reset(self: *@This()) void {
            self.current_dart = self.surface_mesh.firstNonBoundaryDart();
            if (self.marker) |marker| {
                marker.fill(false);
            }
        }
    };
}

pub fn dartIterator(self: *const SurfaceMesh) DartIterator {
    return .{
        .surface_mesh = self,
        .current_dart = self.dart_data.firstIndex(),
    };
}

pub fn cellDartIterator(self: *const SurfaceMesh, cell: Cell) CellDartIterator {
    return .{
        .surface_mesh = self,
        .cell = cell,
        .current_dart = cell.dart(),
    };
}

pub fn init(allocator: std.mem.Allocator) !SurfaceMesh {
    var sm: SurfaceMesh = .{
        .dart_data = try DataContainer.init(allocator),
        .corner_data = try DataContainer.init(allocator),
        .vertex_data = try DataContainer.init(allocator),
        .edge_data = try DataContainer.init(allocator),
        .face_data = try DataContainer.init(allocator),
    };
    sm.dart_phi1 = try sm.dart_data.addData(Dart, "phi1");
    sm.dart_phi_1 = try sm.dart_data.addData(Dart, "phi_1");
    sm.dart_phi2 = try sm.dart_data.addData(Dart, "phi2");
    sm.dart_corner_index = try sm.dart_data.addData(u32, "corner_index");
    sm.dart_vertex_index = try sm.dart_data.addData(u32, "vertex_index");
    sm.dart_edge_index = try sm.dart_data.addData(u32, "edge_index");
    sm.dart_face_index = try sm.dart_data.addData(u32, "face_index");
    sm.dart_boundary_marker = try sm.dart_data.getMarker();
    return sm;
}

pub fn deinit(self: *SurfaceMesh) void {
    self.dart_data.deinit();
    self.corner_data.deinit();
    self.vertex_data.deinit();
    self.edge_data.deinit();
    self.face_data.deinit();
}

pub fn clearRetainingCapacity(self: *SurfaceMesh) void {
    self.dart_data.clearRetainingCapacity();
    self.corner_data.clearRetainingCapacity();
    self.vertex_data.clearRetainingCapacity();
    self.edge_data.clearRetainingCapacity();
    self.face_data.clearRetainingCapacity();
}

// TODO: write SurfaceMeshData type to allow easiest value access from Cell

pub fn addData(self: *SurfaceMesh, cell_type: CellType, comptime T: type, name: []const u8) !*Data(T) {
    switch (cell_type) {
        .corner => return self.corner_data.addData(T, name),
        .vertex => return self.vertex_data.addData(T, name),
        .edge => return self.edge_data.addData(T, name),
        .face => return self.face_data.addData(T, name),
    }
}

pub fn getData(self: *const SurfaceMesh, cell_type: CellType, comptime T: type, name: []const u8) ?*Data(T) {
    switch (cell_type) {
        .corner => return self.corner_data.getData(T, name),
        .vertex => return self.vertex_data.getData(T, name),
        .edge => return self.edge_data.getData(T, name),
        .face => return self.face_data.getData(T, name),
    }
}

pub fn removeData(self: *SurfaceMesh, cell_type: CellType, attribute_gen: *DataGen) void {
    switch (cell_type) {
        .corner => self.corner_data.removeData(attribute_gen),
        .vertex => self.vertex_data.removeData(attribute_gen),
        .edge => self.edge_data.removeData(attribute_gen),
        .face => self.face_data.removeData(attribute_gen),
    }
}

/// Creates a new index for the given cell type.
/// The new index is not associated to any dart of the mesh.
/// This function is only intended for use in SurfaceMesh creation process (import, ...) as the new index is not
/// in use until it is associated to the darts of a cell of the mesh (see setCellIndex)
pub fn newDataIndex(self: *SurfaceMesh, cell_type: CellType) !u32 {
    switch (cell_type) {
        .corner => return self.corner_data.newIndex(),
        .vertex => return self.vertex_data.newIndex(),
        .edge => return self.edge_data.newIndex(),
        .face => return self.face_data.newIndex(),
    }
}

fn addDart(self: *SurfaceMesh) !Dart {
    const d = try self.dart_data.newIndex();
    self.dart_phi1.value(d).* = d;
    self.dart_phi_1.value(d).* = d;
    self.dart_phi2.value(d).* = d;
    self.dart_corner_index.value(d).* = invalid_index;
    self.dart_vertex_index.value(d).* = invalid_index;
    self.dart_edge_index.value(d).* = invalid_index;
    self.dart_face_index.value(d).* = invalid_index;
    // boundary marker is false on new index
    return d;
}

fn removeDart(self: *SurfaceMesh, d: Dart) void {
    self.dart_data.freeIndex(d);
    const corner_index = self.dart_corner_index.value(d).*;
    if (corner_index != invalid_index) {
        self.corner_data.unrefIndex(corner_index);
    }
    const vertex_index = self.dart_vertex_index.value(d).*;
    if (vertex_index != invalid_index) {
        self.vertex_data.unrefIndex(vertex_index);
    }
    const edge_index = self.dart_edge_index.value(d).*;
    if (edge_index != invalid_index) {
        self.edge_data.unrefIndex(edge_index);
    }
    const face_index = self.dart_face_index.value(d).*;
    if (face_index != invalid_index) {
        self.face_data.unrefIndex(face_index);
    }
}

pub fn phi1(self: *const SurfaceMesh, dart: Dart) Dart {
    return self.dart_phi1.value(dart).*;
}
pub fn phi_1(self: *const SurfaceMesh, dart: Dart) Dart {
    return self.dart_phi_1.value(dart).*;
}
pub fn phi2(self: *const SurfaceMesh, dart: Dart) Dart {
    return self.dart_phi2.value(dart).*;
}

pub fn phi1Sew(self: *SurfaceMesh, d1: Dart, d2: Dart) void {
    assert(d1 != d2);
    const d3 = self.phi1(d1);
    const d4 = self.phi1(d2);
    self.dart_phi1.value(d1).* = d4;
    self.dart_phi1.value(d2).* = d3;
    self.dart_phi_1.value(d4).* = d1;
    self.dart_phi_1.value(d3).* = d2;
}

pub fn phi2Sew(self: *SurfaceMesh, d1: Dart, d2: Dart) void {
    assert(d1 != d2);
    assert(self.phi2(d1) == d1);
    assert(self.phi2(d2) == d2);
    self.dart_phi2.value(d1).* = d2;
    self.dart_phi2.value(d2).* = d1;
}

pub fn phi2Unsew(self: *SurfaceMesh, d: Dart) void {
    assert(self.phi2(d) != d);
    const d2 = self.phi2(d);
    self.dart_phi2.value(d).* = d;
    self.dart_phi2.value(d2).* = d2;
}

// TODO: implement isBoundaryFace & isIncidentToBoundary functions?

pub fn isBoundaryDart(self: *const SurfaceMesh, d: Dart) bool {
    return self.dart_boundary_marker.value(d).*;
}

pub fn setDartIndex(self: *SurfaceMesh, d: Dart, cell_type: CellType, index: u32) void {
    var index_data = switch (cell_type) {
        .corner => self.dart_corner_index,
        .vertex => self.dart_vertex_index,
        .edge => self.dart_edge_index,
        .face => self.dart_face_index,
    };
    var data_container = switch (cell_type) {
        .corner => &self.corner_data,
        .vertex => &self.vertex_data,
        .edge => &self.edge_data,
        .face => &self.face_data,
    };
    const old_index: u32 = index_data.value(d).*;
    if (index != invalid_index) {
        data_container.refIndex(index);
    }
    if (old_index != invalid_index) {
        data_container.unrefIndex(old_index);
    }
    index_data.value(d).* = index;
}

pub fn dartIndex(self: *const SurfaceMesh, d: Dart, cell_type: CellType) u32 {
    switch (cell_type) {
        .corner => return self.dart_corner_index.value(d).*,
        .vertex => return self.dart_vertex_index.value(d).*,
        .edge => return self.dart_edge_index.value(d).*,
        .face => return self.dart_face_index.value(d).*,
    }
}

pub fn setCellIndex(self: *SurfaceMesh, c: Cell, index: u32) void {
    var dart_it = self.cellDartIterator(c);
    while (dart_it.next()) |d| {
        self.setDartIndex(d, c.cellType(), index);
    }
}

pub fn cellIndex(self: *const SurfaceMesh, c: Cell) u32 {
    return self.dartIndex(c.dart(), c.cellType());
}

pub fn indexCells(self: *SurfaceMesh, comptime cell_type: CellType) !void {
    var it = try CellIterator(cell_type).init(self);
    defer it.deinit();
    while (it.next()) |cell| {
        if (self.cellIndex(cell) == invalid_index) {
            const index = try self.newDataIndex(cell_type);
            self.setCellIndex(cell, index);
        }
    }
}

pub fn dump(self: *SurfaceMesh, writer: std.io.AnyWriter) void {
    var dart_it = self.dartIterator();
    while (dart_it.next()) |d| {
        try writer.print("Dart {d}: (phi1: {d}, phi_1: {d}, phi2: {d}) (v: {d}, e: {d}, f: {d})\n", .{
            d,
            self.phi1(d),
            self.phi_1(d),
            self.phi2(d),
            self.cellIndex(.{ .vertex = d }),
            self.cellIndex(.{ .edge = d }),
            self.cellIndex(.{ .face = d }),
        });
    }
}

pub fn nbCells(self: *const SurfaceMesh, cell_type: CellType) u32 {
    switch (cell_type) {
        .corner => return self.corner_data.nbElements(),
        .vertex => return self.vertex_data.nbElements(),
        .edge => return self.edge_data.nbElements(),
        .face => return self.face_data.nbElements(),
    }
}

pub fn degree(self: *const SurfaceMesh, cell: Cell) u32 {
    assert(cell.cellType() == .vertex or cell.cellType() == .edge); // face is a top cell and does not have a degree
    var it = self.cellDartIterator(cell);
    var deg: u32 = 0;
    while (it.next()) |_| {
        // if (!self.isBoundary(d)) // TODO: check boundary condition
        deg += 1;
    }
    return deg;
}

pub fn codegree(self: *const SurfaceMesh, cell: Cell) u32 {
    assert(cell.cellType() == .face or cell.cellType() == .edge); // vertex is a 0-cell and does not have a codegree
    var it = self.cellDartIterator(cell);
    var deg: u32 = 0;
    while (it.next()) |_| {
        deg += 1;
    }
    return deg;
}

/// Creates a new face with the given number of vertices.
/// Unbounded means that the face is not linked to any boundary "outer" face (all its darts are phi2-linked to themselves).
/// None of the face darts are associated to vertex/edge/face indices and the face is not closed by a boundary face.
/// This function is only intended for use in SurfaceMesh creation process (import, ...) as the SurfaceMesh is not
/// valid after this function is called.
pub fn addUnboundedFace(self: *SurfaceMesh, nb_vertices: u32) !Cell {
    const d1 = try self.addDart();
    for (1..nb_vertices) |_| {
        const d2 = try self.addDart();
        self.phi1Sew(d1, d2);
    }
    var it = d1;
    while (true) {
        it = self.phi1(it);
        if (it == d1) {
            break;
        }
    }
    return .{ .face = d1 };
}

pub fn close(self: *SurfaceMesh) !u32 {
    var nb_boundary_faces: u32 = 0;
    var dart_it = self.dartIterator();
    while (dart_it.next()) |d| {
        if (self.phi2(d) == d) {
            const b_first = try self.addDart();
            self.dart_boundary_marker.value(b_first).* = true;
            self.phi2Sew(d, b_first);
            // boundary darts do not represent a valid corner, thus they do not have a corner index
            self.setDartIndex(b_first, .vertex, self.dartIndex(self.phi1(d), .vertex));
            self.setDartIndex(b_first, .edge, self.dartIndex(d, .edge));
            // boundary darts do not represent a valid face, thus they do not have a face index

            var d_current = d;
            out: while (true) {
                // find the next dart that is phi2-linked to itself
                while (self.phi2(d_current) != d_current) {
                    d_current = self.phi2(self.phi1(d_current));
                    if (self.phi2(d_current) == d) {
                        // we are back to the starting dart, so we can stop
                        break :out;
                    }
                }
                const b_next = try self.addDart();
                self.dart_boundary_marker.value(b_next).* = true;
                self.phi2Sew(d_current, b_next);
                self.phi1Sew(b_first, b_next);
                // boundary darts do not represent a valid corner, thus they do not have a corner index
                self.setDartIndex(b_next, .vertex, self.dartIndex(self.phi1(d_current), .vertex));
                self.setDartIndex(b_next, .edge, self.dartIndex(d_current, .edge));
                // boundary darts do not represent a valid face, thus they do not have a face index
            }

            nb_boundary_faces += 1;
        }
    }
    return nb_boundary_faces;
}

pub fn flipEdge(self: *SurfaceMesh, edge: Cell) void {
    assert(edge.cellType() == .edge);
    _ = self;
}
