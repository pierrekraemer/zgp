const std = @import("std");
const assert = std.debug.assert;

const c = @import("../main.zig").c;

const PointCloud = @import("../models/point/PointCloud.zig");

const vec = @import("vec.zig");
const Vec3f = vec.Vec3f;

pub const Index = u32;

pub const PointsKDTree = struct {
    initialized: bool = false,
    kdtree_ptr: *anyopaque = undefined,
    point_cloud: *PointCloud = undefined,
    point_position: PointCloud.CellData(Vec3f) = undefined,
    pc_points: std.ArrayList(PointCloud.Point) = .empty,

    pub fn init(
        pc: *PointCloud,
        point_position: PointCloud.CellData(Vec3f),
    ) !PointsKDTree {
        var pc_points = try std.ArrayList(PointCloud.Point).initCapacity(pc.allocator, pc.nbPoints());
        errdefer pc_points.deinit(pc.allocator);

        var point_array = try std.ArrayList(Vec3f).initCapacity(pc.allocator, pc.nbPoints());
        defer point_array.deinit(pc.allocator);

        var point_it = pc.pointIterator();
        var nb_points: u32 = 0;
        while (point_it.next()) |p| : (nb_points += 1) {
            try pc_points.append(pc.allocator, p);
            try point_array.append(pc.allocator, point_position.value(p));
        }

        const kdtree_ptr = c.createKDTree(
            point_array.items.ptr,
            @intCast(point_array.items.len),
        ) orelse return error.FailedToCreateKDTree;

        return .{
            .initialized = true,
            .kdtree_ptr = kdtree_ptr,
            .point_cloud = pc,
            .point_position = point_position,
            .pc_points = pc_points,
        };
    }

    pub fn deinit(kdtree: *PointsKDTree) void {
        if (kdtree.initialized) {
            c.destroyKDTree(kdtree.kdtree_ptr);
            kdtree.pc_points.deinit(kdtree.point_cloud.allocator);
        }
        kdtree.initialized = false;
    }

    pub fn nearestNeighbor(kdtree: *PointsKDTree, point: Vec3f) ?Vec3f {
        assert(kdtree.initialized);
        var nearest: Index = undefined;
        if (c.nearestNeighbor(kdtree.kdtree_ptr, &point, &nearest)) {
            return kdtree.point_position.value(kdtree.pc_points.items[nearest]);
        } else {
            return null;
        }
    }

    pub fn nearestNeighborIndex(kdtree: *PointsKDTree, point: Vec3f) ?PointCloud.Point {
        assert(kdtree.initialized);
        var nearest: Index = undefined;
        if (c.nearestNeighbor(kdtree.kdtree_ptr, &point, &nearest)) {
            return kdtree.pc_points.items[nearest];
        } else {
            return null;
        }
    }

    // caller is responsible for ArrayList deinit
    pub fn nearestNeighbors(
        kdtree: *PointsKDTree,
        allocator: std.mem.Allocator,
        point: Vec3f,
        n: u32,
    ) !std.ArrayList(PointCloud.Point) {
        assert(kdtree.initialized);
        var nn_indices = try std.ArrayList(Index).initCapacity(allocator, n);
        defer nn_indices.deinit(allocator);
        const nb_neighbors = c.nearestNeighbors(kdtree.kdtree_ptr, &point, n, nn_indices.items.ptr);
        nn_indices.items.len = nb_neighbors;

        var nns = try std.ArrayList(PointCloud.Point).initCapacity(allocator, nb_neighbors);
        for (nn_indices.items) |idx| {
            try nns.append(allocator, kdtree.pc_points.items[idx]);
        }
        return nns;
    }
};
