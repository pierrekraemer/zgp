const std = @import("std");
const gl = @import("gl");

const Self = @This();

const gl_log = std.log.scoped(.gl);

const shader_version = switch (gl.info.api) {
    .gl => (
        \\#version 410 core
        \\
    ),
    .gles, .glsc => (
        \\#version 300 es
        \\
    ),
};

pub const ShaderType = enum {
    vertex,
    geometry,
    fragment,
};

index: c_uint = 0,
ready: bool = false,

pub fn init() !Self {
    var s: Self = .{};
    s.index = gl.CreateProgram();
    if (s.index == 0)
        return error.GlCreateProgramFailed;
    return s;
}

pub fn deinit(self: *Self) void {
    if (self.index != 0) {
        gl.DeleteProgram(self.index);
        self.index = 0;
        self.ready = false;
    }
}

pub fn setShader(self: *Self, shader_type: ShaderType, shader_source: []const u8) !void {
    var success: c_int = undefined;
    var info_log_buf: [512:0]u8 = undefined;
    const shader = gl.CreateShader(switch (shader_type) {
        .vertex => gl.VERTEX_SHADER,
        .geometry => gl.GEOMETRY_SHADER,
        .fragment => gl.FRAGMENT_SHADER,
    });
    if (shader == 0)
        return error.GlCreateShaderFailed;
    defer gl.DeleteShader(shader); // attached shader will only be _tagged_ for deletion
    gl.ShaderSource(
        shader,
        2,
        &.{ shader_version, shader_source.ptr },
        &.{ shader_version.len, @intCast(shader_source.len) },
    );
    gl.CompileShader(shader);
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, &success);
    if (success == gl.FALSE) {
        gl.GetShaderInfoLog(shader, info_log_buf.len, null, &info_log_buf);
        gl_log.err("{s}", .{std.mem.sliceTo(&info_log_buf, 0)});
        return error.GlCompileShaderFailed;
    }
    gl.AttachShader(self.index, shader);
}

pub fn linkProgram(self: *Self) !void {
    var success: c_int = undefined;
    var info_log_buf: [512:0]u8 = undefined;
    gl.LinkProgram(self.index);
    gl.GetProgramiv(self.index, gl.LINK_STATUS, &success);
    if (success == gl.FALSE) {
        gl.GetProgramInfoLog(self.index, info_log_buf.len, null, &info_log_buf);
        gl_log.err("{s}", .{std.mem.sliceTo(&info_log_buf, 0)});
        return error.LinkProgramFailed;
    }
    var nb_attached_shaders: c_int = undefined;
    gl.GetProgramiv(self.index, gl.ATTACHED_SHADERS, &nb_attached_shaders);
    if (nb_attached_shaders > 0) {
        var attached_shaders: [16]c_uint = undefined;
        gl.GetAttachedShaders(self.index, attached_shaders.len, &nb_attached_shaders, &attached_shaders);
        var i: u32 = 0;
        while (i < nb_attached_shaders) : (i += 1) {
            gl.DetachShader(self.index, attached_shaders[i]);
        }
    }
    self.ready = true;
}
