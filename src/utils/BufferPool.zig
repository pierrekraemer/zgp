const std = @import("std");

/// A thread-safe pool of generic buffers.
pub fn BufferPool(comptime T: type) type {
    return struct {
        const Self = @This();

        /// A handle to a buffer borrowed from the pool.
        /// `release()` must be called on this handle to return the buffer to the pool.
        pub const Buffer = struct {
            data: []T,
            pool: *Self,

            /// Returns this buffer to the pool.
            /// The data slice is invalidated after this call.
            pub fn release(self: *Buffer) void {
                self.pool.release(self.data);
                self.data = &.{};
            }
        };

        allocator: std.mem.Allocator,
        mutex: std.Thread.Mutex,
        buffer_size: usize,
        max_pool_size: usize,

        /// Stack of free buffers available for reuse.
        free_list: std.ArrayList([]T),

        /// Initialize a new BufferPool.
        /// `buffer_size`: The number of items of type T in each buffer.
        /// `max_pool_size`: The maximum number of idle buffers to keep in the pool.
        pub fn init(allocator: std.mem.Allocator, buffer_size: usize, max_pool_size: usize, init_pool_size: usize) !Self {
            var free_list: std.ArrayList([]T) = try .initCapacity(allocator, init_pool_size);
            errdefer {
                for (free_list.items) |buf| allocator.free(buf);
                free_list.deinit(allocator);
            }
            // Pre-allocate the requested number of buffers
            var i: usize = 0;
            while (i < init_pool_size) : (i += 1) {
                const buf = try allocator.alloc(T, buffer_size);
                free_list.appendAssumeCapacity(buf);
            }
            return Self{
                .allocator = allocator,
                .mutex = .{},
                .buffer_size = buffer_size,
                .max_pool_size = max_pool_size,
                .free_list = free_list,
            };
        }

        /// Deinitialize the pool and free all pooled buffers.
        /// Note: This does not free buffers currently acquired by users of the pool.
        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            for (self.free_list.items) |buf| {
                self.allocator.free(buf);
            }
            self.free_list.deinit(self.allocator);
        }

        /// Acquire a buffer from the pool.
        /// If the pool is empty, a new buffer is allocated.
        pub fn acquire(self: *Self) !Buffer {
            self.mutex.lock();
            // Try to pop from free list first
            if (self.free_list.pop()) |buf| {
                self.mutex.unlock();
                // Reset memory if needed? Usually generic buffers are assumed "dirty"
                return Buffer{ .data = buf, .pool = self };
            }
            self.mutex.unlock();
            // Allocate new buffer if none available (outside lock to reduce contention)
            const buf = try self.allocator.alloc(T, self.buffer_size);
            return Buffer{ .data = buf, .pool = self };
        }

        /// Internal function to return a buffer to the free list.
        pub fn release(self: *Self, buf: []T) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            // If we have hit the max capacity of the pool, discard the buffer
            if (self.free_list.items.len >= self.max_pool_size) {
                self.allocator.free(buf);
            } else {
                // Return to stack for reuse
                self.free_list.append(self.allocator, buf) catch {
                    self.allocator.free(buf);
                };
            }
        }
    };
}
