const PointVector = @This();

const std = @import("std");
const gl = @import("gl");

const Shader = @import("../../Shader.zig");
const VAO = @import("../../VAO.zig");
const VBO = @import("../../VBO.zig");
const IBO = @import("../../IBO.zig");

var global_instance: PointVector = undefined;
var init_global_once = std.once(init_global);
fn init_global() void {
    global_instance = init() catch unreachable;
}
pub fn instance() *PointVector {
    init_global_once.call();
    return &global_instance;
}

program: Shader,

model_view_matrix_uniform: c_int = undefined,
projection_matrix_uniform: c_int = undefined,
vector_scale_uniform: c_int = undefined,
vector_color_uniform: c_int = undefined,
// vector_width_uniform: c_int = undefined,

position_attrib: VAO.VertexAttribInfo = undefined,
vector_attrib: VAO.VertexAttribInfo = undefined,

fn init() !PointVector {
    var pv: PointVector = .{
        .program = Shader.init(),
    };

    const vertex_shader_source = @embedFile("vs.glsl");
    const geometry_shader_source = @embedFile("gs.glsl");
    const fragment_shader_source = @embedFile("fs.glsl");

    try pv.program.setShader(.vertex, vertex_shader_source);
    try pv.program.setShader(.geometry, geometry_shader_source);
    try pv.program.setShader(.fragment, fragment_shader_source);
    try pv.program.linkProgram();

    pv.model_view_matrix_uniform = gl.GetUniformLocation(pv.program.index, "u_model_view_matrix");
    pv.projection_matrix_uniform = gl.GetUniformLocation(pv.program.index, "u_projection_matrix");
    pv.vector_scale_uniform = gl.GetUniformLocation(pv.program.index, "u_vector_scale");
    pv.vector_color_uniform = gl.GetUniformLocation(pv.program.index, "u_vector_color");
    // pv.vector_width_uniform = gl.GetUniformLocation(pv.program.index, "u_vector_width");

    pv.position_attrib = .{
        .index = @intCast(gl.GetAttribLocation(pv.program.index, "a_position")),
        .size = 3,
        .type = gl.FLOAT,
        .normalized = false,
    };
    pv.vector_attrib = .{
        .index = @intCast(gl.GetAttribLocation(pv.program.index, "a_vector")),
        .size = 3,
        .type = gl.FLOAT,
        .normalized = false,
    };

    return pv;
}

pub fn deinit(pv: *PointVector) void {
    pv.program.deinit();
}

pub const Parameters = struct {
    shader: *const PointVector,
    vao: VAO,

    model_view_matrix: [16]f32 = undefined,
    projection_matrix: [16]f32 = undefined,
    vector_scale: f32 = 0.005,
    vector_color: [4]f32 = .{ 0, 0, 0, 0 },
    vector_width: f32 = 1.0,

    const VertexAttrib = enum {
        position,
        vector,
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
            .vector => p.shader.vector_attrib,
        };
        p.vao.enableVertexAttribArray(attrib_info, vbo, stride, pointer);
    }

    pub fn unsetVertexAttribArray(p: *Parameters, attrib: VertexAttrib) void {
        const attrib_info = switch (attrib) {
            .position => p.shader.position_attrib,
            .vector => p.shader.vector_attrib,
        };
        p.vao.disableVertexAttribArray(attrib_info);
    }

    pub fn draw(p: *Parameters, ibo: IBO) void {
        gl.UseProgram(p.shader.program.index);
        defer gl.UseProgram(0);
        gl.UniformMatrix4fv(p.shader.model_view_matrix_uniform, 1, gl.FALSE, @ptrCast(&p.model_view_matrix));
        gl.UniformMatrix4fv(p.shader.projection_matrix_uniform, 1, gl.FALSE, @ptrCast(&p.projection_matrix));
        gl.Uniform1f(p.shader.vector_scale_uniform, p.vector_scale);
        gl.Uniform4fv(p.shader.vector_color_uniform, 1, @ptrCast(&p.vector_color));
        // var viewport: [4]i32 = .{ 0, 0, 0, 0 };
        // gl.GetIntegerv(gl.VIEWPORT, &viewport);
        // gl.Uniform2f(p.shader.vector_width_uniform, p.vector_width / @as(f32, @floatFromInt(viewport[2])), p.vector_width / @as(f32, @floatFromInt(viewport[3])));
        gl.LineWidth(p.vector_width);
        gl.BindVertexArray(p.vao.index);
        defer gl.BindVertexArray(0);
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo.index);
        defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
        gl.DrawElements(gl.POINTS, @intCast(ibo.nb_indices), gl.UNSIGNED_INT, 0);
    }
};
