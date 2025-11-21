const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Order = std.math.Order;
const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;

/// Priority queue for storing generic data. Initialize with `init`.
/// Provide `compareFn` that returns
///  - `Order.lt` when its second argument should get popped before its third argument,
///  - `Order.eq` if the arguments are of equal priority
///  - `Order.gt` if the third argument should be popped first.
/// For example, to make `pop` return the smallest number, provide
/// `fn lessThan(context: void, a: T, b: T) Order { _ = context; return std.math.order(a, b); }`
/// Provide `setElemIndexFn` that is called on insertion and whenever an element's index in the queue changes.
pub fn PriorityQueue(
    comptime T: type,
    comptime Context: type,
    comptime compareFn: fn (context: Context, a: T, b: T) Order,
    comptime setElemIndexFn: fn (context: Context, a: T, index: usize) void,
) type {
    return struct {
        const Self = @This();

        items: []T,
        cap: usize,
        allocator: Allocator,
        context: Context,

        /// Initialize and return a priority queue.
        pub fn init(allocator: Allocator, context: Context) Self {
            return Self{
                .items = &[_]T{},
                .cap = 0,
                .allocator = allocator,
                .context = context,
            };
        }

        /// Free memory used by the queue.
        pub fn deinit(self: Self) void {
            self.allocator.free(self.allocatedSlice());
        }

        /// Insert a new element, maintaining priority.
        pub fn add(self: *Self, elem: T) !void {
            try self.ensureUnusedCapacity(1);
            addUnchecked(self, elem);
        }

        fn addUnchecked(self: *Self, elem: T) void {
            self.items.len += 1;
            self.items[self.items.len - 1] = elem;
            setElemIndexFn(self.context, elem, self.items.len - 1);
            siftUp(self, self.items.len - 1);
        }

        fn siftUp(self: *Self, start_index: usize) void {
            const child = self.items[start_index];
            var child_index = start_index;
            while (child_index > 0) {
                const parent_index = ((child_index - 1) >> 1);
                const parent = self.items[parent_index];
                if (compareFn(self.context, child, parent) != .lt) break;
                self.items[child_index] = parent;
                setElemIndexFn(self.context, parent, child_index);
                child_index = parent_index;
            }
            self.items[child_index] = child;
            setElemIndexFn(self.context, child, child_index);
        }

        /// Add each element in `items` to the queue.
        pub fn addSlice(self: *Self, items: []const T) !void {
            try self.ensureUnusedCapacity(items.len);
            for (items) |e| {
                self.addUnchecked(e);
            }
        }

        /// Look at the highest priority element in the queue. Returns
        /// `null` if empty.
        pub fn peek(self: *Self) ?T {
            return if (self.items.len > 0) self.items[0] else null;
        }

        /// Pop the highest priority element from the queue. Returns
        /// `null` if empty.
        pub fn removeOrNull(self: *Self) ?T {
            return if (self.items.len > 0) self.remove() else null;
        }

        /// Remove and return the highest priority element from the
        /// queue.
        pub fn remove(self: *Self) T {
            return self.removeIndex(0);
        }

        /// Remove and return element at index. Indices are in the
        /// same order as iterator, which is not necessarily priority
        /// order.
        pub fn removeIndex(self: *Self, index: usize) T {
            assert(self.items.len > index);
            const last = self.items[self.items.len - 1];
            const item = self.items[index];
            self.items[index] = last;
            setElemIndexFn(self.context, last, index);
            self.items.len -= 1;

            if (index == self.items.len) {
                // Last element removed, nothing more to do.
            } else if (index == 0) {
                siftDown(self, index);
            } else {
                const parent_index = ((index - 1) >> 1);
                const parent = self.items[parent_index];
                if (compareFn(self.context, last, parent) == .gt) {
                    siftDown(self, index);
                } else {
                    siftUp(self, index);
                }
            }

            return item;
        }

        /// Return the number of elements remaining in the priority
        /// queue.
        pub fn count(self: Self) usize {
            return self.items.len;
        }

        /// Return the number of elements that can be added to the
        /// queue before more memory is allocated.
        pub fn capacity(self: Self) usize {
            return self.cap;
        }

        /// Returns a slice of all the items plus the extra capacity, whose memory
        /// contents are `undefined`.
        fn allocatedSlice(self: Self) []T {
            // `items.len` is the length, not the capacity.
            return self.items.ptr[0..self.cap];
        }

        fn siftDown(self: *Self, target_index: usize) void {
            const target_element = self.items[target_index];
            var index = target_index;
            while (true) {
                var lesser_child_i = (std.math.mul(usize, index, 2) catch break) | 1;
                if (!(lesser_child_i < self.items.len)) break;

                const next_child_i = lesser_child_i + 1;
                if (next_child_i < self.items.len and compareFn(self.context, self.items[next_child_i], self.items[lesser_child_i]) == .lt) {
                    lesser_child_i = next_child_i;
                }

                if (compareFn(self.context, target_element, self.items[lesser_child_i]) == .lt) break;

                self.items[index] = self.items[lesser_child_i];
                setElemIndexFn(self.context, self.items[index], index);
                index = lesser_child_i;
            }
            self.items[index] = target_element;
            setElemIndexFn(self.context, target_element, index);
        }

        /// PriorityQueue takes ownership of the passed in slice. The slice must have been
        /// allocated with `allocator`.
        /// Deinitialize with `deinit`.
        pub fn fromOwnedSlice(allocator: Allocator, items: []T, context: Context) Self {
            var self = Self{
                .items = items,
                .cap = items.len,
                .allocator = allocator,
                .context = context,
            };

            var i = self.items.len >> 1;
            while (i > 0) {
                i -= 1;
                self.siftDown(i);
            }
            return self;
        }

        /// Ensure that the queue can fit at least `new_capacity` items.
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) !void {
            var better_capacity = self.cap;
            if (better_capacity >= new_capacity) return;
            while (true) {
                better_capacity += better_capacity / 2 + 8;
                if (better_capacity >= new_capacity) break;
            }
            try self.ensureTotalCapacityPrecise(better_capacity);
        }

        pub fn ensureTotalCapacityPrecise(self: *Self, new_capacity: usize) !void {
            if (self.capacity() >= new_capacity) return;

            const old_memory = self.allocatedSlice();
            const new_memory = try self.allocator.realloc(old_memory, new_capacity);
            self.items.ptr = new_memory.ptr;
            self.cap = new_memory.len;
        }

        /// Ensure that the queue can fit at least `additional_count` **more** item.
        pub fn ensureUnusedCapacity(self: *Self, additional_count: usize) !void {
            return self.ensureTotalCapacity(self.items.len + additional_count);
        }

        /// Reduce allocated capacity to `new_capacity`.
        pub fn shrinkAndFree(self: *Self, new_capacity: usize) void {
            assert(new_capacity <= self.cap);

            // Cannot shrink to smaller than the current queue size without invalidating the heap property
            assert(new_capacity >= self.items.len);

            const old_memory = self.allocatedSlice();
            const new_memory = self.allocator.realloc(old_memory, new_capacity) catch |e| switch (e) {
                error.OutOfMemory => { // no problem, capacity is still correct then.
                    return;
                },
            };

            self.items.ptr = new_memory.ptr;
            self.cap = new_memory.len;
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.items.len = 0;
        }

        pub fn clearAndFree(self: *Self) void {
            self.allocator.free(self.allocatedSlice());
            self.items.len = 0;
            self.cap = 0;
        }

        // TODO: make an other version that takes an index instead of searching for the element
        pub fn update(self: *Self, elem: T, new_elem: T) !void {
            const update_index = blk: {
                var idx: usize = 0;
                while (idx < self.items.len) : (idx += 1) {
                    const item = self.items[idx];
                    if (compareFn(self.context, item, elem) == .eq) break :blk idx;
                }
                return error.ElementNotFound;
            };
            const old_elem: T = self.items[update_index];
            self.items[update_index] = new_elem;
            setElemIndexFn(self.context, new_elem, update_index);
            switch (compareFn(self.context, new_elem, old_elem)) {
                .lt => siftUp(self, update_index),
                .gt => siftDown(self, update_index),
                .eq => {}, // Nothing to do as the items have equal priority
            }
        }

        pub const Iterator = struct {
            queue: *PriorityQueue(T, Context, compareFn),
            count: usize,

            pub fn next(it: *Iterator) ?T {
                if (it.count >= it.queue.items.len) return null;
                const out = it.count;
                it.count += 1;
                return it.queue.items[out];
            }

            pub fn reset(it: *Iterator) void {
                it.count = 0;
            }
        };

        /// Return an iterator that walks the queue without consuming
        /// it. The iteration order may differ from the priority order.
        /// Invalidated if the heap is modified.
        pub fn iterator(self: *Self) Iterator {
            return Iterator{
                .queue = self,
                .count = 0,
            };
        }

        fn dump(self: *Self) void {
            const print = std.debug.print;
            print("{{ ", .{});
            print("items: ", .{});
            for (self.items) |e| {
                print("{}, ", .{e});
            }
            print("array: ", .{});
            for (self.items) |e| {
                print("{}, ", .{e});
            }
            print("len: {} ", .{self.items.len});
            print("capacity: {}", .{self.cap});
            print(" }}\n", .{});
        }
    };
}
