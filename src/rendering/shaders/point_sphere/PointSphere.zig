const PointSphere = @This();

const std = @import("std");
const gl = @import("gl");

const Shader = @import("../../Shader.zig");
const VAO = @import("../../VAO.zig");
const VBO = @import("../../VBO.zig");
const IBO = @import("../../IBO.zig");

var global_instance: PointSphere = undefined;
var init_global_once = std.once(init_global);
fn init_global() void {
    global_instance = init() catch unreachable;
}
pub fn instance() *PointSphere {
    init_global_once.call();
    return &global_instance;
}

program: Shader,

model_view_matrix_uniform: c_int = undefined,
projection_matrix_uniform: c_int = undefined,
ambiant_color_uniform: c_int = undefined,
light_position_uniform: c_int = undefined,
point_size_uniform: c_int = undefined,

position_attrib: VAO.VertexAttribInfo = undefined,
color_attrib: VAO.VertexAttribInfo = undefined,

fn init() !PointSphere {
    var ps: PointSphere = .{
        .program = Shader.init(),
    };

    const vertex_shader_source = @embedFile("vs.glsl");
    const geometry_shader_source = @embedFile("gs.glsl");
    const fragment_shader_source = @embedFile("fs.glsl");

    try ps.program.setShader(.vertex, vertex_shader_source);
    try ps.program.setShader(.geometry, geometry_shader_source);
    try ps.program.setShader(.fragment, fragment_shader_source);
    try ps.program.linkProgram();

    ps.model_view_matrix_uniform = gl.GetUniformLocation(ps.program.index, "u_model_view_matrix");
    ps.projection_matrix_uniform = gl.GetUniformLocation(ps.program.index, "u_projection_matrix");
    ps.ambiant_color_uniform = gl.GetUniformLocation(ps.program.index, "u_ambiant_color");
    ps.light_position_uniform = gl.GetUniformLocation(ps.program.index, "u_light_position");
    ps.point_size_uniform = gl.GetUniformLocation(ps.program.index, "u_point_size");

    ps.position_attrib = .{
        .index = @intCast(gl.GetAttribLocation(ps.program.index, "a_position")),
        .size = 3,
        .type = gl.FLOAT,
        .normalized = false,
    };
    ps.color_attrib = .{
        .index = @intCast(gl.GetAttribLocation(ps.program.index, "a_color")),
        .size = 3,
        .type = gl.FLOAT,
        .normalized = false,
    };

    return ps;
}

pub fn deinit(ps: *PointSphere) void {
    ps.program.deinit();
}

pub const Parameters = struct {
    shader: *const PointSphere,
    vao: VAO,

    model_view_matrix: [16]f32 = undefined,
    projection_matrix: [16]f32 = undefined,
    ambiant_color: [4]f32 = .{ 0.1, 0.1, 0.1, 1 },
    light_position: [3]f32 = .{ -100, 0, 100 },
    point_size: f32 = 0.001,

    const VertexAttrib = enum {
        position,
        color,
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
            .color => p.shader.color_attrib,
        };
        p.vao.enableVertexAttribArray(attrib_info, vbo, stride, pointer);
    }

    pub fn unsetVertexAttribArray(p: *Parameters, attrib: VertexAttrib) void {
        const attrib_info = switch (attrib) {
            .position => p.shader.position_attrib,
            .color => p.shader.color_attrib,
        };
        p.vao.disableVertexAttribArray(attrib_info);
    }

    pub fn draw(p: *Parameters, ibo: IBO) void {
        gl.UseProgram(p.shader.program.index);
        defer gl.UseProgram(0);
        gl.UniformMatrix4fv(p.shader.model_view_matrix_uniform, 1, gl.FALSE, &p.model_view_matrix);
        gl.UniformMatrix4fv(p.shader.projection_matrix_uniform, 1, gl.FALSE, &p.projection_matrix);
        gl.Uniform4fv(p.shader.ambiant_color_uniform, 1, &p.ambiant_color);
        gl.Uniform3fv(p.shader.light_position_uniform, 1, &p.light_position);
        gl.Uniform1f(p.shader.point_size_uniform, p.point_size);
        gl.BindVertexArray(p.vao.index);
        defer gl.BindVertexArray(0);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo.index);
        defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
        gl.DrawElements(gl.POINTS, @intCast(ibo.nb_indices), gl.UNSIGNED_INT, 0);
    }
};
