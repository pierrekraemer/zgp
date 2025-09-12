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
