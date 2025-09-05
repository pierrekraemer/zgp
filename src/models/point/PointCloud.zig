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

pub fn pointIterator(pc: *const PointCloud) PointIterator {
    return .{
        .point_cloud = pc,
        .current = pc.point_data.firstIndex(),
    };
}

pub fn init(allocator: std.mem.Allocator) !PointCloud {
    return .{
        .point_data = try DataContainer.init(allocator),
    };
}

pub fn deinit(pc: *PointCloud) void {
    pc.point_data.deinit();
}

pub fn clearRetainingCapacity(pc: *PointCloud) void {
    pc.point_data.clearRetainingCapacity();
}

pub fn CellData(comptime T: type) type {
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

pub fn addData(pc: *PointCloud, comptime T: type, name: []const u8) !CellData(T) {
    return .{
        .point_cloud = pc,
        .data = try pc.point_data.addData(T, name),
    };
}

pub fn getData(pc: *PointCloud, comptime T: type, name: []const u8) ?CellData(T) {
    return if (pc.point_data.getData(T, name)) |d| .{ .point_cloud = pc, .data = d } else null;
}

pub fn removeData(pc: *PointCloud, data_gen: *DataGen) void {
    pc.point_data.removeData(data_gen);
}

pub fn nbPoints(pc: *const PointCloud) u32 {
    return pc.point_data.nbElements();
}

pub fn addPoint(pc: *PointCloud) !Point {
    return pc.point_data.newIndex();
}

pub fn removePoint(pc: *PointCloud, p: Point) void {
    pc.point_data.freeIndex(p);
}

pub fn pointIndex(_: *const PointCloud, p: Point) u32 {
    return p;
}
