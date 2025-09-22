const std = @import("std");
const assert = std.debug.assert;

const SegmentedList = @import("SegmentedList.zig").SegmentedList;

const typeId = @import("types.zig").typeId;

pub const DataGen = struct {
    name: []const u8,
    type_id: *const anyopaque, // typeId of T in the Data(T)
    arena: std.heap.ArenaAllocator, // used for data allocation by the Data(T)
    ptr: *anyopaque, // pointer to the Data(T)
    container: *DataContainer, // pointer to the DataContainer that owns this Data(T)
    vtable: *const VTable,

    const VTable = struct {
        ensureLength: *const fn (ptr: *anyopaque, size: u32) anyerror!void,
        clearRetainingCapacity: *const fn (ptr: *anyopaque) void,
    };

    pub fn init(
        comptime T: type,
        name: []const u8,
        type_id: *const anyopaque,
        pointer: *Data(T),
        container: *DataContainer,
        arena: std.heap.ArenaAllocator,
    ) DataGen {
        const gen = struct {
            fn ensureLength(ptr: *anyopaque, size: u32) !void {
                const impl: *Data(T) = @ptrCast(@alignCast(ptr));
                try impl.ensureLength(size);
            }
            fn clearRetainingCapacity(ptr: *anyopaque) void {
                const impl: *Data(T) = @ptrCast(@alignCast(ptr));
                impl.clearRetainingCapacity();
            }
        };

        return .{
            .name = name,
            .type_id = type_id,
            .arena = arena,
            .ptr = pointer,
            .container = container,
            .vtable = comptime &.{
                .ensureLength = gen.ensureLength,
                .clearRetainingCapacity = gen.clearRetainingCapacity,
            },
        };
    }

    pub fn deinit(self: *DataGen) void {
        self.arena.deinit();
    }

    pub inline fn ensureLength(self: *DataGen, size: u32) !void {
        try self.vtable.ensureLength(self.ptr, size);
    }

    pub inline fn clearRetainingCapacity(self: *DataGen) void {
        self.vtable.clearRetainingCapacity(self.ptr);
    }
};

pub fn Data(comptime T: type) type {
    return struct {
        const Self = @This();

        // TODO: evaluate if SegmentedList is the right choice here (vs a simple ArrayList)
        const DataSegmentedList = SegmentedList(T, 512);

        gen: DataGen = undefined,
        data: DataSegmentedList = .{},

        const init: Self = .{};

        /// Expose the Arena of the Data to the user.
        /// Useful when the data type T needs to allocate memory.
        /// The user should not use the arena for anything else.
        /// The Arena is freed on DataGen deinit.
        pub fn arena(self: *Self) std.mem.Allocator {
            return self.gen.arena.allocator();
        }

        pub fn ensureLength(self: *Self, size: u32) !void {
            while (self.data.len < size) {
                _ = try self.data.addOne(self.arena());
            }
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.data.clearRetainingCapacity();
        }

        fn ValuePtrType(comptime SelfType: type) type {
            if (@typeInfo(SelfType).pointer.is_const) {
                return *const T;
            } else {
                return *T;
            }
        }

        pub fn valuePtr(self: anytype, index: u32) ValuePtrType(@TypeOf(self)) {
            return self.data.at(index);
        }

        pub fn value(self: *Self, index: u32) T {
            return self.data.at(index).*;
        }

        pub fn fill(self: *Self, val: T) void {
            var it = self.data.iterator(0);
            while (it.next()) |element| {
                element.* = val;
            }
        }

        pub fn rawLength(self: *const Self) usize {
            return self.data.len;
        }

        pub fn rawSize(self: *const Self) usize {
            return self.data.len * @sizeOf(T);
        }

        pub fn rawIterator(self: *Self) DataSegmentedList.Iterator {
            return self.data.iterator(0);
        }

        pub fn rawConstIterator(self: *const Self) DataSegmentedList.ConstIterator {
            return self.data.constIterator(0);
        }

        pub fn nbElements(self: *const Self) usize {
            return self.gen.container.nbElements();
        }

        pub const Iterator = BaseIterator(*Self, *T);
        pub const ConstIterator = BaseIterator(*const Self, *const T);
        fn BaseIterator(comptime SelfPtr: type, comptime ElementPtr: type) type {
            return struct {
                data: SelfPtr,
                index: u32,
                pub fn next(it: *@This()) ?ElementPtr {
                    if (it.index == it.data.gen.container.lastIndex()) {
                        return null;
                    }
                    defer it.index = it.data.gen.container.nextIndex(it.index);
                    return it.data.data.at(it.index);
                }
                pub fn reset(it: *@This()) void {
                    it.index = it.data.gen.container.firstIndex();
                }
            };
        }

        pub fn iterator(self: *Self) Iterator {
            return .{
                .data = self,
                .index = self.gen.container.firstIndex(),
            };
        }

        pub fn constIterator(self: *const Self) ConstIterator {
            return .{
                .data = self,
                .index = self.gen.container.firstIndex(),
            };
        }
    };
}

pub const DataContainer = struct {
    allocator: std.mem.Allocator,
    datas: std.StringHashMap(*DataGen),
    markers: std.ArrayList(*Data(bool)),
    available_markers_indices: std.ArrayList(u32),
    free_indices: std.ArrayList(u32),
    capacity: u32 = 0,
    is_active: *Data(bool) = undefined,
    nb_refs: *Data(u32) = undefined,

    pub fn init(allocator: std.mem.Allocator) !DataContainer {
        var dc: DataContainer = .{
            .allocator = allocator,
            .datas = std.StringHashMap(*DataGen).init(allocator),
            .markers = .empty,
            .available_markers_indices = .empty,
            .free_indices = .empty,
        };
        dc.is_active = try dc.addData(bool, "__is_active");
        dc.nb_refs = try dc.addData(u32, "__nb_refs");
        return dc;
    }

    pub fn deinit(dc: *DataContainer) void {
        var it = dc.datas.iterator();
        while (it.next()) |entry| {
            const data_gen = entry.value_ptr.*;
            data_gen.deinit();
        }
        for (dc.markers.items) |marker| {
            marker.gen.deinit();
        }
        dc.datas.deinit();
        dc.markers.deinit(dc.allocator);
        dc.available_markers_indices.deinit(dc.allocator);
        dc.free_indices.deinit(dc.allocator);
    }

    pub fn clearRetainingCapacity(dc: *DataContainer) void {
        var it = dc.datas.iterator();
        while (it.next()) |entry| {
            const data_gen = entry.value_ptr.*;
            data_gen.clearRetainingCapacity();
        }
        for (dc.markers.items) |marker| {
            marker.clearRetainingCapacity();
        }
        dc.free_indices.clearRetainingCapacity();
        dc.capacity = 0;
    }

    pub fn addData(dc: *DataContainer, comptime T: type, name: []const u8) !*Data(T) {
        const maybe_data_gen = dc.datas.get(name);
        if (maybe_data_gen) |_| {
            return error.DataNameAlreadyExists;
        }
        // The arena created for the Data is used to allocate:
        // - the Data(T) struct itself,
        // - an owned copy of the name of the Data,
        // It is then passed to the DataGen of the Data.
        // The Data(T) then:
        // - use it to allocate its SegmentedList(T, 32) data,
        // - exposes it to allow the user to use it if T needs to allocate memory.
        var data_arena = std.heap.ArenaAllocator.init(dc.allocator);
        errdefer data_arena.deinit();
        const data = try data_arena.allocator().create(Data(T));
        data.* = .init;
        const owned_name = try data_arena.allocator().dupe(u8, name);
        data.gen = DataGen.init(T, owned_name, comptime typeId(T), data, dc, data_arena);
        try data.ensureLength(dc.capacity);
        try dc.datas.put(owned_name, &data.gen);
        return data;
    }

    pub fn getData(dc: *const DataContainer, comptime T: type, name: []const u8) ?*Data(T) {
        if (dc.datas.get(name)) |data_gen| {
            if (data_gen.type_id == comptime typeId(T)) {
                // const data: *Data(T) = @alignCast(@fieldParentPtr("gen", data_gen));
                const data: *Data(T) = @ptrCast(@alignCast(data_gen.ptr));
                return data;
            }
            return null;
        } else {
            return null;
        }
    }

    pub fn removeData(dc: *DataContainer, data_gen: *DataGen) void {
        assert(data_gen.container == dc);
        if (dc.datas.remove(data_gen.name)) {
            data_gen.deinit();
        }
    }

    const DataGenIterator = struct {
        iterator: std.StringHashMap(*DataGen).Iterator,
        pub fn next(it: *@This()) ?*DataGen {
            if (it.iterator.next()) |entry| {
                return entry.value_ptr.*;
            }
            return null;
        }
    };

    pub fn iterator(dc: *const DataContainer) DataGenIterator {
        return .{
            .iterator = dc.datas.iterator(),
        };
    }

    fn DataIterator(comptime T: type) type {
        return struct {
            iterator: std.StringHashMap(*DataGen).Iterator,
            pub fn next(it: *@This()) ?*Data(T) {
                while (it.iterator.next()) |entry| {
                    const data_gen = entry.value_ptr.*;
                    if (data_gen.type_id == comptime typeId(T)) {
                        // const data: *Data(T) = @alignCast(@fieldParentPtr("gen", data_gen));
                        const data: *Data(T) = @ptrCast(@alignCast(data_gen.ptr));
                        return data;
                    }
                }
                return null;
            }
        };
    }

    pub fn typedIterator(dc: *const DataContainer, comptime T: type) DataIterator(T) {
        return .{
            .iterator = dc.datas.iterator(),
        };
    }

    pub fn getMarker(dc: *DataContainer) !*Data(bool) {
        const index = dc.available_markers_indices.pop();
        if (index) |i| {
            var marker = dc.markers.items[i];
            marker.fill(false); // reset the marker to false
            return marker;
        }
        // same as for addData, but the name is not used (the marker is not stored in the hashmap)
        var marker_arena = std.heap.ArenaAllocator.init(dc.allocator);
        errdefer marker_arena.deinit();
        const marker = try marker_arena.allocator().create(Data(bool));
        marker.* = .init;
        marker.gen = DataGen.init(bool, "", comptime typeId(bool), marker, dc, marker_arena);
        try marker.ensureLength(dc.capacity);
        marker.fill(false); // marker is filled with false before use
        try dc.markers.append(dc.allocator, marker);
        return marker;
    }

    pub fn releaseMarker(dc: *DataContainer, marker: *Data(bool)) void {
        assert(marker.gen.container == dc);
        const marker_index = std.mem.indexOfScalar(*Data(bool), dc.markers.items, marker);
        if (marker_index) |i| {
            dc.available_markers_indices.append(dc.allocator, @intCast(i)) catch |err| {
                std.debug.print("Error releasing marker: {}\n", .{err});
            };
        }
    }

    pub fn newIndex(dc: *DataContainer) !u32 {
        const index = if (dc.free_indices.pop()) |index| blk: {
            for (dc.markers.items) |marker| {
                marker.valuePtr(index).* = false; // reset the markers at this index
            }
            break :blk index;
        } else blk: {
            const index = dc.capacity;
            dc.capacity += 1;
            for (dc.markers.items) |marker| {
                try marker.ensureLength(dc.capacity);
                marker.valuePtr(index).* = false; // reset the markers at this index
            }
            var datas_it = dc.datas.iterator();
            while (datas_it.next()) |entry| {
                try entry.value_ptr.*.ensureLength(dc.capacity);
            }
            try dc.is_active.ensureLength(dc.capacity);
            try dc.nb_refs.ensureLength(dc.capacity);
            break :blk index;
        };
        dc.is_active.valuePtr(index).* = true; // index returned by newIndex is active
        dc.nb_refs.valuePtr(index).* = 0; // but has no reference yet
        return index;
    }

    pub fn freeIndex(dc: *DataContainer, index: u32) void {
        assert(index < dc.capacity);
        assert(dc.is_active.value(index));
        dc.is_active.valuePtr(index).* = false;
        dc.nb_refs.valuePtr(index).* = 0;
        dc.free_indices.append(dc.allocator, index) catch |err| {
            std.debug.print("Error freeing index {}: {}\n", .{ index, err });
        };
    }

    pub fn refIndex(dc: *DataContainer, index: u32) void {
        assert(index < dc.capacity);
        assert(dc.is_active.value(index));
        dc.nb_refs.valuePtr(index).* += 1;
    }

    pub fn unrefIndex(dc: *DataContainer, index: u32) void {
        assert(index < dc.capacity);
        assert(dc.is_active.value(index));
        dc.nb_refs.valuePtr(index).* -= 1;
        if (dc.nb_refs.value(index) == 0) {
            dc.freeIndex(index);
        }
    }

    pub fn nbElements(dc: *const DataContainer) u32 {
        return @intCast(dc.capacity - dc.free_indices.items.len);
    }

    pub fn firstIndex(dc: *const DataContainer) u32 {
        var index: u32 = 0;
        return while (index < dc.capacity) : (index += 1) {
            if (dc.isActiveIndex(index)) {
                break index;
            }
        } else dc.capacity;
    }

    pub fn nextIndex(dc: *const DataContainer, index: u32) u32 {
        var next: u32 = index + 1;
        return while (next < dc.capacity) : (next += 1) {
            if (dc.isActiveIndex(next)) {
                break next;
            }
        } else dc.capacity;
    }

    /// lastIndex actually returns one past the last valid index.
    pub fn lastIndex(dc: *const DataContainer) u32 {
        return dc.capacity;
    }

    pub fn isActiveIndex(dc: *const DataContainer, index: u32) bool {
        return index < dc.capacity and dc.is_active.valuePtr(index).*;
    }
};
