const std = @import("std");
const data = @import("../../utils/Data.zig");

const Self = @This();

pub const DataContainer = data.DataContainer;
pub const DataGen = data.DataGen;
pub const Data = data.Data;

pub const HalfEdge = u32;

pub const CellType = enum {
    halfedge,
    vertex,
    edge,
    face,
};
pub const Cell = union(CellType) {
    halfedge: HalfEdge,
    vertex: HalfEdge,
    edge: HalfEdge,
    face: HalfEdge,
};

pub fn halfEdge(cell: Cell) HalfEdge {
    const he, _ = switch (cell) {
        inline else => |val, tag| .{ val, tag },
    };
    return he;
}

pub fn cellType(cell: Cell) CellType {
    // std.meta.activeTag(cell)
    _, const tag = switch (cell) {
        inline else => |val, tag| .{ val, tag },
    };
    return tag;
}

const invalid_index = std.math.maxInt(u32);

/// data containers for the different cell types
halfedge_data: DataContainer,
vertex_data: DataContainer,
edge_data: DataContainer,
face_data: DataContainer,

/// halfedge data: connectivity & cell indices
he_phi1: *Data(HalfEdge) = undefined,
he_phi_1: *Data(HalfEdge) = undefined,
he_phi2: *Data(HalfEdge) = undefined,
he_vertex_index: *Data(u32) = undefined,
he_edge_index: *Data(u32) = undefined,
he_face_index: *Data(u32) = undefined,

pub fn CellIterator(comptime cell_type: CellType) type {
    return struct {
        surface_mesh: *Self,
        current_halfedge: HalfEdge,
        marker: ?*Data(bool),
        pub fn init(surface_mesh: *Self) !@This() {
            return .{
                .surface_mesh = surface_mesh,
                // no marker needed for halfedge iterator
                .marker = if (cell_type != .halfedge) try surface_mesh.halfedge_data.getMarker() else null,
                .current_halfedge = surface_mesh.halfedge_data.firstIndex(),
            };
        }
        pub fn deinit(self: *@This()) void {
            if (self.marker) |marker| {
                self.surface_mesh.halfedge_data.releaseMarker(marker);
            }
        }
        pub fn next(self: *@This()) ?(if (cell_type == .halfedge) HalfEdge else Cell) {
            if (self.current_halfedge == self.surface_mesh.halfedge_data.lastIndex()) {
                return null;
            }
            // special case for halfedge iterator: no need to mark the halfedges of the cell
            if (cell_type == .halfedge) {
                // prepare current_halfedge for next iteration
                defer self.current_halfedge = self.surface_mesh.halfedge_data.nextIndex(self.current_halfedge);
                return self.current_halfedge;
            }
            // other cells: mark the halfedges of the cell
            const cell = @unionInit(Cell, @tagName(cell_type), self.current_halfedge);
            var it: CellHalfEdgeIterator = .{
                .surface_mesh = self.surface_mesh,
                .cell = cell,
                .current = self.current_halfedge,
            };
            while (it.next()) |he| {
                self.marker.?.value(he).* = true;
            }
            // prepare current_halfedge for next iteration
            defer {
                while (true) {
                    self.current_halfedge = self.surface_mesh.halfedge_data.nextIndex(self.current_halfedge);
                    if (self.current_halfedge == self.surface_mesh.halfedge_data.lastIndex() or
                        !self.marker.?.value(self.current_halfedge).*)
                    {
                        break;
                    }
                }
            }
            return cell;
        }
        pub fn reset(self: *@This()) void {
            self.current_halfedge = self.surface_mesh.halfedge_data.firstIndex();
        }
    };
}

pub const CellHalfEdgeIterator = struct {
    surface_mesh: *const Self,
    cell: Cell,
    current: ?HalfEdge,
    pub fn next(self: *CellHalfEdgeIterator) ?HalfEdge {
        // prepare current for next iteration
        defer {
            if (self.current) |current| {
                self.current = switch (self.cell) {
                    .halfedge => current,
                    .vertex => self.surface_mesh.phi2(self.surface_mesh.phi_1(current)),
                    .edge => self.surface_mesh.phi2(current),
                    .face => self.surface_mesh.phi1(current),
                };
                // the next current becomes null when we get back to the starting halfedge
                if (self.current == halfEdge(self.cell)) {
                    self.current = null;
                }
            }
        }
        return self.current;
    }
};

pub fn init(allocator: std.mem.Allocator) !Self {
    var sm: Self = .{
        .halfedge_data = try DataContainer.init(allocator),
        .vertex_data = try DataContainer.init(allocator),
        .edge_data = try DataContainer.init(allocator),
        .face_data = try DataContainer.init(allocator),
    };
    sm.he_phi1 = try sm.halfedge_data.addData(HalfEdge, "phi1");
    sm.he_phi_1 = try sm.halfedge_data.addData(HalfEdge, "phi_1");
    sm.he_phi2 = try sm.halfedge_data.addData(HalfEdge, "phi2");
    sm.he_vertex_index = try sm.halfedge_data.addData(u32, "vertex_index");
    sm.he_edge_index = try sm.halfedge_data.addData(u32, "edge_index");
    sm.he_face_index = try sm.halfedge_data.addData(u32, "face_index");
    return sm;
}

pub fn deinit(self: *Self) void {
    self.halfedge_data.deinit();
    self.vertex_data.deinit();
    self.edge_data.deinit();
    self.face_data.deinit();
}

pub fn clearRetainingCapacity(self: *Self) void {
    self.halfedge_data.clearRetainingCapacity();
    self.vertex_data.clearRetainingCapacity();
    self.edge_data.clearRetainingCapacity();
    self.face_data.clearRetainingCapacity();
}

pub fn addData(self: *Self, cell_type: CellType, comptime T: type, name: []const u8) !*Data(T) {
    switch (cell_type) {
        .halfedge => return self.halfedge_data.addData(T, name),
        .vertex => return self.vertex_data.addData(T, name),
        .edge => return self.edge_data.addData(T, name),
        .face => return self.face_data.addData(T, name),
    }
}

pub fn getData(self: *const Self, cell_type: CellType, comptime T: type, name: []const u8) ?*Data(T) {
    switch (cell_type) {
        .halfedge => return self.halfedge_data.getData(T, name),
        .vertex => return self.vertex_data.getData(T, name),
        .edge => return self.edge_data.getData(T, name),
        .face => return self.face_data.getData(T, name),
    }
}

pub fn removeData(self: *Self, cell_type: CellType, attribute_gen: *DataGen) void {
    switch (cell_type) {
        .halfedge => self.halfedge_data.removeData(attribute_gen),
        .vertex => self.vertex_data.removeData(attribute_gen),
        .edge => self.edge_data.removeData(attribute_gen),
        .face => self.face_data.removeData(attribute_gen),
    }
}

/// Creates a new index for the given cell type.
/// The new index is not associated to any halfedge of the mesh.
/// This function is only intended for use in SurfaceMesh creation process (import, ...) as the new index is not
/// in use until it is associated to the halfedges of a cell of the mesh (see setCellIndex)
pub fn newDataIndex(self: *Self, cell_type: CellType) !u32 {
    switch (cell_type) {
        .halfedge => unreachable, // halfedge are to be created with addHalfEdge
        .vertex => return self.vertex_data.newIndex(),
        .edge => return self.edge_data.newIndex(),
        .face => return self.face_data.newIndex(),
    }
}

pub fn nbCells(self: *const Self, cell_type: CellType) u32 {
    switch (cell_type) {
        .halfedge => return self.halfedge_data.nbElements(),
        .vertex => return self.vertex_data.nbElements(),
        .edge => return self.edge_data.nbElements(),
        .face => return self.face_data.nbElements(),
    }
}

fn addHalfEdge(self: *Self) !HalfEdge {
    const he = try self.halfedge_data.newIndex();
    self.he_phi1.value(he).* = he;
    self.he_phi_1.value(he).* = he;
    self.he_phi2.value(he).* = he;
    self.he_vertex_index.value(he).* = invalid_index;
    self.he_edge_index.value(he).* = invalid_index;
    self.he_face_index.value(he).* = invalid_index;
    return he;
}

fn removeHalfEdge(self: *Self, he: HalfEdge) void {
    const vertex_index = self.he_vertex_index.value(he).*;
    if (vertex_index != invalid_index) {
        self.vertex_data.unrefIndex(vertex_index);
    }
    const edge_index = self.he_edge_index.value(he).*;
    if (edge_index != invalid_index) {
        self.edge_data.unrefIndex(edge_index);
    }
    const face_index = self.he_face_index.value(he).*;
    if (face_index != invalid_index) {
        self.face_data.unrefIndex(face_index);
    }
    self.halfedge_data.freeIndex(he);
}

pub fn phi1(self: *const Self, he: HalfEdge) HalfEdge {
    return self.he_phi1.value(he).*;
}
pub fn phi_1(self: *const Self, he: HalfEdge) HalfEdge {
    return self.he_phi_1.value(he).*;
}
pub fn phi2(self: *const Self, he: HalfEdge) HalfEdge {
    return self.he_phi2.value(he).*;
}

pub fn phi1Sew(self: *Self, he1: HalfEdge, he2: HalfEdge) void {
    std.debug.assert(he1 != he2);
    const he3 = self.phi1(he1);
    const he4 = self.phi1(he2);
    self.he_phi1.value(he1).* = he4;
    self.he_phi1.value(he2).* = he3;
    self.he_phi_1.value(he4).* = he1;
    self.he_phi_1.value(he3).* = he2;
}

pub fn phi2Sew(self: *Self, he1: HalfEdge, he2: HalfEdge) void {
    std.debug.assert(he1 != he2);
    std.debug.assert(self.phi2(he1) == he1);
    std.debug.assert(self.phi2(he2) == he2);
    self.he_phi2.value(he1).* = he2;
    self.he_phi2.value(he2).* = he1;
}

pub fn phi2Unsew(self: *Self, he: HalfEdge) void {
    std.debug.assert(self.phi2(he) != he);
    const he2 = self.phi2(he);
    self.he_phi2.value(he).* = he;
    self.he_phi2.value(he2).* = he2;
}

pub fn setHalfEdgeIndex(self: *Self, he: HalfEdge, cell_type: CellType, index: u32) void {
    var index_data = switch (cell_type) {
        .halfedge => unreachable,
        .vertex => self.he_vertex_index,
        .edge => self.he_edge_index,
        .face => self.he_face_index,
    };
    var data_container = switch (cell_type) {
        .halfedge => unreachable,
        .vertex => self.he_vertex_data,
        .edge => self.he_edge_data,
        .face => self.he_face_data,
    };
    const old_index: u32 = index_data.value(he).*;
    if (index != invalid_index) {
        data_container.refIndex(index);
    }
    if (old_index != invalid_index) {
        data_container.unrefIndex(old_index);
    }
    index_data.value(he).* = index;
}

pub fn setCellIndex(self: *Self, c: Cell, index: u32) void {
    var it: CellHalfEdgeIterator = .{
        .surface_mesh = self,
        .cell = c,
        .current = halfEdge(c),
    };
    while (it.next()) |he| {
        self.setHalfEdgeIndex(he, cellType(c), index);
    }
}

pub fn indexCells(self: *Self, comptime cell_type: CellType) !void {
    var it = try CellIterator(cell_type).init(self);
    defer it.deinit();
    while (it.next()) |cell| {
        if (self.indexOf(cell) == invalid_index) {
            const index = try self.newDataIndex(cell_type);
            self.setCellIndex(cell, index);
        }
    }
}

pub fn indexOf(self: *const Self, c: Cell) u32 {
    const he = halfEdge(c);
    switch (c) {
        .halfedge => return he,
        .vertex => return self.he_vertex_index.value(he).*,
        .edge => return self.he_edge_index.value(he).*,
        .face => return self.he_face_index.value(he).*,
    }
}

pub fn dump(self: *Self, writer: std.io.AnyWriter) !void {
    var it = try CellIterator(.halfedge).init(self);
    defer it.deinit();
    while (it.next()) |he| {
        try writer.print("halfedge {d}: (phi1: {d}, phi_1: {d}, phi2: {d}) (v: {d}, e: {d}, f: {d})\n", .{
            he,
            self.phi1(he),
            self.phi_1(he),
            self.phi2(he),
            self.indexOf(.{ .vertex = he }),
            self.indexOf(.{ .edge = he }),
            self.indexOf(.{ .face = he }),
        });
    }
}

/// Creates a new face with the given number of vertices.
/// Unbounded means that the face is not linked to any boundary "outer" face (all its halfedges are opposite-linked to themselves).
/// None of the face HalfEdges are associated to vertex/edge/face indices and the face is not closed by a boundary face.
/// This function is only intended for use in SurfaceMesh creation process (import, ...) as the SurfaceMesh is not
/// valid after this function is called.
pub fn addUnboundedFace(self: *Self, nb_vertices: u32) !Cell {
    const he1 = try self.addHalfEdge();
    for (1..nb_vertices) |_| {
        const he2 = try self.addHalfEdge();
        self.phi1Sew(he1, he2);
    }
    var it = he1;
    while (true) {
        it = self.phi1(it);
        if (it == he1) {
            break;
        }
    }
    return .{ .face = he1 };
}
