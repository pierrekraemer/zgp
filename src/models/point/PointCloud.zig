const std = @import("std");

const PointCloud = @This();

const data = @import("../../utils/Data.zig");
const DataContainer = data.DataContainer;
const DataGen = data.DataGen;
const Data = data.Data;

pub const Point = u32;

point_data: DataContainer,

const PointIterator = struct {
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
    pub fn reset(self: *PointIterator) void {
        self.current = self.point_cloud.point_data.firstIndex();
    }
};

pub fn pointIterator(self: *const PointCloud) PointIterator {
    return .{
        .point_cloud = self,
        .current = self.point_data.firstIndex(),
    };
}

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

pub fn PointCloudData(comptime T: type) type {
    return struct {
        const Self = @This();

        point_cloud: *const PointCloud,
        data: *Data(T),

        pub fn value(self: Self, p: Point) T {
            return self.data.value(self.point_cloud.pointIndex(p));
        }

        pub fn valuePtr(self: Self, p: Point) *T {
            return self.data.valuePtr(self.point_cloud.pointIndex(p));
        }

        pub fn name(self: Self) []const u8 {
            return self.gen().name;
        }

        pub fn gen(self: Self) *DataGen {
            return &self.data.gen;
        }
    };
}

pub fn addData(self: *PointCloud, comptime T: type, name: []const u8) !PointCloudData(T) {
    return .{
        .point_cloud = self,
        .data = try self.point_data.addData(T, name),
    };
}

pub fn getData(self: *PointCloud, comptime T: type, name: []const u8) ?PointCloudData(T) {
    return if (self.point_data.getData(T, name)) |d| .{ .point_cloud = self, .data = d } else null;
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
