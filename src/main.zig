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

const ModelsRegistry = @import("models/ModelsRegistry.zig");

const Module = @import("modules/Module.zig");
const PointCloudRenderer = @import("modules/PointCloudRenderer.zig");
const SurfaceMeshRenderer = @import("modules/SurfaceMeshRenderer.zig");
const VectorPerVertexRenderer = @import("modules/VectorPerVertexRenderer.zig");
const SurfaceMeshModeling = @import("modules/SurfaceMeshModeling.zig");

const vec = @import("geometry/vec.zig");
const Vec3 = vec.Vec3;
const Vec4 = vec.Vec4;

const mat = @import("geometry/mat.zig");
const Mat4 = mat.Mat4;

const geometry_utils = @import("geometry/utils.zig");
const normal = @import("models/surface/normal.zig");
const length = @import("models/surface/length.zig");
const angle = @import("models/surface/angle.zig");

const Camera = @import("rendering/Camera.zig");
const Texture2D = @import("rendering/Texture2D.zig");
const FBO = @import("rendering/FBO.zig");

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
pub var modules: std.ArrayList(Module) = .empty;

var point_cloud_renderer: PointCloudRenderer = undefined;
var surface_mesh_renderer: SurfaceMeshRenderer = undefined;
var vector_per_vertex_renderer: VectorPerVertexRenderer = undefined;
var surface_mesh_modeling: SurfaceMeshModeling = undefined;

var window: *c.SDL_Window = undefined;
var window_width: c_int = 1200;
var window_height: c_int = 800;
var gl_context: c.SDL_GLContext = undefined;
var gl_procs: gl.ProcTable = undefined;

// TODO: should move view & FBO management into separate module

var screen_color_tex: Texture2D = undefined;
var screen_depth_tex: Texture2D = undefined;
var fbo: FBO = undefined;
const FullscreenTexture = @import("rendering/shaders/fullscreen_texture/FullscreenTexture.zig");
var fullscreen_texture_shader: FullscreenTexture = undefined;
var fullscreen_texture_shader_parameters: FullscreenTexture.Parameters = undefined;

pub var need_redraw: bool = true;

var camera: Camera = .{};

fn sdlAppInit(appstate: ?*?*anyopaque, argv: [][*:0]u8) !c.SDL_AppResult {
    _ = appstate;
    _ = argv;

    // SDL & GL initialization
    // ***********************

    sdl_log.info("SDL build time version: {d}.{d}.{d}", .{
        c.SDL_MAJOR_VERSION,
        c.SDL_MINOR_VERSION,
        c.SDL_MICRO_VERSION,
    });
    sdl_log.info("SDL build time revision: {s}", .{c.SDL_REVISION});
    {
        const version = c.SDL_GetVersion();
        sdl_log.info("SDL runtime version: {d}.{d}.{d}", .{
            c.SDL_VERSIONNUM_MAJOR(version),
            c.SDL_VERSIONNUM_MINOR(version),
            c.SDL_VERSIONNUM_MICRO(version),
        });
        const revision: [*:0]const u8 = c.SDL_GetRevision();
        sdl_log.info("SDL runtime revision: {s}", .{revision});
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

    // Camera initialization
    // *********************

    camera.position = .{ 0.0, 0.0, 2.0 };
    camera.look_dir = vec.normalized3(vec.sub3(.{ 0.0, 0.0, 0.0 }, camera.position));
    camera.up_dir = .{ 0.0, 1.0, 0.0 };
    camera.pivot_position = .{ 0.0, 0.0, 0.0 };
    camera.updateViewMatrix();

    camera.aspect_ratio = @as(f32, @floatFromInt(window_width)) / @as(f32, @floatFromInt(window_height));
    camera.field_of_view = 0.2 * std.math.pi;
    camera.projection_type = .perspective;
    camera.updateProjectionMatrix();

    // Fullscreen texture & FBO initialization
    // ***************************************

    screen_color_tex = Texture2D.init(&[_]Texture2D.Parameter{
        .{ .name = gl.TEXTURE_MIN_FILTER, .value = gl.NEAREST },
        .{ .name = gl.TEXTURE_MAG_FILTER, .value = gl.NEAREST },
    });
    screen_color_tex.resize(window_width, window_height, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE);
    screen_depth_tex = Texture2D.init(&[_]Texture2D.Parameter{
        .{ .name = gl.TEXTURE_MIN_FILTER, .value = gl.NEAREST },
        .{ .name = gl.TEXTURE_MAG_FILTER, .value = gl.NEAREST },
    });
    screen_depth_tex.resize(window_width, window_height, gl.DEPTH_COMPONENT, gl.DEPTH_COMPONENT, gl.FLOAT);

    fbo = FBO.init();
    fbo.attachTexture(gl.COLOR_ATTACHMENT0, screen_color_tex);
    fbo.attachTexture(gl.DEPTH_ATTACHMENT, screen_depth_tex);

    const status = gl.CheckFramebufferStatus(gl.FRAMEBUFFER);
    if (status != gl.FRAMEBUFFER_COMPLETE) {
        gl_log.err("Framebuffer not complete: {d}", .{status});
    }

    fullscreen_texture_shader = try FullscreenTexture.init();
    fullscreen_texture_shader_parameters = fullscreen_texture_shader.createParameters();
    fullscreen_texture_shader_parameters.setTexture(screen_color_tex, 0);

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

    imgui_log.info("ImGui initialized", .{});

    // Models registry initialization
    // *****************************************

    models_registry = ModelsRegistry.init(allocator);
    errdefer models_registry.deinit();

    // Modules initialization
    // **********************

    point_cloud_renderer = try PointCloudRenderer.init(allocator);
    errdefer point_cloud_renderer.deinit();
    surface_mesh_renderer = try SurfaceMeshRenderer.init(allocator);
    errdefer surface_mesh_renderer.deinit();
    vector_per_vertex_renderer = try VectorPerVertexRenderer.init(allocator);
    errdefer vector_per_vertex_renderer.deinit();
    surface_mesh_modeling = .{};

    errdefer modules.deinit(allocator);
    try modules.append(allocator, point_cloud_renderer.module());
    try modules.append(allocator, surface_mesh_renderer.module());
    try modules.append(allocator, vector_per_vertex_renderer.module());
    try modules.append(allocator, surface_mesh_modeling.module());

    // Example surface mesh initialization
    // ***********************************

    {
        // const sm = try models_registry.loadSurfaceMeshFromFile("/Users/kraemer/Data/surface/julius_388k.off");
        const sm = try models_registry.loadSurfaceMeshFromFile("/Users/kraemer/Data/surface/grid_tri.off");
        errdefer sm.deinit();

        const sm_vertex_position = sm.getData(.vertex, Vec3, "position") orelse try sm.addData(.vertex, Vec3, "position");
        // scale the mesh position in the range [0, 1] and center it on the origin
        const bb_min, const bb_max = geometry_utils.boundingBox(sm_vertex_position.data);
        geometry_utils.scale(sm_vertex_position.data, 1.0 / vec.maxComponent3(vec.sub3(bb_max, bb_min)));
        geometry_utils.centerAround(sm_vertex_position.data, vec.zero3);

        const sm_vertex_color = try sm.addData(.vertex, Vec3, "color");
        var col_it = sm_vertex_color.data.iterator();
        const r = rng.random();
        while (col_it.next()) |col| {
            col.* = vec.random3(r);
        }

        const sm_face_normal = try sm.addData(.face, Vec3, "normal");
        try normal.computeFaceNormals(sm, sm_vertex_position, sm_face_normal);

        const sm_vertex_normal = try sm.addData(.vertex, Vec3, "normal");
        try normal.computeVertexNormals(sm, sm_vertex_position, sm_vertex_normal);

        const sm_edge_length = try sm.addData(.edge, f32, "length");
        try length.computeEdgeLengths(sm, sm_vertex_position, sm_edge_length);

        const sm_corner_angle = try sm.addData(.corner, f32, "angle");
        try angle.computeCornerAngles(sm, sm_vertex_position, sm_corner_angle);

        const sm_edge_dihedral_angle = try sm.addData(.edge, f32, "dihedral_angle");
        try angle.computeEdgeDihedralAngles(sm, sm_vertex_position, sm_edge_dihedral_angle);

        try models_registry.setSurfaceMeshStandardData(sm, .vertex_position, .vertex, Vec3, sm_vertex_position);
        try models_registry.setSurfaceMeshStandardData(sm, .vertex_normal, .vertex, Vec3, sm_vertex_normal);
        try models_registry.setSurfaceMeshStandardData(sm, .vertex_color, .vertex, Vec3, sm_vertex_color);

        try models_registry.surfaceMeshConnectivityUpdated(sm);
    }

    // sm.dump(std.io.getStdErr().writer().any());

    {
        const sm = try models_registry.loadSurfaceMeshFromFile("/Users/kraemer/Data/surface/elephant_isotropic_25k.off");
        errdefer sm.deinit();

        const sm_vertex_position = sm.getData(.vertex, Vec3, "position") orelse try sm.addData(.vertex, Vec3, "position");
        // scale the mesh position in the range [0, 1] and center it on the origin
        const bb_min, const bb_max = geometry_utils.boundingBox(sm_vertex_position.data);
        geometry_utils.scale(sm_vertex_position.data, 1.0 / vec.maxComponent3(vec.sub3(bb_max, bb_min)));
        geometry_utils.centerAround(sm_vertex_position.data, vec.zero3);

        const sm_vertex_color = try sm.addData(.vertex, Vec3, "color");
        var col_it = sm_vertex_color.data.iterator();
        const r = rng.random();
        while (col_it.next()) |col| {
            col.* = vec.random3(r);
        }

        const sm_face_normal = try sm.addData(.face, Vec3, "normal");
        try normal.computeFaceNormals(sm, sm_vertex_position, sm_face_normal);

        const sm_vertex_normal = try sm.addData(.vertex, Vec3, "normal");
        try normal.computeVertexNormals(sm, sm_vertex_position, sm_vertex_normal);

        const sm_edge_length = try sm.addData(.edge, f32, "length");
        try length.computeEdgeLengths(sm, sm_vertex_position, sm_edge_length);

        const sm_corner_angle = try sm.addData(.corner, f32, "angle");
        try angle.computeCornerAngles(sm, sm_vertex_position, sm_corner_angle);

        const sm_edge_dihedral_angle = try sm.addData(.edge, f32, "dihedral_angle");
        try angle.computeEdgeDihedralAngles(sm, sm_vertex_position, sm_edge_dihedral_angle);

        try models_registry.setSurfaceMeshStandardData(sm, .vertex_position, .vertex, Vec3, sm_vertex_position);
        try models_registry.setSurfaceMeshStandardData(sm, .vertex_normal, .vertex, Vec3, sm_vertex_normal);
        try models_registry.setSurfaceMeshStandardData(sm, .vertex_color, .vertex, Vec3, sm_vertex_color);

        try models_registry.surfaceMeshConnectivityUpdated(sm);
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
            var background_color: [4]f32 = .{ 0.65, 0.65, 0.65, 1 };
        };

        gl.ClearColor(UiData.background_color[0], UiData.background_color[1], UiData.background_color[2], UiData.background_color[3]);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        gl.Enable(gl.CULL_FACE);
        gl.CullFace(gl.BACK);
        gl.Enable(gl.DEPTH_TEST);
        gl.Enable(gl.POLYGON_OFFSET_FILL);
        gl.PolygonOffset(1.0, 1.5);

        gl.Viewport(0, 0, window_width, window_height);

        if (need_redraw) {
            gl.BindFramebuffer(gl.FRAMEBUFFER, fbo.index);
            defer gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
            gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
            // gl.DrawBuffer(gl.COLOR_ATTACHMENT0); // not needed as it is already the default
            for (modules.items) |*module| {
                module.draw(camera.view_matrix, camera.projection_matrix);
            }
            need_redraw = false;
        }

        fullscreen_texture_shader_parameters.useShader();
        fullscreen_texture_shader_parameters.draw();
        gl.UseProgram(0);

        c.cImGui_ImplOpenGL3_NewFrame();
        c.cImGui_ImplSDL3_NewFrame();
        c.ImGui_NewFrame();

        const viewport = c.ImGui_GetMainViewport();

        var main_menu_bar_size: c.ImVec2 = undefined;

        if (c.ImGui_BeginMainMenuBar()) {
            defer c.ImGui_EndMainMenuBar();

            main_menu_bar_size = c.ImGui_GetWindowSize();

            if (c.ImGui_BeginMenu("File")) {
                defer c.ImGui_EndMenu();
                _ = c.ImGui_Checkbox("show demo", &UiData.show_demo_window);
                c.ImGui_Separator();
                if (c.ImGui_MenuItem("Quit")) {
                    return c.SDL_APP_SUCCESS;
                }
            }

            if (c.ImGui_BeginMenu("Camera")) {
                defer c.ImGui_EndMenu();
                if (c.ImGui_ColorEdit3("Background color", &UiData.background_color, c.ImGuiColorEditFlags_NoInputs)) {
                    need_redraw = true;
                }
                c.ImGui_Separator();
                if (c.ImGui_MenuItemEx("Perspective", null, camera.projection_type == .perspective, true)) {
                    camera.projection_type = .perspective;
                    camera.updateProjectionMatrix();
                    need_redraw = true;
                }
                if (c.ImGui_MenuItemEx("Orthographic", null, camera.projection_type == .orthographic, true)) {
                    camera.projection_type = .orthographic;
                    camera.updateProjectionMatrix();
                    need_redraw = true;
                }
                c.ImGui_Separator();
                if (c.ImGui_Button("Look at pivot point")) {
                    camera.look_dir = vec.normalized3(vec.sub3(camera.pivot_position, camera.position));
                    camera.updateViewMatrix();
                    need_redraw = true;
                }
            }

            models_registry.menuBar();

            for (modules.items) |*module| {
                module.menuBar();
            }
        }

        c.ImGui_PushStyleVar(c.ImGuiStyleVar_WindowRounding, 0.0);
        c.ImGui_PushStyleVar(c.ImGuiStyleVar_WindowBorderSize, 0.0);

        c.ImGui_SetNextWindowPos(c.ImVec2{
            .x = viewport.*.Pos.x,
            .y = viewport.*.Pos.y + main_menu_bar_size.y,
        }, 0);
        c.ImGui_SetNextWindowSize(c.ImVec2{
            .x = viewport.*.Size.x * 0.22,
            .y = viewport.*.Size.y - main_menu_bar_size.y,
        }, 0);
        c.ImGui_SetNextWindowBgAlpha(0.2);
        if (c.ImGui_Begin("Models Registry", null, c.ImGuiWindowFlags_NoTitleBar | c.ImGuiWindowFlags_NoCollapse | c.ImGuiWindowFlags_NoResize |
            c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoBringToFrontOnFocus | c.ImGuiWindowFlags_NoNavFocus))
        {
            defer c.ImGui_End();
            models_registry.uiPanel();
        }

        c.ImGui_SetNextWindowPos(c.ImVec2{
            .x = viewport.*.Pos.x + viewport.*.Size.x * 0.78,
            .y = viewport.*.Pos.y + main_menu_bar_size.y,
        }, 0);
        c.ImGui_SetNextWindowSize(c.ImVec2{
            .x = viewport.*.Size.x * 0.22,
            .y = viewport.*.Size.y - main_menu_bar_size.y,
        }, 0);
        c.ImGui_SetNextWindowBgAlpha(0.2);
        if (c.ImGui_Begin("Modules", null, c.ImGuiWindowFlags_NoTitleBar | c.ImGuiWindowFlags_NoCollapse | c.ImGuiWindowFlags_NoResize |
            c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoBringToFrontOnFocus | c.ImGuiWindowFlags_NoNavFocus))
        {
            defer c.ImGui_End();
            for (modules.items) |*module| {
                c.ImGui_PushIDPtr(module);
                defer c.ImGui_PopID();
                c.ImGui_PushStyleColor(c.ImGuiCol_Header, c.IM_COL32(255, 128, 0, 200));
                c.ImGui_PushStyleColor(c.ImGuiCol_HeaderActive, c.IM_COL32(255, 128, 0, 255));
                c.ImGui_PushStyleColor(c.ImGuiCol_HeaderHovered, c.IM_COL32(255, 128, 0, 128));
                if (c.ImGui_CollapsingHeader(module.name().ptr, 0)) {
                    c.ImGui_PopStyleColorEx(3);
                    module.uiPanel();
                } else {
                    c.ImGui_PopStyleColorEx(3);
                }
            }
        }

        c.ImGui_PopStyleVarEx(2);

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
            screen_color_tex.resize(window_width, window_height, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE);
            screen_depth_tex.resize(window_width, window_height, gl.DEPTH_COMPONENT, gl.DEPTH_COMPONENT, gl.FLOAT);
            need_redraw = true;
        },
        c.SDL_EVENT_KEY_DOWN => {
            switch (event.key.key) {
                c.SDLK_ESCAPE => return c.SDL_APP_SUCCESS,
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            switch (event.button.button) {
                c.SDL_BUTTON_LEFT => {},
                c.SDL_BUTTON_RIGHT => {},
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_BUTTON_UP => {
            switch (event.button.button) {
                c.SDL_BUTTON_LEFT => {},
                c.SDL_BUTTON_RIGHT => {},
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_MOTION => {
            switch (event.motion.state) {
                c.SDL_BUTTON_LMASK => {
                    camera.rotateFromScreenVec(.{ event.motion.xrel, event.motion.yrel });
                    need_redraw = true;
                },
                c.SDL_BUTTON_RMASK => {
                    camera.translateFromScreenVec(.{ event.motion.xrel, event.motion.yrel });
                    need_redraw = true;
                },
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_WHEEL => {
            const wheel = event.wheel.y;
            if (wheel != 0) {
                camera.moveForward(wheel * 0.01);
                if (camera.projection_type == .orthographic) {
                    camera.updateProjectionMatrix();
                }
                need_redraw = true;
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
        modules.deinit(allocator);
        point_cloud_renderer.deinit();
        surface_mesh_renderer.deinit();
        vector_per_vertex_renderer.deinit();
        screen_color_tex.deinit();
        // screen_depth_tex.deinit();
        fbo.deinit();

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

    // TODO: manage command-line options

    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    defer _ = da.detectLeaks();
    allocator = da.allocator();
    // allocator = std.heap.smp_allocator;

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
