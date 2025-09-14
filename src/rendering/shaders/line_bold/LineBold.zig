const LineBold = @This();

const std = @import("std");
const gl = @import("gl");

const Shader = @import("../../Shader.zig");
const VAO = @import("../../VAO.zig");
const VBO = @import("../../VBO.zig");
const IBO = @import("../../IBO.zig");

var global_instance: LineBold = undefined;
var init_global_once = std.once(init_global);
fn init_global() void {
    global_instance = init() catch unreachable;
}
pub fn instance() *LineBold {
    init_global_once.call();
    return &global_instance;
}

program: Shader,

model_view_matrix_uniform: c_int = undefined,
projection_matrix_uniform: c_int = undefined,
line_color_uniform: c_int = undefined,
line_width_uniform: c_int = undefined,

position_attrib: VAO.VertexAttribInfo = undefined,

fn init() !LineBold {
    var lb: LineBold = .{
        .program = Shader.init(),
    };

    const vertex_shader_source = @embedFile("vs.glsl");
    // const geometry_shader_source = @embedFile("gs.glsl");
    const fragment_shader_source = @embedFile("fs.glsl");

    try lb.program.setShader(.vertex, vertex_shader_source);
    // try lb.program.setShader(.geometry, geometry_shader_source);
    try lb.program.setShader(.fragment, fragment_shader_source);
    try lb.program.linkProgram();

    lb.model_view_matrix_uniform = gl.GetUniformLocation(lb.program.index, "u_model_view_matrix");
    lb.projection_matrix_uniform = gl.GetUniformLocation(lb.program.index, "u_projection_matrix");
    lb.line_color_uniform = gl.GetUniformLocation(lb.program.index, "u_line_color");
    lb.line_width_uniform = gl.GetUniformLocation(lb.program.index, "u_line_width");

    lb.position_attrib = .{
        .index = @intCast(gl.GetAttribLocation(lb.program.index, "a_position")),
        .size = 3,
        .type = gl.FLOAT,
        .normalized = false,
    };

    return lb;
}

pub fn deinit(lb: *LineBold) void {
    lb.program.deinit();
}

pub const Parameters = struct {
    shader: *const LineBold,
    vao: VAO,

    model_view_matrix: [16]f32 = undefined,
    projection_matrix: [16]f32 = undefined,
    line_color: [4]f32 = .{ 0, 0, 0.1, 1 },
    line_width: f32 = 1.0,

    const VertexAttrib = enum {
        position,
    };

    pub fn init() Parameters {
        return .{
            .shader = instance(),
            .vao = VAO.init(),
        };
    }

    pub fn deinit(p: *Parameters) void {
        p.vao.deinit();
    }

    pub fn setVertexAttribArray(p: *Parameters, attrib: VertexAttrib, vbo: VBO, stride: isize, pointer: usize) void {
        const attrib_info = switch (attrib) {
            .position => p.shader.position_attrib,
        };
        p.vao.enableVertexAttribArray(attrib_info, vbo, stride, pointer);
    }

    pub fn unsetVertexAttribArray(p: *Parameters, attrib: VertexAttrib) void {
        const attrib_info = switch (attrib) {
            .position => p.shader.position_attrib,
        };
        p.vao.disableVertexAttribArray(attrib_info);
    }

    pub fn draw(p: *Parameters, ibo: IBO) void {
        gl.UseProgram(p.shader.program.index);
        defer gl.UseProgram(0);
        gl.UniformMatrix4fv(p.shader.model_view_matrix_uniform, 1, gl.FALSE, @ptrCast(&p.model_view_matrix));
        gl.UniformMatrix4fv(p.shader.projection_matrix_uniform, 1, gl.FALSE, @ptrCast(&p.projection_matrix));
        // var viewport: [4]i32 = .{ 0, 0, 0, 0 };
        // gl.GetIntegerv(gl.VIEWPORT, &viewport);
        // gl.Uniform2f(p.shader.viewport_size_uniform, @as(f32, @floatFromInt(viewport[2])), @as(f32, @floatFromInt(viewport[3])));
        gl.Uniform4fv(p.shader.line_color_uniform, 1, @ptrCast(&p.line_color));
        gl.LineWidth(p.line_width);
        gl.BindVertexArray(p.vao.index);
        defer gl.BindVertexArray(0);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo.index);
        defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
        gl.DrawElements(gl.LINES, @intCast(ibo.nb_indices), gl.UNSIGNED_INT, 0);
    }
};
