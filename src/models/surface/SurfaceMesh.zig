const std = @import("std");
const attributes = @import("Attributes.zig");

const Self = @This();

pub const AttributeContainer = attributes.AttributeContainer;
pub const AttributeGen = attributes.AttributeGen;
pub const Attribute = attributes.Attribute;

pub const Dart = u32;
pub const HalfEdge = Dart;
pub const Vertex = Dart;
pub const Edge = Dart;
pub const Face = Dart;

pub const CellTypes = enum {
    halfedge,
    vertex,
    edge,
    face,
};
pub const Cell = union(CellTypes) {
    halfedge: HalfEdge,
    vertex: Vertex,
    edge: Edge,
    face: Face,
};

// pub const VertexIterator = struct {
//     surface_mesh: *const Self,
//     current: Vertex,
//     pub fn next(self: *VertexIterator) ?Vertex {
//         if (self.current == self.surface_mesh.vertex_attributes.lastIndex()) {
//             return null;
//         }
//         const res = self.current;
//         self.current = self.surface_mesh.vertex_attributes.nextIndex(self.current);
//         return res;
//     }
// };

allocator: std.mem.Allocator,

dart_attributes: AttributeContainer,
vertex_attributes: AttributeContainer,
edge_attributes: AttributeContainer,
face_attributes: AttributeContainer,

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .dart_attributes = try AttributeContainer.init(allocator),
        .vertex_attributes = try AttributeContainer.init(allocator),
        .edge_attributes = try AttributeContainer.init(allocator),
        .face_attributes = try AttributeContainer.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.dart_attributes.deinit();
    self.vertex_attributes.deinit();
    self.edge_attributes.deinit();
    self.face_attributes.deinit();
}

pub fn clearRetainingCapacity(self: *Self) void {
    self.dart_attributes.clearRetainingCapacity();
    self.vertex_attributes.clearRetainingCapacity();
    self.edge_attributes.clearRetainingCapacity();
    self.face_attributes.clearRetainingCapacity();
}

pub fn addAttribute(self: *Self, cellType: CellTypes, comptime T: type, name: []const u8) !*Attribute(T) {
    switch (cellType) {
        .halfedge => return self.dart_attributes.addAttribute(T, name),
        .vertex => return self.vertex_attributes.addAttribute(T, name),
        .edge => return self.edge_attributes.addAttribute(T, name),
        .face => return self.face_attributes.addAttribute(T, name),
    }
}

pub fn getAttribute(self: *Self, cellType: CellTypes, comptime T: type, name: []const u8) !*Attribute(T) {
    switch (cellType) {
        .halfedge => return self.dart_attributes.getAttribute(T, name),
        .vertex => return self.vertex_attributes.getAttribute(T, name),
        .edge => return self.edge_attributes.getAttribute(T, name),
        .face => return self.face_attributes.getAttribute(T, name),
    }
}

pub fn removeAttribute(self: *Self, cellType: CellTypes, attribute_gen: *AttributeGen) void {
    switch (cellType) {
        .halfedge => self.dart_attributes.removeAttribute(attribute_gen),
        .vertex => self.vertex_attributes.removeAttribute(attribute_gen),
        .edge => self.edge_attributes.removeAttribute(attribute_gen),
        .face => self.face_attributes.removeAttribute(attribute_gen),
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

pub fn nbCells(self: *const Self, cellType: CellTypes) u32 {
    switch (cellType) {
        .halfedge => return self.dart_attributes.nbElements(),
        .vertex => return self.vertex_attributes.nbElements(),
        .edge => return self.edge_attributes.nbElements(),
        .face => return self.face_attributes.nbElements(),
    }
}

// pub fn vertices(self: *const Self) VertexIterator {
//     return VertexIterator{
//         .surface_mesh = self,
//         .current = self.vertex_attributes.firstIndex(),
//     };
// }
