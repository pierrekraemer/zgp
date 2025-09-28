const VBO = @This();

const std = @import("std");
const gl = @import("gl");

const Data = @import("../utils/Data.zig").Data;

index: c_uint = 0,

pub fn init() VBO {
    var v: VBO = .{};
    gl.GenBuffers(1, (&v.index)[0..1]);
    return v;
}

pub fn deinit(v: *VBO) void {
    if (v.index != 0) {
        gl.DeleteBuffers(1, (&v.index)[0..1]);
        v.index = 0;
    }
}

pub fn fillFrom(v: *VBO, comptime T: type, data: *const Data(T)) void {
    gl.BindBuffer(gl.ARRAY_BUFFER, v.index);
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    gl.BufferData(
        gl.ARRAY_BUFFER,
        @intCast(data.rawSize()),
        data.data.items.ptr,
        gl.STATIC_DRAW,
    );
}
