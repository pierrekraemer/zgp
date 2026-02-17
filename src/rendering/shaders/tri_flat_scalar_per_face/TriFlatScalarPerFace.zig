const TriFlatScalarPerFace = @This();

const std = @import("std");
const assert = std.debug.assert;
const gl = @import("gl");

const Shader = @import("../../Shader.zig");
const VAO = @import("../../VAO.zig");
const VBO = @import("../../VBO.zig");
const IBO = @import("../../IBO.zig");
const TextureBuffer = @import("../../TextureBuffer.zig");

var global_instance: TriFlatScalarPerFace = undefined;
var init_global_once = std.once(init_global);
fn init_global() void {
    global_instance = init() catch unreachable;
    Shader.register(&global_instance.program);
}
pub fn instance() *TriFlatScalarPerFace {
    init_global_once.call();
    return &global_instance;
}

program: Shader,

model_view_matrix_uniform: c_int = undefined,
projection_matrix_uniform: c_int = undefined,
ambiant_color_uniform: c_int = undefined,
light_position_uniform: c_int = undefined,
min_value_uniform: c_int = undefined,
max_value_uniform: c_int = undefined,
face_index_buffer_uniform: c_int = undefined,
face_scalar_buffer_uniform: c_int = undefined,

position_attrib: VAO.VertexAttribInfo = undefined,

const VertexAttrib = enum {
    position,
};

fn init() !TriFlatScalarPerFace {
    var tfspf: TriFlatScalarPerFace = .{
        .program = Shader.init(),
    };

    const vertex_shader_source = @embedFile("vs.glsl");
    const fragment_shader_source = @embedFile("fs.glsl");

    try tfspf.program.setShader(.vertex, vertex_shader_source);
    try tfspf.program.setShader(.fragment, fragment_shader_source);
    try tfspf.program.linkProgram();

    tfspf.model_view_matrix_uniform = gl.GetUniformLocation(tfspf.program.index, "u_model_view_matrix");
    tfspf.projection_matrix_uniform = gl.GetUniformLocation(tfspf.program.index, "u_projection_matrix");
    tfspf.ambiant_color_uniform = gl.GetUniformLocation(tfspf.program.index, "u_ambiant_color");
    tfspf.light_position_uniform = gl.GetUniformLocation(tfspf.program.index, "u_light_position");
    tfspf.min_value_uniform = gl.GetUniformLocation(tfspf.program.index, "u_min_value");
    tfspf.max_value_uniform = gl.GetUniformLocation(tfspf.program.index, "u_max_value");
    tfspf.face_index_buffer_uniform = gl.GetUniformLocation(tfspf.program.index, "u_face_index_buffer");
    tfspf.face_scalar_buffer_uniform = gl.GetUniformLocation(tfspf.program.index, "u_face_scalar_buffer");

    tfspf.position_attrib = .{
        .index = @intCast(gl.GetAttribLocation(tfspf.program.index, "a_position")),
        .size = 3,
        .type = gl.FLOAT,
        .normalized = false,
    };

    return tfspf;
}

pub const Parameters = struct {
    shader: *const TriFlatScalarPerFace,
    vao: VAO,

    face_index_buffer_texture: TextureBuffer,
    face_index_buffer_texture_unit: c_int,
    face_scalar_buffer_texture: TextureBuffer,
    face_scalar_buffer_texture_unit: c_int,

    face_scalar_buffer: ?VBO = null,

    model_view_matrix: [16]f32 = undefined,
    projection_matrix: [16]f32 = undefined,
    ambiant_color: [4]f32 = .{ 0.1, 0.1, 0.1, 1 },
    light_position: [3]f32 = .{ 10, 0, 100 },
    min_value: f32 = 0.0,
    max_value: f32 = 1.0,

    pub fn init() Parameters {
        return .{
            .shader = instance(),
            .vao = VAO.init(),
            .face_index_buffer_texture = TextureBuffer.init(),
            .face_index_buffer_texture_unit = 0,
            .face_scalar_buffer_texture = TextureBuffer.init(),
            .face_scalar_buffer_texture_unit = 1,
        };
    }

    pub fn deinit(p: *Parameters) void {
        p.vao.deinit();
        p.face_index_buffer_texture.deinit();
        p.face_scalar_buffer_texture.deinit();
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
        gl.Uniform1f(p.shader.min_value_uniform, p.min_value);
        gl.Uniform1f(p.shader.max_value_uniform, p.max_value);

        gl.ActiveTexture(gl.TEXTURE0 + @as(c_uint, @intCast(p.face_index_buffer_texture_unit)));
        gl.BindTexture(gl.TEXTURE_BUFFER, p.face_index_buffer_texture.index);
        gl.TexBuffer(gl.TEXTURE_BUFFER, gl.R32UI, ibo.cell_index_buffer_index);
        gl.Uniform1i(p.shader.face_index_buffer_uniform, p.face_index_buffer_texture_unit);
        defer {
            gl.ActiveTexture(gl.TEXTURE0 + @as(c_uint, @intCast(p.face_index_buffer_texture_unit)));
            gl.BindTexture(gl.TEXTURE_BUFFER, 0);
        }

        if (p.face_scalar_buffer) |face_scalar_buffer| {
            gl.ActiveTexture(gl.TEXTURE0 + @as(c_uint, @intCast(p.face_scalar_buffer_texture_unit)));
            gl.BindTexture(gl.TEXTURE_BUFFER, p.face_scalar_buffer_texture.index);
            gl.TexBuffer(gl.TEXTURE_BUFFER, gl.R32F, face_scalar_buffer.index);
            gl.Uniform1i(p.shader.face_scalar_buffer_uniform, p.face_scalar_buffer_texture_unit);
        }
        defer {
            gl.ActiveTexture(gl.TEXTURE0 + @as(c_uint, @intCast(p.face_scalar_buffer_texture_unit)));
            gl.BindTexture(gl.TEXTURE_BUFFER, 0);
        }

        gl.BindVertexArray(p.vao.index);
        defer gl.BindVertexArray(0);

        assert(ibo.primitive == .triangles);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo.index);
        defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);

        gl.DrawElements(gl.TRIANGLES, @intCast(ibo.nb_indices), gl.UNSIGNED_INT, 0);
    }
};
