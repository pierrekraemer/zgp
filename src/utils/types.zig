const std = @import("std");

fn TypeIdContainer(T: type) type {
    return struct {
        // dummy struct declaration (static) whose type depends on T
        var id: *const T = undefined;
    };
}

pub fn typeId(T: type) *const anyopaque {
    return @ptrCast(&TypeIdContainer(T).id);
}

/// Evaluates at compile-time to check if a type has a specific function with a given name.
pub fn hasFn(comptime T: type, comptime name: []const u8) bool {
    // 1. Safely handle explicit `null` or `void`
    if (T == @TypeOf(null) or T == void) return false;
    // 2. Unwrap pointer types (so context pointers like `*MyContext` work)
    const BaseT = switch (@typeInfo(T)) {
        .pointer => |ptrInfo| ptrInfo.child,
        else => T,
    };
    // 3. We only expect functions to live inside structs
    if (@typeInfo(BaseT) != .@"struct") return false;
    // 4. Check if the function exists as a method (decl) or a function pointer (field)
    return @hasDecl(BaseT, name) or @hasField(BaseT, name);
}

pub fn StructFromUnion(U: type) type {
    const nbfields = @typeInfo(U).@"union".fields.len;
    var field_names: [nbfields][]const u8 = undefined;
    var field_types: [nbfields]type = undefined;
    inline for (@typeInfo(U).@"union".fields, 0..nbfields) |*union_field, i| {
        field_names[i] = union_field.name;
        field_types[i] = union_field.type;
    }
    return @Struct(.auto, null, &field_names, &field_types, &@splat(.{}));
}

pub fn UnionFromStruct(S: type) type {
    const nbfields = @typeInfo(S).@"struct".fields.len;
    var field_names: [nbfields][]const u8 = undefined;
    var field_types: [nbfields]type = undefined;
    var enum_values: [nbfields]u32 = undefined;
    inline for (@typeInfo(S).@"struct".fields, 0..nbfields) |*struct_field, i| {
        field_names[i] = struct_field.name;
        field_types[i] = struct_field.type;
        enum_values[i] = i;
    }
    const EnumType = @Enum(u32, .exhaustive, &field_names, &enum_values);
    return @Union(.auto, EnumType, &field_names, &field_types, &@splat(.{}));
}
