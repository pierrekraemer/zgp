const std = @import("std");
const gl = @import("gl");
pub const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
    // @cInclude("SDL3/SDL_opengl.h");
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_sdl3.h");
    @cInclude("backends/dcimgui_impl_opengl3.h");
    @cInclude("utils/IconsFontAwesome7.h");
    @cInclude("ceigen/small.h");
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
const SurfaceMeshSelection = @import("modules/SurfaceMeshSelection.zig");
const SurfaceMeshDeformation = @import("modules/SurfaceMeshDeformation.zig");
const SurfaceMeshConnectivity = @import("modules/SurfaceMeshConnectivity.zig");
const SurfaceMeshDistance = @import("modules/SurfaceMeshDistance.zig");
const SurfaceMeshCurvature = @import("modules/SurfaceMeshCurvature.zig");
const SurfaceMeshMedialAxis = @import("modules/SurfaceMeshMedialAxis.zig");
const SurfaceMeshProceduralTexturing = @import("modules/SurfaceMeshProceduralTexturing.zig");

const geometry_utils = @import("geometry/utils.zig");
const vec = @import("geometry/vec.zig");
const Vec3f = vec.Vec3f;

const Window = @import("utils/Window.zig");
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
/// - PointCloud / SurfaceMesh / VolumeMesh stores
/// - modules list
/// - view
/// - window
/// - random number generator
/// - thread pool
pub var point_cloud_store: PointCloudStore = undefined;
pub var surface_mesh_store: SurfaceMeshStore = undefined;
pub var modules: std.ArrayList(*Module) = .empty;
pub var view: View = undefined;
pub var window: Window = undefined;
pub var rng: std.Random.DefaultPrng = undefined;
pub var thread_pool: std.Thread.Pool = undefined;

var camera: Camera = undefined;

/// ZGP modules
/// TODO: could be declared in a config file and loaded at runtime
pub var point_cloud_renderer: PointCloudRenderer = undefined;
pub var surface_mesh_renderer: SurfaceMeshRenderer = undefined;
pub var vector_per_vertex_renderer: VectorPerVertexRenderer = undefined;
pub var surface_mesh_selection: SurfaceMeshSelection = undefined;
pub var surface_mesh_deformation: SurfaceMeshDeformation = undefined;
pub var surface_mesh_connectivity: SurfaceMeshConnectivity = undefined;
pub var surface_mesh_distance: SurfaceMeshDistance = undefined;
pub var surface_mesh_curvature: SurfaceMeshCurvature = undefined;
pub var surface_mesh_medial_axis: SurfaceMeshMedialAxis = undefined;
pub var surface_mesh_procedural_texturing: SurfaceMeshProceduralTexturing = undefined;

// TODO: add a console bar at the bottom of the window to display logs & info messages

// TODO: find a better place to put this function (or remove it and directly access 'view.need_redraw' from the modules)
pub fn requestRedraw() void {
    view.need_redraw = true;
}

fn sdlAppInit(appstate: ?*?*anyopaque, argv: [][*:0]u8) !c.SDL_AppResult {
    _ = appstate;
    _ = argv;

    // SDL window & GL initialization
    // ******************************

    try window.init();

    // Camera & View initialization
    // ****************************

    camera = Camera.init(
        .{ 0.0, 0.0, 2.0 },
        .{ 0.0, 0.0, -1.0 },
        .{ 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 0.0 },
        @as(f32, @floatFromInt(window.width)) / @as(f32, @floatFromInt(window.height)),
        0.2 * std.math.pi,
        .perspective,
    );
    errdefer camera.deinit(allocator);

    view = try View.init(window.width, window.height);
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

    _ = c.cImGui_ImplSDL3_InitForOpenGL(window.sdl_window, window.gl_context);
    errdefer c.cImGui_ImplSDL3_Shutdown();
    _ = c.cImGui_ImplOpenGL3_InitEx(shader_version);
    errdefer c.cImGui_ImplOpenGL3_Shutdown();

    imgui_log.info("ImGui initialized", .{});

    // PointCloud / SurfaceMesh / VolumeMesh stores initialization
    // ***********************************************************

    point_cloud_store = .init(allocator);
    errdefer point_cloud_store.deinit();
    surface_mesh_store = try .init(allocator);
    errdefer surface_mesh_store.deinit();

    // Modules initialization
    // **********************

    point_cloud_renderer = .init(allocator);
    errdefer point_cloud_renderer.deinit();
    surface_mesh_renderer = .init(allocator);
    errdefer surface_mesh_renderer.deinit();
    vector_per_vertex_renderer = .init(allocator);
    errdefer vector_per_vertex_renderer.deinit();
    surface_mesh_selection = .init(allocator);
    errdefer surface_mesh_selection.deinit();
    surface_mesh_deformation = .init();
    errdefer surface_mesh_deformation.deinit();
    surface_mesh_connectivity = .init();
    errdefer surface_mesh_connectivity.deinit();
    surface_mesh_distance = .init();
    errdefer surface_mesh_distance.deinit();
    surface_mesh_curvature = .init(allocator);
    errdefer surface_mesh_curvature.deinit();
    surface_mesh_medial_axis = .init(allocator);
    errdefer surface_mesh_medial_axis.deinit();
    surface_mesh_procedural_texturing = .init(allocator);
    errdefer surface_mesh_procedural_texturing.deinit();

    // TODO: find a way to tag Modules with the type of model they handle (PointCloud, SurfaceMesh, etc.)
    // and only show them in the UI when a compatible model is selected
    try modules.append(allocator, &point_cloud_renderer.module);
    try modules.append(allocator, &surface_mesh_renderer.module);
    try modules.append(allocator, &vector_per_vertex_renderer.module);
    try modules.append(allocator, &surface_mesh_selection.module);
    try modules.append(allocator, &surface_mesh_deformation.module);
    try modules.append(allocator, &surface_mesh_connectivity.module);
    try modules.append(allocator, &surface_mesh_distance.module);
    try modules.append(allocator, &surface_mesh_curvature.module);
    try modules.append(allocator, &surface_mesh_medial_axis.module);
    try modules.append(allocator, &surface_mesh_procedural_texturing.module);
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

    // Draw the main view
    // ******************

    view.draw(modules.items);

    // ImGui frame initialization
    // **************************

    c.cImGui_ImplOpenGL3_NewFrame();
    c.cImGui_ImplSDL3_NewFrame();
    c.ImGui_NewFrame();

    const imgui_viewport = c.ImGui_GetMainViewport();

    var main_menu_bar_size: c.ImVec2 = undefined;

    // Right-click context menu
    // ************************

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

    // Main menu bar
    // *************

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

        point_cloud_store.menuBar();
        surface_mesh_store.menuBar();

        for (modules.items) |module| {
            module.menuBar();
        }
    }

    c.ImGui_PushStyleVar(c.ImGuiStyleVar_WindowRounding, 0.0);
    c.ImGui_PushStyleVar(c.ImGuiStyleVar_WindowBorderSize, 0.0);

    // Left panel: models stores
    // *************************

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

    // Right panel: modules
    // ********************

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

    try errify(c.SDL_GL_MakeCurrent(window.sdl_window, window.gl_context));
    try errify(c.SDL_GL_SwapWindow(window.sdl_window));

    return c.SDL_APP_CONTINUE;
}

fn sdlAppEvent(appstate: ?*anyopaque, event: *c.SDL_Event) !c.SDL_AppResult {
    _ = appstate;

    _ = c.cImGui_ImplSDL3_ProcessEvent(event);

    // handle app events
    switch (event.type) {
        c.SDL_EVENT_QUIT => {
            return c.SDL_APP_SUCCESS;
        },
        c.SDL_EVENT_KEY_DOWN => {
            switch (event.key.key) {
                c.SDLK_ESCAPE => return c.SDL_APP_SUCCESS,
                else => {},
            }
        },
        else => {},
    }

    // dispatch event to window
    window.sdlEvent(event);

    // if ImGui wants to capture the mouse, do not process mouse events further
    if (c.ImGui_GetIO().*.WantCaptureMouse or c.ImGui_IsWindowHovered(c.ImGuiHoveredFlags_AnyWindow)) {
        return c.SDL_APP_CONTINUE;
    }

    // dispatch event to view
    view.sdlEvent(event);

    // dispatch event to modules
    for (modules.items) |module| {
        module.sdlEvent(event);
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

        // clear the list of modules before deinitializing them
        // to avoid potential inter-dependencies issues
        modules.clearRetainingCapacity();

        point_cloud_renderer.deinit();
        surface_mesh_renderer.deinit();
        vector_per_vertex_renderer.deinit();
        surface_mesh_selection.deinit();
        surface_mesh_deformation.deinit();
        surface_mesh_connectivity.deinit();
        surface_mesh_distance.deinit();
        surface_mesh_curvature.deinit();
        surface_mesh_medial_axis.deinit();
        surface_mesh_procedural_texturing.deinit();
        modules.deinit(allocator);

        camera.deinit(allocator);
        view.deinit();

        point_cloud_store.deinit();
        surface_mesh_store.deinit();

        window.deinit();

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
pub inline fn errify(value: anytype) error{SdlError}!switch (@typeInfo(@TypeOf(value))) {
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
