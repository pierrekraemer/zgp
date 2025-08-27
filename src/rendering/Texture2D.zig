const Texture2D = @This();

const std = @import("std");
const gl = @import("gl");

index: c_uint = 0,

pub const Parameter = struct {
    name: c_uint,
    value: c_int,
};

pub fn init(parameters: []const Parameter) Texture2D {
    var t: Texture2D = .{};
    gl.GenTextures(1, (&t.index)[0..1]);
    gl.BindTexture(gl.TEXTURE_2D, t.index);
    defer gl.BindTexture(gl.TEXTURE_2D, 0);
    for (parameters) |param| {
        gl.TexParameteri(gl.TEXTURE_2D, param.name, param.value);
    }
    return t;
}

pub fn deinit(t: *Texture2D) void {
    if (t.index != 0) {
        gl.DeleteTextures(1, (&t.index)[0..1]);
        t.index = 0;
    }
}

pub fn resize(t: Texture2D, width: c_int, height: c_int, internal_format: c_int, format: c_uint, datatype: c_uint) void {
    gl.BindTexture(gl.TEXTURE_2D, t.index);
    defer gl.BindTexture(gl.TEXTURE_2D, 0);
    gl.TexImage2D(gl.TEXTURE_2D, 0, internal_format, width, height, 0, format, datatype, null);
}
