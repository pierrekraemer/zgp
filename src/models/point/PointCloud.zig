const std = @import("std");

const PointCloud = @This();

const data = @import("../../utils/Data.zig");
const DataContainer = data.DataContainer;
const DataGen = data.DataGen;
const Data = data.Data;

pub const Point = u32;

point_data: DataContainer,

pub const PointIterator = struct {
    point_cloud: *const PointCloud,
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

pub fn init(allocator: std.mem.Allocator) !PointCloud {
    return .{
        .point_data = try DataContainer.init(allocator),
    };
}

pub fn deinit(self: *PointCloud) void {
    self.point_data.deinit();
}

pub fn clearRetainingCapacity(self: *PointCloud) void {
    self.point_data.clearRetainingCapacity();
}

pub fn addData(self: *PointCloud, comptime T: type, name: []const u8) !*Data(T) {
    return self.point_data.addData(T, name);
}

pub fn getData(self: *PointCloud, comptime T: type, name: []const u8) !*Data(T) {
    return self.point_data.getData(T, name);
}

pub fn removeData(self: *PointCloud, data_gen: *DataGen) void {
    self.point_data.removeData(data_gen);
}

pub fn nbPoints(self: *const PointCloud) u32 {
    return self.point_data.nbElements();
}

pub fn addPoint(self: *PointCloud) !Point {
    return self.point_data.newIndex();
}

pub fn removePoint(self: *PointCloud, p: Point) void {
    self.point_data.freeIndex(p);
}

pub fn pointIndex(_: *const PointCloud, p: Point) u32 {
    return p;
}
