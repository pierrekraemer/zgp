const InfiniteGrid = @This();

const std = @import("std");
const gl = @import("gl");

const Shader = @import("../../Shader.zig");
const VAO = @import("../../VAO.zig");
const eigen = @import("../../../geometry/eigen.zig");
const mat = @import("../../../geometry/mat.zig");
const Mat4f = mat.Mat4f;

const gl_log = std.log.scoped(.infinite_grid);

var global_instance: ?InfiniteGrid = null;
fn init_global() void {
    if (global_instance) |_| return;
    global_instance = init() catch unreachable;
    Shader.register(&global_instance.?.program);
}
pub fn instance() *InfiniteGrid {
    init_global();
    return &global_instance.?;
}

program: Shader,

inv_view_proj_uniform: c_int = undefined,
view_proj_uniform: c_int = undefined,
near_uniform: c_int = undefined,
far_uniform: c_int = undefined,

fn init() !InfiniteGrid {
    var ig: InfiniteGrid = .{
        .program = Shader.init(),
    };

    const vertex_shader_source = @embedFile("vs.glsl");
    const fragment_shader_source = @embedFile("fs.glsl");

    try ig.program.setShader(.vertex, vertex_shader_source);
    try ig.program.setShader(.fragment, fragment_shader_source);
    try ig.program.linkProgram();

    ig.inv_view_proj_uniform = gl.GetUniformLocation(ig.program.index, "u_inv_view_proj");
    ig.view_proj_uniform = gl.GetUniformLocation(ig.program.index, "u_view_proj");
    ig.near_uniform = gl.GetUniformLocation(ig.program.index, "u_near");
    ig.far_uniform = gl.GetUniformLocation(ig.program.index, "u_far");

    return ig;
}

pub const Parameters = struct {
    shader: *const InfiniteGrid,
    vao: VAO,

    pub fn init() Parameters {
        return .{
            .shader = instance(),
            .vao = VAO.init(),
        };
    }

    pub fn deinit(p: *Parameters) void {
        p.vao.deinit();
    }

    pub fn draw(p: *Parameters, view_matrix: Mat4f, projection_matrix: Mat4f) void {
        // Compute view-projection (P * V) and its inverse
        const view_proj = mat.mul4f(projection_matrix, view_matrix);
        // Use Eigen (double precision) to invert, same as View.viewToWorldZ
        const view_proj_d = mat.mat4dFromMat4f(view_proj);
        const inv_view_proj_d = eigen.computeInverse4d(view_proj_d) orelse {
            gl_log.err("Cannot invert view-projection matrix", .{});
            return;
        };
        const inv_view_proj = mat.mat4fFromMat4d(inv_view_proj_d);

        gl.UseProgram(p.shader.program.index);
        defer gl.UseProgram(0);

        gl.UniformMatrix4fv(p.shader.inv_view_proj_uniform, 1, gl.FALSE, @ptrCast(&inv_view_proj));
        gl.UniformMatrix4fv(p.shader.view_proj_uniform, 1, gl.FALSE, @ptrCast(&view_proj));
        gl.Uniform1f(p.shader.near_uniform, 0.01);
        gl.Uniform1f(p.shader.far_uniform, 5.0);

        gl.BindVertexArray(p.vao.index);
        defer gl.BindVertexArray(0);

        // Enable blending for the distance-fade transparency
        gl.Enable(gl.BLEND);
        gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        gl.DrawArrays(gl.TRIANGLES, 0, 6);

        gl.Disable(gl.BLEND);
    }
};
