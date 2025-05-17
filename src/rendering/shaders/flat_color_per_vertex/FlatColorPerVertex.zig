const std = @import("std");
const gl = @import("gl");

const Shader = @import("../../Shader.zig");

const Self = @This();

shader: Shader,

model_view_matrix_uniform: c_int = undefined,
projection_matrix_uniform: c_int = undefined,
ambiant_color_uniform: c_int = undefined,
light_position_uniform: c_int = undefined,

position_attrib: Shader.VertexAttrib = undefined,
color_attrib: Shader.VertexAttrib = undefined,

pub fn init() !Self {
    var s: Self = .{
        .shader = try Shader.init(),
    };

    const vertex_shader_source = @embedFile("vs.glsl");
    const fragment_shader_source = @embedFile("fs.glsl");

    try s.shader.setShader(.vertex, vertex_shader_source);
    try s.shader.setShader(.fragment, fragment_shader_source);
    try s.shader.linkProgram();

    s.model_view_matrix_uniform = gl.GetUniformLocation(s.shader.program, "u_model_view_matrix");
    s.projection_matrix_uniform = gl.GetUniformLocation(s.shader.program, "u_projection_matrix");
    s.ambiant_color_uniform = gl.GetUniformLocation(s.shader.program, "u_ambiant_color");
    s.light_position_uniform = gl.GetUniformLocation(s.shader.program, "u_light_position");

    s.position_attrib = .{
        .index = @intCast(gl.GetAttribLocation(s.shader.program, "a_position")),
        .size = 3,
        .type = gl.FLOAT,
        .normalized = false,
        .stride = 0,
        .pointer = 0,
    };
    s.color_attrib = .{
        .index = @intCast(gl.GetAttribLocation(s.shader.program, "a_color")),
        .size = 3,
        .type = gl.FLOAT,
        .normalized = false,
        .stride = 0,
        .pointer = 0,
    };

    return s;
}

pub fn deinit(self: *Self) void {
    self.shader.deinit();
}

pub const Parameters = struct {
    shader: *const Self,
    vao: c_uint = 0,
    model_view_matrix: [16]f32 = undefined,
    projection_matrix: [16]f32 = undefined,
    ambiant_color: [4]f32 = .{ 0, 0, 0, 1 },
    light_position: [4]f32 = .{ 0, 0, 0, 1 },

    const VertexAttribs = enum {
        position,
        color,
    };

    pub fn init(shader: *const Self) !Parameters {
        var p: Parameters = .{ .shader = shader };
        gl.GenVertexArrays(1, (&p.vao)[0..1]);
        if (p.vao == 0)
            return error.GlGenVertexArraysFailed;
        return p;
    }

    pub fn deinit(self: *Parameters) void {
        if (self.vao != 0) {
            gl.DeleteVertexArrays(1, (&self.vao)[0..1]);
            self.vao = 0;
        }
    }

    pub fn setVBO(self: *Parameters, attrib: VertexAttribs, vbo: c_uint) void {
        gl.BindVertexArray(self.vao);
        defer gl.BindVertexArray(0);
        gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
        defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);
        const attrib_info = switch (attrib) {
            .position => self.shader.position_attrib,
            .color => self.shader.color_attrib,
        };
        gl.VertexAttribPointer(
            attrib_info.index,
            attrib_info.size,
            attrib_info.type,
            if (attrib_info.normalized) gl.TRUE else gl.FALSE,
            @intCast(attrib_info.stride),
            attrib_info.pointer,
        );
        gl.EnableVertexAttribArray(attrib_info.index);
    }

    pub fn setIBO(self: *Parameters, ibo: c_uint) void {
        gl.BindVertexArray(self.vao);
        defer gl.BindVertexArray(0);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo);
    }
};
