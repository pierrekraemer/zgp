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
    var struct_fields: [nbfields]std.builtin.Type.StructField = undefined;
    inline for (@typeInfo(U).@"union".fields, 0..nbfields) |*union_field, i| {
        struct_fields[i] = .{
            .name = union_field.name,
            .type = union_field.type,
            .alignment = @alignOf(union_field.type),
            .default_value_ptr = switch (@typeInfo(union_field.type)) {
                .optional => @ptrCast(&@as(union_field.type, null)),
                else => null,
            },
            .is_comptime = false,
        };
    }
    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &struct_fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

pub fn UnionFromStruct(S: type) type {
    const nbfields = @typeInfo(S).@"struct".fields.len;
    var union_fields: [nbfields]std.builtin.Type.UnionField = undefined;
    var enum_fields: [nbfields]std.builtin.Type.EnumField = undefined;
    inline for (@typeInfo(S).@"struct".fields, 0..nbfields) |*struct_field, i| {
        union_fields[i] = .{
            .name = struct_field.name,
            .type = struct_field.type,
            .alignment = @alignOf(struct_field.type),
        };
        enum_fields[i] = .{
            .name = struct_field.name,
            .value = i,
        };
    }
    return @Type(.{ .@"union" = .{
        .layout = .auto,
        .tag_type = @Type(.{ .@"enum" = .{
            .tag_type = if (nbfields <= 256) u8 else if (nbfields <= 65536) u16 else u32,
            .fields = &enum_fields,
            .decls = &.{},
            .is_exhaustive = true,
        } }),
        .fields = &union_fields,
        .decls = &.{},
    } });
}
