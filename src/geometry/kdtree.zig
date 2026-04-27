const std = @import("std");
const assert = std.debug.assert;

const c = @import("../main.zig").c;

const PointCloud = @import("../models/point/PointCloud.zig");

const vec = @import("vec.zig");
const Vec3f = vec.Vec3f;

pub const Index = u32;

pub const KDTree = struct {
    initialized: bool = false,
    kdtree_ptr: *anyopaque = undefined,
    point_cloud: *PointCloud = undefined,
    positions: PointCloud.CellData(.point, Vec3f) = undefined,

    pub fn init(
        pc: *PointCloud,
        positions: PointCloud.CellData(.point, Vec3f),
    ) !KDTree {
        var point_index = try pc.addData(.point, u32, "__point_index");
        defer pc.removeData(.point, u32, point_index);

        var point_array = try std.ArrayList(Vec3f).initCapacity(pc.allocator, pc.nbCells(.point));
        defer point_array.deinit(pc.allocator);

        var point_it: PointCloud.CellIterator = try .init(pc, .point);
        defer point_it.deinit();
        var nb_points: u32 = 0;
        while (point_it.next()) |p| : (nb_points += 1) {
            point_index.valuePtr(p).* = nb_points;
            try point_array.append(pc.allocator, positions.value(p));
        }

        const kdtree_ptr = c.createKDTree(
            point_array.items.ptr,
            @intCast(point_array.items.len),
        ) orelse return error.FailedToCreateKDTree;

        return .{
            .initialized = true,
            .kdtree_ptr = kdtree_ptr,
            .point_cloud = pc,
            .positions = positions,
        };
    }

    pub fn deinit(kdtree: *KDTree) void {
        if (kdtree.initialized) {
            c.destroyKDTree(kdtree.kdtree_ptr);
        }
        kdtree.initialized = false;
    }

    pub fn nearestNeighbor(kdtree: KDTree, point: Vec3f) Vec3f {
        assert(kdtree.initialized);
        var nearest: Vec3f = undefined;
        c.nearestNeighbor(kdtree.kdtree_ptr, &point, &nearest);
        return nearest;
    }
};
