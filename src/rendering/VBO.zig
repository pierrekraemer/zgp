const VBO = @This();

const std = @import("std");
const gl = @import("gl");

index: c_uint = 0,
allocated_bytes: usize = 0,

pub fn init() VBO {
    var v: VBO = .{};
    gl.GenBuffers(1, (&v.index)[0..1]);
    return v;
}

pub fn deinit(v: *VBO) void {
    if (v.index != 0) {
        gl.DeleteBuffers(1, (&v.index)[0..1]);
        v.index = 0;
        v.allocated_bytes = 0;
    }
}

pub fn fillFrom(v: *VBO, comptime T: type, data: []const T) void {
    const byte_size = data.len * @sizeOf(T);
    gl.BindBuffer(gl.ARRAY_BUFFER, v.index);
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    if (byte_size > 0 and byte_size <= v.allocated_bytes) {
        gl.BufferSubData(
            gl.ARRAY_BUFFER,
            0,
            @intCast(byte_size),
            data.ptr,
        );
    } else {
        gl.BufferData(
            gl.ARRAY_BUFFER,
            @intCast(byte_size),
            if (byte_size > 0) data.ptr else null,
            gl.STATIC_DRAW,
        );
        v.allocated_bytes = byte_size;
    }
}
