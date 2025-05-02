const std = @import("std");
const data = @import("../../utils/Data.zig");

const Self = @This();

pub const DataContainer = data.DataContainer;
pub const DataGen = data.DataGen;
pub const Data = data.Data;

pub const Point = u32;

pub const PointIterator = struct {
    point_cloud: *const Self,
    current: Point,
    pub fn next(self: *PointIterator) ?Point {
        if (self.current == self.point_cloud.point_data.lastIndex()) {
            return null;
        }
        const res = self.current;
        self.current = self.point_cloud.point_data.nextIndex(self.current);
        return res;
    }
};

// allocator: std.mem.Allocator,

point_data: DataContainer,

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        // .allocator = allocator,
        .point_data = try DataContainer.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.point_data.deinit();
}

pub fn clearRetainingCapacity(self: *Self) void {
    self.point_data.clearRetainingCapacity();
}

pub fn addData(self: *Self, comptime T: type, name: []const u8) !*Data(T) {
    return self.point_data.addData(T, name);
}

pub fn getData(self: *Self, comptime T: type, name: []const u8) !*Data(T) {
    return self.point_data.getData(T, name);
}

pub fn removeData(self: *Self, data_gen: *DataGen) void {
    self.point_data.removeData(data_gen);
}

pub fn indexOf(_: *const Self, p: Point) u32 {
    return @intCast(p);
}

pub fn nbPoints(self: *const Self) u32 {
    return self.point_data.nbElements();
}

pub fn addPoint(self: *Self) !Point {
    return try self.point_data.newIndex();
}

pub fn removePoint(self: *Self, p: Point) void {
    self.point_data.freeIndex(p);
}

pub fn points(self: *const Self) PointIterator {
    return PointIterator{
        .point_cloud = self,
        .current = self.point_data.firstIndex(),
    };
}
