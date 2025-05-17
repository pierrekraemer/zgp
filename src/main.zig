const std = @import("std");
const gl = @import("gl");
const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
    @cInclude("SDL3/SDL_opengl.h");
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_sdl3.h");
    @cInclude("backends/dcimgui_impl_opengl3.h");
});
const zm = @import("zmath");

const Registry = @import("models/Registry.zig");
const Vec3 = @import("numerical/types.zig").Vec3;
const Vec4 = @import("numerical/types.zig").Vec4;

const FlatColorPerVertex = @import("rendering/shaders/flat_color_per_vertex/FlatColorPerVertex.zig");
const PointSprite = @import("rendering/shaders/point_sprite/PointSprite.zig");

var rng: std.Random.DefaultPrng = undefined;

const halfEdge = Registry.SurfaceMesh.halfEdge;

pub const std_options: std.Options = .{ .log_level = .debug };

const sdl_log = std.log.scoped(.sdl);
const gl_log = std.log.scoped(.gl);
const imgui_log = std.log.scoped(.imgui);
const zgp_log = std.log.scoped(.zgp);

var fully_initialized = false;
var uptime: std.time.Timer = undefined;

var registry: Registry = undefined;

var sm: *Registry.SurfaceMesh = undefined;

var sm_position: *Registry.SurfaceMesh.Data(Vec3) = undefined;
var sm_color: *Registry.SurfaceMesh.Data(Vec3) = undefined;
var sm_triangles_indices: std.ArrayList(u32) = undefined;
var sm_points_indices: std.ArrayList(u32) = undefined;

var sm_position_vbo: c_uint = undefined;
var sm_color_vbo: c_uint = undefined;
var sm_triangles_ibo: c_uint = undefined;
var sm_points_ibo: c_uint = undefined;

var window: *c.SDL_Window = undefined;
var window_width: c_int = 800;
var window_height: c_int = 800;
var gl_context: c.SDL_GLContext = undefined;
var gl_procs: gl.ProcTable = undefined;

var flat_color_shader: FlatColorPerVertex = undefined;
var flat_color_shader_parameters: FlatColorPerVertex.Parameters = undefined;
var point_sprite_shader: PointSprite = undefined;
var point_sprite_shader_parameters: PointSprite.Parameters = undefined;

var camera = zm.lookAtRh(
    zm.f32x4(0.0, 0.0, 2.0, 1.0),
    zm.f32x4(0.0, 0.0, 0.0, 0.0),
    zm.f32x4(0.0, 1.0, 0.0, 0.0),
);
const CameraProjectionType = enum {
    perspective,
    orthographic,
};
var camera_mode = CameraProjectionType.perspective;

fn sdlAppInit(appstate: ?*?*anyopaque, argv: [][*:0]u8) !c.SDL_AppResult {
    _ = appstate;
    _ = argv;

    sdl_log.debug("SDL build time version: {d}.{d}.{d}", .{
        c.SDL_MAJOR_VERSION,
        c.SDL_MINOR_VERSION,
        c.SDL_MICRO_VERSION,
    });
    sdl_log.debug("SDL build time revision: {s}", .{c.SDL_REVISION});
    {
        const version = c.SDL_GetVersion();
        sdl_log.debug("SDL runtime version: {d}.{d}.{d}", .{
            c.SDL_VERSIONNUM_MAJOR(version),
            c.SDL_VERSIONNUM_MINOR(version),
            c.SDL_VERSIONNUM_MICRO(version),
        });
        const revision: [*:0]const u8 = c.SDL_GetRevision();
        sdl_log.debug("SDL runtime revision: {s}", .{revision});
    }

    try errify(c.SDL_SetAppMetadata("zgp", "0.0.0", "zgp"));

    try errify(c.SDL_Init(c.SDL_INIT_VIDEO));
    // We don't need to call 'SDL_Quit()' when using main callbacks.

    // Set relevant OpenGL context attributes before creating the window.
    try errify(c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, gl.info.version_major));
    try errify(c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, gl.info.version_minor));
    try errify(c.SDL_GL_SetAttribute(
        c.SDL_GL_CONTEXT_PROFILE_MASK,
        switch (gl.info.api) {
            .gl => if (gl.info.profile) |profile| switch (profile) {
                .core => c.SDL_GL_CONTEXT_PROFILE_CORE,
                .compatibility => c.SDL_GL_CONTEXT_PROFILE_COMPATIBILITY,
                else => comptime unreachable,
            } else 0,
            .gles, .glsc => c.SDL_GL_CONTEXT_PROFILE_ES,
        },
    ));
    try errify(c.SDL_GL_SetAttribute(
        c.SDL_GL_CONTEXT_FLAGS,
        if (gl.info.api == .gl and gl.info.version_major >= 3) c.SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG else 0,
    ));

    window = try errify(c.SDL_CreateWindow("zgp", window_width, window_height, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE));
    errdefer c.SDL_DestroyWindow(window);

    gl_context = try errify(c.SDL_GL_CreateContext(window));
    errdefer errify(c.SDL_GL_DestroyContext(gl_context)) catch {};

    try errify(c.SDL_GL_MakeCurrent(window, gl_context));
    errdefer errify(c.SDL_GL_MakeCurrent(window, null)) catch {};

    try errify(c.SDL_GL_SetSwapInterval(1));

    if (!gl_procs.init(c.SDL_GL_GetProcAddress)) return error.GlInitFailed;

    gl.makeProcTableCurrent(&gl_procs);
    errdefer gl.makeProcTableCurrent(null);

    const shader_version = switch (gl.info.api) {
        .gl => (
            \\#version 410 core
            \\
        ),
        .gles, .glsc => (
            \\#version 300 es
            \\
        ),
    };

    _ = c.CIMGUI_CHECKVERSION();
    _ = c.ImGui_CreateContext(null);
    errdefer c.ImGui_DestroyContext(null);

    const imio = c.ImGui_GetIO();
    imio.*.ConfigFlags = c.ImGuiConfigFlags_NavEnableKeyboard;

    c.ImGui_StyleColorsDark(null);

    _ = c.cImGui_ImplSDL3_InitForOpenGL(window, gl_context);
    errdefer c.cImGui_ImplSDL3_Shutdown();
    _ = c.cImGui_ImplOpenGL3_InitEx(shader_version);
    errdefer c.cImGui_ImplOpenGL3_Shutdown();

    imgui_log.debug("ImGui initialized\n", .{});

    // ****************************************************************

    sm = try registry.loadSurfaceMeshFromFile("/Users/kraemer/Data/surface/david_25k.off");
    errdefer sm.deinit();

    sm_position = sm.getData(.vertex, Vec3, "position") orelse try sm.addData(.vertex, Vec3, "position");
    // scale the mesh position in the range [0, 1]
    var pos_it = sm_position.rawIterator(); // TODO: use an iterator that only iterates over active indices
    var bb_min = zm.f32x4(std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32), 0.0);
    var bb_max = zm.f32x4(std.math.floatMin(f32), std.math.floatMin(f32), std.math.floatMin(f32), 0.0);
    while (pos_it.next()) |value| {
        bb_min[0] = @min(bb_min[0], value[0]);
        bb_min[1] = @min(bb_min[1], value[1]);
        bb_min[2] = @min(bb_min[2], value[2]);
        bb_max[0] = @max(bb_max[0], value[0]);
        bb_max[1] = @max(bb_max[1], value[1]);
        bb_max[2] = @max(bb_max[2], value[2]);
    }
    const range = bb_max - bb_min;
    const max = @reduce(.Max, range);
    const scale = range / zm.f32x4s(max);
    pos_it.set(0);
    while (pos_it.next()) |value| {
        value[0] = (value[0] - bb_min[0]) / range[0] * scale[0];
        value[1] = (value[1] - bb_min[1]) / range[1] * scale[1];
        value[2] = (value[2] - bb_min[2]) / range[2] * scale[2];
    }
    // center the mesh position on the origin
    var centroid = zm.f32x4s(0.0);
    pos_it.set(0);
    while (pos_it.next()) |value| {
        centroid += zm.f32x4(value[0], value[1], value[2], 0.0);
    }
    centroid /= zm.f32x4s(@floatFromInt(sm_position.rawLength()));
    pos_it.set(0);
    while (pos_it.next()) |value| {
        value[0] = value[0] - centroid[0];
        value[1] = value[1] - centroid[1];
        value[2] = value[2] - centroid[2];
    }

    sm_color = try sm.addData(.vertex, Vec3, "color");
    var col_it = sm_color.rawIterator();
    const r = rng.random();
    while (col_it.next()) |value| {
        value[0] = r.float(f32);
        value[1] = r.float(f32);
        value[2] = r.float(f32);
    }

    // try sm.dump(std.io.getStdErr().writer().any());

    // create indices for the triangles and points

    var f_it = try Registry.SurfaceMesh.CellIterator(.face).init(sm); // TODO: replace with a more user friendly iterator initializer
    while (f_it.next()) |f| {
        var he_it: Registry.SurfaceMesh.CellHalfEdgeIterator = .{ // TODO: replace with a more user friendly local iterator
            .surface_mesh = sm,
            .cell = f,
            .current = Registry.SurfaceMesh.halfEdge(f),
        };
        while (he_it.next()) |he| {
            try sm_triangles_indices.append(sm.indexOf(.{ .vertex = he }));
        }
    }

    var v_it = try Registry.SurfaceMesh.CellIterator(.vertex).init(sm); // TODO: replace with a more user friendly iterator initializer
    while (v_it.next()) |v| {
        try sm_points_indices.append(sm.indexOf(v));
    }

    // create VBOs & fill them with data

    gl.GenBuffers(1, (&sm_position_vbo)[0..1]);
    errdefer gl.DeleteBuffers(1, (&sm_position_vbo)[0..1]);
    {
        gl.BindBuffer(gl.ARRAY_BUFFER, sm_position_vbo);
        defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);
        const vec_size = @typeInfo(Vec3).array.len;
        const buf_size = sm_position.rawSize();
        gl.BufferData(gl.ARRAY_BUFFER, @intCast(buf_size), null, gl.STATIC_DRAW);
        const maybe_buffer = gl.MapBuffer(gl.ARRAY_BUFFER, gl.WRITE_ONLY);
        if (maybe_buffer) |buffer| {
            const buffer_f32: [*]f32 = @ptrCast(@alignCast(buffer));
            var it = sm_position.rawConstIterator();
            var index: u32 = 0;
            while (it.next()) |value| {
                defer index += 1;
                const offset = index * vec_size;
                @memcpy(buffer_f32[offset .. offset + vec_size], value);
            }
            _ = gl.UnmapBuffer(gl.ARRAY_BUFFER);
        }
    }

    gl.GenBuffers(1, (&sm_color_vbo)[0..1]);
    errdefer gl.DeleteBuffers(1, (&sm_color_vbo)[0..1]);
    {
        gl.BindBuffer(gl.ARRAY_BUFFER, sm_color_vbo);
        defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);
        const vec_size = @typeInfo(Vec3).array.len;
        const buf_size = sm_color.rawSize();
        gl.BufferData(gl.ARRAY_BUFFER, @intCast(buf_size), null, gl.STATIC_DRAW);
        const maybe_buffer = gl.MapBuffer(gl.ARRAY_BUFFER, gl.WRITE_ONLY);
        if (maybe_buffer) |buffer| {
            const buffer_f32: [*]f32 = @ptrCast(@alignCast(buffer));
            var it = sm_color.rawConstIterator();
            var index: u32 = 0;
            while (it.next()) |value| {
                defer index += 1;
                const offset = index * vec_size;
                @memcpy(buffer_f32[offset .. offset + vec_size], value);
            }
            _ = gl.UnmapBuffer(gl.ARRAY_BUFFER);
        }
    }

    // create IBOs && fill them with data

    gl.GenBuffers(1, (&sm_triangles_ibo)[0..1]);
    errdefer gl.DeleteBuffers(1, (&sm_triangles_ibo)[0..1]);
    {
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, sm_triangles_ibo);
        defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
        gl.BufferData(
            gl.ELEMENT_ARRAY_BUFFER,
            @intCast(sm_triangles_indices.items.len * @sizeOf(u32)),
            sm_triangles_indices.items.ptr,
            gl.STATIC_DRAW,
        );
    }

    gl.GenBuffers(1, (&sm_points_ibo)[0..1]);
    errdefer gl.DeleteBuffers(1, (&sm_points_ibo)[0..1]);
    {
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, sm_points_ibo);
        defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
        gl.BufferData(
            gl.ELEMENT_ARRAY_BUFFER,
            @intCast(sm_points_indices.items.len * @sizeOf(u32)),
            sm_points_indices.items.ptr,
            gl.STATIC_DRAW,
        );
    }

    // init shaders & their parameters

    flat_color_shader = try FlatColorPerVertex.init();
    errdefer flat_color_shader.deinit();
    point_sprite_shader = try PointSprite.init();
    errdefer point_sprite_shader.deinit();

    flat_color_shader_parameters = try FlatColorPerVertex.Parameters.init(&flat_color_shader);
    errdefer flat_color_shader_parameters.deinit();
    flat_color_shader_parameters.setVBO(.position, sm_position_vbo);
    flat_color_shader_parameters.setVBO(.color, sm_color_vbo);
    flat_color_shader_parameters.setIBO(sm_triangles_ibo);

    point_sprite_shader_parameters = try PointSprite.Parameters.init(&point_sprite_shader);
    errdefer point_sprite_shader_parameters.deinit();
    point_sprite_shader_parameters.setVBO(.position, sm_position_vbo);
    point_sprite_shader_parameters.setVBO(.color, sm_color_vbo);
    point_sprite_shader_parameters.setIBO(sm_points_ibo);

    uptime = try .start();

    fully_initialized = true;
    errdefer comptime unreachable;

    return c.SDL_APP_CONTINUE;
}

fn sdlAppIterate(appstate: ?*anyopaque) !c.SDL_AppResult {
    _ = appstate;

    {
        gl.ClearColor(0.2, 0.2, 0.2, 1);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        gl.Enable(gl.CULL_FACE);
        gl.CullFace(gl.BACK);
        gl.Enable(gl.DEPTH_TEST);

        gl.Viewport(0, 0, window_width, window_height);
        const aspect_ratio = @as(f32, @floatFromInt(window_width)) / @as(f32, @floatFromInt(window_height));

        const field_of_view: f32 = 0.33 * std.math.pi;
        // const scene_radius: f32 = 1.0;
        // const focal_distance: f32 = scene_radius / @tan(field_of_view / 2.0);
        // const pivot_point = zm.f32x4(0.0, 0.0, 0.0, 1.0);

        const object_to_world = zm.identity();
        const object_to_view = zm.mul(object_to_world, camera);

        const view_to_clip = switch (camera_mode) {
            CameraProjectionType.perspective => zm.perspectiveFovRhGl(field_of_view, aspect_ratio, 0.01, 50.0),
            CameraProjectionType.orthographic => zm.orthographicRhGl(4.0, 4.0, 0.01, 50.0),
        };

        {
            gl.UseProgram(flat_color_shader.shader.program);
            defer gl.UseProgram(0);

            gl.UniformMatrix4fv(
                flat_color_shader.model_view_matrix_uniform,
                1,
                gl.FALSE,
                zm.arrNPtr(&object_to_view),
            );
            gl.UniformMatrix4fv(
                flat_color_shader.projection_matrix_uniform,
                1,
                gl.FALSE,
                zm.arrNPtr(&view_to_clip),
            );
            const ambiant_color: [4]f32 = .{ 0.1, 0.1, 0.1, 1 };
            gl.Uniform4fv(
                flat_color_shader.ambiant_color_uniform,
                1,
                &ambiant_color,
            );
            const light_position: [3]f32 = .{ 10, 0, 100 };
            gl.Uniform3fv(
                flat_color_shader.light_position_uniform,
                1,
                &light_position,
            );

            gl.BindVertexArray(flat_color_shader_parameters.vao);
            defer gl.BindVertexArray(0);
            gl.DrawElements(gl.TRIANGLES, @intCast(sm_triangles_indices.items.len), gl.UNSIGNED_INT, 0);
        }

        {
            gl.UseProgram(point_sprite_shader.shader.program);
            defer gl.UseProgram(0);

            gl.UniformMatrix4fv(
                point_sprite_shader.model_view_matrix_uniform,
                1,
                gl.FALSE,
                zm.arrNPtr(&object_to_view),
            );
            gl.UniformMatrix4fv(
                point_sprite_shader.projection_matrix_uniform,
                1,
                gl.FALSE,
                zm.arrNPtr(&view_to_clip),
            );
            gl.Uniform1f(
                point_sprite_shader.point_size_uniform,
                0.001,
            );
            const ambiant_color: [4]f32 = .{ 0.1, 0.1, 0.1, 1 };
            gl.Uniform4fv(
                point_sprite_shader.ambiant_color_uniform,
                1,
                &ambiant_color,
            );
            const light_position: [3]f32 = .{ -100, 0, 100 };
            gl.Uniform3fv(
                point_sprite_shader.light_position_uniform,
                1,
                &light_position,
            );

            gl.BindVertexArray(point_sprite_shader_parameters.vao);
            defer gl.BindVertexArray(0);
            gl.DrawElements(gl.POINTS, @intCast(sm_points_indices.items.len), gl.UNSIGNED_INT, 0);
        }

        c.cImGui_ImplOpenGL3_NewFrame();
        c.cImGui_ImplSDL3_NewFrame();
        c.ImGui_NewFrame();

        const data = struct {
            var show_demo_window: bool = false;
        };
        _ = c.ImGui_Begin("Rendering", null, c.ImGuiWindowFlags_NoSavedSettings);
        c.ImGui_Text("Camera mode");
        if (c.ImGui_RadioButton("Perspective", camera_mode == CameraProjectionType.perspective)) {
            camera_mode = CameraProjectionType.perspective;
        }
        c.ImGui_SameLine();
        if (c.ImGui_RadioButton("Orthographic", camera_mode == CameraProjectionType.orthographic)) {
            camera_mode = CameraProjectionType.orthographic;
        }
        _ = c.ImGui_Checkbox("show demo", &data.show_demo_window);
        c.ImGui_End();
        if (data.show_demo_window) {
            c.ImGui_ShowDemoWindow(null);
        }
        c.ImGui_Render();
        c.cImGui_ImplOpenGL3_RenderDrawData(c.ImGui_GetDrawData());
    }

    try errify(c.SDL_GL_SwapWindow(window));

    return c.SDL_APP_CONTINUE;
}

fn sdlAppEvent(appstate: ?*anyopaque, event: *c.SDL_Event) !c.SDL_AppResult {
    _ = appstate;

    _ = c.cImGui_ImplSDL3_ProcessEvent(event);
    if (c.ImGui_GetIO().*.WantCaptureMouse or c.ImGui_IsWindowHovered(c.ImGuiHoveredFlags_AnyWindow)) {
        return c.SDL_APP_CONTINUE;
    }

    switch (event.type) {
        c.SDL_EVENT_QUIT => {
            return c.SDL_APP_SUCCESS;
        },
        c.SDL_EVENT_WINDOW_RESIZED => {
            try errify(c.SDL_GetWindowSizeInPixels(window, &window_width, &window_height));
        },
        c.SDL_EVENT_KEY_DOWN => {
            // const down = event.type == c.SDL_EVENT_KEY_DOWN;
            switch (event.key.key) {
                c.SDLK_ESCAPE => return c.SDL_APP_SUCCESS,
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_BUTTON_UP => {
            // const down = event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN;
            switch (event.button.button) {
                // c.SDL_BUTTON_LEFT => sdl_log.info("mouse button: left ({s})", .{if (down) "down" else "up"}),
                // c.SDL_BUTTON_RIGHT => sdl_log.info("mouse button: right ({s})", .{if (down) "down" else "up"}),
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_MOTION => {
            switch (event.motion.state) {
                c.SDL_BUTTON_LMASK => {
                    const axis = zm.f32x4(event.motion.yrel, event.motion.xrel, 0.0, 0.0);
                    const speed = zm.length3(axis)[0] * 0.01;
                    const rot = zm.matFromAxisAngle(axis, speed);
                    const tr = camera[3]; // save translation
                    camera[3] = zm.f32x4(0.0, 0.0, 0.0, 1.0); // set translation to zero
                    camera = zm.mul(camera, rot); // apply rotation
                    camera[3] = tr; // restore translation
                },
                c.SDL_BUTTON_RMASK => {
                    const aspect_ratio = @as(f32, @floatFromInt(window_width)) / @as(f32, @floatFromInt(window_height));
                    const nx = event.motion.xrel / @as(f32, @floatFromInt(window_width)) * if (aspect_ratio > 1.0) aspect_ratio else 1.0;
                    const ny = -1.0 * event.motion.yrel / @as(f32, @floatFromInt(window_height)) * if (aspect_ratio > 1.0) 1.0 else 1.0 / aspect_ratio;
                    camera[3][0] += 2 * nx;
                    camera[3][1] += 2 * ny;
                },
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_WHEEL => {
            const wheel = event.wheel.y;
            if (wheel != 0) {
                const forward = zm.f32x4(0.0, 0.0, -1.0, 0.0);
                camera[3] += zm.splat(zm.Vec, -wheel * 0.01) * forward;
            }
        },
        else => {},
    }

    return c.SDL_APP_CONTINUE;
}

fn sdlAppQuit(appstate: ?*anyopaque, result: anyerror!c.SDL_AppResult) void {
    _ = appstate;

    _ = result catch |err| if (err == error.SdlError) {
        sdl_log.err("{s}", .{c.SDL_GetError()});
    };

    if (fully_initialized) {
        c.cImGui_ImplOpenGL3_Shutdown();
        c.cImGui_ImplSDL3_Shutdown();
        c.ImGui_DestroyContext(null);

        gl.DeleteBuffers(1, (&sm_triangles_ibo)[0..1]);
        gl.DeleteBuffers(1, (&sm_points_ibo)[0..1]);
        gl.DeleteBuffers(1, (&sm_position_vbo)[0..1]);
        gl.DeleteBuffers(1, (&sm_color_vbo)[0..1]);
        flat_color_shader_parameters.deinit();
        point_sprite_shader_parameters.deinit();
        flat_color_shader.deinit();
        point_sprite_shader.deinit();

        gl.makeProcTableCurrent(null);
        errify(c.SDL_GL_MakeCurrent(window, null)) catch {};
        errify(c.SDL_GL_DestroyContext(gl_context)) catch {};
        c.SDL_DestroyWindow(window);
        fully_initialized = false;
    }
}

pub fn main() !u8 {
    app_err.reset();
    var empty_argv: [0:null]?[*:0]u8 = .{};

    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();
    // const allocator = std.heap.raw_c_allocator;

    rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));

    registry = Registry.init(allocator);
    defer registry.deinit();

    sm_triangles_indices = std.ArrayList(u32).init(allocator);
    defer sm_triangles_indices.deinit();

    sm_points_indices = std.ArrayList(u32).init(allocator);
    defer sm_points_indices.deinit();

    const status: u8 = @truncate(@as(c_uint, @bitCast(c.SDL_RunApp(empty_argv.len, @ptrCast(&empty_argv), sdlMainC, null))));
    return app_err.load() orelse status;
}

fn sdlMainC(argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c_int {
    return c.SDL_EnterAppMainCallbacks(argc, @ptrCast(argv), sdlAppInitC, sdlAppIterateC, sdlAppEventC, sdlAppQuitC);
}

fn sdlAppInitC(appstate: ?*?*anyopaque, argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c.SDL_AppResult {
    return sdlAppInit(appstate.?, @ptrCast(argv.?[0..@intCast(argc)])) catch |err| app_err.store(err);
}

fn sdlAppIterateC(appstate: ?*anyopaque) callconv(.c) c.SDL_AppResult {
    return sdlAppIterate(appstate) catch |err| app_err.store(err);
}

fn sdlAppEventC(appstate: ?*anyopaque, event: ?*c.SDL_Event) callconv(.c) c.SDL_AppResult {
    return sdlAppEvent(appstate, event.?) catch |err| app_err.store(err);
}

fn sdlAppQuitC(appstate: ?*anyopaque, result: c.SDL_AppResult) callconv(.c) void {
    sdlAppQuit(appstate, app_err.load() orelse result);
}

/// Converts the return value of an SDL function to an error union.
inline fn errify(value: anytype) error{SdlError}!switch (@typeInfo(@TypeOf(value))) {
    .bool => void,
    .pointer, .optional => @TypeOf(value.?),
    .int => |info| switch (info.signedness) {
        .signed => @TypeOf(@max(0, value)),
        .unsigned => @TypeOf(value),
    },
    else => @compileError("unerrifiable type: " ++ @typeName(@TypeOf(value))),
} {
    return switch (@typeInfo(@TypeOf(value))) {
        .bool => if (!value) error.SdlError,
        .pointer, .optional => value orelse error.SdlError,
        .int => |info| switch (info.signedness) {
            .signed => if (value >= 0) @max(0, value) else error.SdlError,
            .unsigned => if (value != 0) value else error.SdlError,
        },
        else => comptime unreachable,
    };
}

var app_err: ErrorStore = .{};

const ErrorStore = struct {
    const status_not_stored = 0;
    const status_storing = 1;
    const status_stored = 2;

    status: c.SDL_AtomicInt = .{},
    err: anyerror = undefined,
    trace_index: usize = undefined,
    trace_addrs: [32]usize = undefined,

    fn reset(es: *ErrorStore) void {
        _ = c.SDL_SetAtomicInt(&es.status, status_not_stored);
    }

    fn store(es: *ErrorStore, err: anyerror) c.SDL_AppResult {
        if (c.SDL_CompareAndSwapAtomicInt(&es.status, status_not_stored, status_storing)) {
            es.err = err;
            if (@errorReturnTrace()) |src_trace| {
                es.trace_index = src_trace.index;
                const len = @min(es.trace_addrs.len, src_trace.instruction_addresses.len);
                @memcpy(es.trace_addrs[0..len], src_trace.instruction_addresses[0..len]);
            }
            _ = c.SDL_SetAtomicInt(&es.status, status_stored);
        }
        return c.SDL_APP_FAILURE;
    }

    fn load(es: *ErrorStore) ?anyerror {
        if (c.SDL_GetAtomicInt(&es.status) != status_stored) return null;
        if (@errorReturnTrace()) |dst_trace| {
            dst_trace.index = es.trace_index;
            const len = @min(dst_trace.instruction_addresses.len, es.trace_addrs.len);
            @memcpy(dst_trace.instruction_addresses[0..len], es.trace_addrs[0..len]);
        }
        return es.err;
    }
};
