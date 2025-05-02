const std = @import("std");
const data = @import("../../utils/Data.zig");

const Self = @This();

pub const DataContainer = data.DataContainer;
pub const DataGen = data.DataGen;
pub const Data = data.Data;

pub const HalfEdge = u32;
pub const Vertex = HalfEdge;
pub const Edge = HalfEdge;
pub const Face = HalfEdge;

pub const CellType = enum {
    halfedge,
    vertex,
    edge,
    face,
};
pub const Cell = union(CellType) {
    halfedge: HalfEdge,
    vertex: Vertex,
    edge: Edge,
    face: Face,
};

// pub const VertexIterator = struct {
//     surface_mesh: *const Self,
//     current: Vertex,
//     pub fn next(self: *VertexIterator) ?Vertex {
//         if (self.current == self.surface_mesh.vertex_data.lastIndex()) {
//             return null;
//         }
//         const res = self.current;
//         self.current = self.surface_mesh.vertex_data.nextIndex(self.current);
//         return res;
//     }
// };

// allocator: std.mem.Allocator,

halfedge_data: DataContainer,
vertex_data: DataContainer,
edge_data: DataContainer,
face_data: DataContainer,

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        // .allocator = allocator,
        .halfedge_data = try DataContainer.init(allocator),
        .vertex_data = try DataContainer.init(allocator),
        .edge_data = try DataContainer.init(allocator),
        .face_data = try DataContainer.init(allocator),
    };
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

pub fn getData(self: *Self, cell_type: CellType, comptime T: type, name: []const u8) !*Data(T) {
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

pub fn indexOf(_: *const Self, c: Cell) u32 {
    switch (c) {
        .halfedge => return @intCast(c.halfedge),
        // .vertex => return @intCast(c.vertex),
        // .edge => return @intCast(c.edge),
        // .face => return @intCast(c.face),
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

// pub fn vertices(self: *const Self) VertexIterator {
//     return VertexIterator{
//         .surface_mesh = self,
//         .current = self.vertex_data.firstIndex(),
//     };
// }
