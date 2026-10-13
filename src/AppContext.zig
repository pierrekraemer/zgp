//! Application Context:
//! - io instance
//! - allocator instance
//! - random number generator
//! - window
//! - view
//! - model stores
//! - current selected model
//! - modules

const AppContext = @This();

const std = @import("std");
const c = @import("c");
const zgp_log = std.log.scoped(.zgp);

const CLIArgs = @import("utils/CLIArgs.zig");

const Window = @import("ui/Window.zig");
const imgui = @import("ui/imgui.zig");

const View = @import("rendering/View.zig");
const Shader = @import("rendering/Shader.zig");

const PointCloud = @import("models/point/PointCloud.zig");
const PointCloudStore = @import("models/PointCloudStore.zig");
const SurfaceMesh = @import("models/surface/SurfaceMesh.zig");
const SurfaceMeshStore = @import("models/SurfaceMeshStore.zig");
const IncidenceGraph = @import("models/incidenceGraph/IncidenceGraph.zig");
const IncidenceGraphStore = @import("models/IncidenceGraphStore.zig");

const Module = @import("modules/Module.zig");

const PointCloudStdDatas = @import("modules/PointCloudStdDatas.zig");
const SurfaceMeshStdDatas = @import("modules/SurfaceMeshStdDatas.zig");
const IncidenceGraphStdDatas = @import("modules/IncidenceGraphStdDatas.zig");

const PointCloudRenderer = @import("modules/PointCloudRenderer.zig");
const SurfaceMeshRenderer = @import("modules/SurfaceMeshRenderer.zig");
const IncidenceGraphRenderer = @import("modules/IncidenceGraphRenderer.zig");
const VectorPerVertexRenderer = @import("modules/VectorPerVertexRenderer.zig");

const SurfaceMeshDistance = @import("modules/SurfaceMeshDistance.zig");
const SurfaceMeshCurvature = @import("modules/SurfaceMeshCurvature.zig");
const SurfaceMeshSelection = @import("modules/SurfaceMeshSelection.zig");
const SurfaceMeshDeformation = @import("modules/SurfaceMeshDeformation.zig");
const SurfaceMeshConnectivity = @import("modules/SurfaceMeshConnectivity.zig");
const SurfaceMeshSampling = @import("modules/SurfaceMeshSampling.zig");
const SurfaceMeshParameterization = @import("modules/SurfaceMeshParameterization.zig");
const SurfaceMeshMedialAxis = @import("modules/SurfaceMeshMedialAxis.zig");
const PointCloudMedialAxis = @import("modules/PointCloudMedialAxis.zig");
const SurfaceMeshProceduralTexturing = @import("modules/SurfaceMeshProceduralTexturing.zig");

const geometry_utils = @import("geometry/utils.zig");
const vec = @import("geometry/vec.zig");
const Vec3f = vec.Vec3f;

io: std.Io,
allocator: std.mem.Allocator,
rng: std.Random.DefaultPrng,

window: Window,
view: View,

// model stores
point_cloud_store: PointCloudStore,
surface_mesh_store: SurfaceMeshStore,
incidence_graph_store: IncidenceGraphStore,
selected_model: ModelSelection = .none,

// modules
point_cloud_std_datas: PointCloudStdDatas = .{},
surface_mesh_std_datas: SurfaceMeshStdDatas = .{},
incidence_graph_std_datas: IncidenceGraphStdDatas = .{},
point_cloud_renderer: PointCloudRenderer = .{},
surface_mesh_renderer: SurfaceMeshRenderer = .{},
incidence_graph_renderer: IncidenceGraphRenderer = .{},
vector_per_vertex_renderer: VectorPerVertexRenderer = .{},
surface_mesh_distance: SurfaceMeshDistance = .{},
surface_mesh_curvature: SurfaceMeshCurvature = .{},
surface_mesh_selection: SurfaceMeshSelection = .{},
surface_mesh_deformation: SurfaceMeshDeformation = .{},
surface_mesh_connectivity: SurfaceMeshConnectivity = .{},
surface_mesh_sampling: SurfaceMeshSampling = .{},
surface_mesh_parameterization: SurfaceMeshParameterization = .{},
surface_mesh_medial_axis: SurfaceMeshMedialAxis = .{},
point_cloud_medial_axis: PointCloudMedialAxis = .{},
surface_mesh_procedural_texturing: SurfaceMeshProceduralTexturing = .{},

// array of type-erased modules
modules: std.ArrayList(*Module) = .empty,

pub fn init(io: std.Io, allocator: std.mem.Allocator) !AppContext {
    var seed: u64 = undefined;
    io.random(std.mem.asBytes(&seed));

    try Shader.initRegistry(allocator);

    return .{
        .io = io,
        .allocator = allocator,
        .rng = .init(seed),
        .window = try .init(),
        .view = .init(),
        .point_cloud_store = try .init(io, allocator),
        .surface_mesh_store = try .init(io, allocator),
        .incidence_graph_store = try .init(io, allocator),
    };
}

pub fn wireUp(app_ctx: *AppContext) !void {
    // call init function of each module and pass them the app_ctx
    try app_ctx.point_cloud_std_datas.init(app_ctx);
    try app_ctx.surface_mesh_std_datas.init(app_ctx);
    try app_ctx.incidence_graph_std_datas.init(app_ctx);
    try app_ctx.point_cloud_renderer.init(app_ctx);
    try app_ctx.surface_mesh_renderer.init(app_ctx);
    try app_ctx.incidence_graph_renderer.init(app_ctx);
    try app_ctx.vector_per_vertex_renderer.init(app_ctx);
    try app_ctx.surface_mesh_distance.init(app_ctx);
    try app_ctx.surface_mesh_curvature.init(app_ctx);
    try app_ctx.surface_mesh_selection.init(app_ctx);
    try app_ctx.surface_mesh_deformation.init(app_ctx);
    try app_ctx.surface_mesh_connectivity.init(app_ctx);
    try app_ctx.surface_mesh_sampling.init(app_ctx);
    try app_ctx.surface_mesh_parameterization.init(app_ctx);
    try app_ctx.surface_mesh_medial_axis.init(app_ctx);
    try app_ctx.point_cloud_medial_axis.init(app_ctx);
    try app_ctx.surface_mesh_procedural_texturing.init(app_ctx);

    // store generic modules in the modules array
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.point_cloud_std_datas.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.surface_mesh_std_datas.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.incidence_graph_std_datas.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.point_cloud_renderer.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.surface_mesh_renderer.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.incidence_graph_renderer.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.vector_per_vertex_renderer.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.surface_mesh_distance.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.surface_mesh_curvature.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.surface_mesh_selection.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.surface_mesh_deformation.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.surface_mesh_connectivity.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.surface_mesh_sampling.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.surface_mesh_parameterization.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.surface_mesh_medial_axis.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.point_cloud_medial_axis.module);
    try app_ctx.modules.append(app_ctx.allocator, &app_ctx.surface_mesh_procedural_texturing.module);

    app_ctx.point_cloud_store.selected_model = &app_ctx.selected_model;
    app_ctx.surface_mesh_store.selected_model = &app_ctx.selected_model;
    app_ctx.incidence_graph_store.selected_model = &app_ctx.selected_model;

    app_ctx.view.resize(app_ctx.window.width, app_ctx.window.height);

    imgui.init(app_ctx.window.sdl_window, app_ctx.window.gl_context);
}

pub fn deinit(app_ctx: *AppContext) void {
    app_ctx.point_cloud_std_datas.deinit();
    app_ctx.surface_mesh_std_datas.deinit();
    app_ctx.incidence_graph_std_datas.deinit();
    app_ctx.point_cloud_renderer.deinit();
    app_ctx.surface_mesh_renderer.deinit();
    app_ctx.incidence_graph_renderer.deinit();
    app_ctx.vector_per_vertex_renderer.deinit();
    app_ctx.surface_mesh_distance.deinit();
    app_ctx.surface_mesh_curvature.deinit();
    app_ctx.surface_mesh_selection.deinit();
    app_ctx.surface_mesh_deformation.deinit();
    app_ctx.surface_mesh_connectivity.deinit();
    app_ctx.surface_mesh_sampling.deinit();
    app_ctx.surface_mesh_parameterization.deinit();
    app_ctx.surface_mesh_medial_axis.deinit();
    app_ctx.point_cloud_medial_axis.deinit();
    app_ctx.surface_mesh_procedural_texturing.deinit();

    app_ctx.modules.deinit(app_ctx.allocator);

    app_ctx.point_cloud_store.deinit();
    app_ctx.surface_mesh_store.deinit();
    app_ctx.incidence_graph_store.deinit();

    Shader.deinitRegistry();

    app_ctx.view.deinit();
    app_ctx.window.deinit();
}

pub fn readArgs(app_ctx: *AppContext, args: CLIArgs) !void {
    for (args.mesh_files) |mesh_file| {
        const t = std.Io.Timestamp.now(app_ctx.io, .real);

        const sm = try app_ctx.surface_mesh_store.loadSurfaceMeshFromFile(mesh_file);
        const vertex_position = sm.getData(.vertex, Vec3f, "position").?;

        if (args.normalize) {
            // scale the mesh position in the range [0, 1] and center it on the origin
            const bb_min, const bb_max = geometry_utils.boundingBox(vertex_position.data);
            geometry_utils.scale(vertex_position.data, 1.0 / vec.maxComponent3f(vec.sub3f(bb_max, bb_min)));
        }
        if (args.center) {
            geometry_utils.centerAround(vertex_position.data, vec.zero3f);
        }

        // TODO: why not configure this Data as standard Data directly in the loadSurfaceMeshFromFile function?
        app_ctx.surface_mesh_store.setSurfaceMeshStdData(sm, .{ .vertex_position = vertex_position });

        app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, vertex_position);
        app_ctx.surface_mesh_store.surfaceMeshConnectivityUpdated(sm);

        const elapsed: f64 = @floatFromInt(std.Io.Timestamp.untilNow(t, app_ctx.io, .real).nanoseconds);
        zgp_log.info("Mesh loaded in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
    }
}

/// Return true if:
///  - the module does not declare any supported model type
///  - the module declares supported model types and the currently selected model is of one of those types
fn shouldCallOnModule(app_ctx: *AppContext, module: *Module) bool {
    // Fast path: if no models are exclusively supported, it's a global module
    if (!module.supported_models.point_cloud and
        !module.supported_models.surface_mesh and
        !module.supported_models.incidence_graph)
    {
        return true;
    }

    // Check specific capabilities against currently selected models
    return switch (app_ctx.selected_model) {
        .point_cloud => module.supported_models.point_cloud,
        .surface_mesh => module.supported_models.surface_mesh,
        .incidence_graph => module.supported_models.incidence_graph,
        .none => false,
    };
}

// Main UI function, called every frame
// Return true if the application should continue running, false otherwise
pub fn mainUI(app_ctx: *AppContext) !bool {
    const style = c.ImGui_GetStyle();

    // Draw the main view
    // ******************

    app_ctx.view.draw(app_ctx.modules.items);

    // ImGui frame initialization
    // **************************

    c.cImGui_ImplOpenGL3_NewFrame();
    c.cImGui_ImplSDL3_NewFrame();
    c.ImGui_NewFrame();

    const imgui_viewport = c.ImGui_GetMainViewport();

    // Right-click context menu
    // ************************

    const imgui_io = c.ImGui_GetIO();
    if (c.ImGui_IsMouseClicked(1) and !(imgui_io.*.WantCaptureMouse or c.ImGui_IsWindowHovered(c.ImGuiHoveredFlags_AnyWindow))) {
        _ = c.ImGui_OpenPopup("RightClickMenu", 0);
    }
    if (c.ImGui_BeginPopup("RightClickMenu", 0)) {
        defer c.ImGui_EndPopup();
        switch (app_ctx.selected_model) {
            .point_cloud => |pc| {
                c.ImGui_TextDisabled("Point Cloud:");
                c.ImGui_SameLine();
                c.ImGui_TextDisabled(app_ctx.point_cloud_store.pointCloudName(pc).?);
            },
            .surface_mesh => |sm| {
                c.ImGui_TextDisabled("Surface Mesh:");
                c.ImGui_SameLine();
                c.ImGui_TextDisabled(app_ctx.surface_mesh_store.surfaceMeshName(sm).?);
            },
            .incidence_graph => |ig| {
                c.ImGui_TextDisabled("Incidence Graph:");
                c.ImGui_SameLine();
                c.ImGui_TextDisabled(app_ctx.incidence_graph_store.incidenceGraphName(ig).?);
            },
            .none => c.ImGui_TextDisabled("No selected model"),
        }
        for (app_ctx.modules.items) |module| {
            if (app_ctx.shouldCallOnModule(module)) {
                module.rightClickMenu();
            }
        }
        c.ImGui_Separator();
        if (c.ImGui_MenuItem("Quit")) {
            return false;
        }
    }

    // Main menu bar
    // *************

    var main_menu_bar_size: c.ImVec2 = undefined;

    if (c.ImGui_BeginMainMenuBar()) {
        defer c.ImGui_EndMainMenuBar();

        main_menu_bar_size = c.ImGui_GetWindowSize();

        if (c.ImGui_BeginMenu("ZGP")) {
            defer c.ImGui_EndMenu();
            if (c.ImGui_MenuItem("Quit")) {
                return false;
            }
        }

        app_ctx.view.menuBar();
        app_ctx.point_cloud_store.menuBar();
        app_ctx.surface_mesh_store.menuBar();
        app_ctx.incidence_graph_store.menuBar();
        for (app_ctx.modules.items) |module| {
            if (app_ctx.shouldCallOnModule(module)) {
                module.menuBar();
            }
        }

        // FPS display (ImGui computed value) – right-aligned in the menu bar.
        const fps = imgui_io.*.Framerate;
        var fps_buf: [32]u8 = undefined;
        const fps_str = std.fmt.bufPrintSentinel(&fps_buf, "FPS: {d:.1}", .{fps}, 0) catch "FPS: ?";
        const fps_text_width = c.ImGui_CalcTextSize(fps_str.ptr).x;
        c.ImGui_SetCursorPosX(c.ImGui_GetWindowWidth() - fps_text_width - 8.0);
        c.ImGui_TextUnformatted(fps_str.ptr);
    }

    c.ImGui_PushStyleVar(c.ImGuiStyleVar_WindowRounding, 0.0);
    c.ImGui_PushStyleVar(c.ImGuiStyleVar_WindowBorderSize, 0.0);

    // Left panel + models stores
    // **************************

    c.ImGui_SetNextWindowPos(c.ImVec2{
        .x = imgui_viewport.*.Pos.x,
        .y = imgui_viewport.*.Pos.y + main_menu_bar_size.y,
    }, 0);
    c.ImGui_SetNextWindowSize(c.ImVec2{
        .x = imgui_viewport.*.Size.x * 0.22,
        .y = imgui_viewport.*.Size.y - main_menu_bar_size.y,
    }, 0);
    c.ImGui_SetNextWindowBgAlpha(0.5);
    if (c.ImGui_Begin("Left panel", null, c.ImGuiWindowFlags_NoTitleBar | c.ImGuiWindowFlags_NoCollapse | c.ImGuiWindowFlags_NoResize |
        c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoBringToFrontOnFocus | c.ImGuiWindowFlags_NoNavFocus | c.ImGuiWindowFlags_NoScrollbar))
    {
        defer c.ImGui_End();

        {
            c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
            defer c.ImGui_PopItemWidth();

            var selected_model_changed = false;

            c.ImGui_SeparatorText("Point Clouds");
            const nb_point_clouds_f = @as(f32, @floatFromInt(app_ctx.point_cloud_store.point_clouds.count() + 1));
            switch (imgui.pointCloudListBox(
                &app_ctx.point_cloud_store,
                style.*.FontSizeBase * nb_point_clouds_f + style.*.ItemSpacing.y * nb_point_clouds_f,
            )) {
                .unchanged => {},
                .cleared => {
                    app_ctx.selected_model = .none;
                    selected_model_changed = true;
                    app_ctx.view.requestRedraw();
                },
                .changed => |new_pc| {
                    app_ctx.selected_model = .{ .point_cloud = new_pc };
                    selected_model_changed = true;
                    app_ctx.view.requestRedraw();
                },
            }

            c.ImGui_SeparatorText("Surface Meshes");
            const nb_surface_meshes_f = @as(f32, @floatFromInt(app_ctx.surface_mesh_store.surface_meshes.count() + 1));
            switch (imgui.surfaceMeshListBox(
                &app_ctx.surface_mesh_store,
                style.*.FontSizeBase * nb_surface_meshes_f + style.*.ItemSpacing.y * nb_surface_meshes_f,
            )) {
                .unchanged => {},
                .cleared => {
                    app_ctx.selected_model = .none;
                    selected_model_changed = true;
                    app_ctx.view.requestRedraw();
                },
                .changed => |new_sm| {
                    app_ctx.selected_model = .{ .surface_mesh = new_sm };
                    selected_model_changed = true;
                    app_ctx.view.requestRedraw();
                },
            }

            c.ImGui_SeparatorText("Incidence Graphs");
            const nb_incidence_graphs_f = @as(f32, @floatFromInt(app_ctx.incidence_graph_store.incidence_graphs.count() + 1));
            switch (imgui.incidenceGraphListBox(
                &app_ctx.incidence_graph_store,
                style.*.FontSizeBase * nb_incidence_graphs_f + style.*.ItemSpacing.y * nb_incidence_graphs_f,
            )) {
                .unchanged => {},
                .cleared => {
                    app_ctx.selected_model = .none;
                    selected_model_changed = true;
                    app_ctx.view.requestRedraw();
                },
                .changed => |new_ig| {
                    app_ctx.selected_model = .{ .incidence_graph = new_ig };
                    selected_model_changed = true;
                    app_ctx.view.requestRedraw();
                },
            }

            if (selected_model_changed) {
                for (app_ctx.modules.items) |module| {
                    module.selectedModelChanged();
                }
            }
        }

        c.ImGui_Separator();

        switch (app_ctx.selected_model) {
            .point_cloud => {
                c.ImGui_PushIDPtr(&app_ctx.point_cloud_store);
                app_ctx.point_cloud_store.leftPanel();
                c.ImGui_PopID();
            },
            .surface_mesh => {
                c.ImGui_PushIDPtr(&app_ctx.surface_mesh_store);
                app_ctx.surface_mesh_store.leftPanel();
                c.ImGui_PopID();
            },
            .incidence_graph => {
                c.ImGui_PushIDPtr(&app_ctx.incidence_graph_store);
                app_ctx.incidence_graph_store.leftPanel();
                c.ImGui_PopID();
            },
            .none => {},
        }

        c.ImGui_Separator();

        for (app_ctx.modules.items) |module| {
            if (!app_ctx.shouldCallOnModule(module)) continue;
            c.ImGui_PushIDPtr(module);
            module.leftPanel();
            c.ImGui_PopID();
        }
    }

    // Right panel
    // ***********

    c.ImGui_SetNextWindowPos(c.ImVec2{
        .x = imgui_viewport.*.Pos.x + imgui_viewport.*.Size.x * 0.78,
        .y = imgui_viewport.*.Pos.y + main_menu_bar_size.y,
    }, 0);
    c.ImGui_SetNextWindowSize(c.ImVec2{
        .x = imgui_viewport.*.Size.x * 0.22,
        .y = imgui_viewport.*.Size.y - main_menu_bar_size.y,
    }, 0);
    c.ImGui_SetNextWindowBgAlpha(0.5);
    if (c.ImGui_Begin("Right panel", null, c.ImGuiWindowFlags_NoTitleBar | c.ImGuiWindowFlags_NoCollapse | c.ImGuiWindowFlags_NoResize |
        c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoBringToFrontOnFocus | c.ImGuiWindowFlags_NoNavFocus | c.ImGuiWindowFlags_NoScrollbar))
    {
        defer c.ImGui_End();
        switch (app_ctx.selected_model) {
            .point_cloud => {
                c.ImGui_TextDisabled("Point Cloud: ");
                c.ImGui_SameLine();
                c.ImGui_Text(app_ctx.point_cloud_store.pointCloudName(app_ctx.selected_model.point_cloud).?);
            },
            .surface_mesh => {
                c.ImGui_TextDisabled("Surface Mesh: ");
                c.ImGui_SameLine();
                c.ImGui_Text(app_ctx.surface_mesh_store.surfaceMeshName(app_ctx.selected_model.surface_mesh).?);
            },
            .incidence_graph => {
                c.ImGui_TextDisabled("Incidence Graph: ");
                c.ImGui_SameLine();
                c.ImGui_Text(app_ctx.incidence_graph_store.incidenceGraphName(app_ctx.selected_model.incidence_graph).?);
            },
            .none => c.ImGui_TextDisabled("No selected model"),
        }
        c.ImGui_Separator();
        for (app_ctx.modules.items) |module| {
            if (!app_ctx.shouldCallOnModule(module)) continue;
            if (module.vtable.rightPanel == Module.defaultRightPanel) continue; // check if the module has a custom rightPanel function
            c.ImGui_PushIDPtr(module);
            defer c.ImGui_PopID();
            c.ImGui_PushStyleColor(c.ImGuiCol_Text, c.IM_COL32(25, 25, 25, 255));
            c.ImGui_PushStyleColor(c.ImGuiCol_Header, c.IM_COL32(65, 255, 130, 200));
            c.ImGui_PushStyleColor(c.ImGuiCol_HeaderActive, c.IM_COL32(65, 255, 130, 255));
            c.ImGui_PushStyleColor(c.ImGuiCol_HeaderHovered, c.IM_COL32(65, 255, 130, 128));
            if (c.ImGui_CollapsingHeader(module.name.ptr, 0)) {
                c.ImGui_PopStyleColorEx(4);
                module.rightPanel();
            } else {
                c.ImGui_PopStyleColorEx(4);
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

    try Window.errify(c.SDL_GL_MakeCurrent(app_ctx.window.sdl_window, app_ctx.window.gl_context));
    try Window.errify(c.SDL_GL_SwapWindow(app_ctx.window.sdl_window));

    return true;
}

pub fn sdlEvent(app_ctx: *AppContext, event: *const c.SDL_Event) void {
    _ = c.cImGui_ImplSDL3_ProcessEvent(event);

    // handle app events
    switch (event.type) {
        c.SDL_EVENT_WINDOW_RESIZED => {
            _ = c.SDL_GetWindowSizeInPixels(app_ctx.window.sdl_window, &app_ctx.window.width, &app_ctx.window.height);
            app_ctx.view.resize(app_ctx.window.width, app_ctx.window.height);
            app_ctx.view.requestRedraw();
        },
        else => {},
    }

    // if ImGui wants to capture the mouse, stop event propagation to modules and the view
    if (c.ImGui_GetIO().*.WantCaptureMouse or c.ImGui_IsWindowHovered(c.ImGuiHoveredFlags_AnyWindow)) {
        return;
    }

    // dispatch event to modules
    for (app_ctx.modules.items) |module| {
        if (app_ctx.shouldCallOnModule(module)) {
            if (module.sdlEvent(event)) { // if the module handled the event,
                return; // stop event propagation to other modules and the view
            }
        }
    }

    // dispatch event to view
    app_ctx.view.sdlEvent(event);
}

pub const ModelSelection = union(enum) {
    none,
    surface_mesh: *SurfaceMesh,
    point_cloud: *PointCloud,
    incidence_graph: *IncidenceGraph,

    pub fn modelType(self: ModelSelection) ModelType {
        return std.meta.activeTag(self);
    }
};
pub const ModelType = std.meta.Tag(ModelSelection);
