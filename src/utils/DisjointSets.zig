const std = @import("std");

pub fn DisjointSets(comptime T: type) type {
    const Element = struct {
        value: T,
        parent: usize,
    };

    return struct {
        const Self = @This();

        elements: std.ArrayListUnmanaged(Element) = .empty, // TODO: becomes simply ArrayList in zig 0.15

        pub const init: Self = .{};

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.elements.deinit(allocator);
        }

        pub fn ensureCapacity(self: *Self, allocator: std.mem.Allocator, size: usize) !void {
            try self.elements.ensureTotalCapacity(allocator, size);
        }

        pub fn addElement(self: *Self, allocator: std.mem.Allocator, value: T) !usize {
            const e = try self.elements.addOne(allocator);
            e.* = .{
                .value = value,
                .parent = self.elements.items.len - 1,
            };
            return self.elements.items.len - 1;
        }

        pub fn find(self: *Self, index: usize) usize {
            const e = self.elements.items[index];
            if (e.parent == index) {
                return index;
            }
            const root = self.find(e.parent);
            self.elements.items[index].parent = root; // Path compression
            return root;
        }

        pub fn merge(self: *Self, index1: usize, index2: usize) void {
            const root1 = self.find(index1);
            const root2 = self.find(index2);
            if (root1 != root2) {
                self.elements.items[root2].parent = root1;
            }
        }

        pub fn sameSet(self: *Self, index1: usize, index2: usize) bool {
            return self.find(index1) == self.find(index2);
        }

        pub fn nbSets(self: *Self) usize {
            var count: usize = 0;
            for (self.elements.items, 0..) |e, index| {
                if (e.parent == index) {
                    count += 1;
                }
            }
            return count;
        }
    };
}
