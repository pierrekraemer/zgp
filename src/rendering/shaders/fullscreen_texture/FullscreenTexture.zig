const FullscreenTexture = @This();

const std = @import("std");
const gl = @import("gl");

const Shader = @import("../../Shader.zig");
const VAO = @import("../../VAO.zig");
const Texture2D = @import("../../Texture2D.zig");

var global_instance: FullscreenTexture = undefined;
var init_global_once = std.once(init_global);
fn init_global() void {
    global_instance = init() catch unreachable;
    Shader.register(&global_instance.program);
}
pub fn instance() *FullscreenTexture {
    init_global_once.call();
    return &global_instance;
}

program: Shader,

texture_unit_uniform: c_int = undefined,

fn init() !FullscreenTexture {
    var ft: FullscreenTexture = .{
        .program = Shader.init(),
    };

    const vertex_shader_source = @embedFile("vs.glsl");
    const fragment_shader_source = @embedFile("fs.glsl");

    try ft.program.setShader(.vertex, vertex_shader_source);
    try ft.program.setShader(.fragment, fragment_shader_source);
    try ft.program.linkProgram();

    ft.texture_unit_uniform = gl.GetUniformLocation(ft.program.index, "u_texture_unit");

    return ft;
}

pub const Parameters = struct {
    shader: *const FullscreenTexture,
    vao: VAO,

    texture: Texture2D = undefined,
    texture_unit: c_int = undefined,

    pub fn init() Parameters {
        return .{
            .shader = instance(),
            .vao = VAO.init(),
        };
    }

    pub fn deinit(p: *Parameters) void {
        p.vao.deinit();
    }

    pub fn setTexture(p: *Parameters, texture: Texture2D) void {
        p.texture = texture;
        p.texture_unit = 0;
    }

    pub fn draw(p: *Parameters) void {
        gl.UseProgram(p.shader.program.index);
        defer gl.UseProgram(0);

        const unit: c_uint = @intCast(p.texture_unit);
        gl.ActiveTexture(gl.TEXTURE0 + unit);
        gl.BindTexture(gl.TEXTURE_2D, p.texture.index);
        defer gl.BindTexture(gl.TEXTURE_2D, 0);

        gl.BindVertexArray(p.vao.index); // even an empty VAO is needed in order for DrawArrays to work
        defer gl.BindVertexArray(0);
        gl.DrawArrays(gl.TRIANGLES, 0, 3);
    }
};
