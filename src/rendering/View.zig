const View = @This();

const std = @import("std");
const gl = @import("gl");
const gl_log = std.log.scoped(.gl);

const c = @import("../main.zig").c;

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
const InfiniteGrid = @import("shaders/infinite_grid/InfiniteGrid.zig");

camera: Camera = undefined,

width: c_int = 0,
height: c_int = 0,

screen_color_tex: Texture2D = undefined,
screen_depth_tex: Texture2D = undefined,

fbo: FBO = undefined,
fullscreen_texture_shader_parameters: FullscreenTexture.Parameters = undefined,
infinite_grid_parameters: InfiniteGrid.Parameters = undefined,

background_color: Vec4f = .{ 0.35, 0.35, 0.35, 1 },
show_grid: bool = true,

needs_redraw: bool = true,

pub fn init(view: *View) void {
    view.camera = .init(
        .{ -0.5, 0.5, 2.0 },
        .{ 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 0.0 },
        1.0,
        0.2 * std.math.pi,
        .perspective,
    );

    view.screen_color_tex = .init(&[_]Texture2D.Parameter{
        .{ .name = gl.TEXTURE_MIN_FILTER, .value = gl.NEAREST },
        .{ .name = gl.TEXTURE_MAG_FILTER, .value = gl.NEAREST },
    });
    view.screen_depth_tex = .init(&[_]Texture2D.Parameter{
        .{ .name = gl.TEXTURE_MIN_FILTER, .value = gl.NEAREST },
        .{ .name = gl.TEXTURE_MAG_FILTER, .value = gl.NEAREST },
    });

    view.fbo = FBO.init();
    view.fbo.attachTexture(gl.COLOR_ATTACHMENT0, view.screen_color_tex);
    view.fbo.attachTexture(gl.DEPTH_ATTACHMENT, view.screen_depth_tex);

    const status = gl.CheckFramebufferStatus(gl.FRAMEBUFFER);
    if (status != gl.FRAMEBUFFER_COMPLETE) {
        gl_log.err("Framebuffer not complete: {d}", .{status});
    }

    view.fullscreen_texture_shader_parameters = .init();
    view.fullscreen_texture_shader_parameters.setTexture(view.screen_color_tex);
    view.infinite_grid_parameters = .init();
}

pub fn deinit(view: *View) void {
    view.infinite_grid_parameters.deinit();
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

    view.camera.aspect_ratio = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
    view.camera.updateProjectionMatrix();
}

pub fn draw(view: *View, modules: []*Module) void {
    gl.ClearColor(
        view.background_color[0],
        view.background_color[1],
        view.background_color[2],
        view.background_color[3],
    );
    gl.Viewport(0, 0, view.width, view.height);
    if (view.needs_redraw) {
        gl.BindFramebuffer(gl.FRAMEBUFFER, view.fbo.index);
        defer gl.BindFramebuffer(gl.FRAMEBUFFER, 0);

        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        gl.Enable(gl.DEPTH_TEST);
        gl.DrawBuffer(gl.COLOR_ATTACHMENT0);
        for (modules) |module| {
            module.draw(view.camera.view_matrix, view.camera.projection_matrix);
        }
        if (view.show_grid) {
            gl.DepthMask(gl.FALSE);
            view.infinite_grid_parameters.draw(view.camera.view_matrix, view.camera.projection_matrix);
            gl.DepthMask(gl.TRUE);
        }
        gl.Disable(gl.DEPTH_TEST);

        view.needs_redraw = false;
    }
    gl.Clear(gl.COLOR_BUFFER_BIT);
    view.fullscreen_texture_shader_parameters.draw();
    gl.UseProgram(0);
}

pub fn menuBar(view: *View) void {
    if (c.ImGui_BeginMenu("Camera")) {
        defer c.ImGui_EndMenu();
        if (c.ImGui_ColorEdit3("Background color", &view.background_color, c.ImGuiColorEditFlags_NoInputs)) {
            view.needs_redraw = true;
        }
        if (c.ImGui_MenuItemEx("Show grid", null, view.show_grid, true)) {
            view.show_grid = !view.show_grid;
            view.needs_redraw = true;
        }
        c.ImGui_Separator();
        if (c.ImGui_MenuItemEx("Perspective", null, view.camera.projection_type == .perspective, true)) {
            view.camera.projection_type = .perspective;
            view.camera.updateProjectionMatrix();
            view.needs_redraw = true;
        }
        if (c.ImGui_MenuItemEx("Orthographic", null, view.camera.projection_type == .orthographic, true)) {
            view.camera.projection_type = .orthographic;
            view.camera.updateProjectionMatrix();
            view.needs_redraw = true;
        }
        c.ImGui_Separator();
        if (c.ImGui_Button("Pivot around world origin")) {
            view.camera.pivot_position = .{ 0.0, 0.0, 0.0 };
            view.camera.look_dir = vec.normalized3f(vec.sub3f(view.camera.pivot_position, view.camera.position));
            view.camera.updateViewMatrix();
            view.needs_redraw = true;
        }
        if (c.ImGui_Button("Look at pivot point")) {
            view.camera.look_dir = vec.normalized3f(vec.sub3f(view.camera.pivot_position, view.camera.position));
            view.camera.updateViewMatrix();
            view.needs_redraw = true;
        }
    }
}

pub fn sdlEvent(view: *View, event: *const c.SDL_Event) void {
    switch (event.type) {
        c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            switch (event.button.button) {
                c.SDL_BUTTON_LEFT => {
                    const modState = c.SDL_GetModState();
                    if ((modState & c.SDL_KMOD_SHIFT) != 0 and event.button.clicks == 2) {
                        const world_pos = view.viewToWorld(event.button.x, event.button.y);
                        if (world_pos) |wp| {
                            view.camera.pivot_position = wp;
                        } else {
                            view.camera.pivot_position = .{ 0.0, 0.0, 0.0 };
                        }
                        view.camera.lookAtPivotPosition();
                        view.needs_redraw = true;
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
                    if ((modState & c.SDL_KMOD_SHIFT) != 0) {
                        view.camera.translateFromScreenVec(.{ event.motion.xrel, event.motion.yrel });
                        view.needs_redraw = true;
                    } else {
                        view.camera.rotateFromScreenVec(.{ event.motion.xrel, event.motion.yrel });
                        view.needs_redraw = true;
                    }
                },
                c.SDL_BUTTON_RMASK => {},
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_WHEEL => {
            const wheel = event.wheel.y;
            if (wheel != 0) {
                view.camera.moveForward(wheel * 0.01);
                if (view.camera.projection_type == .orthographic) {
                    view.camera.updateProjectionMatrix();
                }
                view.needs_redraw = true;
            }
        },
        else => {},
    }
}

/// Reconstruct the world position of the pixel at (x, y) in the view with given depth value z.
/// z is expected to be in [0, 1], as read from the depth buffer.
/// Returns null if the world position cannot be reconstructed (e.g. if the camera is not set or if the projection/view matrix cannot be inverted).
pub fn viewToWorldZ(view: *const View, x: f32, y: f32, z: f32) ?Vec3f {
    // reconstruct the world position from the depth value
    // warning: Eigen (via ceigen) uses double precision
    const p_ndc: Vec4d = .{
        2.0 * (x / @as(f64, @floatFromInt(view.width))) - 1.0,
        1.0 - (2.0 * y) / @as(f64, @floatFromInt(view.height)),
        z * 2.0 - 1.0,
        1.0,
    };
    const m_proj = mat.mat4dFromMat4f(view.camera.projection_matrix);
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
    const m_view = mat.mat4dFromMat4f(view.camera.view_matrix);
    const m_view_inv = eigen.computeInverse4d(m_view) orelse {
        gl_log.err("Cannot invert view matrix", .{});
        return null;
    };
    const p_world_f = vec.vec4fFromVec4d(mat.mulVec4d(m_view_inv, p_view));
    return .{ p_world_f[0], p_world_f[1], p_world_f[2] };
}

/// Reconstruct the world position of the pixel at (x, y) in the view with depth value read from the depth buffer.
/// Returns null if no geometry was drawn at this pixel (i.e. if the depth value is 1.0).
pub fn viewToWorld(view: *const View, x: f32, y: f32) ?Vec3f {
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
    return view.viewToWorldZ(x, y, z);
}

/// Reconstruct a ray in world space from the camera position through the pixel at (x, y) in the view.
/// Returns null if no geometry was drawn at this pixel (i.e. if the depth value read from the depth buffer is 1.0).
pub fn viewToWorldRayIfGeometry(view: *const View, x: f32, y: f32) ?Ray {
    const pwp = viewToWorld(view, x, y);
    return if (pwp == null) null else .{
        .origin = view.camera.position,
        .direction = vec.normalized3f(vec.sub3f(pwp.?, view.camera.position)),
    };
}

/// Reconstruct a ray in world space from the camera position through the pixel at (x, y) in the view.
pub fn viewToWorldRay(view: *const View, x: f32, y: f32) Ray {
    const width: f32 = @floatFromInt(view.width);
    const height: f32 = @floatFromInt(view.height);
    const x_ndc = 2.0 * (x / width) - 1.0;
    const y_ndc = 1.0 - 2.0 * (y / height);

    const right = vec.normalized3f(vec.cross3f(view.camera.look_dir, view.camera.up_dir));

    return switch (view.camera.projection_type) {
        .perspective => blk: {
            const tan_half_fov = @tan(view.camera.field_of_view / 2.0);
            const dir = vec.normalized3f(vec.add3f(
                view.camera.look_dir,
                vec.add3f(
                    vec.mulScalar3f(right, x_ndc * view.camera.aspect_ratio * tan_half_fov),
                    vec.mulScalar3f(view.camera.up_dir, y_ndc * tan_half_fov),
                ),
            ));
            break :blk .{
                .origin = view.camera.position,
                .direction = dir,
            };
        },
        .orthographic => blk: {
            const ortho_height = -view.camera.view_matrix[3][2];
            const ortho_width = view.camera.aspect_ratio * ortho_height;
            const origin = vec.add3f(
                view.camera.position,
                vec.add3f(
                    vec.mulScalar3f(right, x_ndc * ortho_width * 0.5),
                    vec.mulScalar3f(view.camera.up_dir, y_ndc * ortho_height * 0.5),
                ),
            );
            break :blk .{
                .origin = origin,
                .direction = view.camera.look_dir,
            };
        },
    };
}

pub fn worldToView(view: *const View, world_pos: Vec3f) ?Vec3f {
    const p_world: Vec4f = .{ world_pos[0], world_pos[1], world_pos[2], 1.0 };
    const p_clip = mat.mulVec4f(view.camera.projection_matrix, mat.mulVec4f(view.camera.view_matrix, p_world));
    if (p_clip[3] == 0.0) {
        gl_log.err("Cannot divide by zero w component", .{});
        return null;
    }
    const p_ndc = vec.divScalar4f(p_clip, p_clip[3]);
    return .{
        ((p_ndc[0] + 1.0) / 2.0) * @as(f32, @floatFromInt(view.width)),
        ((1.0 - p_ndc[1]) / 2.0) * @as(f32, @floatFromInt(view.height)),
        (p_ndc[2] + 1.0) / 2.0,
    };
}
