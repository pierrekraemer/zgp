const TriFlat = @This();

const std = @import("std");
const assert = std.debug.assert;
const gl = @import("gl");

const Shader = @import("../../Shader.zig");
const VAO = @import("../../VAO.zig");
const VBO = @import("../../VBO.zig");
const IBO = @import("../../IBO.zig");

var global_instance: TriFlat = undefined;
var init_global_once = std.once(init_global);
fn init_global() void {
    global_instance = init() catch unreachable;
    Shader.register(&global_instance.program);
}
pub fn instance() *TriFlat {
    init_global_once.call();
    return &global_instance;
}

program: Shader,

model_view_matrix_uniform: c_int = undefined,
projection_matrix_uniform: c_int = undefined,
ambiant_color_uniform: c_int = undefined,
light_position_uniform: c_int = undefined,
vertex_color_uniform: c_int = undefined,

position_attrib: VAO.VertexAttribInfo = undefined,

const VertexAttrib = enum {
    position,
};

fn init() !TriFlat {
    var tf: TriFlat = .{
        .program = Shader.init(),
    };

    const vertex_shader_source = @embedFile("vs.glsl");
    const fragment_shader_source = @embedFile("fs.glsl");

    try tf.program.setShader(.vertex, vertex_shader_source);
    try tf.program.setShader(.fragment, fragment_shader_source);
    try tf.program.linkProgram();

    tf.model_view_matrix_uniform = gl.GetUniformLocation(tf.program.index, "u_model_view_matrix");
    tf.projection_matrix_uniform = gl.GetUniformLocation(tf.program.index, "u_projection_matrix");
    tf.ambiant_color_uniform = gl.GetUniformLocation(tf.program.index, "u_ambiant_color");
    tf.light_position_uniform = gl.GetUniformLocation(tf.program.index, "u_light_position");
    tf.vertex_color_uniform = gl.GetUniformLocation(tf.program.index, "u_vertex_color");

    tf.position_attrib = .{
        .index = @intCast(gl.GetAttribLocation(tf.program.index, "a_position")),
        .size = 3,
        .type = gl.FLOAT,
        .normalized = false,
    };

    return tf;
}

pub const Parameters = struct {
    shader: *const TriFlat,
    vao: VAO,

    model_view_matrix: [16]f32 = undefined,
    projection_matrix: [16]f32 = undefined,
    ambiant_color: [4]f32 = .{ 0.1, 0.1, 0.1, 1 },
    light_position: [3]f32 = .{ 10, 0, 100 },
    vertex_color: [4]f32 = .{ 0.8, 0.8, 0.8, 1 },

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
        gl.Uniform4fv(p.shader.ambiant_color_uniform, 1, @ptrCast(&p.ambiant_color));
        gl.Uniform3fv(p.shader.light_position_uniform, 1, @ptrCast(&p.light_position));
        gl.Uniform4fv(p.shader.vertex_color_uniform, 1, @ptrCast(&p.vertex_color));

        gl.BindVertexArray(p.vao.index);
        defer gl.BindVertexArray(0);

        assert(ibo.primitive == .triangles);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo.index);
        defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);

        gl.DrawElements(gl.TRIANGLES, @intCast(ibo.nb_indices), gl.UNSIGNED_INT, 0);
    }
};
