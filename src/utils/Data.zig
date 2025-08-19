const std = @import("std");
const assert = std.debug.assert;

const typeId = @import("typeId.zig").typeId;

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
            .vtable = &.{
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

        gen: DataGen = undefined,
        data: std.SegmentedList(T, 32) = .{},

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

        pub fn rawIterator(self: *Self) std.SegmentedList(T, 32).Iterator {
            return self.data.iterator(0);
        }

        pub fn rawConstIterator(self: *const Self) std.SegmentedList(T, 32).ConstIterator {
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
            .markers = std.ArrayList(*Data(bool)).init(allocator),
            .available_markers_indices = std.ArrayList(u32).init(allocator),
            .free_indices = std.ArrayList(u32).init(allocator),
        };
        dc.is_active = try dc.addData(bool, "__is_active");
        dc.nb_refs = try dc.addData(u32, "__nb_refs");
        return dc;
    }

    pub fn deinit(self: *DataContainer) void {
        var it = self.datas.iterator();
        while (it.next()) |entry| {
            const data_gen = entry.value_ptr.*;
            data_gen.deinit();
        }
        for (self.markers.items) |marker| {
            marker.gen.deinit();
        }
        self.datas.deinit();
        self.markers.deinit();
        self.available_markers_indices.deinit();
        self.free_indices.deinit();
    }

    pub fn clearRetainingCapacity(self: *DataContainer) void {
        var it = self.datas.iterator();
        while (it.next()) |entry| {
            const data_gen = entry.value_ptr.*;
            data_gen.clearRetainingCapacity();
        }
        for (self.markers.items) |marker| {
            marker.clearRetainingCapacity();
        }
        self.free_indices.clearRetainingCapacity();
        self.capacity = 0;
    }

    pub fn addData(self: *DataContainer, comptime T: type, name: []const u8) !*Data(T) {
        const maybe_data_gen = self.datas.get(name);
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
        var data_arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer data_arena.deinit();
        const data = try data_arena.allocator().create(Data(T));
        data.* = .init;
        const owned_name = try data_arena.allocator().dupe(u8, name);
        data.gen = DataGen.init(T, owned_name, comptime typeId(T), data, self, data_arena);
        try data.ensureLength(self.capacity);
        try self.datas.put(owned_name, &data.gen);
        return data;
    }

    pub fn getData(self: *const DataContainer, comptime T: type, name: []const u8) ?*Data(T) {
        if (self.datas.get(name)) |data_gen| {
            if (data_gen.type_id == comptime typeId(T)) {
                // const data: *Data(T) = @alignCast(@fieldParentPtr("gen", data_gen));
                const data: *Data(T) = @alignCast(@ptrCast(data_gen.ptr));
                return data;
            }
            return null;
        } else {
            return null;
        }
    }

    pub fn removeData(self: *DataContainer, data_gen: *DataGen) void {
        assert(data_gen.container == self);
        if (self.datas.remove(data_gen.name)) {
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

    pub fn iterator(self: *const DataContainer) DataGenIterator {
        return .{
            .iterator = self.datas.iterator(),
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
                        const data: *Data(T) = @alignCast(@ptrCast(data_gen.ptr));
                        return data;
                    }
                }
                return null;
            }
        };
    }

    pub fn typedIterator(self: *const DataContainer, comptime T: type) DataIterator(T) {
        return .{
            .iterator = self.datas.iterator(),
        };
    }

    pub fn getMarker(self: *DataContainer) !*Data(bool) {
        const index = self.available_markers_indices.pop();
        if (index) |i| {
            var marker = self.markers.items[i];
            marker.fill(false); // reset the marker to false
            return marker;
        }
        // same as for addData, but the name is not used (the marker is not stored in the hashmap)
        var marker_arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer marker_arena.deinit();
        const marker = try marker_arena.allocator().create(Data(bool));
        marker.* = .init;
        marker.gen = DataGen.init(bool, "", comptime typeId(bool), marker, self, marker_arena);
        try marker.ensureLength(self.capacity);
        marker.fill(false); // marker is filled with false before use
        try self.markers.append(marker);
        return marker;
    }

    pub fn releaseMarker(self: *DataContainer, marker: *Data(bool)) void {
        assert(marker.gen.container == self);
        const marker_index = std.mem.indexOf(*Data(bool), self.markers.items, (&marker)[0..1]);
        if (marker_index) |i| {
            self.available_markers_indices.append(@intCast(i)) catch |err| {
                std.debug.print("Error releasing marker: {}\n", .{err});
            };
        }
    }

    pub fn newIndex(self: *DataContainer) !u32 {
        const index = self.free_indices.pop() orelse blk: {
            defer self.capacity += 1;
            break :blk self.capacity;
        };
        // should not be necessary when the index comes from free_indices
        var it = self.datas.iterator();
        while (it.next()) |entry| {
            const data_gen = entry.value_ptr.*;
            try data_gen.ensureLength(index + 1);
        }
        for (self.markers.items) |marker| {
            try marker.ensureLength(index + 1);
            marker.valuePtr(index).* = false; // reset the markers at this index
        }
        self.is_active.valuePtr(index).* = true; // after newIndex, the index is active
        self.nb_refs.valuePtr(index).* = 0; // but has no reference yet
        return index;
    }

    pub fn freeIndex(self: *DataContainer, index: u32) void {
        self.is_active.valuePtr(index).* = false;
        self.nb_refs.valuePtr(index).* = 0;
        self.free_indices.append(index) catch |err| {
            std.debug.print("Error freeing index {}: {}\n", .{ index, err });
        };
    }

    pub fn refIndex(self: *DataContainer, index: u32) void {
        self.nb_refs.valuePtr(index).* += 1;
    }

    pub fn unrefIndex(self: *DataContainer, index: u32) void {
        self.nb_refs.valuePtr(index).* -= 1;
        if (self.nb_refs.valuePtr(index).* == 0) {
            self.freeIndex(index);
        }
    }

    pub fn nbElements(self: *const DataContainer) u32 {
        return @intCast(self.capacity - self.free_indices.items.len);
    }

    pub fn firstIndex(self: *const DataContainer) u32 {
        var index: u32 = 0;
        return while (index < self.capacity) : (index += 1) {
            if (self.isActiveIndex(index)) {
                break index;
            }
        } else self.capacity;
    }

    pub fn nextIndex(self: *const DataContainer, index: u32) u32 {
        var next: u32 = index + 1;
        return while (next < self.capacity) : (next += 1) {
            if (self.isActiveIndex(next)) {
                break next;
            }
        } else self.capacity;
    }

    /// lastIndex actually returns one past the last valid index.
    pub fn lastIndex(self: *const DataContainer) u32 {
        return self.capacity;
    }

    pub fn isActiveIndex(self: *const DataContainer, index: u32) bool {
        return self.is_active.valuePtr(index).*;
    }
};
