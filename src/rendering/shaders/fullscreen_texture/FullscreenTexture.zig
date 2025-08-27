const FullscreenTexture = @This();

const std = @import("std");
const gl = @import("gl");

const Shader = @import("../../Shader.zig");
const VAO = @import("../../VAO.zig");
const Texture2D = @import("../../Texture2D.zig");

program: Shader,

texture_unit_uniform: c_int = undefined,

pub fn init() !FullscreenTexture {
    var ft: FullscreenTexture = .{
        .program = try Shader.init(),
    };

    const vertex_shader_source = @embedFile("vs.glsl");
    const fragment_shader_source = @embedFile("fs.glsl");

    try ft.program.setShader(.vertex, vertex_shader_source);
    try ft.program.setShader(.fragment, fragment_shader_source);
    try ft.program.linkProgram();

    ft.texture_unit_uniform = gl.GetUniformLocation(ft.program.index, "u_texture_unit");

    return ft;
}

pub fn deinit(ft: *FullscreenTexture) void {
    ft.program.deinit();
}

pub fn createParameters(ft: *const FullscreenTexture) Parameters {
    return Parameters.init(ft);
}

pub const Parameters = struct {
    shader: *const FullscreenTexture,
    vao: VAO,

    tex: Texture2D = undefined,
    texture_unit: c_int = undefined,

    pub fn init(ft: *const FullscreenTexture) Parameters {
        return .{
            .shader = ft,
            .vao = VAO.init(),
        };
    }

    pub fn deinit(p: *Parameters) void {
        p.vao.deinit();
    }

    pub fn setTexture(p: *Parameters, tex: Texture2D, unit: c_int) void {
        p.tex = tex;
        p.texture_unit = unit;
    }

    pub fn useShader(p: *Parameters) void {
        gl.UseProgram(p.shader.program.index);
        const unit: c_uint = @intCast(p.texture_unit);
        gl.ActiveTexture(gl.TEXTURE0 + unit);
        gl.BindTexture(gl.TEXTURE_2D, p.tex.index);
        gl.Uniform1i(p.shader.texture_unit_uniform, p.texture_unit);
    }

    pub fn draw(p: *Parameters) void {
        gl.BindVertexArray(p.vao.index); // even an empty VAO is needed in order for DrawArrays to work
        defer gl.BindVertexArray(0);
        gl.DrawArrays(gl.TRIANGLES, 0, 3);
    }
};
