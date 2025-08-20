const std = @import("std");
const gl = @import("gl");

const Shader = @import("../../Shader.zig");
const VAO = @import("../../VAO.zig");
const Texture2D = @import("../../Texture2D.zig");

const Self = @This();

program: Shader,

texture_unit_uniform: c_int = undefined,

pub fn init() !Self {
    var s: Self = .{
        .program = try Shader.init(),
    };

    const vertex_shader_source = @embedFile("vs.glsl");
    const fragment_shader_source = @embedFile("fs.glsl");

    try s.program.setShader(.vertex, vertex_shader_source);
    try s.program.setShader(.fragment, fragment_shader_source);
    try s.program.linkProgram();

    s.texture_unit_uniform = gl.GetUniformLocation(s.program.index, "u_texture_unit");

    return s;
}

pub fn deinit(self: *Self) void {
    self.program.deinit();
}

pub fn createParameters(self: *const Self) Parameters {
    return Parameters.init(self);
}

pub const Parameters = struct {
    shader: *const Self,
    vao: VAO,

    tex: Texture2D = undefined,
    texture_unit: c_int = undefined,

    pub fn init(shader: *const Self) Parameters {
        return .{
            .shader = shader,
            .vao = VAO.init(),
        };
    }

    pub fn deinit(self: *Parameters) void {
        self.vao.deinit();
    }

    pub fn setTexture(self: *Parameters, tex: Texture2D, unit: c_int) void {
        self.tex = tex;
        self.texture_unit = unit;
    }

    pub fn useShader(self: *Parameters) void {
        gl.UseProgram(self.shader.program.index);
        const unit: c_uint = @intCast(self.texture_unit);
        gl.ActiveTexture(gl.TEXTURE0 + unit);
        gl.BindTexture(gl.TEXTURE_2D, self.tex.index);
        gl.Uniform1i(self.shader.texture_unit_uniform, self.texture_unit);
    }

    pub fn draw(self: *Parameters) void {
        gl.BindVertexArray(self.vao.index); // even an empty VAO is needed in order for DrawArrays to work
        defer gl.BindVertexArray(0);
        gl.DrawArrays(gl.TRIANGLES, 0, 3);
    }
};
