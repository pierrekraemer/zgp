const TextureBuffer = @This();

const std = @import("std");
const gl = @import("gl");

index: c_uint = 0,

pub fn init() TextureBuffer {
    var t: TextureBuffer = .{};
    gl.GenTextures(1, (&t.index)[0..1]);
    return t;
}

pub fn deinit(t: *TextureBuffer) void {
    if (t.index != 0) {
        gl.DeleteTextures(1, (&t.index)[0..1]);
        t.index = 0;
    }
}
