const std = @import("std");
const gl = @import("gl");

const Texture2D = @import("Texture2D.zig");

const Self = @This();

index: c_uint = 0,

pub fn init() Self {
    var s: Self = .{};
    gl.GenFramebuffers(1, (&s.index)[0..1]);
    return s;
}

pub fn deinit(self: *Self) void {
    if (self.index != 0) {
        gl.DeleteFramebuffers(1, (&self.index)[0..1]);
        self.index = 0;
    }
}

pub fn attachTexture(self: Self, attachement: c_uint, texture: Texture2D) void {
    gl.BindFramebuffer(gl.FRAMEBUFFER, self.index);
    defer gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, attachement, gl.TEXTURE_2D, texture.index, 0);
}
