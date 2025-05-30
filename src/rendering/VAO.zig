const std = @import("std");
const gl = @import("gl");

const VBO = @import("./VBO.zig");

const Self = @This();

index: c_uint = 0,

pub const VertexAttribInfo = struct {
    index: u32,
    size: i32,
    type: u32,
    normalized: bool,
};

pub fn init() Self {
    var s: Self = .{};
    gl.GenVertexArrays(1, (&s.index)[0..1]);
    return s;
}

pub fn deinit(self: *Self) void {
    if (self.index != 0) {
        gl.DeleteVertexArrays(1, (&self.index)[0..1]);
        self.index = 0;
    }
}

pub fn setVertexAttribArray(self: *Self, attrib_info: VertexAttribInfo, vbo: VBO, stride: isize, pointer: usize) void {
    gl.BindVertexArray(self.index);
    defer gl.BindVertexArray(0);
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo.index);
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    gl.VertexAttribPointer(
        attrib_info.index,
        attrib_info.size,
        attrib_info.type,
        if (attrib_info.normalized) gl.TRUE else gl.FALSE,
        @intCast(stride),
        pointer,
    );
    gl.EnableVertexAttribArray(attrib_info.index);
}

// pub fn setVertexAttribValue(self: *Self, generic_attrib_index: u32, comptime T: type, value: T) void {
//     gl.BindVertexArray(self.index);
//     defer gl.BindVertexArray(0);
//     switch (@typeInfo(T)) {
//         .array => {
//             switch (@typeInfo(T).array.len) {
//                 1 => gl.VertexAttrib1f(generic_attrib_index, value[0]),
//                 2 => gl.VertexAttrib2f(generic_attrib_index, value[0], value[1]),
//                 3 => gl.VertexAttrib3f(generic_attrib_index, value[0], value[1], value[2]),
//                 4 => gl.VertexAttrib4f(generic_attrib_index, value[0], value[1], value[2], value[3]),
//                 else => unreachable,
//             }
//         },
//         else => @compileError("setVertexAttribValue only support array types"),
//     }
// }
