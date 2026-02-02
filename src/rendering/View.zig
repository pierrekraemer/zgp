const View = @This();

const std = @import("std");
const gl = @import("gl");
const gl_log = std.log.scoped(.gl);

const zgp = @import("../main.zig");
const c = zgp.c;

const Module = @import("../modules/Module.zig");

const eigen = @import("../geometry/eigen.zig");
const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;
const Vec4d = vec.Vec4d;
const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;
const Mat4d = mat.Mat4d;
const bvh = @import("../geometry/bvh.zig");
const Ray = bvh.Ray;

const Camera = @import("Camera.zig");
const FBO = @import("FBO.zig");
const Texture2D = @import("Texture2D.zig");
const FullscreenTexture = @import("shaders/fullscreen_texture/FullscreenTexture.zig");

camera: ?*Camera = null,

width: c_int,
height: c_int,
screen_color_tex: Texture2D = undefined,
screen_depth_tex: Texture2D = undefined,

fbo: FBO = undefined,
fullscreen_texture_shader_parameters: FullscreenTexture.Parameters = undefined,

need_redraw: bool,

pub fn init(width: c_int, height: c_int) !View {
    var view: View = .{
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

pub fn setCamera(view: *View, camera: *Camera, allocator: std.mem.Allocator) !void {
    if (view.camera) |old_camera| {
        // remove the view from its previous camera
        const idx: usize = for (old_camera.views_using_camera.items, 0..) |v, index| {
            if (v == view) {
                break index;
            }
        } else unreachable; // the view must be found in the old camera's list of views using it
        _ = old_camera.views_using_camera.swapRemove(idx);
    }
    view.camera = camera;
    try camera.views_using_camera.append(allocator, view);
}

pub fn resize(view: *View, width: c_int, height: c_int) void {
    view.width = width;
    view.height = height;
    view.screen_color_tex.resize(width, height, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE);
    view.screen_depth_tex.resize(width, height, gl.DEPTH_COMPONENT, gl.DEPTH_COMPONENT, gl.FLOAT);

    if (view.camera) |camera| {
        camera.aspect_ratio = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
        camera.updateProjectionMatrix();
    } else {
        gl_log.err("No camera set for view, cannot update aspect ratio", .{});
    }
}

pub fn draw(view: *View, modules: []*Module) void {
    if (view.camera == null) {
        gl_log.err("No camera set for view", .{});
        return;
    }
    gl.Viewport(0, 0, view.width, view.height);
    if (view.need_redraw) {
        gl.BindFramebuffer(gl.FRAMEBUFFER, view.fbo.index);
        defer gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        gl.Enable(gl.DEPTH_TEST);
        // gl.DrawBuffer(gl.COLOR_ATTACHMENT0); // not needed as it is already the default
        for (modules) |module| {
            module.draw(view.camera.?.view_matrix, view.camera.?.projection_matrix);
        }
        gl.Disable(gl.DEPTH_TEST);
        view.need_redraw = false;
    }
    gl.Clear(gl.COLOR_BUFFER_BIT);
    view.fullscreen_texture_shader_parameters.useShader();
    view.fullscreen_texture_shader_parameters.draw();
    gl.UseProgram(0);
}

pub fn sdlEvent(view: *View, event: *const c.SDL_Event) void {
    switch (event.type) {
        c.SDL_EVENT_WINDOW_RESIZED => {
            view.resize(zgp.window_width, zgp.window_height);
        },
        c.SDL_EVENT_MOUSE_BUTTON_UP => {
            switch (event.button.button) {
                c.SDL_BUTTON_LEFT => {
                    const modState = c.SDL_GetModState();
                    if (view.camera != null and (modState & c.SDL_KMOD_SHIFT) != 0 and event.button.clicks == 2) {
                        const world_pos = view.pixelWorldPosition(event.button.x, event.button.y);
                        if (world_pos) |wp| {
                            view.camera.?.pivot_position = wp;
                        } else {
                            view.camera.?.pivot_position = .{ 0.0, 0.0, 0.0 };
                        }
                        view.camera.?.lookAtPivotPosition();
                    }
                },
                c.SDL_BUTTON_RIGHT => {},
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_MOTION => {
            switch (event.motion.state) {
                c.SDL_BUTTON_LMASK => {
                    const modState = c.SDL_GetModState();
                    if (view.camera != null) {
                        if ((modState & c.SDL_KMOD_SHIFT) != 0) {
                            view.camera.?.translateFromScreenVec(.{ event.motion.xrel, event.motion.yrel });
                        } else {
                            view.camera.?.rotateFromScreenVec(.{ event.motion.xrel, event.motion.yrel });
                        }
                    }
                },
                c.SDL_BUTTON_RMASK => {},
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_WHEEL => {
            const wheel = event.wheel.y;
            if (view.camera != null and wheel != 0) {
                view.camera.?.moveForward(wheel * 0.01);
                if (view.camera.?.projection_type == .orthographic) {
                    view.camera.?.updateProjectionMatrix();
                }
            }
        },
        else => {},
    }
}

pub fn pixelWorldPosition(view: *const View, x: f32, y: f32) ?Vec3f {
    if (view.camera == null) {
        gl_log.err("No camera set for view", .{});
        return null;
    }
    var z: f32 = undefined;
    gl.BindFramebuffer(gl.READ_FRAMEBUFFER, view.fbo.index);
    defer gl.BindFramebuffer(gl.READ_FRAMEBUFFER, 0);
    gl.ReadBuffer(gl.DEPTH_ATTACHMENT);
    gl.ReadPixels(
        @intFromFloat(x),
        view.height - 1 - @as(c_int, @intFromFloat(y)), // OpenGL's origin is bottom-left
        1,
        1,
        gl.DEPTH_COMPONENT,
        gl.FLOAT,
        &z,
    );
    if (z == 1.0) {
        // no geometry was drawn at this pixel
        return null;
    }
    // reconstruct the world position from the depth value
    // warning: Eigen (via ceigen) uses double precision
    const p_ndc: Vec4d = .{
        2.0 * (x / @as(f64, @floatFromInt(view.width))) - 1.0,
        1.0 - (2.0 * y) / @as(f64, @floatFromInt(view.height)),
        z * 2.0 - 1.0,
        1.0,
    };
    const m_proj = mat.mat4dFromMat4f(view.camera.?.projection_matrix);
    const m_proj_inv = eigen.computeInverse4d(m_proj) orelse {
        gl_log.err("Cannot invert projection matrix", .{});
        return null;
    };
    var p_view = mat.mulVec4d(m_proj_inv, p_ndc);
    if (p_view[3] == 0.0) {
        gl_log.err("Cannot divide by zero w component", .{});
        return null;
    }
    p_view = vec.divScalar4d(p_view, p_view[3]);
    const m_view = mat.mat4dFromMat4f(view.camera.?.view_matrix);
    const m_view_inv = eigen.computeInverse4d(m_view) orelse {
        gl_log.err("Cannot invert view matrix", .{});
        return null;
    };
    const p_world_f = vec.vec4fFromVec4d(mat.mulVec4d(m_view_inv, p_view));
    return .{ p_world_f[0], p_world_f[1], p_world_f[2] };
}

pub fn pixelWorldRayIfGeometry(view: *const View, x: f32, y: f32) ?Ray {
    if (view.camera == null) {
        gl_log.err("No camera set for view", .{});
        return null;
    }
    const pwp = pixelWorldPosition(view, x, y);
    return if (pwp == null) null else .{
        .origin = view.camera.?.position,
        .direction = vec.normalized3f(vec.sub3f(pwp.?, view.camera.?.position)),
    };
}
