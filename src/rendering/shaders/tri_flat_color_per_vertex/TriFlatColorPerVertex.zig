const std = @import("std");
const gl = @import("gl");

const Shader = @import("../../Shader.zig");
const VAO = @import("../../VAO.zig");
const VBO = @import("../../VBO.zig");
const IBO = @import("../../IBO.zig");

const Self = @This();

program: Shader,

model_view_matrix_uniform: c_int = undefined,
projection_matrix_uniform: c_int = undefined,
ambiant_color_uniform: c_int = undefined,
light_position_uniform: c_int = undefined,

position_attrib: VAO.VertexAttribInfo = undefined,
color_attrib: VAO.VertexAttribInfo = undefined,

const VertexAttrib = enum {
    position,
    color,
};

pub fn init() !Self {
    var s: Self = .{
        .program = try Shader.init(),
    };

    const vertex_shader_source = @embedFile("vs.glsl");
    const fragment_shader_source = @embedFile("fs.glsl");

    try s.program.setShader(.vertex, vertex_shader_source);
    try s.program.setShader(.fragment, fragment_shader_source);
    try s.program.linkProgram();

    s.model_view_matrix_uniform = gl.GetUniformLocation(s.program.index, "u_model_view_matrix");
    s.projection_matrix_uniform = gl.GetUniformLocation(s.program.index, "u_projection_matrix");
    s.ambiant_color_uniform = gl.GetUniformLocation(s.program.index, "u_ambiant_color");
    s.light_position_uniform = gl.GetUniformLocation(s.program.index, "u_light_position");

    s.position_attrib = .{
        .index = @intCast(gl.GetAttribLocation(s.program.index, "a_position")),
        .size = 3,
        .type = gl.FLOAT,
        .normalized = false,
    };
    s.color_attrib = .{
        .index = @intCast(gl.GetAttribLocation(s.program.index, "a_color")),
        .size = 3,
        .type = gl.FLOAT,
        .normalized = false,
    };

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

    model_view_matrix: [16]f32 = undefined,
    projection_matrix: [16]f32 = undefined,
    ambiant_color: [4]f32 = .{ 0.1, 0.1, 0.1, 1 },
    light_position: [3]f32 = .{ 10, 0, 100 },

    pub fn init(shader: *const Self) Parameters {
        return .{
            .shader = shader,
            .vao = VAO.init(),
        };
    }

    pub fn deinit(self: *Parameters) void {
        self.vao.deinit();
    }

    pub fn setVertexAttribArray(self: *Parameters, attrib: VertexAttrib, vbo: VBO, stride: isize, pointer: usize) void {
        const attrib_info = switch (attrib) {
            .position => self.shader.position_attrib,
            .color => self.shader.color_attrib,
        };
        self.vao.setVertexAttribArray(attrib_info, vbo, stride, pointer);
    }

    pub fn useShader(self: *Parameters) void {
        gl.UseProgram(self.shader.program.index);
        gl.UniformMatrix4fv(self.shader.model_view_matrix_uniform, 1, gl.FALSE, &self.model_view_matrix);
        gl.UniformMatrix4fv(self.shader.projection_matrix_uniform, 1, gl.FALSE, &self.projection_matrix);
        gl.Uniform4fv(self.shader.ambiant_color_uniform, 1, &self.ambiant_color);
        gl.Uniform3fv(self.shader.light_position_uniform, 1, &self.light_position);
    }

    pub fn drawElements(self: *Parameters, ibo: IBO) void {
        gl.BindVertexArray(self.vao.index);
        defer gl.BindVertexArray(0);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo.index);
        defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
        gl.DrawElements(gl.TRIANGLES, @intCast(ibo.nb_indices), gl.UNSIGNED_INT, 0);
    }
};
