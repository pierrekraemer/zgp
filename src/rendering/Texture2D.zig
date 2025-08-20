const std = @import("std");
const gl = @import("gl");

const Self = @This();

index: c_uint = 0,

pub const Parameter = struct {
    name: c_uint,
    value: c_int,
};

pub fn init(parameters: []const Parameter) Self {
    var s: Self = .{};
    gl.GenTextures(1, (&s.index)[0..1]);
    gl.BindTexture(gl.TEXTURE_2D, s.index);
    defer gl.BindTexture(gl.TEXTURE_2D, 0);
    for (parameters) |param| {
        gl.TexParameteri(gl.TEXTURE_2D, param.name, param.value);
    }
    return s;
}

pub fn deinit(self: *Self) void {
    if (self.index != 0) {
        gl.DeleteTextures(1, (&self.index)[0..1]);
        self.index = 0;
    }
}

pub fn resize(self: Self, width: c_int, height: c_int, internal_format: c_int, format: c_uint, datatype: c_uint) void {
    gl.BindTexture(gl.TEXTURE_2D, self.index);
    defer gl.BindTexture(gl.TEXTURE_2D, 0);
    gl.TexImage2D(gl.TEXTURE_2D, 0, internal_format, width, height, 0, format, datatype, null);
}
