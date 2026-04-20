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
