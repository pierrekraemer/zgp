const std = @import("std");
const gl = @import("gl");
pub const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
    @cInclude("SDL3/SDL_opengl.h");
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_sdl3.h");
    @cInclude("backends/dcimgui_impl_opengl3.h");
    @cInclude("utils/IconsFontAwesome7.h");
    @cInclude("ceigen/mat4.h");
    @cInclude("ceigen/sparse.h");
    @cInclude("ceigen/dense.h");
    @cInclude("clibacc/bvh.h");
});

const SurfaceMeshStore = @import("models/SurfaceMeshStore.zig");
const PointCloudStore = @import("models/PointCloudStore.zig");

const Module = @import("modules/Module.zig");
const PointCloudRenderer = @import("modules/PointCloudRenderer.zig");
const SurfaceMeshRenderer = @import("modules/SurfaceMeshRenderer.zig");
const VectorPerVertexRenderer = @import("modules/VectorPerVertexRenderer.zig");
const SurfaceMeshConnectivity = @import("modules/SurfaceMeshConnectivity.zig");
const SurfaceMeshDistance = @import("modules/SurfaceMeshDistance.zig");
const SurfaceMeshMedialAxis = @import("modules/SurfaceMeshMedialAxis.zig");

const geometry_utils = @import("geometry/utils.zig");
const vec = @import("geometry/vec.zig");
const Vec3f = vec.Vec3f;

const Camera = @import("rendering/Camera.zig");
const View = @import("rendering/View.zig");

pub const std_options: std.Options = .{ .log_level = .debug };
const gl_log = std.log.scoped(.gl);
const sdl_log = std.log.scoped(.sdl);
const imgui_log = std.log.scoped(.imgui);
const zgp_log = std.log.scoped(.zgp);

// TODO: use a lib like:
// https://github.com/joegm/flags
// https://github.com/Hejsil/zig-clap
const CLIArgs = @import("utils/CLIArgs.zig");
var cli_args: CLIArgs = undefined;

var fully_initialized = false;

var allocator: std.mem.Allocator = undefined;

// TODO: use the thread pool to parallelize stuff (cell iterators, etc.)

/// Global elements publicly accessible from all modules:
/// - random number generator
/// - thread pool
/// - PointCloud / SurfaceMesh / VolumeMesh stores
/// - modules list
pub var rng: std.Random.DefaultPrng = undefined;
pub var thread_pool: std.Thread.Pool = undefined;
pub var surface_mesh_store: SurfaceMeshStore = undefined;
pub var point_cloud_store: PointCloudStore = undefined;
pub var modules: std.ArrayList(*Module) = .empty;

/// ZGP modules
/// TODO: could be declared in a config file and loaded at runtime
var point_cloud_renderer: PointCloudRenderer = undefined;
var surface_mesh_renderer: SurfaceMeshRenderer = undefined;
var vector_per_vertex_renderer: VectorPerVertexRenderer = undefined;
var surface_mesh_connectivity: SurfaceMeshConnectivity = undefined;
var surface_mesh_distance: SurfaceMeshDistance = undefined;
var surface_mesh_medial_axis: SurfaceMeshMedialAxis = undefined;

/// Application SDL Window & OpenGL context
var window: *c.SDL_Window = undefined;
var window_width: c_int = 1200;
var window_height: c_int = 800;
var gl_context: c.SDL_GLContext = undefined;
var gl_procs: gl.ProcTable = undefined;

var camera: Camera = undefined;
var view: View = undefined;

pub fn requestRedraw() void {
    view.need_redraw = true;
}

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

    // Camera & View initialization
    // ****************************

    camera = Camera.init(
        .{ 0.0, 0.0, 2.0 },
        .{ 0.0, 0.0, -1.0 },
        .{ 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 0.0 },
        @as(f32, @floatFromInt(window_width)) / @as(f32, @floatFromInt(window_height)),
        0.2 * std.math.pi,
        .perspective,
    );
    errdefer camera.deinit(allocator);

    view = try View.init(window_width, window_height);
    errdefer view.deinit();

    try view.setCamera(&camera, allocator);

    // ImGui initialization
    // ********************

    _ = c.CIMGUI_CHECKVERSION();
    _ = c.ImGui_CreateContext(null);
    errdefer c.ImGui_DestroyContext(null);

    const font_size: f32 = 16.0;
    const imio = c.ImGui_GetIO();
    imio.*.ConfigFlags = c.ImGuiConfigFlags_NavEnableKeyboard | c.ImGuiConfigFlags_DockingEnable | c.ImGuiConfigFlags_ViewportsEnable;
    _ = c.ImFontAtlas_AddFontFromFileTTF(imio.*.Fonts, "src/utils/DroidSans.ttf", font_size, null, null);
    // _ = c.ImFontAtlas_AddFontDefault(imio.*.Fonts, null);
    var font_config: c.ImFontConfig = .{};
    font_config.MergeMode = true;
    font_config.SizePixels = font_size;
    font_config.GlyphMinAdvanceX = font_size;
    font_config.GlyphMaxAdvanceX = font_size;
    font_config.RasterizerMultiply = 1.0;
    font_config.RasterizerDensity = 1.0;
    _ = c.ImFontAtlas_AddFontFromFileTTF(imio.*.Fonts, "src/utils/fa-regular-400.ttf", font_size, &font_config, null);
    _ = c.ImFontAtlas_AddFontFromFileTTF(imio.*.Fonts, "src/utils/fa-solid-900.ttf", font_size, &font_config, null);

    c.ImGui_StyleColorsDark(null);
    const imstyle = c.ImGui_GetStyle();
    imstyle.*.Colors[c.ImGuiCol_Header] = c.ImVec4_t{ .x = 65.0 / 255.0, .y = 255.0 / 255.0, .z = 255.0 / 255.0, .w = 120.0 / 255.0 };
    imstyle.*.Colors[c.ImGuiCol_HeaderActive] = c.ImVec4_t{ .x = 65.0 / 255.0, .y = 255.0 / 255.0, .z = 255.0 / 255.0, .w = 200.0 / 255.0 };
    imstyle.*.Colors[c.ImGuiCol_HeaderHovered] = c.ImVec4_t{ .x = 65.0 / 255.0, .y = 255.0 / 255.0, .z = 255.0 / 255.0, .w = 80.0 / 255.0 };
    imstyle.*.SeparatorTextAlign = c.ImVec2{ .x = 1.0, .y = 0.0 };
    imstyle.*.FrameRounding = 3;

    _ = c.cImGui_ImplSDL3_InitForOpenGL(window, gl_context);
    errdefer c.cImGui_ImplSDL3_Shutdown();
    _ = c.cImGui_ImplOpenGL3_InitEx(shader_version);
    errdefer c.cImGui_ImplOpenGL3_Shutdown();

    imgui_log.info("ImGui initialized", .{});

    // PointCloud / SurfaceMesh / VolumeMesh stores initialization
    // ***********************************************************

    point_cloud_store = PointCloudStore.init(allocator);
    errdefer point_cloud_store.deinit();
    surface_mesh_store = SurfaceMeshStore.init(allocator);
    errdefer surface_mesh_store.deinit();

    // Modules initialization
    // **********************

    point_cloud_renderer = PointCloudRenderer.init(allocator);
    errdefer point_cloud_renderer.deinit();
    surface_mesh_renderer = SurfaceMeshRenderer.init(allocator);
    errdefer surface_mesh_renderer.deinit();
    vector_per_vertex_renderer = VectorPerVertexRenderer.init(allocator);
    errdefer vector_per_vertex_renderer.deinit();
    surface_mesh_connectivity = SurfaceMeshConnectivity.init();
    errdefer surface_mesh_connectivity.deinit();
    surface_mesh_distance = SurfaceMeshDistance.init();
    errdefer surface_mesh_distance.deinit();
    surface_mesh_medial_axis = SurfaceMeshMedialAxis.init(allocator);
    errdefer surface_mesh_medial_axis.deinit();

    // TODO: find a way to tag Modules with the type of model they handle (PointCloud, SurfaceMesh, etc.)
    // and only show them in the UI when a compatible model is selected
    try modules.append(allocator, &point_cloud_renderer.module);
    try modules.append(allocator, &surface_mesh_renderer.module);
    try modules.append(allocator, &vector_per_vertex_renderer.module);
    try modules.append(allocator, &surface_mesh_connectivity.module);
    try modules.append(allocator, &surface_mesh_distance.module);
    try modules.append(allocator, &surface_mesh_medial_axis.module);
    errdefer modules.deinit(allocator);

    // CLI arguments parsing
    // *********************

    for (cli_args.mesh_files) |mesh_file| {
        var timer = try std.time.Timer.start();

        const sm = try surface_mesh_store.loadSurfaceMeshFromFile(mesh_file);
        errdefer sm.deinit();

        const vertex_position = sm.getData(.vertex, Vec3f, "position").?;

        if (cli_args.normalize) {
            // scale the mesh position in the range [0, 1] and center it on the origin
            const bb_min, const bb_max = geometry_utils.boundingBox(vertex_position.data);
            geometry_utils.scale(vertex_position.data, 1.0 / vec.maxComponent3f(vec.sub3f(bb_max, bb_min)));
        }
        if (cli_args.center) {
            geometry_utils.centerAround(vertex_position.data, vec.zero3f);
        }

        surface_mesh_store.setSurfaceMeshStdData(sm, .{ .vertex_position = vertex_position });

        surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, vertex_position);
        surface_mesh_store.surfaceMeshConnectivityUpdated(sm);

        const elapsed: f64 = @floatFromInt(timer.read());
        zgp_log.info("Mesh loaded in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
    }

    // Init end
    // ********

    fully_initialized = true;
    errdefer comptime unreachable;

    return c.SDL_APP_CONTINUE;
}

fn sdlAppIterate(appstate: ?*anyopaque) !c.SDL_AppResult {
    _ = appstate;

    const UiData = struct {
        var background_color: [4]f32 = .{ 0.48, 0.48, 0.48, 1 };
    };

    gl.ClearColor(UiData.background_color[0], UiData.background_color[1], UiData.background_color[2], UiData.background_color[3]);

    view.draw(modules.items);

    c.cImGui_ImplOpenGL3_NewFrame();
    c.cImGui_ImplSDL3_NewFrame();
    c.ImGui_NewFrame();

    const imgui_viewport = c.ImGui_GetMainViewport();

    var main_menu_bar_size: c.ImVec2 = undefined;

    const imgui_io = c.ImGui_GetIO();
    if (imgui_io.*.MouseClicked[1] and !(imgui_io.*.WantCaptureMouse or c.ImGui_IsWindowHovered(c.ImGuiHoveredFlags_AnyWindow))) {
        c.ImGui_OpenPopup("RightClickMenu", 0);
    }
    if (c.ImGui_BeginPopup("RightClickMenu", 0)) {
        defer c.ImGui_EndPopup();
        for (modules.items) |module| {
            module.rightClickMenu();
        }
        c.ImGui_Separator();
        if (c.ImGui_MenuItem("Quit")) {
            return c.SDL_APP_SUCCESS;
        }
    }

    if (c.ImGui_BeginMainMenuBar()) {
        defer c.ImGui_EndMainMenuBar();

        main_menu_bar_size = c.ImGui_GetWindowSize();

        if (c.ImGui_BeginMenu("ZGP")) {
            defer c.ImGui_EndMenu();
            if (c.ImGui_MenuItem("Quit")) {
                return c.SDL_APP_SUCCESS;
            }
        }

        if (c.ImGui_BeginMenu("Camera")) {
            defer c.ImGui_EndMenu();
            if (c.ImGui_ColorEdit3("Background color", &UiData.background_color, c.ImGuiColorEditFlags_NoInputs)) {
                requestRedraw();
            }
            c.ImGui_Separator();
            if (c.ImGui_MenuItemEx("Perspective", null, camera.projection_type == .perspective, true)) {
                camera.projection_type = .perspective;
                camera.updateProjectionMatrix();
            }
            if (c.ImGui_MenuItemEx("Orthographic", null, camera.projection_type == .orthographic, true)) {
                camera.projection_type = .orthographic;
                camera.updateProjectionMatrix();
            }
            c.ImGui_Separator();
            if (c.ImGui_Button("Pivot around world origin")) {
                camera.pivot_position = .{ 0.0, 0.0, 0.0 };
                camera.look_dir = vec.normalized3f(vec.sub3f(camera.pivot_position, camera.position));
                camera.updateViewMatrix();
            }
            if (c.ImGui_Button("Look at pivot point")) {
                camera.look_dir = vec.normalized3f(vec.sub3f(camera.pivot_position, camera.position));
                camera.updateViewMatrix();
            }
        }

        surface_mesh_store.menuBar();
        point_cloud_store.menuBar();

        for (modules.items) |module| {
            module.menuBar();
        }
    }

    c.ImGui_PushStyleVar(c.ImGuiStyleVar_WindowRounding, 0.0);
    c.ImGui_PushStyleVar(c.ImGuiStyleVar_WindowBorderSize, 0.0);

    c.ImGui_SetNextWindowPos(c.ImVec2{
        .x = imgui_viewport.*.Pos.x,
        .y = imgui_viewport.*.Pos.y + main_menu_bar_size.y,
    }, 0);
    c.ImGui_SetNextWindowSize(c.ImVec2{
        .x = imgui_viewport.*.Size.x * 0.22,
        .y = imgui_viewport.*.Size.y - main_menu_bar_size.y,
    }, 0);
    c.ImGui_SetNextWindowBgAlpha(0.5);
    if (c.ImGui_Begin("Models Stores", null, c.ImGuiWindowFlags_NoTitleBar | c.ImGuiWindowFlags_NoCollapse | c.ImGuiWindowFlags_NoResize |
        c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoBringToFrontOnFocus | c.ImGuiWindowFlags_NoNavFocus | c.ImGuiWindowFlags_NoScrollbar))
    {
        defer c.ImGui_End();
        surface_mesh_store.uiPanel();
        point_cloud_store.uiPanel();
    }

    c.ImGui_SetNextWindowPos(c.ImVec2{
        .x = imgui_viewport.*.Pos.x + imgui_viewport.*.Size.x * 0.78,
        .y = imgui_viewport.*.Pos.y + main_menu_bar_size.y,
    }, 0);
    c.ImGui_SetNextWindowSize(c.ImVec2{
        .x = imgui_viewport.*.Size.x * 0.22,
        .y = imgui_viewport.*.Size.y - main_menu_bar_size.y,
    }, 0);
    c.ImGui_SetNextWindowBgAlpha(0.5);
    if (c.ImGui_Begin("Modules", null, c.ImGuiWindowFlags_NoTitleBar | c.ImGuiWindowFlags_NoCollapse | c.ImGuiWindowFlags_NoResize |
        c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoBringToFrontOnFocus | c.ImGuiWindowFlags_NoNavFocus | c.ImGuiWindowFlags_NoScrollbar))
    {
        defer c.ImGui_End();
        for (modules.items) |module| {
            if (module.vtable.uiPanel == null) continue; // check if the module has a uiPanel function
            c.ImGui_PushIDPtr(module);
            defer c.ImGui_PopID();
            c.ImGui_PushStyleColor(c.ImGuiCol_Header, c.IM_COL32(255, 128, 0, 200));
            c.ImGui_PushStyleColor(c.ImGuiCol_HeaderActive, c.IM_COL32(255, 128, 0, 255));
            c.ImGui_PushStyleColor(c.ImGuiCol_HeaderHovered, c.IM_COL32(255, 128, 0, 128));
            if (c.ImGui_CollapsingHeader(module.name.ptr, 0)) {
                c.ImGui_PopStyleColorEx(3);
                module.uiPanel();
            } else {
                c.ImGui_PopStyleColorEx(3);
            }
        }
    }

    c.ImGui_PopStyleVarEx(2);

    // c.ImGui_ShowDemoWindow(null);
    // c.ImGui_ShowStyleEditor(null);

    c.ImGui_Render();
    c.cImGui_ImplOpenGL3_RenderDrawData(c.ImGui_GetDrawData());

    c.ImGui_UpdatePlatformWindows();
    c.ImGui_RenderPlatformWindowsDefault();

    try errify(c.SDL_GL_MakeCurrent(window, gl_context));

    try errify(c.SDL_GL_SwapWindow(window));

    return c.SDL_APP_CONTINUE;
}

fn sdlAppEvent(appstate: ?*anyopaque, event: *c.SDL_Event) !c.SDL_AppResult {
    _ = appstate;

    const UiData = struct {
        var selecting = false;
    };

    _ = c.cImGui_ImplSDL3_ProcessEvent(event);
    if (c.ImGui_GetIO().*.WantCaptureMouse or c.ImGui_IsWindowHovered(c.ImGuiHoveredFlags_AnyWindow)) {
        return c.SDL_APP_CONTINUE;
    }

    // TODO: pass mouse/keyboard events to the view & to the modules (e.g. for interaction)
    // instead of having all the logic here

    switch (event.type) {
        c.SDL_EVENT_QUIT => {
            return c.SDL_APP_SUCCESS;
        },
        c.SDL_EVENT_WINDOW_RESIZED => {
            try errify(c.SDL_GetWindowSizeInPixels(window, &window_width, &window_height));
            view.resize(window_width, window_height);
        },
        c.SDL_EVENT_KEY_DOWN => {
            switch (event.key.key) {
                c.SDLK_ESCAPE => return c.SDL_APP_SUCCESS,
                c.SDLK_S => UiData.selecting = true,
                else => {},
            }
        },
        c.SDL_EVENT_KEY_UP => {
            switch (event.key.key) {
                c.SDLK_S => UiData.selecting = false,
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            switch (event.button.button) {
                c.SDL_BUTTON_LEFT => {
                    if (UiData.selecting and surface_mesh_store.selected_surface_mesh != null) {
                        const sm = surface_mesh_store.selected_surface_mesh.?;
                        const info = surface_mesh_store.surfaceMeshInfo(sm);
                        if (info.bvh.bvh_ptr) |_| {
                            if (view.pixelWorldRayIfGeometry(event.button.x, event.button.y)) |ray| {
                                if (info.bvh.intersectedVertex(ray)) |v| {
                                    try info.vertex_set.add(v);
                                    surface_mesh_store.surfaceMeshCellSetUpdated(sm, .vertex);
                                }
                            }
                        }
                    }
                },
                c.SDL_BUTTON_RIGHT => {},
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_BUTTON_UP => {
            switch (event.button.button) {
                c.SDL_BUTTON_LEFT => {
                    const modState = c.SDL_GetModState();
                    if ((modState & c.SDL_KMOD_SHIFT) != 0 and event.button.clicks == 2) {
                        const world_pos = view.pixelWorldPosition(event.button.x, event.button.y);
                        if (world_pos) |wp| {
                            camera.pivot_position = wp;
                        } else {
                            camera.pivot_position = .{ 0.0, 0.0, 0.0 };
                        }
                        camera.look_dir = vec.normalized3f(vec.sub3f(camera.pivot_position, camera.position));
                        camera.updateViewMatrix();
                        requestRedraw();
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
                        camera.translateFromScreenVec(.{ event.motion.xrel, event.motion.yrel });
                    } else {
                        camera.rotateFromScreenVec(.{ event.motion.xrel, event.motion.yrel });
                    }
                },
                c.SDL_BUTTON_RMASK => {},
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

        point_cloud_renderer.deinit();
        surface_mesh_renderer.deinit();
        vector_per_vertex_renderer.deinit();
        surface_mesh_connectivity.deinit();
        surface_mesh_distance.deinit();
        surface_mesh_medial_axis.deinit();
        modules.deinit(allocator);

        camera.deinit(allocator);
        view.deinit();

        point_cloud_store.deinit();
        surface_mesh_store.deinit();

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
    defer _ = da.detectLeaks();
    allocator = da.allocator();
    // allocator = std.heap.smp_allocator;

    const argv = std.process.argsAlloc(allocator) catch {
        zgp_log.err("Failed to get command line arguments", .{});
        return 1;
    };
    defer std.process.argsFree(allocator, argv);
    cli_args = CLIArgs.init(argv) catch |err| {
        switch (err) {
            error.MissingArgs => return c.SDL_APP_FAILURE,
            error.InvalidArgs => return c.SDL_APP_FAILURE,
        }
    };

    rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));

    try thread_pool.init(.{ .allocator = allocator });
    defer thread_pool.deinit();

    const status: u8 = @truncate(@as(c_uint, @bitCast(c.SDL_RunApp(@intCast(empty_argv.len), @ptrCast(&empty_argv), sdlMainC, null))));
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
