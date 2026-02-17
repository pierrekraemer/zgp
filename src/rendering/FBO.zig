const FBO = @This();

const std = @import("std");
const gl = @import("gl");

const Texture2D = @import("Texture2D.zig");

index: c_uint = 0,

pub fn init() FBO {
    var f: FBO = .{};
    gl.GenFramebuffers(1, (&f.index)[0..1]);
    return f;
}

pub fn deinit(f: *FBO) void {
    if (f.index != 0) {
        gl.DeleteFramebuffers(1, (&f.index)[0..1]);
        f.index = 0;
    }
}

pub fn attachTexture(f: FBO, attachement: c_uint, texture: Texture2D) void {
    gl.BindFramebuffer(gl.FRAMEBUFFER, f.index);
    defer gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
    gl.FramebufferTexture2D(
        gl.FRAMEBUFFER,
        attachement,
        gl.TEXTURE_2D,
        texture.index,
        0,
    );
}
