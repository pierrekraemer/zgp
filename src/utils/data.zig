const std = @import("std");
const assert = std.debug.assert;

const typeId = @import("types.zig").typeId;

pub const invalid_index = std.math.maxInt(u32);

pub const DataGen = struct {
    name: []const u8,
    container: *DataContainer, // pointer to the DataContainer that owns this Data(T)
    type_id: *const anyopaque, // typeId of T in the Data(T)
    vtable: *const VTable,

    const VTable = struct {
        deinit: *const fn (data_gen: *DataGen) void,
        ensureSize: *const fn (data_gen: *DataGen, size: usize) anyerror!void,
        clearRetainingCapacity: *const fn (data_gen: *DataGen) void,
        clone: *const fn (data_gen: *const DataGen, name: []const u8, container: *DataContainer) anyerror!*DataGen,
    };

    pub fn deinit(data_gen: *DataGen) void {
        data_gen.vtable.deinit(data_gen);
    }
    pub fn ensureSize(data_gen: *DataGen, size: usize) !void {
        try data_gen.vtable.ensureSize(data_gen, size);
    }
    pub fn clearRetainingCapacity(data_gen: *DataGen) void {
        data_gen.vtable.clearRetainingCapacity(data_gen);
    }
    pub fn clone(data_gen: *const DataGen, name: []const u8, container: *DataContainer) !*DataGen {
        return try data_gen.vtable.clone(data_gen, name, container);
    }
};

pub fn Data(comptime T: type) type {
    return struct {
        const Self = @This();

        data_gen: DataGen,
        data: std.ArrayList(T),

        pub fn init(self: *Self, name: []const u8, container: *DataContainer) void {
            self.data_gen = .{
                .name = name,
                .container = container,
                .type_id = typeId(T),
                .vtable = &.{
                    .deinit = deinit,
                    .ensureSize = ensureSize,
                    .clearRetainingCapacity = clearRetainingCapacity,
                    .clone = clone,
                },
            };
            self.data = .empty;
        }

        /// Part of the DataGen interface.
        pub fn deinit(data_gen: *DataGen) void {
            const self: *Data(T) = @alignCast(@fieldParentPtr("data_gen", data_gen));
            self.data.deinit(self.data_gen.container.allocator);
            self.data_gen.container.allocator.destroy(self); // created in DataContainer.addData
        }

        /// Part of the DataGen interface.
        pub fn ensureSize(data_gen: *DataGen, size: usize) !void {
            const self: *Data(T) = @alignCast(@fieldParentPtr("data_gen", data_gen));
            if (self.data.items.len >= size) {
                return;
            }
            try self.data.ensureTotalCapacity(self.data_gen.container.allocator, size);
            _ = self.data.addManyAsSliceAssumeCapacity(size -| self.data.items.len);
        }

        /// Part of the DataGen interface.
        pub fn clearRetainingCapacity(data_gen: *DataGen) void {
            const self: *Data(T) = @alignCast(@fieldParentPtr("data_gen", data_gen));
            self.data.clearRetainingCapacity();
        }

        /// Part of the DataGen interface.
        pub fn clone(data_gen: *const DataGen, name: []const u8, container: *DataContainer) !*DataGen {
            const self: *const Data(T) = @alignCast(@fieldParentPtr("data_gen", data_gen));
            const cloned_data = try container.allocator.create(Data(T));
            cloned_data.init(name, container);
            cloned_data.data = try self.data.clone(container.allocator);
            return &cloned_data.data_gen;
        }

        fn ValuePtrType(comptime SelfType: type) type {
            if (@typeInfo(SelfType).pointer.is_const) {
                return *const T;
            } else {
                return *T;
            }
        }

        pub fn valuePtr(self: anytype, index: u32) ValuePtrType(@TypeOf(self)) {
            return &self.data.items[index];
        }

        pub fn value(self: *Self, index: u32) T {
            return self.data.items[index];
        }

        pub fn fill(self: *Self, val: T) void {
            for (self.data.items) |*element| {
                element.* = val;
            }
        }

        pub fn fillInactive(self: *Self, val: T) void {
            for (self.data.items, 0..) |*element, index| {
                if (!self.data_gen.container.isActiveIndexAssumeSize(@intCast(index))) {
                    element.* = val;
                }
            }
        }

        pub fn copyFrom(self: *Self, src: *const Self) void {
            assert(self.data_gen.type_id == src.data_gen.type_id);
            assert(self.data.items.len == src.data.items.len);
            @memcpy(self.data.items, src.data.items);
        }

        pub fn minValue(
            self: *Self,
            context: anytype,
            comptime compareFn: fn (ctx: @TypeOf(context), a: T, b: T) std.math.Order,
        ) T {
            assert(self.nbElements() > 0);
            var best = self.value(self.data_gen.container.firstIndex());
            var it = self.constIterator();
            while (it.next()) |element| {
                if (compareFn(context, element.*, best) == .lt) {
                    best = element.*;
                }
            }
            return best;
        }

        pub fn maxValue(
            self: *Self,
            context: anytype,
            comptime compareFn: fn (ctx: @TypeOf(context), a: T, b: T) std.math.Order,
        ) T {
            assert(self.nbElements() > 0);
            var best = self.value(self.data_gen.container.firstIndex());
            var it = self.constIterator();
            while (it.next()) |element| {
                if (compareFn(context, element.*, best) == .gt) {
                    best = element.*;
                }
            }
            return best;
        }

        pub fn minMaxValues(
            self: *Self,
            context: anytype,
            comptime compareFn: fn (ctx: @TypeOf(context), a: T, b: T) std.math.Order,
        ) struct { T, T } {
            assert(self.nbElements() > 0);
            var min = self.value(self.data_gen.container.firstIndex());
            var max = min;
            var it = self.constIterator();
            while (it.next()) |element| {
                if (compareFn(context, element.*, min) == .lt) {
                    min = element.*;
                }
                if (compareFn(context, element.*, max) == .gt) {
                    max = element.*;
                }
            }
            return .{ min, max };
        }

        /// Return the number of elements in the raw data storage.
        /// This is different from nbElements() which returns the number of elements
        /// corresponding to active indices in the DataContainer.
        pub fn rawLength(self: *const Self) usize {
            return self.data.items.len;
        }

        /// Return the size in bytes of the raw data stored in this Data.
        pub fn rawSize(self: *const Self) usize {
            return self.data.items.len * @sizeOf(T);
        }

        pub const RawIterator = BaseRawIterator(*Self, *T);
        pub const ConstRawIterator = BaseRawIterator(*const Self, *const T);
        fn BaseRawIterator(comptime SelfPtr: type, comptime ElementPtr: type) type {
            return struct {
                data: SelfPtr,
                index: u32,
                pub fn next(it: *@This()) ?ElementPtr {
                    if (it.index == it.data.data.items.len) {
                        return null;
                    }
                    defer it.index = it.index + 1;
                    return &it.data.data.items[it.index];
                }
                pub fn reset(it: *@This()) void {
                    it.index = 0;
                }
            };
        }

        pub fn rawIterator(self: *Self) RawIterator {
            return .{
                .data = self,
                .index = 0,
            };
        }

        pub fn rawConstIterator(self: *const Self) ConstRawIterator {
            return .{
                .data = self,
                .index = 0,
            };
        }

        pub fn nbElements(self: *const Self) usize {
            return self.data_gen.container.nbElements();
        }

        pub const Iterator = BaseIterator(*Self, *T);
        pub const ConstIterator = BaseIterator(*const Self, *const T);
        fn BaseIterator(comptime SelfPtr: type, comptime ElementPtr: type) type {
            return struct {
                data: SelfPtr,
                index: u32,
                pub fn next(it: *@This()) ?ElementPtr {
                    if (it.index == it.data.data_gen.container.lastIndex()) {
                        return null;
                    }
                    defer it.index = it.data.data_gen.container.nextIndex(it.index);
                    return &it.data.data.items[it.index];
                }
                pub fn reset(it: *@This()) void {
                    it.index = it.data.data_gen.container.firstIndex();
                }
            };
        }

        pub fn iterator(self: *Self) Iterator {
            return .{
                .data = self,
                .index = self.data_gen.container.firstIndex(),
            };
        }

        pub fn constIterator(self: *const Self) ConstIterator {
            return .{
                .data = self,
                .index = self.data_gen.container.firstIndex(),
            };
        }
    };
}

pub const DataContainer = struct {
    allocator: std.mem.Allocator,
    datas: std.StringHashMapUnmanaged(*DataGen),
    markers: std.ArrayList(*Data(bool)),
    available_markers: std.ArrayList(*Data(bool)),
    // size is the maximum index that has been allocated so far
    // to get the number of current active elements, use nbElements()
    size: u32,
    // the is_active data is used to mark indices as active or inactive
    // active indices are currently used and processed by iterators
    // inactive indices are skipped by iterators, and will be used upon calls to getIndex
    is_active: *Data(bool),
    // the nb_refs data is used by the refIndex/unrefIndex API
    // each time an index is activated and returned by getIndex, its nb_refs is set to 0
    // each time an active index is refed, its nb_refs is incremented
    // each time an active index is unreffed, if its nb_refs reaches 0, it becomes inactive and is added to the list of inactive indices
    nb_refs: *Data(u32),
    // the list of inactive indices is implemented as a linked list using the nb_refs data as a backing store (which is not used on inactive indices)
    // when an index is released, the first_inactive_index is set to this index
    // and its nb_refs is set to the previous first_inactive_index
    first_inactive_index: u32,
    // nb_inactive_indices is used to quickly check if there are any inactive indices and quickly compute nbElements
    nb_inactive_indices: u32,

    pub fn init(dc: *DataContainer, allocator: std.mem.Allocator) !void {
        dc.allocator = allocator;
        dc.datas = .empty;
        dc.markers = try .initCapacity(allocator, 16);
        dc.available_markers = try .initCapacity(allocator, 16);
        dc.size = 0;
        dc.is_active = try dc.addData(bool, "__is_active");
        dc.nb_refs = try dc.addData(u32, "__nb_refs");
        dc.first_inactive_index = invalid_index;
        dc.nb_inactive_indices = 0;
    }

    pub fn initFrom(dst: *DataContainer, src: *const DataContainer, copy_data: bool, allocator: std.mem.Allocator) !void {
        dst.allocator = allocator;
        dst.datas = .empty;
        dst.markers = try .initCapacity(dst.allocator, 16);
        dst.available_markers = try .initCapacity(dst.allocator, 16);
        dst.size = src.size;
        if (copy_data) {
            // if copy_data is true, all the Data(T) are cloned
            // which includes the internal is_active & nb_refs data, which are then recovered
            var src_it = src.datas.iterator();
            while (src_it.next()) |src_entry| {
                const dst_owned_name: [:0]const u8 = try dst.allocator.dupeZ(u8, src_entry.key_ptr.*); // duplicate name to own the hashmap key
                errdefer dst.allocator.free(dst_owned_name);
                const dst_data_gen = try src_entry.value_ptr.*.clone(dst_owned_name, dst); // clone the src DataGen, which also clones the Data(T)
                errdefer dst_data_gen.deinit(); // DataGen deinit calls Data(T) deinit, which also destroys the Data(T)
                try dst.datas.put(dst.allocator, dst_owned_name, dst_data_gen);
            }
            dst.is_active = dst.getData(bool, "__is_active").?; // recover the is_active data from the cloned datas hashmap
            dst.nb_refs = dst.getData(u32, "__nb_refs").?; // recover the nb_refs data from the cloned datas hashmap
        } else {
            // else, only the structure of the DataContainer is copied
            // and the internal is_active & nb_refs data are created and copied from the src ones
            dst.is_active = try dst.addData(bool, "__is_active");
            dst.is_active.copyFrom(src.is_active);
            dst.nb_refs = try dst.addData(u32, "__nb_refs");
            dst.nb_refs.copyFrom(src.nb_refs);
        }
        dst.first_inactive_index = src.first_inactive_index;
        dst.nb_inactive_indices = src.nb_inactive_indices;
    }

    pub fn deinit(dc: *DataContainer) void {
        var it = dc.datas.iterator();
        while (it.next()) |entry| {
            const name: [:0]const u8 = @ptrCast(entry.key_ptr.*); // the name is a null-terminated string (dupeZ in addData)
            dc.allocator.free(name); // free the name
            entry.value_ptr.*.deinit(); // DataGen deinit calls Data(T) deinit, which also destroys the Data(T)
        }
        for (dc.markers.items) |marker| {
            marker.data_gen.deinit();
        }
        dc.datas.deinit(dc.allocator);
        dc.markers.deinit(dc.allocator);
        dc.available_markers.deinit(dc.allocator);
    }

    pub fn clearRetainingCapacity(dc: *DataContainer) void {
        var it = dc.datas.iterator();
        while (it.next()) |entry| {
            const data_gen = entry.value_ptr.*;
            data_gen.clearRetainingCapacity();
        }
        for (dc.markers.items) |marker| {
            marker.data_gen.clearRetainingCapacity();
        }
        dc.first_inactive_index = invalid_index;
        dc.nb_inactive_indices = 0;
        dc.size = 0;
    }

    pub fn addData(dc: *DataContainer, comptime T: type, name: []const u8) !*Data(T) {
        if (dc.datas.contains(name)) {
            return error.DataNameAlreadyExists;
        }

        const owned_name = try dc.allocator.dupeZ(u8, name); // duplicate name to own the hashmap key
        errdefer dc.allocator.free(owned_name);

        const data = try dc.allocator.create(Data(T));
        data.init(owned_name, dc);
        errdefer data.data_gen.deinit(); // DataGen deinit calls Data(T) deinit, which also destroys the Data(T)

        try data.data_gen.ensureSize(dc.size);
        try dc.datas.put(dc.allocator, owned_name, &data.data_gen);
        return data;
    }

    pub fn getData(dc: *const DataContainer, comptime T: type, name: []const u8) ?*Data(T) {
        if (dc.datas.get(name)) |data_gen| {
            if (data_gen.type_id == comptime typeId(T)) {
                return @alignCast(@fieldParentPtr("data_gen", data_gen));
            }
            return null;
        } else {
            return null;
        }
    }

    pub fn getOrAddData(dc: *DataContainer, comptime T: type, name: []const u8) !*Data(T) {
        if (dc.getData(T, name)) |data| {
            return data;
        } else {
            return try dc.addData(T, name);
        }
    }

    pub fn removeData(dc: *DataContainer, data_gen: *DataGen) void {
        assert(data_gen.container == dc);
        if (dc.datas.remove(data_gen.name)) {
            const name: [:0]const u8 = @ptrCast(data_gen.name); // the name is a null-terminated string (dupeZ in addData)
            dc.allocator.free(name); // free the name
            data_gen.deinit(); // DataGen deinit calls Data(T) deinit, which also destroys the Data(T)
        }
    }

    const DataGenIterator = struct {
        iterator: std.StringHashMapUnmanaged(*DataGen).Iterator,
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
            iterator: std.StringHashMapUnmanaged(*DataGen).Iterator,
            pub fn next(it: *@This()) ?*Data(T) {
                while (it.iterator.next()) |entry| {
                    const data_gen = entry.value_ptr.*;
                    if (data_gen.type_id == comptime typeId(T)) {
                        return @alignCast(@fieldParentPtr("data_gen", data_gen));
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

    // TODO: should probably better be thread-safe!
    pub fn getMarker(dc: *DataContainer) !*Data(bool) {
        if (dc.available_markers.pop()) |marker| {
            marker.fill(false); // reset the marker to false before reuse
            return marker;
        }

        // same as for addData, but the name is not used (the marker is not stored in the hashmap)
        const marker = try dc.allocator.create(Data(bool));
        marker.init("", dc);
        errdefer marker.data_gen.deinit(); // DataGen deinit calls Data(T) deinit, which also destroys the Data(T)

        try marker.data_gen.ensureSize(dc.size);
        marker.fill(false); // marker is filled with false before use
        try dc.markers.append(dc.allocator, marker);
        return marker;
    }

    pub fn releaseMarker(dc: *DataContainer, marker: *Data(bool)) void {
        assert(marker.data_gen.container == dc); // check that this marker belongs to this container
        dc.available_markers.append(dc.allocator, marker) catch |err| {
            std.debug.print("Error releasing marker: {}\n", .{err});
        };
    }

    pub fn getIndex(dc: *DataContainer) !u32 {
        const index = if (dc.nb_inactive_indices > 0) blk: {
            const index = dc.first_inactive_index;
            assert(!dc.is_active.value(index));
            dc.first_inactive_index = dc.nb_refs.value(index);
            dc.nb_inactive_indices -= 1;
            for (dc.markers.items) |marker| {
                marker.valuePtr(index).* = false; // reset the markers at this index
            }
            break :blk index;
        } else blk: {
            const index = dc.size;
            dc.size += 1;
            for (dc.markers.items) |marker| {
                try marker.data_gen.ensureSize(dc.size);
                marker.valuePtr(index).* = false; // reset the markers at this index
            }
            var datas_it = dc.datas.iterator();
            while (datas_it.next()) |entry| {
                try entry.value_ptr.*.ensureSize(dc.size);
            }
            break :blk index;
        };
        dc.is_active.valuePtr(index).* = true; // index returned by newIndex is active
        dc.nb_refs.valuePtr(index).* = 0; // but has no reference yet
        return index;
    }

    pub fn releaseIndex(dc: *DataContainer, index: u32) void {
        assert(index < dc.size);
        assert(dc.is_active.value(index));
        dc.is_active.valuePtr(index).* = false;
        dc.nb_refs.valuePtr(index).* = dc.first_inactive_index;
        dc.first_inactive_index = index;
        dc.nb_inactive_indices += 1;
    }

    pub fn refIndex(dc: *DataContainer, index: u32) void {
        assert(index < dc.size);
        assert(dc.is_active.value(index));
        dc.nb_refs.valuePtr(index).* += 1;
    }

    pub fn unrefIndex(dc: *DataContainer, index: u32) void {
        assert(index < dc.size);
        assert(dc.is_active.value(index));
        assert(dc.nb_refs.value(index) > 0);
        dc.nb_refs.valuePtr(index).* -= 1;
        if (dc.nb_refs.value(index) == 0) {
            dc.releaseIndex(index);
        }
    }

    pub fn nbElements(dc: *const DataContainer) u32 {
        return dc.size - dc.nb_inactive_indices;
    }

    // pub fn density(dc: *const DataContainer) f32 {
    //     if (dc.size == 0) {
    //         return 0.0;
    //     }
    //     return 1.0 - (@as(f32, @floatFromInt(dc.nb_inactive_indices)) / @as(f32, @floatFromInt(dc.size)));
    // }

    pub fn firstIndex(dc: *const DataContainer) u32 {
        var index: u32 = 0;
        return while (index < dc.size) : (index += 1) {
            if (dc.isActiveIndexAssumeSize(index)) {
                break index;
            }
        } else dc.size;
    }

    pub fn nextIndex(dc: *const DataContainer, index: u32) u32 {
        var next: u32 = index + 1;
        return while (next < dc.size) : (next += 1) {
            if (dc.isActiveIndexAssumeSize(next)) {
                break next;
            }
        } else dc.size;
    }

    /// lastIndex actually returns one past the last valid index.
    pub fn lastIndex(dc: *const DataContainer) u32 {
        return dc.size;
    }

    pub fn isActiveIndex(dc: *const DataContainer, index: u32) bool {
        return index < dc.size and dc.is_active.value(index);
    }

    pub fn isActiveIndexAssumeSize(dc: *const DataContainer, index: u32) bool {
        return dc.is_active.value(index);
    }
};
