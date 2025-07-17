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

const ModelsRegistry = @import("models/ModelsRegistry.zig");

const Module = @import("modules/Module.zig");
const PointCloudRenderer = @import("modules/PointCloudRenderer.zig");
const SurfaceMeshRenderer = @import("modules/SurfaceMeshRenderer.zig");
const VectorPerVertexRenderer = @import("modules/VectorPerVertexRenderer.zig");

const normal = @import("models/surface/normal.zig");

const Vec3 = @import("numerical/types.zig").Vec3;

var allocator: std.mem.Allocator = undefined;
var rng: std.Random.DefaultPrng = undefined;

pub const std_options: std.Options = .{ .log_level = .debug };

const sdl_log = std.log.scoped(.sdl);
pub const gl_log = std.log.scoped(.gl);
pub const imgui_log = std.log.scoped(.imgui);
pub const zgp_log = std.log.scoped(.zgp);

var fully_initialized = false;
var uptime: std.time.Timer = undefined;

/// Global models registry accessible from all modules.
pub var models_registry: ModelsRegistry = undefined;
pub var modules: std.ArrayList(Module) = undefined;

var point_cloud_renderer: PointCloudRenderer = undefined;
var surface_mesh_renderer: SurfaceMeshRenderer = undefined;
var vector_per_vertex_renderer: VectorPerVertexRenderer = undefined;

var window: *c.SDL_Window = undefined;
var window_width: c_int = 800;
var window_height: c_int = 800;
var gl_context: c.SDL_GLContext = undefined;
var gl_procs: gl.ProcTable = undefined;

var view_matrix = zm.lookAtRh(
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

    // SDL & GL initialization
    // ***********************

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

    // ImGui initialization
    // ********************

    _ = c.CIMGUI_CHECKVERSION();
    _ = c.ImGui_CreateContext(null);
    errdefer c.ImGui_DestroyContext(null);

    const imio = c.ImGui_GetIO();
    imio.*.ConfigFlags = c.ImGuiConfigFlags_NavEnableKeyboard | c.ImGuiConfigFlags_DockingEnable | c.ImGuiConfigFlags_ViewportsEnable;

    c.ImGui_StyleColorsDark(null);

    _ = c.cImGui_ImplSDL3_InitForOpenGL(window, gl_context);
    errdefer c.cImGui_ImplSDL3_Shutdown();
    _ = c.cImGui_ImplOpenGL3_InitEx(shader_version);
    errdefer c.cImGui_ImplOpenGL3_Shutdown();

    imgui_log.debug("ImGui initialized\n", .{});

    // Models registry initialization
    // *****************************************

    models_registry = ModelsRegistry.init(allocator);
    errdefer models_registry.deinit();

    // Modules initialization
    // **********************

    modules = std.ArrayList(Module).init(allocator);
    errdefer modules.deinit();

    point_cloud_renderer = try PointCloudRenderer.init(allocator);
    errdefer point_cloud_renderer.deinit();
    try modules.append(point_cloud_renderer.module());
    surface_mesh_renderer = try SurfaceMeshRenderer.init(allocator);
    errdefer surface_mesh_renderer.deinit();
    try modules.append(surface_mesh_renderer.module());
    vector_per_vertex_renderer = try VectorPerVertexRenderer.init(allocator);
    errdefer vector_per_vertex_renderer.deinit();
    try modules.append(vector_per_vertex_renderer.module());

    // Example surface mesh initialization
    // ***********************************

    {
        const sm = try models_registry.loadSurfaceMeshFromFile("/Users/kraemer/Data/surface/david_25k.off");
        errdefer sm.deinit();

        const sm_vertex_position = sm.getData(.vertex, Vec3, "position") orelse try sm.addData(.vertex, Vec3, "position");
        // scale the mesh position in the range [0, 1]
        var pos_it = sm_vertex_position.iterator();
        var bb_min = zm.f32x4s(std.math.floatMax(f32));
        var bb_max = zm.f32x4s(std.math.floatMin(f32));
        while (pos_it.next()) |pos| {
            bb_min[0] = @min(bb_min[0], pos[0]);
            bb_min[1] = @min(bb_min[1], pos[1]);
            bb_min[2] = @min(bb_min[2], pos[2]);
            bb_max[0] = @max(bb_max[0], pos[0]);
            bb_max[1] = @max(bb_max[1], pos[1]);
            bb_max[2] = @max(bb_max[2], pos[2]);
        }
        const range = bb_max - bb_min;
        const max = @reduce(.Max, range);
        const scale = range / zm.f32x4s(max);
        pos_it.reset();
        while (pos_it.next()) |pos| {
            pos[0] = (pos[0] - bb_min[0]) / range[0] * scale[0];
            pos[1] = (pos[1] - bb_min[1]) / range[1] * scale[1];
            pos[2] = (pos[2] - bb_min[2]) / range[2] * scale[2];
        }
        // center the mesh position on the origin
        var centroid = zm.f32x4s(0.0);
        pos_it.reset();
        while (pos_it.next()) |pos| {
            centroid += zm.f32x4(pos[0], pos[1], pos[2], 0.0);
        }
        centroid /= zm.f32x4s(@floatFromInt(sm_vertex_position.nbElements()));
        pos_it.reset();
        while (pos_it.next()) |pos| {
            pos[0] = pos[0] - centroid[0];
            pos[1] = pos[1] - centroid[1];
            pos[2] = pos[2] - centroid[2];
        }

        const sm_vertex_color = try sm.addData(.vertex, Vec3, "color");
        var col_it = sm_vertex_color.iterator();
        const r = rng.random();
        while (col_it.next()) |col| {
            col[0] = r.float(f32);
            col[1] = r.float(f32);
            col[2] = r.float(f32);
        }

        const sm_face_normal = try sm.addData(.face, Vec3, "normal");
        try normal.computeFaceNormals(sm, sm_vertex_position, sm_face_normal);

        const sm_vertex_normal = try sm.addData(.vertex, Vec3, "normal");
        try normal.computeVertexNormals(sm, sm_vertex_position, sm_vertex_normal);

        try models_registry.setSurfaceMeshStandardData(sm, .vertex_position, Vec3, sm_vertex_position);
        try models_registry.setSurfaceMeshStandardData(sm, .vertex_normal, Vec3, sm_vertex_normal);
        try models_registry.setSurfaceMeshStandardData(sm, .vertex_color, Vec3, sm_vertex_color);
        try models_registry.connectivityUpdated(sm);
    }

    // try sm.dump(std.io.getStdErr().writer().any());

    {
        const sm = try models_registry.loadSurfaceMeshFromFile("/Users/kraemer/Data/surface/elephant_isotropic_25k.off");
        errdefer sm.deinit();

        const sm_vertex_position = sm.getData(.vertex, Vec3, "position") orelse try sm.addData(.vertex, Vec3, "position");
        // scale the mesh position in the range [0, 1]
        var pos_it = sm_vertex_position.iterator();
        var bb_min = zm.f32x4s(std.math.floatMax(f32));
        var bb_max = zm.f32x4s(std.math.floatMin(f32));
        while (pos_it.next()) |pos| {
            bb_min[0] = @min(bb_min[0], pos[0]);
            bb_min[1] = @min(bb_min[1], pos[1]);
            bb_min[2] = @min(bb_min[2], pos[2]);
            bb_max[0] = @max(bb_max[0], pos[0]);
            bb_max[1] = @max(bb_max[1], pos[1]);
            bb_max[2] = @max(bb_max[2], pos[2]);
        }
        const range = bb_max - bb_min;
        const max = @reduce(.Max, range);
        const scale = range / zm.f32x4s(max);
        pos_it.reset();
        while (pos_it.next()) |pos| {
            pos[0] = (pos[0] - bb_min[0]) / range[0] * scale[0];
            pos[1] = (pos[1] - bb_min[1]) / range[1] * scale[1];
            pos[2] = (pos[2] - bb_min[2]) / range[2] * scale[2];
        }
        // center the mesh position on the origin
        var centroid = zm.f32x4s(0.0);
        pos_it.reset();
        while (pos_it.next()) |pos| {
            centroid += zm.f32x4(pos[0], pos[1], pos[2], 0.0);
        }
        centroid /= zm.f32x4s(@floatFromInt(sm_vertex_position.nbElements()));
        pos_it.reset();
        while (pos_it.next()) |pos| {
            pos[0] = pos[0] - centroid[0];
            pos[1] = pos[1] - centroid[1];
            pos[2] = pos[2] - centroid[2];
        }

        const sm_vertex_color = try sm.addData(.vertex, Vec3, "color");
        var col_it = sm_vertex_color.iterator();
        const r = rng.random();
        while (col_it.next()) |col| {
            col[0] = r.float(f32);
            col[1] = r.float(f32);
            col[2] = r.float(f32);
        }

        const sm_face_normal = try sm.addData(.face, Vec3, "normal");
        try normal.computeFaceNormals(sm, sm_vertex_position, sm_face_normal);

        const sm_vertex_normal = try sm.addData(.vertex, Vec3, "normal");
        try normal.computeVertexNormals(sm, sm_vertex_position, sm_vertex_normal);

        try models_registry.setSurfaceMeshStandardData(sm, .vertex_position, Vec3, sm_vertex_position);
        try models_registry.setSurfaceMeshStandardData(sm, .vertex_normal, Vec3, sm_vertex_normal);
        try models_registry.setSurfaceMeshStandardData(sm, .vertex_color, Vec3, sm_vertex_color);
        try models_registry.connectivityUpdated(sm);
    }

    // Init end
    // ********

    uptime = try .start();

    fully_initialized = true;
    errdefer comptime unreachable;

    return c.SDL_APP_CONTINUE;
}

fn sdlAppIterate(appstate: ?*anyopaque) !c.SDL_AppResult {
    _ = appstate;

    {
        const UiData = struct {
            var show_demo_window: bool = false;
            var background_color: [4]f32 = .{ 0.45, 0.45, 0.45, 1 };
        };

        gl.ClearColor(UiData.background_color[0], UiData.background_color[1], UiData.background_color[2], UiData.background_color[3]);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        gl.Enable(gl.CULL_FACE);
        gl.CullFace(gl.BACK);
        gl.Enable(gl.DEPTH_TEST);
        gl.Enable(gl.POLYGON_OFFSET_FILL);
        gl.PolygonOffset(1.0, 1.5);

        gl.Viewport(0, 0, window_width, window_height);
        const aspect_ratio = @as(f32, @floatFromInt(window_width)) / @as(f32, @floatFromInt(window_height));

        const field_of_view: f32 = 0.2 * std.math.pi;
        // const scene_radius: f32 = 1.0;
        // const focal_distance: f32 = scene_radius / @tan(field_of_view / 2.0);
        // const pivot_point = zm.f32x4(0.0, 0.0, 0.0, 1.0);

        const projection_matrix = switch (camera_mode) {
            CameraProjectionType.perspective => zm.perspectiveFovRhGl(field_of_view, aspect_ratio, 0.01, 50.0),
            CameraProjectionType.orthographic => zm.orthographicRhGl(4.0, 4.0, 0.01, 50.0),
        };

        for (modules.items) |*module| {
            module.draw(view_matrix, projection_matrix);
        }

        c.cImGui_ImplOpenGL3_NewFrame();
        c.cImGui_ImplSDL3_NewFrame();
        c.ImGui_NewFrame();

        if (c.ImGui_BeginMainMenuBar()) {
            defer c.ImGui_EndMainMenuBar();
            if (c.ImGui_BeginMenu("File")) {
                defer c.ImGui_EndMenu();
                _ = c.ImGui_Checkbox("show demo", &UiData.show_demo_window);
                c.ImGui_Separator();
                if (c.ImGui_MenuItem("Quit")) {
                    return c.SDL_APP_SUCCESS;
                }
            }
            if (c.ImGui_BeginMenu("Rendering")) {
                defer c.ImGui_EndMenu();
                _ = c.ImGui_ColorEdit3("Background color", &UiData.background_color, c.ImGuiColorEditFlags_NoInputs);
                c.ImGui_Separator();
                if (c.ImGui_MenuItemEx("Perspective", null, camera_mode == CameraProjectionType.perspective, true)) {
                    camera_mode = CameraProjectionType.perspective;
                }
                if (c.ImGui_MenuItemEx("Orthographic", null, camera_mode == CameraProjectionType.orthographic, true)) {
                    camera_mode = CameraProjectionType.orthographic;
                }
            }
        }

        models_registry.uiPanel();
        for (modules.items) |*module| {
            module.uiPanel();
        }

        if (UiData.show_demo_window) {
            c.ImGui_ShowDemoWindow(null);
        }

        c.ImGui_Render();
        c.cImGui_ImplOpenGL3_RenderDrawData(c.ImGui_GetDrawData());

        c.ImGui_UpdatePlatformWindows();
        c.ImGui_RenderPlatformWindowsDefault();

        try errify(c.SDL_GL_MakeCurrent(window, gl_context));
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
                    const tr = view_matrix[3]; // save translation
                    view_matrix[3] = zm.f32x4(0.0, 0.0, 0.0, 1.0); // set translation to zero
                    view_matrix = zm.mul(view_matrix, rot); // apply rotation
                    view_matrix[3] = tr; // restore translation
                },
                c.SDL_BUTTON_RMASK => {
                    const aspect_ratio = @as(f32, @floatFromInt(window_width)) / @as(f32, @floatFromInt(window_height));
                    const nx = event.motion.xrel / @as(f32, @floatFromInt(window_width)) * if (aspect_ratio > 1.0) aspect_ratio else 1.0;
                    const ny = -1.0 * event.motion.yrel / @as(f32, @floatFromInt(window_height)) * if (aspect_ratio > 1.0) 1.0 else 1.0 / aspect_ratio;
                    view_matrix[3][0] += 2 * nx;
                    view_matrix[3][1] += 2 * ny;
                },
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_WHEEL => {
            const wheel = event.wheel.y;
            if (wheel != 0) {
                const forward = zm.f32x4(0.0, 0.0, -1.0, 0.0);
                view_matrix[3] += zm.splat(zm.Vec, -wheel * 0.01) * forward;
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

        models_registry.deinit();
        modules.deinit();
        point_cloud_renderer.deinit();
        surface_mesh_renderer.deinit();
        vector_per_vertex_renderer.deinit();

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
    allocator = da.allocator();
    // allocator = std.heap.raw_c_allocator;

    rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));

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
