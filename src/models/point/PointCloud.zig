//! TODO: write docs for PointCloud
const PointCloud = @This();

const std = @import("std");
const assert = std.debug.assert;

const AppContext = @import("../../main.zig").AppContext;

const data = @import("../../utils/data.zig");
const DataContainer = data.DataContainer;
const DataGen = data.DataGen;
const Data = data.Data;

const BufferPool = @import("../../utils/BufferPool.zig").BufferPool;

pub const Point = u32;

allocator: std.mem.Allocator,
point_buffer_pool: *BufferPool(Point),

point_data: *DataContainer,

pub fn init(allocator: std.mem.Allocator, point_buffer_pool: *BufferPool(Point)) !PointCloud {
    return .{
        .allocator = allocator,
        .point_buffer_pool = point_buffer_pool,
        .point_data = try .init(allocator),
    };
}

pub fn deinit(pc: *PointCloud) void {
    pc.point_data.deinit();
}

pub fn clearRetainingCapacity(pc: *PointCloud) void {
    pc.point_data.clearRetainingCapacity();
}

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

/// A ParallelPointTaskRunner allows to run tasks on the points in parallel.
/// The `run` function takes a Task as an argument which is expected to expose a `run` function that takes a point as argument.
/// The main thread iterates over the points and fills buffers, in a double-buffering scheme.
/// Once the first group of buffers is filled, threads are spawned to run the task on these buffers, with a WaitGroup to track the completion of the tasks on this group of buffers.
/// Meanwhile, the main thread continues to iterate over the points and fills the other group of buffers.
/// Once the second group of buffers is filled, threads are spawned to run the task on these buffers, with a WaitGroup to track the completion of the tasks on this group of buffers.
/// This process is repeated until all points have been processed.
pub const ParallelPointTaskRunner = struct {
    const PointBuffer = BufferPool(Point).Buffer;

    point_cloud: *PointCloud,
    iterator: PointIterator,
    // manage two groups of buffers to be able to run tasks on one group while filling the other
    buffers: [2][]PointBuffer,
    // one WaitGroup per group of buffers to be able to wait for the completion of tasks on each group independently
    wg: [2]std.Thread.WaitGroup,

    pub fn init(pc: *PointCloud) !ParallelPointTaskRunner {
        const cpu_count = try std.Thread.getCpuCount();
        return .{
            .point_cloud = pc,
            .iterator = pointIterator(pc),
            .buffers = .{
                blk: {
                    // acquire buffers from the pool (one buffer per thread) - first group
                    const buffers: []PointBuffer = try pc.allocator.alloc(PointBuffer, cpu_count);
                    for (buffers) |*buffer| {
                        buffer.* = try pc.point_buffer_pool.acquire();
                    }
                    break :blk buffers;
                },
                blk: {
                    // acquire buffers from the pool (one buffer per thread) - second group
                    const buffers: []PointBuffer = try pc.allocator.alloc(PointBuffer, cpu_count);
                    for (buffers) |*buffer| {
                        buffer.* = try pc.point_buffer_pool.acquire();
                    }
                    break :blk buffers;
                },
            },
            .wg = .{ .{}, .{} },
        };
    }

    pub fn deinit(pctr: *ParallelPointTaskRunner) void {
        for (0..2) |i| {
            for (pctr.buffers[i]) |*buffer| {
                buffer.release();
            }
            pctr.point_cloud.allocator.free(pctr.buffers[i]);
        }
    }

    pub fn reset(pctr: *ParallelPointTaskRunner) void {
        pctr.iterator.reset();
    }

    fn runTaskOnBuffer(task: anytype, buf: []Point) void {
        for (buf) |p| {
            task.run(p);
        }
    }

    // The `task` must expose a `run(self: *Self, point: Point) void` function
    pub fn run(pctr: *ParallelPointTaskRunner, app_ctx: *AppContext, task: anytype) !void {
        var current_buf_group: usize = 0;
        var current_buf_index: usize = 0;
        var current_index_in_buffer: usize = 0;
        while (pctr.iterator.next()) |p| {
            // add point to current buffer of current buffer group
            pctr.buffers[current_buf_group][current_buf_index].data[current_index_in_buffer] = p;
            current_index_in_buffer += 1;
            // if the current buffer is full, run the task on it and switch to the next buffer of the current buffer group
            if (current_index_in_buffer == pctr.buffers[current_buf_group][current_buf_index].data.len) {
                app_ctx.thread_pool.spawnWg(
                    &pctr.wg[current_buf_group],
                    runTaskOnBuffer,
                    .{ &task, pctr.buffers[current_buf_group][current_buf_index].data },
                );
                current_buf_index += 1;
                current_index_in_buffer = 0;
            }
            // if we have used all the buffers of the current buffer group, switch to the next buffer group
            if (current_buf_index == pctr.buffers[current_buf_group].len) {
                current_buf_group = (current_buf_group + 1) % 2;
                // threads working on this buffer group are waited on before we can reuse the buffers of this group
                pctr.wg[current_buf_group].wait();
                pctr.wg[current_buf_group].reset();
                current_buf_index = 0;
            }
        }
        // run the task on the last potentially partially filled buffer and wait for the threads to finish
        if (current_index_in_buffer > 0) {
            app_ctx.thread_pool.spawnWg(
                &pctr.wg[current_buf_group],
                runTaskOnBuffer,
                .{ &task, pctr.buffers[current_buf_group][current_buf_index].data[0..current_index_in_buffer] },
            );
        }
        pctr.wg[0].wait();
        pctr.wg[0].reset();
        pctr.wg[1].wait();
        pctr.wg[1].reset();
    }
};

pub fn CellData(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const DataType = T;

        point_cloud: *const PointCloud,
        data: *Data(T),

        pub fn value(self: Self, p: Point) T {
            return self.data.value(self.point_cloud.pointIndex(p));
        }
        pub fn valuePtr(self: Self, p: Point) *T {
            return self.data.valuePtr(self.point_cloud.pointIndex(p));
        }
        pub fn name(self: Self) []const u8 {
            return self.data.data_gen.name;
        }
        pub fn gen(self: Self) *DataGen {
            return &self.data.data_gen;
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

pub fn getOrAddData(pc: *PointCloud, comptime T: type, name: []const u8) !CellData(T) {
    return .{
        .point_cloud = pc,
        .data = try pc.point_data.getOrAddData(T, name),
    };
}

pub fn removeData(pc: *PointCloud, comptime T: type, cellData: CellData(T)) void {
    assert(cellData.point_cloud == pc);
    pc.point_data.removeData(&cellData.data.data_gen);
}

pub fn nbPoints(pc: *const PointCloud) u32 {
    return pc.point_data.nbElements();
}

pub fn addPoint(pc: *PointCloud) !Point {
    return pc.point_data.getIndex();
}

pub fn removePoint(pc: *PointCloud, p: Point) void {
    pc.point_data.releaseIndex(p);
}

pub fn pointIndex(_: *const PointCloud, p: Point) u32 {
    return p;
}
