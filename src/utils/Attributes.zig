const std = @import("std");
const typeId = @import("typeId.zig").typeId;

pub const AttributeGen = struct {
    name: []const u8,
    type_id: *const anyopaque, // typeId of T in the Attribute(T)
    arena: std.heap.ArenaAllocator, // used for data allocation by the Attribute(T)
    ptr: *anyopaque, // pointer to the Attribute(T)
    container: *AttributeContainer, // pointer to the AttributeContainer that owns this attribute
    vtable: *const VTable,

    const VTable = struct {
        ensureSize: *const fn (ptr: *anyopaque, size: u32) anyerror!void,
        clearRetainingCapacity: *const fn (ptr: *anyopaque) void,
    };

    pub fn init(
        comptime T: type,
        name: []const u8,
        type_id: *const anyopaque,
        pointer: *Attribute(T),
        container: *AttributeContainer,
        arena: std.heap.ArenaAllocator,
    ) AttributeGen {
        const gen = struct {
            fn ensureSize(ptr: *anyopaque, size: u32) !void {
                const impl: *Attribute(T) = @ptrCast(@alignCast(ptr));
                try impl.ensureSize(size);
            }
            fn clearRetainingCapacity(ptr: *anyopaque) void {
                const impl: *Attribute(T) = @ptrCast(@alignCast(ptr));
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
                .ensureSize = gen.ensureSize,
                .clearRetainingCapacity = gen.clearRetainingCapacity,
            },
        };
    }

    pub fn deinit(self: *AttributeGen) void {
        self.arena.deinit();
    }

    pub inline fn ensureSize(self: *AttributeGen, size: u32) !void {
        try self.vtable.ensureSize(self.ptr, size);
    }

    pub inline fn clearRetainingCapacity(self: *AttributeGen) void {
        self.vtable.clearRetainingCapacity(self.ptr);
    }
};

pub fn Attribute(comptime T: type) type {
    return struct {
        const Self = @This();

        gen: AttributeGen = undefined,
        data: std.SegmentedList(T, 32) = .{},

        const init: Self = .{};

        pub fn arena(self: *Self) std.mem.Allocator {
            return self.gen.arena.allocator();
        }

        pub fn ensureSize(self: *Self, size: u32) !void {
            while (self.data.len < size) {
                _ = try self.data.addOne(self.gen.arena.allocator());
            }
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.data.clearRetainingCapacity();
        }

        fn ValueType(comptime SelfType: type) type {
            if (@typeInfo(SelfType).pointer.is_const) {
                return *const T;
            } else {
                return *T;
            }
        }

        pub fn value(self: anytype, index: u32) ValueType(@TypeOf(self)) {
            return self.data.at(index);
        }

        pub fn fill(self: *Self, val: T) void {
            var it = self.data.iterator(0);
            while (it.next()) |element| {
                element.* = val;
            }
        }

        pub fn rawIterator(self: *Self) std.SegmentedList(T, 32).Iterator {
            return self.data.iterator(0);
        }

        pub fn rawConstIterator(self: *const Self) std.SegmentedList(T, 32).ConstIterator {
            return self.data.constIterator(0);
        }

        // TODO: iterator & constIterator (filtered to active indices of the container)
    };
}

pub const AttributeContainer = struct {
    allocator: std.mem.Allocator,
    attributes: std.StringHashMap(*AttributeGen),
    free_indices: std.ArrayList(u32),
    capacity: u32,
    is_active: *Attribute(bool),

    pub fn init(allocator: std.mem.Allocator) !AttributeContainer {
        var ac: AttributeContainer = .{
            .allocator = allocator,
            .attributes = std.StringHashMap(*AttributeGen).init(allocator),
            .free_indices = std.ArrayList(u32).init(allocator),
            .capacity = 0,
            .is_active = undefined,
        };
        ac.is_active = try ac.addAttribute(bool, "__is_active");
        return ac;
    }

    pub fn deinit(self: *AttributeContainer) void {
        var it = self.attributes.iterator();
        while (it.next()) |entry| {
            const attribute_gen = entry.value_ptr.*;
            attribute_gen.deinit();
        }
        self.attributes.deinit();
        self.free_indices.deinit();
    }

    pub fn clearRetainingCapacity(self: *AttributeContainer) void {
        var it = self.attributes.iterator();
        while (it.next()) |entry| {
            const attribute_gen = entry.value_ptr.*;
            attribute_gen.clearRetainingCapacity();
        }
        self.free_indices.clearRetainingCapacity();
        self.capacity = 0;
    }

    pub fn addAttribute(self: *AttributeContainer, comptime T: type, name: []const u8) !*Attribute(T) {
        const type_id = comptime typeId(T);
        const maybe_attribute_gen = self.attributes.get(name);
        if (maybe_attribute_gen) |_| {
            return error.AttributeNameAlreadyExists;
        }
        // the arena created for the attribute is used to allocate:
        // - the Attribute(T) struct itself,
        // - an owned copy of the name of the attribute,
        // It is then passed to the AttributeGen of the attribute.
        // The Attribute(T) then:
        // - use it to allocate its SegmentedList(T, 32) data,
        // - exposes it to allow the user to use it if T needs to allocate memory.
        var attribute_arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer attribute_arena.deinit();
        const attribute = try attribute_arena.allocator().create(Attribute(T));
        attribute.* = .init;
        const owned_name = try attribute_arena.allocator().dupe(u8, name);
        attribute.gen = AttributeGen.init(
            T,
            owned_name,
            type_id,
            attribute,
            self,
            attribute_arena,
        );
        try attribute.ensureSize(self.capacity);
        try self.attributes.put(owned_name, &attribute.gen);
        return attribute;
    }

    pub fn getAttribute(self: *AttributeContainer, comptime T: type, name: []const u8) ?*Attribute(T) {
        const type_id = comptime typeId(T);
        const maybe_attribute_gen = self.attributes.get(name);
        if (maybe_attribute_gen) |attribute_gen| {
            if (attribute_gen.type_id == type_id) {
                // const attribute: *Attribute(T) = @alignCast(@fieldParentPtr("gen", attribute_gen));
                const attribute: *Attribute(T) = @alignCast(attribute_gen.ptr);
                return attribute;
            }
            return null;
        } else {
            return null;
        }
    }

    pub fn removeAttribute(self: *AttributeContainer, attribute: *AttributeGen) void {
        const name = attribute.name;
        if (self.attributes.remove(name)) {
            attribute.deinit();
        }
    }

    pub fn newIndex(self: *AttributeContainer) !u32 {
        const index = self.free_indices.pop() orelse blk: {
            defer self.capacity += 1;
            break :blk self.capacity;
        };
        // should not be necessary when the index comes from free_indices
        var it = self.attributes.iterator();
        while (it.next()) |entry| {
            const attribute_gen = entry.value_ptr.*;
            try attribute_gen.ensureSize(index + 1);
        }
        self.is_active.value(index).* = true;
        return index;
    }

    pub fn freeIndex(self: *AttributeContainer, index: u32) void {
        self.is_active.value(index).* = false;
        self.free_indices.append(index);
    }

    pub fn nbElements(self: *const AttributeContainer) u32 {
        return @intCast(self.capacity - self.free_indices.items.len);
    }

    pub fn firstIndex(self: *const AttributeContainer) u32 {
        var index: u32 = 0;
        return while (index < self.capacity) : (index += 1) {
            if (self.isActiveIndex(index)) {
                break index;
            }
        } else self.capacity;
    }

    pub fn lastIndex(self: *const AttributeContainer) u32 {
        return self.capacity;
    }

    pub fn nextIndex(self: *const AttributeContainer, index: u32) u32 {
        var next: u32 = index + 1;
        return while (next < self.capacity) : (next += 1) {
            if (self.isActiveIndex(next)) {
                break next;
            }
        } else self.capacity;
    }

    pub fn isActiveIndex(self: *const AttributeContainer, index: u32) bool {
        return self.is_active.value(index).*;
    }
};
