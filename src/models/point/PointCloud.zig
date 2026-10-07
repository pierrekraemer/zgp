//! TODO: write docs for PointCloud
const PointCloud = @This();

const std = @import("std");
const assert = std.debug.assert;

const zgp_log = std.log.scoped(.zgp);

const data = @import("../../utils/data.zig");
const DataContainer = data.DataContainer;
const DataGen = data.DataGen;
const Data = data.Data;

const BufferPool = @import("../../utils/BufferPool.zig").BufferPool;

// ------------------------------------------------------------------------- //
// Basic types
// ------------------------------------------------------------------------- //

pub const Point = u32;

// ------------------------------------------------------------------------- //
// Fields
// ------------------------------------------------------------------------- //

allocator: std.mem.Allocator,
point_buffer_pool: *BufferPool(Point), // the BufferPool is shared between PointClouds (owned by the PointCloudStore)

point_data: DataContainer,

// ------------------------------------------------------------------------- //
// Initialization, deinitialization
// ------------------------------------------------------------------------- //

pub fn init(pc: *PointCloud, allocator: std.mem.Allocator, point_buffer_pool: *BufferPool(Point)) !void {
    pc.allocator = allocator;
    pc.point_buffer_pool = point_buffer_pool;
    try pc.point_data.init(allocator);
}

pub fn deinit(pc: *PointCloud) void {
    pc.point_data.deinit();
}

pub fn clearRetainingCapacity(pc: *PointCloud) void {
    pc.point_data.clearRetainingCapacity();
}

// ------------------------------------------------------------------------- //
// Iterators
// ------------------------------------------------------------------------- //

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

// ------------------------------------------------------------------------- //
// Parallel Cell Task Runner
// ------------------------------------------------------------------------- //

/// A ParallelPointTaskRunner allows to run tasks on the points in parallel.
/// The `run` function takes a Task as an argument which is expected to expose a `run` function that takes a point as argument.
/// The main thread iterates over the points and fills buffers, in a double-buffering scheme.
/// Once the first group of buffers is filled, threads are spawned to run the task on these buffers, with a WaitGroup to track the completion of the tasks on this group of buffers.
/// Meanwhile, the main thread continues to iterate over the points and fills the other group of buffers.
/// Once the second group of buffers is filled, threads are spawned to run the task on these buffers, with a WaitGroup to track the completion of the tasks on this group of buffers.
/// This process is repeated until all points have been processed.
pub const ParallelPointTaskRunner = struct {
    const PointBuffer = BufferPool(Point).Buffer;
    const max_workers = 32;

    point_cloud: *PointCloud,
    iterator: PointIterator,
    // manage two groups of buffers to be able to run tasks on one group while filling the other
    buffers: [2][max_workers]PointBuffer,
    nb_workers: usize,
    // one Group per group of buffers to be able to wait for the completion of tasks on each group independently
    wg: [2]std.Io.Group,

    pub fn init(pc: *PointCloud) !@This() {
        return initWithWorkerCount(pc, try std.Thread.getCpuCount());
    }

    pub fn initWithWorkerCount(pc: *PointCloud, nb_workers: usize) !@This() {
        if (nb_workers == 0 or nb_workers > max_workers) {
            return error.InvalidWorkerCount;
        }

        var pctr: @This() = .{
            .point_cloud = pc,
            .iterator = pointIterator(pc),
            .buffers = undefined,
            .nb_workers = nb_workers,
            .wg = .{ .init, .init },
        };

        for (0..2) |group| {
            for (0..nb_workers) |worker| {
                pctr.buffers[group][worker] = try pc.point_buffer_pool.acquire();
            }
        }

        return pctr;
    }

    pub fn deinit(pctr: *ParallelPointTaskRunner) void {
        for (0..2) |i| {
            for (pctr.buffers[i][0..pctr.nb_workers]) |*buffer| {
                buffer.release() catch |err| {
                    zgp_log.warn("Failed to release buffer: {}", .{err});
                };
            }
        }
    }

    pub fn reset(pctr: *ParallelPointTaskRunner) void {
        pctr.iterator.reset();
    }

    fn runTaskOnBuffer(Task: type) fn (*const Task, []Point) void {
        return struct {
            fn f(task: *const Task, buf: []Point) void {
                for (buf) |cell| task.run(cell);
            }
        }.f;
    }

    // The `task` must expose a `run(self: *Self, point: Point) void` function
    pub fn run(pptr: *ParallelPointTaskRunner, io: std.Io, task: anytype) !void {
        var current_buf_group: usize = 0;
        var current_buf_index: usize = 0;
        var current_index_in_buffer: usize = 0;
        while (pptr.iterator.next()) |p| {
            // add point to current buffer of current buffer group
            pptr.buffers[current_buf_group][current_buf_index].data[current_index_in_buffer] = p;
            current_index_in_buffer += 1;
            // if the current buffer is full, run the task on it and switch to the next buffer of the current buffer group
            if (current_index_in_buffer == pptr.buffers[current_buf_group][current_buf_index].data.len) {
                pptr.wg[current_buf_group].async(
                    io,
                    runTaskOnBuffer(@TypeOf(task)),
                    .{ &task, pptr.buffers[current_buf_group][current_buf_index].data },
                );
                current_buf_index += 1;
                current_index_in_buffer = 0;
            }
            // if we have used all the buffers of the current buffer group, switch to the next buffer group
            if (current_buf_index == pptr.nb_workers) {
                current_buf_group = (current_buf_group + 1) % 2;
                // threads working on this buffer group are waited on before we can reuse the buffers of this group
                try pptr.wg[current_buf_group].await(io);
                current_buf_index = 0;
            }
        }
        // run the task on the last potentially partially filled buffer and wait for the threads to finish
        if (current_index_in_buffer > 0) {
            pptr.wg[current_buf_group].async(
                io,
                runTaskOnBuffer(@TypeOf(task)),
                .{ &task, pptr.buffers[current_buf_group][current_buf_index].data[0..current_index_in_buffer] },
            );
        }
        try pptr.wg[0].await(io);
        try pptr.wg[1].await(io);
    }
};

// ------------------------------------------------------------------------- //
// Cell Data
// ------------------------------------------------------------------------- //

pub fn CellData(comptime T: type) type {
    return struct {
        pub const DataType = T;

        data: *Data(T),

        fn ValuePtrType(comptime SelfType: type) type {
            if (@typeInfo(SelfType).pointer.is_const) {
                return *const T;
            } else {
                return *T;
            }
        }
        pub fn valuePtr(cd: @This(), p: Point) *T {
            return cd.data.valuePtr(p);
        }
        pub fn value(cd: @This(), p: Point) T {
            return cd.data.value(p);
        }

        pub fn name(cd: @This()) []const u8 {
            return cd.data.data_gen.name;
        }

        pub fn gen(cd: @This()) *DataGen {
            return &cd.data.data_gen;
        }
    };
}

/// Creates a new data array of the type `T`.
/// The `name` must be unique for the creation to succeed.
pub fn addData(pc: *PointCloud, comptime T: type, name: []const u8) !CellData(T) {
    return .{ .data = try pc.point_data.addData(T, name) };
}

/// Returns a handle to the data array of the type `T` if it exists with the given name, otherwise returns null.
pub fn getData(pc: *PointCloud, comptime T: type, name: []const u8) ?CellData(T) {
    return if (pc.point_data.getData(T, name)) |d| .{ .point_cloud = pc, .data = d } else null;
}

/// Returns a handle to the data array of the type `T` if it exists with the given name, otherwise creates a new data array of the type `T`,
/// and returns a handle to it, along with a boolean indicating whether the data array was newly created (true) or already existed (false).
pub fn getOrAddData(pc: *PointCloud, comptime T: type, name: []const u8) !struct { CellData(T), bool } {
    const d, const created = try pc.point_data.getOrAddData(T, name);
    return .{ .{ .data = d }, created };
}

/// Remove the given CellData.
pub fn removeData(pc: *PointCloud, cell_data: anytype) void {
    pc.point_data.removeData(cell_data.gen());
}

// ------------------------------------------------------------------------- //
// Cell Management
// ------------------------------------------------------------------------- //

pub fn addPoint(pc: *PointCloud) !Point {
    return pc.point_data.acquireIndex();
}

pub fn removePoint(pc: *PointCloud, p: Point) void {
    pc.point_data.releaseIndex(p);
}

pub fn nbPoints(pc: *const PointCloud) u32 {
    return pc.point_data.nbElements();
}
