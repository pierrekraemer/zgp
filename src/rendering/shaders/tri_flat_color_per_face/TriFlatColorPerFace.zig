const TriFlatColorPerFace = @This();

const std = @import("std");
const assert = std.debug.assert;
const gl = @import("gl");

const Shader = @import("../../Shader.zig");
const VAO = @import("../../VAO.zig");
const VBO = @import("../../VBO.zig");
const IBO = @import("../../IBO.zig");
const TextureBuffer = @import("../../TextureBuffer.zig");

var global_instance: TriFlatColorPerFace = undefined;
var init_global_once = std.once(init_global);
fn init_global() void {
    global_instance = init() catch unreachable;
}
pub fn instance() *TriFlatColorPerFace {
    init_global_once.call();
    return &global_instance;
}

program: Shader,

model_view_matrix_uniform: c_int = undefined,
projection_matrix_uniform: c_int = undefined,
ambiant_color_uniform: c_int = undefined,
light_position_uniform: c_int = undefined,
face_index_buffer_uniform: c_int = undefined,
face_color_buffer_uniform: c_int = undefined,

position_attrib: VAO.VertexAttribInfo = undefined,

const VertexAttrib = enum {
    position,
};

fn init() !TriFlatColorPerFace {
    var tfcpf: TriFlatColorPerFace = .{
        .program = Shader.init(),
    };

    const vertex_shader_source = @embedFile("vs.glsl");
    const fragment_shader_source = @embedFile("fs.glsl");

    try tfcpf.program.setShader(.vertex, vertex_shader_source);
    try tfcpf.program.setShader(.fragment, fragment_shader_source);
    try tfcpf.program.linkProgram();

    tfcpf.model_view_matrix_uniform = gl.GetUniformLocation(tfcpf.program.index, "u_model_view_matrix");
    tfcpf.projection_matrix_uniform = gl.GetUniformLocation(tfcpf.program.index, "u_projection_matrix");
    tfcpf.ambiant_color_uniform = gl.GetUniformLocation(tfcpf.program.index, "u_ambiant_color");
    tfcpf.light_position_uniform = gl.GetUniformLocation(tfcpf.program.index, "u_light_position");
    tfcpf.face_index_buffer_uniform = gl.GetUniformLocation(tfcpf.program.index, "u_face_index_buffer");
    tfcpf.face_color_buffer_uniform = gl.GetUniformLocation(tfcpf.program.index, "u_face_color_buffer");

    tfcpf.position_attrib = .{
        .index = @intCast(gl.GetAttribLocation(tfcpf.program.index, "a_position")),
        .size = 3,
        .type = gl.FLOAT,
        .normalized = false,
    };

    return tfcpf;
}

pub fn deinit(tfcpf: *TriFlatColorPerFace) void {
    tfcpf.program.deinit();
}

pub const Parameters = struct {
    shader: *const TriFlatColorPerFace,
    vao: VAO,

    face_index_buffer_texture: TextureBuffer,
    face_index_buffer_texture_unit: c_int,
    face_color_buffer_texture: TextureBuffer,
    face_color_buffer_texture_unit: c_int,

    face_color_buffer: ?VBO = null,

    model_view_matrix: [16]f32 = undefined,
    projection_matrix: [16]f32 = undefined,
    ambiant_color: [4]f32 = .{ 0.1, 0.1, 0.1, 1 },
    light_position: [3]f32 = .{ 10, 0, 100 },

    pub fn init() Parameters {
        return .{
            .shader = instance(),
            .vao = VAO.init(),
            .face_index_buffer_texture = TextureBuffer.init(),
            .face_index_buffer_texture_unit = 0,
            .face_color_buffer_texture = TextureBuffer.init(),
            .face_color_buffer_texture_unit = 1,
        };
    }

    pub fn deinit(p: *Parameters) void {
        p.vao.deinit();
        p.face_index_buffer_texture.deinit();
        p.face_color_buffer_texture.deinit();
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

        gl.ActiveTexture(gl.TEXTURE0 + @as(c_uint, @intCast(p.face_index_buffer_texture_unit)));
        gl.BindTexture(gl.TEXTURE_BUFFER, p.face_index_buffer_texture.index);
        gl.TexBuffer(gl.TEXTURE_BUFFER, gl.R32UI, ibo.cell_index_buffer_index);
        gl.Uniform1i(p.shader.face_index_buffer_uniform, p.face_index_buffer_texture_unit);
        defer {
            gl.ActiveTexture(gl.TEXTURE0 + @as(c_uint, @intCast(p.face_index_buffer_texture_unit)));
            gl.BindTexture(gl.TEXTURE_BUFFER, 0);
        }

        if (p.face_color_buffer) |face_color_buffer| {
            gl.ActiveTexture(gl.TEXTURE0 + @as(c_uint, @intCast(p.face_color_buffer_texture_unit)));
            gl.BindTexture(gl.TEXTURE_BUFFER, p.face_color_buffer_texture.index);
            gl.TexBuffer(gl.TEXTURE_BUFFER, gl.RGB32F, face_color_buffer.index);
            gl.Uniform1i(p.shader.face_color_buffer_uniform, p.face_color_buffer_texture_unit);
        }
        defer {
            gl.ActiveTexture(gl.TEXTURE0 + @as(c_uint, @intCast(p.face_color_buffer_texture_unit)));
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
