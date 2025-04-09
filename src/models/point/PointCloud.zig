const std = @import("std");
const attributes = @import("Attributes.zig");

const Self = @This();

pub const AttributeContainer = attributes.AttributeContainer;
pub const AttributeGen = attributes.AttributeGen;
pub const Attribute = attributes.Attribute;

pub const Point = u32;

pub const PointIterator = struct {
    graph: *const Self,
    current: Point,
    pub fn next(self: *PointIterator) ?Point {
        if (self.current == self.graph.point_attributes.lastIndex()) {
            return null;
        }
        const res = self.current;
        self.current = self.graph.point_attributes.nextIndex(self.current);
        return res;
    }
};

allocator: std.mem.Allocator,

point_attributes: AttributeContainer,

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .point_attributes = try AttributeContainer.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.point_attributes.deinit();
}

pub fn clearRetainingCapacity(self: *Self) void {
    self.point_attributes.clearRetainingCapacity();
}

pub fn addAttribute(self: *Self, comptime T: type, name: []const u8) !*Attribute(T) {
    return self.point_attributes.addAttribute(T, name);
}

pub fn getAttribute(self: *Self, comptime T: type, name: []const u8) !*Attribute(T) {
    return self.point_attributes.getAttribute(T, name);
}

pub fn removeAttribute(self: *Self, attribute_gen: *AttributeGen) void {
    self.point_attributes.removeAttribute(attribute_gen);
}

pub fn indexOf(_: *const Self, p: Point) u32 {
    return @intCast(p);
}

pub fn nbPoints(self: *const Self) u32 {
    return self.point_attributes.nbElements();
}

pub fn addPoint(self: *Self) !Point {
    return try self.point_attributes.newIndex();
}

pub fn removePoint(self: *Self, p: Point) void {
    self.point_attributes.freeIndex(p);
}

pub fn points(self: *const Self) PointIterator {
    return PointIterator{
        .graph = self,
        .current = self.point_attributes.firstIndex(),
    };
}
