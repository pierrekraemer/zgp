//! TODO: write docs for PointCloud
const PointCloud = @This();

const std = @import("std");
const assert = std.debug.assert;

const data = @import("../../utils/data.zig");
const DataContainer = data.DataContainer;
const DataGen = data.DataGen;
const Data = data.Data;

// ------------------------------------------------------------------------- //
// Basic types
// ------------------------------------------------------------------------- //

pub const Point = u32;

// ------------------------------------------------------------------------- //
// Fields
// ------------------------------------------------------------------------- //

allocator: std.mem.Allocator,

point_data: DataContainer,

// ------------------------------------------------------------------------- //
// Initialization, deinitialization
// ------------------------------------------------------------------------- //

pub fn init(pc: *PointCloud, allocator: std.mem.Allocator, io: std.Io) !void {
    pc.allocator = allocator;
    try pc.point_data.init(allocator, io);
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

/// A ParallelPointTaskRunner runs tasks on the points in parallel,
/// delegating work scheduling to `DataContainer.ParallelIndexTaskRunner`.
/// The `task` must expose a `run(self: *Self / *const Self, point: Point) void` function.
pub const ParallelPointTaskRunner = struct {
    dc_runner: DataContainer.ParallelIndexTaskRunner,

    pub fn init(pc: *const PointCloud) !ParallelPointTaskRunner {
        return .{ .dc_runner = try .init(&pc.point_data) };
    }

    pub fn initWithWorkerCount(pc: *const PointCloud, nb_workers: usize) !ParallelPointTaskRunner {
        return .{ .dc_runner = try .initWithWorkerCount(&pc.point_data, nb_workers) };
    }

    pub fn run(pptr: *const ParallelPointTaskRunner, task: anytype) !void {
        try pptr.dc_runner.run(task);
    }
};

/// A ParallelPointTaskRunnerWithContext runs tasks on the points in parallel,
/// giving each worker its own `Context` via `DataContainer.ParallelIndexTaskRunnerWithContext`.
/// `Context` must have an `initialized: bool` field and a `deinit(self: *Context) void` function.
/// The `task` must expose a `run(self: *Self / *const Self, ctx: *Context, point: Point) void` function.
pub fn ParallelPointTaskRunnerWithContext(comptime Context: type) type {
    return struct {
        dc_runner: DataContainer.ParallelIndexTaskRunnerWithContext(Context),

        pub fn init(pc: *const PointCloud) !@This() {
            return .{ .dc_runner = try .init(&pc.point_data) };
        }

        pub fn initWithWorkerCount(pc: *const PointCloud, nb_workers: usize) !@This() {
            return .{ .dc_runner = try .initWithWorkerCount(&pc.point_data, nb_workers) };
        }

        pub fn deinit(pptr: *@This()) void {
            pptr.dc_runner.deinit();
        }

        pub fn run(pptr: *@This(), task: anytype) !void {
            try pptr.dc_runner.run(task);
        }
    };
}

// ------------------------------------------------------------------------- //
// Point Data
// ------------------------------------------------------------------------- //

pub fn PointData(comptime T: type) type {
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
pub fn addData(pc: *PointCloud, comptime T: type, name: []const u8) !PointData(T) {
    return .{ .data = try pc.point_data.addData(T, name) };
}

/// Returns a handle to the data array of the type `T` if it exists with the given name, otherwise returns null.
pub fn getData(pc: *PointCloud, comptime T: type, name: []const u8) ?PointData(T) {
    return if (pc.point_data.getData(T, name)) |d| .{ .data = d } else null;
}

/// Returns a handle to the data array of the type `T` if it exists with the given name, otherwise creates a new data array of the type `T`,
/// and returns a handle to it, along with a boolean indicating whether the data array was newly created (true) or already existed (false).
pub fn getOrAddData(pc: *PointCloud, comptime T: type, name: []const u8) !struct { PointData(T), bool } {
    const d, const created = try pc.point_data.getOrAddData(T, name);
    return .{ .{ .data = d }, created };
}

/// Remove the given PointData.
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
