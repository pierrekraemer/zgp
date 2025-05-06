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

pub const std_options: std.Options = .{ .log_level = .debug };

const sdl_log = std.log.scoped(.sdl);
const gl_log = std.log.scoped(.gl);
const imgui_log = std.log.scoped(.imgui);
const zgp_log = std.log.scoped(.zgp);

/// ```txt
///               (5)
///             ..'''..
///         ..''       ''..
/// (3) ._'_________________'_. (4)
///     |\                   /|
///     |  \               /  |
///     |    \           /    |
///     |     \         /     |
/// (1) ''..    \     /    ..'' (2)
///         ''..  \ /  ..''
///             ''.V.''
///               (0)
/// ```
const hexagon_mesh = struct {
    // zig fmt: off
    const vertices = [_]Vertex{
        .{ .position = .{  0,                        -1   , 0 }, .color = .{ 0, 1, 1 } },
        .{ .position = .{ -(@sqrt(@as(f32, 3)) / 2), -0.5, 0 }, .color = .{ 0, 0, 1 } },
        .{ .position = .{  (@sqrt(@as(f32, 3)) / 2), -0.5, 0 }, .color = .{ 0, 1, 0 } },
        .{ .position = .{ -(@sqrt(@as(f32, 3)) / 2),  0.5, 0 }, .color = .{ 1, 0, 1 } },
        .{ .position = .{  (@sqrt(@as(f32, 3)) / 2),  0.5, 0 }, .color = .{ 1, 1, 0 } },
        .{ .position = .{  0,                         1  , 0 }, .color = .{ 1, 0, 0 } },
    };
    // zig fmt: on

    const indices = [_]u8{
        0, 3, 1,
        0, 4, 3,
        0, 2, 4,
        3, 4, 5,
    };

    const Vertex = extern struct {
        position: [3]f32,
        color: [3]f32,
    };
};

var fully_initialized = false;
var uptime: std.time.Timer = undefined;

var registry: Registry = undefined;
var pc: *Registry.PointCloud = undefined;
var pc_position: *Registry.PointCloud.Data(Vec3) = undefined;
var pc_color: *Registry.PointCloud.Data(Vec3) = undefined;
var pc_indices: std.ArrayList(u32) = undefined;

var window: *c.SDL_Window = undefined;
var window_width: c_int = 800;
var window_height: c_int = 800;
var gl_context: c.SDL_GLContext = undefined;
var gl_procs: gl.ProcTable = undefined;

const Shader = struct {
    program: c_uint = undefined,

    model_view_matrix_uniform: c_int = undefined,
    projection_matrix_uniform: c_int = undefined,
    point_size_uniform: c_int = undefined,
    color_uniform: c_int = undefined,
    ambiant_color_uniform: c_int = undefined,
    light_position_uniform: c_int = undefined,

    vao: c_uint = undefined,
    vbos: [2]c_uint = undefined,
    ibo: c_uint = undefined,
};

var no_light_color_shader: Shader = .{};
var point_sprite_shader: Shader = .{};

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

    pc = try registry.createPointCloud("test");
    pc_position = try pc.addData(Vec3, "position");
    pc_color = try pc.addData(Vec3, "color");
    const p1 = try pc.addPoint();
    const p2 = try pc.addPoint();
    const p3 = try pc.addPoint();
    const p4 = try pc.addPoint();
    pc_position.value(pc.indexOf(p1)).* = .{ 0, 0, 0 };
    pc_position.value(pc.indexOf(p2)).* = .{ 1, 0, 0 };
    pc_position.value(pc.indexOf(p3)).* = .{ 0, 1, 0 };
    pc_position.value(pc.indexOf(p4)).* = .{ -1, 0, 0 };
    pc_color.value(pc.indexOf(p1)).* = .{ 1, 0, 0 };
    pc_color.value(pc.indexOf(p2)).* = .{ 0, 1, 0 };
    pc_color.value(pc.indexOf(p3)).* = .{ 0, 0, 1 };
    pc_color.value(pc.indexOf(p4)).* = .{ 1, 1, 0 };
    try pc_indices.append(pc.indexOf(p1));
    try pc_indices.append(pc.indexOf(p2));
    try pc_indices.append(pc.indexOf(p3));
    try pc_indices.append(pc.indexOf(p4));

    _ = try registry.loadSurfaceMeshFromFile("/Users/kraemer/Data/surface/duck_163.off");

    // no light color shader

    no_light_color_shader.program = gl.CreateProgram();
    if (no_light_color_shader.program == 0) return error.GlCreateProgramFailed;
    errdefer gl.DeleteProgram(no_light_color_shader.program);

    {
        var success: c_int = undefined;
        var info_log_buf: [512:0]u8 = undefined;

        const vertex_shader = gl.CreateShader(gl.VERTEX_SHADER);
        if (vertex_shader == 0) return error.GlCreateVertexShaderFailed;
        defer gl.DeleteShader(vertex_shader);
        const vertex_shader_source = @embedFile("rendering/shaders/no_light_color_per_vertex/vs.glsl");
        gl.ShaderSource(
            vertex_shader,
            2,
            &.{ shader_version, vertex_shader_source },
            &.{ shader_version.len, vertex_shader_source.len },
        );
        gl.CompileShader(vertex_shader);
        gl.GetShaderiv(vertex_shader, gl.COMPILE_STATUS, &success);
        if (success == gl.FALSE) {
            gl.GetShaderInfoLog(vertex_shader, info_log_buf.len, null, &info_log_buf);
            gl_log.err("{s}", .{std.mem.sliceTo(&info_log_buf, 0)});
            return error.GlCompileVertexShaderFailed;
        }

        const fragment_shader = gl.CreateShader(gl.FRAGMENT_SHADER);
        if (fragment_shader == 0) return error.GlCreateFragmentShaderFailed;
        defer gl.DeleteShader(fragment_shader);
        const fragment_shader_source = @embedFile("rendering/shaders/no_light_color_per_vertex/fs.glsl");
        gl.ShaderSource(
            fragment_shader,
            2,
            &.{ shader_version, fragment_shader_source },
            &.{ shader_version.len, fragment_shader_source.len },
        );
        gl.CompileShader(fragment_shader);
        gl.GetShaderiv(fragment_shader, gl.COMPILE_STATUS, &success);
        if (success == gl.FALSE) {
            gl.GetShaderInfoLog(fragment_shader, info_log_buf.len, null, &info_log_buf);
            gl_log.err("{s}", .{std.mem.sliceTo(&info_log_buf, 0)});
            return error.GlCompileFragmentShaderFailed;
        }

        gl.AttachShader(no_light_color_shader.program, vertex_shader);
        gl.AttachShader(no_light_color_shader.program, fragment_shader);
        gl.LinkProgram(no_light_color_shader.program);
        gl.GetProgramiv(no_light_color_shader.program, gl.LINK_STATUS, &success);
        if (success == gl.FALSE) {
            gl.GetProgramInfoLog(no_light_color_shader.program, info_log_buf.len, null, &info_log_buf);
            gl_log.err("{s}", .{std.mem.sliceTo(&info_log_buf, 0)});
            return error.LinkProgramFailed;
        }
    }

    no_light_color_shader.model_view_matrix_uniform = gl.GetUniformLocation(no_light_color_shader.program, "u_model_view_matrix");
    no_light_color_shader.projection_matrix_uniform = gl.GetUniformLocation(no_light_color_shader.program, "u_projection_matrix");

    // point sprite shader

    point_sprite_shader.program = gl.CreateProgram();
    if (point_sprite_shader.program == 0) return error.GlCreateProgramFailed;
    errdefer gl.DeleteProgram(point_sprite_shader.program);

    {
        var success: c_int = undefined;
        var info_log_buf: [512:0]u8 = undefined;

        const vertex_shader = gl.CreateShader(gl.VERTEX_SHADER);
        if (vertex_shader == 0) return error.GlCreateVertexShaderFailed;
        defer gl.DeleteShader(vertex_shader);
        const vertex_shader_source = @embedFile("rendering/shaders/point_sprite/vs.glsl");
        gl.ShaderSource(
            vertex_shader,
            2,
            &.{ shader_version, vertex_shader_source },
            &.{ shader_version.len, vertex_shader_source.len },
        );
        gl.CompileShader(vertex_shader);
        gl.GetShaderiv(vertex_shader, gl.COMPILE_STATUS, &success);
        if (success == gl.FALSE) {
            gl.GetShaderInfoLog(vertex_shader, info_log_buf.len, null, &info_log_buf);
            gl_log.err("{s}", .{std.mem.sliceTo(&info_log_buf, 0)});
            return error.GlCompileVertexShaderFailed;
        }

        const geometry_shader = gl.CreateShader(gl.GEOMETRY_SHADER);
        if (geometry_shader == 0) return error.GlCreateFragmentShaderFailed;
        defer gl.DeleteShader(geometry_shader);
        const geometry_shader_source = @embedFile("rendering/shaders/point_sprite/gs.glsl");
        gl.ShaderSource(
            geometry_shader,
            2,
            &.{ shader_version, geometry_shader_source },
            &.{ shader_version.len, geometry_shader_source.len },
        );
        gl.CompileShader(geometry_shader);
        gl.GetShaderiv(geometry_shader, gl.COMPILE_STATUS, &success);
        if (success == gl.FALSE) {
            gl.GetShaderInfoLog(geometry_shader, info_log_buf.len, null, &info_log_buf);
            gl_log.err("{s}", .{std.mem.sliceTo(&info_log_buf, 0)});
            return error.GlCompileGeoemtryShaderFailed;
        }

        const fragment_shader = gl.CreateShader(gl.FRAGMENT_SHADER);
        if (fragment_shader == 0) return error.GlCreateFragmentShaderFailed;
        defer gl.DeleteShader(fragment_shader);
        const fragment_shader_source = @embedFile("rendering/shaders/point_sprite/fs.glsl");
        gl.ShaderSource(
            fragment_shader,
            2,
            &.{ shader_version, fragment_shader_source },
            &.{ shader_version.len, fragment_shader_source.len },
        );
        gl.CompileShader(fragment_shader);
        gl.GetShaderiv(fragment_shader, gl.COMPILE_STATUS, &success);
        if (success == gl.FALSE) {
            gl.GetShaderInfoLog(fragment_shader, info_log_buf.len, null, &info_log_buf);
            gl_log.err("{s}", .{std.mem.sliceTo(&info_log_buf, 0)});
            return error.GlCompileFragmentShaderFailed;
        }

        gl.AttachShader(point_sprite_shader.program, vertex_shader);
        gl.AttachShader(point_sprite_shader.program, geometry_shader);
        gl.AttachShader(point_sprite_shader.program, fragment_shader);
        gl.LinkProgram(point_sprite_shader.program);
        gl.GetProgramiv(point_sprite_shader.program, gl.LINK_STATUS, &success);
        if (success == gl.FALSE) {
            gl.GetProgramInfoLog(point_sprite_shader.program, info_log_buf.len, null, &info_log_buf);
            gl_log.err("{s}", .{std.mem.sliceTo(&info_log_buf, 0)});
            return error.LinkProgramFailed;
        }
    }

    point_sprite_shader.model_view_matrix_uniform = gl.GetUniformLocation(point_sprite_shader.program, "u_model_view_matrix");
    point_sprite_shader.projection_matrix_uniform = gl.GetUniformLocation(point_sprite_shader.program, "u_projection_matrix");
    point_sprite_shader.point_size_uniform = gl.GetUniformLocation(point_sprite_shader.program, "u_point_size");
    point_sprite_shader.color_uniform = gl.GetUniformLocation(point_sprite_shader.program, "u_color");
    point_sprite_shader.ambiant_color_uniform = gl.GetUniformLocation(point_sprite_shader.program, "u_ambiant_color");
    point_sprite_shader.light_position_uniform = gl.GetUniformLocation(point_sprite_shader.program, "u_light_position");

    // no light color shader VAO/VBO/IBO

    gl.GenVertexArrays(1, (&no_light_color_shader.vao)[0..1]);
    errdefer gl.DeleteVertexArrays(1, (&no_light_color_shader.vao)[0..1]);

    gl.GenBuffers(2, &no_light_color_shader.vbos);
    errdefer gl.DeleteBuffers(2, &no_light_color_shader.vbos);

    gl.GenBuffers(1, (&no_light_color_shader.ibo)[0..1]);
    errdefer gl.DeleteBuffers(1, (&no_light_color_shader.ibo)[0..1]);

    {
        gl.BindVertexArray(no_light_color_shader.vao);
        defer gl.BindVertexArray(0);

        {
            gl.BindBuffer(gl.ARRAY_BUFFER, no_light_color_shader.vbos[0]);
            defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);

            const vec_size = @typeInfo(@FieldType(hexagon_mesh.Vertex, "position")).array.len;
            const buf_size = hexagon_mesh.vertices.len * @sizeOf(@FieldType(hexagon_mesh.Vertex, "position"));

            gl.BufferData(gl.ARRAY_BUFFER, buf_size, null, gl.STATIC_DRAW);
            const maybe_buffer = gl.MapBuffer(gl.ARRAY_BUFFER, gl.WRITE_ONLY);
            if (maybe_buffer) |buffer| {
                const buffer_f32: [*]f32 = @ptrCast(@alignCast(buffer));
                for (&hexagon_mesh.vertices, 0..) |*vertex, index| {
                    const offset = index * vec_size;
                    @memcpy(buffer_f32[offset .. offset + vec_size], &vertex.position);
                }
                _ = gl.UnmapBuffer(gl.ARRAY_BUFFER);
            }

            const position_attrib: c_uint = @intCast(gl.GetAttribLocation(no_light_color_shader.program, "a_position"));
            gl.EnableVertexAttribArray(position_attrib);
            gl.VertexAttribPointer(position_attrib, vec_size, gl.FLOAT, gl.FALSE, 0, 0);
        }

        {
            gl.BindBuffer(gl.ARRAY_BUFFER, no_light_color_shader.vbos[1]);
            defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);

            const vec_size = @typeInfo(@FieldType(hexagon_mesh.Vertex, "color")).array.len;
            const buf_size = hexagon_mesh.vertices.len * @sizeOf(@FieldType(hexagon_mesh.Vertex, "color"));

            gl.BufferData(gl.ARRAY_BUFFER, buf_size, null, gl.STATIC_DRAW);
            const maybe_buffer = gl.MapBuffer(gl.ARRAY_BUFFER, gl.WRITE_ONLY);
            if (maybe_buffer) |buffer| {
                const buffer_f32: [*]f32 = @ptrCast(@alignCast(buffer));
                for (&hexagon_mesh.vertices, 0..) |*vertex, index| {
                    const offset = index * vec_size;
                    @memcpy(buffer_f32[offset .. offset + vec_size], &vertex.color);
                }
                _ = gl.UnmapBuffer(gl.ARRAY_BUFFER);
            }

            const color_attrib: c_uint = @intCast(gl.GetAttribLocation(no_light_color_shader.program, "a_color"));
            gl.EnableVertexAttribArray(color_attrib);
            gl.VertexAttribPointer(color_attrib, vec_size, gl.FLOAT, gl.FALSE, 0, 0);
        }

        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, no_light_color_shader.ibo);
        gl.BufferData(
            gl.ELEMENT_ARRAY_BUFFER,
            @sizeOf(@TypeOf(hexagon_mesh.indices)),
            &hexagon_mesh.indices,
            gl.STATIC_DRAW,
        );
    }

    // point sprite shader VAO/VBO/IBO

    gl.GenVertexArrays(1, (&point_sprite_shader.vao)[0..1]);
    errdefer gl.DeleteVertexArrays(1, (&point_sprite_shader.vao)[0..1]);

    gl.GenBuffers(1, &point_sprite_shader.vbos);
    errdefer gl.DeleteBuffers(1, &point_sprite_shader.vbos);

    gl.GenBuffers(1, (&point_sprite_shader.ibo)[0..1]);
    errdefer gl.DeleteBuffers(1, (&point_sprite_shader.ibo)[0..1]);

    {
        gl.BindVertexArray(point_sprite_shader.vao);
        defer gl.BindVertexArray(0);

        {
            gl.BindBuffer(gl.ARRAY_BUFFER, point_sprite_shader.vbos[0]);
            defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);

            const vec_size = @typeInfo(Vec3).array.len;
            const buf_size = pc_position.data.count() * @sizeOf(Vec3);

            gl.BufferData(gl.ARRAY_BUFFER, @intCast(buf_size), null, gl.STATIC_DRAW);
            const maybe_buffer = gl.MapBuffer(gl.ARRAY_BUFFER, gl.WRITE_ONLY);
            if (maybe_buffer) |buffer| {
                const buffer_f32: [*]f32 = @ptrCast(@alignCast(buffer));
                var it = pc_position.data.constIterator(0);
                var index: usize = 0;
                while (it.next()) |value| {
                    const offset = index * vec_size;
                    @memcpy(buffer_f32[offset .. offset + 3], value);
                    index += 1;
                }
                _ = gl.UnmapBuffer(gl.ARRAY_BUFFER);
            }

            const position_attrib: c_uint = @intCast(gl.GetAttribLocation(point_sprite_shader.program, "a_position"));
            gl.EnableVertexAttribArray(position_attrib);
            gl.VertexAttribPointer(position_attrib, vec_size, gl.FLOAT, gl.FALSE, 0, 0);
        }

        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, point_sprite_shader.ibo);
        gl.BufferData(
            gl.ELEMENT_ARRAY_BUFFER,
            @intCast(pc_indices.items.len * @sizeOf(u32)),
            pc_indices.items.ptr,
            gl.STATIC_DRAW,
        );
    }

    uptime = try .start();

    fully_initialized = true;
    errdefer comptime unreachable;

    return c.SDL_APP_CONTINUE;
}

fn sdlAppIterate(appstate: ?*anyopaque) !c.SDL_AppResult {
    _ = appstate;

    {
        gl.ClearColor(0.2, 0.2, 0.2, 1);
        gl.Clear(gl.COLOR_BUFFER_BIT);

        gl.Viewport(0, 0, window_width, window_height);
        const aspect_ratio = @as(f32, @floatFromInt(window_width)) / @as(f32, @floatFromInt(window_height));

        const object_to_world = zm.identity();
        const object_to_view = zm.mul(object_to_world, camera);

        const view_to_clip = switch (camera_mode) {
            CameraProjectionType.perspective => zm.perspectiveFovRhGl(0.5 * std.math.pi, aspect_ratio, 0.01, 50.0),
            CameraProjectionType.orthographic => zm.orthographicRhGl(4.0, 4.0, 0.01, 50.0),
        };

        {
            gl.UseProgram(no_light_color_shader.program);
            defer gl.UseProgram(0);

            gl.UniformMatrix4fv(
                no_light_color_shader.model_view_matrix_uniform,
                1,
                gl.FALSE,
                zm.arrNPtr(&object_to_view),
            );
            gl.UniformMatrix4fv(
                no_light_color_shader.projection_matrix_uniform,
                1,
                gl.FALSE,
                zm.arrNPtr(&view_to_clip),
            );

            gl.BindVertexArray(no_light_color_shader.vao);
            gl.DrawElements(gl.TRIANGLES, hexagon_mesh.indices.len, gl.UNSIGNED_BYTE, 0);
            gl.BindVertexArray(0);
        }

        {
            gl.UseProgram(point_sprite_shader.program);
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
                0.05,
            );
            const point_color: [4]f32 = .{ 1, 0, 0, 1 };
            gl.Uniform4fv(
                point_sprite_shader.color_uniform,
                1,
                &point_color,
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

            gl.BindVertexArray(point_sprite_shader.vao);
            gl.DrawElements(gl.POINTS, @intCast(pc_indices.items.len), gl.UNSIGNED_INT, 0);
            gl.BindVertexArray(0);
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
                    camera = zm.mul(rot, camera); // apply rotation
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
                camera[3] += zm.splat(zm.Vec, wheel * 0.01) * forward;
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

        gl.DeleteBuffers(1, (&no_light_color_shader.ibo)[0..1]);
        gl.DeleteBuffers(2, &no_light_color_shader.vbos);
        gl.DeleteVertexArrays(1, (&no_light_color_shader.vao)[0..1]);
        gl.DeleteProgram(no_light_color_shader.program);

        gl.DeleteBuffers(1, (&point_sprite_shader.ibo)[0..1]);
        gl.DeleteBuffers(1, &point_sprite_shader.vbos);
        gl.DeleteVertexArrays(1, (&point_sprite_shader.vao)[0..1]);
        gl.DeleteProgram(point_sprite_shader.program);

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

    registry = Registry.init(allocator);
    defer registry.deinit();

    pc_indices = std.ArrayList(u32).init(allocator);
    defer pc_indices.deinit();

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
