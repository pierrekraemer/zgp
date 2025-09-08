const View = @This();

const std = @import("std");
const gl = @import("gl");

const gl_log = std.log.scoped(.gl);

const Module = @import("../modules/Module.zig");

const Camera = @import("Camera.zig");
const FBO = @import("FBO.zig");
const Texture2D = @import("Texture2D.zig");
const FullscreenTexture = @import("shaders/fullscreen_texture/FullscreenTexture.zig");

camera: *const Camera,

width: c_int,
height: c_int,
screen_color_tex: Texture2D = undefined,
screen_depth_tex: Texture2D = undefined,

fbo: FBO = undefined,
fullscreen_texture_shader_parameters: FullscreenTexture.Parameters = undefined,

need_redraw: bool,

pub fn init(camera: *const Camera, width: c_int, height: c_int) !View {
    var view: View = .{
        .camera = camera,
        .width = width,
        .height = height,
        .need_redraw = true,
    };

    view.screen_color_tex = Texture2D.init(&[_]Texture2D.Parameter{
        .{ .name = gl.TEXTURE_MIN_FILTER, .value = gl.NEAREST },
        .{ .name = gl.TEXTURE_MAG_FILTER, .value = gl.NEAREST },
    });
    view.screen_color_tex.resize(view.width, view.height, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE);
    view.screen_depth_tex = Texture2D.init(&[_]Texture2D.Parameter{
        .{ .name = gl.TEXTURE_MIN_FILTER, .value = gl.NEAREST },
        .{ .name = gl.TEXTURE_MAG_FILTER, .value = gl.NEAREST },
    });
    view.screen_depth_tex.resize(view.width, view.height, gl.DEPTH_COMPONENT, gl.DEPTH_COMPONENT, gl.FLOAT);

    view.fbo = FBO.init();
    view.fbo.attachTexture(gl.COLOR_ATTACHMENT0, view.screen_color_tex);
    view.fbo.attachTexture(gl.DEPTH_ATTACHMENT, view.screen_depth_tex);

    const status = gl.CheckFramebufferStatus(gl.FRAMEBUFFER);
    if (status != gl.FRAMEBUFFER_COMPLETE) {
        gl_log.err("Framebuffer not complete: {d}", .{status});
    }

    view.fullscreen_texture_shader_parameters = FullscreenTexture.Parameters.init();
    view.fullscreen_texture_shader_parameters.setTexture(view.screen_color_tex, 0);

    return view;
}

pub fn deinit(view: *View) void {
    view.fullscreen_texture_shader_parameters.deinit();
    view.fbo.deinit();
    view.screen_depth_tex.deinit();
    view.screen_color_tex.deinit();
}

pub fn resize(view: *View, width: c_int, height: c_int) void {
    view.width = width;
    view.height = height;
    view.screen_color_tex.resize(width, height, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE);
    view.screen_depth_tex.resize(width, height, gl.DEPTH_COMPONENT, gl.DEPTH_COMPONENT, gl.FLOAT);
    view.need_redraw = true;
}

pub fn draw(view: *View, modules: []Module) void {
    gl.Viewport(0, 0, view.width, view.height);
    if (view.need_redraw) {
        gl.BindFramebuffer(gl.FRAMEBUFFER, view.fbo.index);
        defer gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        // gl.DrawBuffer(gl.COLOR_ATTACHMENT0); // not needed as it is already the default
        for (modules) |*module| {
            module.draw(view.camera.view_matrix, view.camera.projection_matrix);
        }
        view.need_redraw = false;
    }
    view.fullscreen_texture_shader_parameters.useShader();
    view.fullscreen_texture_shader_parameters.draw();
    gl.UseProgram(0);
}
