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
line_color_uniform: c_int = undefined,
// line_width_uniform: c_int = undefined,

position_attrib: VAO.VertexAttribInfo = undefined,

pub fn init() !Self {
    var s: Self = .{
        .program = try Shader.init(),
    };

    const vertex_shader_source = @embedFile("vs.glsl");
    // const geometry_shader_source = @embedFile("gs.glsl");
    const fragment_shader_source = @embedFile("fs.glsl");

    try s.program.setShader(.vertex, vertex_shader_source);
    // try s.program.setShader(.geometry, geometry_shader_source);
    try s.program.setShader(.fragment, fragment_shader_source);
    try s.program.linkProgram();

    s.model_view_matrix_uniform = gl.GetUniformLocation(s.program.index, "u_model_view_matrix");
    s.projection_matrix_uniform = gl.GetUniformLocation(s.program.index, "u_projection_matrix");
    s.line_color_uniform = gl.GetUniformLocation(s.program.index, "u_line_color");
    // s.line_width_uniform = gl.GetUniformLocation(s.program.index, "u_line_width");

    s.position_attrib = .{
        .index = @intCast(gl.GetAttribLocation(s.program.index, "a_position")),
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
    line_color: [4]f32 = .{ 0, 0, 0, 0 },
    line_width: f32 = 1.0,

    const VertexAttrib = enum {
        position,
    };

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
        };
        self.vao.setVertexAttribArray(attrib_info, vbo, stride, pointer);
    }

    pub fn useShader(self: *Parameters) void {
        gl.UseProgram(self.shader.program.index);
        gl.UniformMatrix4fv(self.shader.model_view_matrix_uniform, 1, gl.FALSE, &self.model_view_matrix);
        gl.UniformMatrix4fv(self.shader.projection_matrix_uniform, 1, gl.FALSE, &self.projection_matrix);
        gl.Uniform4fv(self.shader.line_color_uniform, 1, &self.line_color);
        // var viewport: [4]i32 = .{ 0, 0, 0, 0 };
        // gl.GetIntegerv(gl.VIEWPORT, &viewport);
        // gl.Uniform2f(self.shader.line_width_uniform, self.line_width / @as(f32, @floatFromInt(viewport[2])), self.line_width / @as(f32, @floatFromInt(viewport[3])));
        gl.LineWidth(self.line_width);
    }

    pub fn drawElements(self: *Parameters, primitive: c_uint, ibo: IBO) void {
        gl.BindVertexArray(self.vao.index);
        defer gl.BindVertexArray(0);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo.index);
        defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
        gl.DrawElements(primitive, @intCast(ibo.nb_indices), gl.UNSIGNED_INT, 0);
    }
};
