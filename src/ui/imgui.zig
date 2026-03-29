const std = @import("std");
const gl = @import("gl");
const c = @import("../main.zig").c;

const PointCloudStore = @import("../models/PointCloudStore.zig");
const PointCloud = @import("../models/point/PointCloud.zig");

const SurfaceMeshStore = @import("../models/SurfaceMeshStore.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");

const IncidenceGraphStore = @import("../models/IncidenceGraphStore.zig");
const IncidenceGraph = @import("../models/incidenceGraph/IncidenceGraph.zig");

const Data = @import("../utils/data.zig").Data;

pub fn init(sdl_window: *c.SDL_Window, gl_context: c.SDL_GLContext) void {
    _ = c.CIMGUI_CHECKVERSION();
    _ = c.ImGui_CreateContext(null);

    const font_size: f32 = 16.0;
    const imio = c.ImGui_GetIO();
    imio.*.ConfigFlags = c.ImGuiConfigFlags_NavEnableKeyboard | c.ImGuiConfigFlags_DockingEnable | c.ImGuiConfigFlags_ViewportsEnable;
    _ = c.ImFontAtlas_AddFontFromFileTTF(imio.*.Fonts, "src/ui/DroidSans.ttf", font_size, null, null);
    // _ = c.ImFontAtlas_AddFontDefault(imio.*.Fonts, null);
    var font_config: c.ImFontConfig = .{};
    font_config.MergeMode = true;
    font_config.SizePixels = font_size;
    font_config.GlyphMinAdvanceX = font_size;
    font_config.GlyphMaxAdvanceX = font_size;
    font_config.RasterizerMultiply = 1.0;
    font_config.RasterizerDensity = 1.0;
    _ = c.ImFontAtlas_AddFontFromFileTTF(imio.*.Fonts, "src/ui/fa-regular-400.ttf", font_size, &font_config, null);
    _ = c.ImFontAtlas_AddFontFromFileTTF(imio.*.Fonts, "src/ui/fa-solid-900.ttf", font_size, &font_config, null);

    c.ImGui_StyleColorsDark(null);

    const imstyle = c.ImGui_GetStyle();
    imstyle.*.SeparatorTextAlign = c.ImVec2{ .x = 1.0, .y = 0.0 };
    imstyle.*.FrameRounding = 2;
    imstyle.*.WindowPadding = c.ImVec2{ .x = 4.0, .y = 4.0 };
    imstyle.*.FramePadding = c.ImVec2{ .x = 4.0, .y = 2.0 };
    imstyle.*.ItemSpacing = c.ImVec2{ .x = 6.0, .y = 2.0 };
    imstyle.*.CellPadding = c.ImVec2{ .x = 4.0, .y = 1.0 };

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

    _ = c.cImGui_ImplSDL3_InitForOpenGL(sdl_window, gl_context);
    _ = c.cImGui_ImplOpenGL3_InitEx(shader_version);
}

pub fn deinit() void {
    c.cImGui_ImplOpenGL3_Shutdown();
    c.cImGui_ImplSDL3_Shutdown();
    c.ImGui_DestroyContext(null);
}

pub fn tooltip(text: []const u8) void {
    if (c.ImGui_BeginItemTooltip()) {
        c.ImGui_PushTextWrapPos(c.ImGui_GetFontSize() * 35.0);
        c.ImGui_TextUnformatted(text.ptr);
        c.ImGui_PopTextWrapPos();
        c.ImGui_EndTooltip();
    }
}

// pub fn addDataButton(
//     id: []const u8,
//     button_text: []const u8,
//     data_name: []u8,
// ) bool {
//     c.ImGui_PushID(id.ptr);
//     defer c.ImGui_PopID();
//     if (c.ImGui_Button("+")) {
//         c.ImGui_OpenPopup("add_data_popup", c.ImGuiPopupFlags_NoReopen);
//     }
//     if (c.ImGui_BeginPopup("add_data_popup", 0)) {
//         defer c.ImGui_EndPopup();
//         _ = c.ImGui_InputText(
//             "name",
//             data_name.ptr,
//             data_name.len,
//             c.ImGuiInputTextFlags_CharsNoBlank,
//         );
//         if (c.ImGui_Button(button_text.ptr)) {
//             c.ImGui_CloseCurrentPopup();
//             return true;
//         }
//     }
//     return false;
// }

pub fn SelectionResult(comptime T: type) type {
    return union(enum) {
        unchanged,
        cleared,
        changed: T,
    };
}

pub fn pointCloudListBox(
    pc_store: *PointCloudStore,
    height: f32,
) SelectionResult(*PointCloud) {
    if (c.ImGui_BeginListBox("##Point Clouds", c.ImVec2{ .x = 0, .y = height })) {
        defer c.ImGui_EndListBox();
        var pc_it = pc_store.point_clouds.iterator();
        while (pc_it.next()) |entry| {
            const pc = entry.value_ptr.*;
            const name = entry.key_ptr.*;
            const is_selected = pc_store.selected_model.modelType() == .point_cloud and pc_store.selected_model.point_cloud == pc;
            if (c.ImGui_SelectableEx(name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                if (!is_selected) {
                    return .{ .changed = pc }; // only return if it was not previously selected
                } else {
                    return .cleared; // clicking on the currently selected item clears the selection
                }
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
    return .unchanged;
}

pub fn pointCloudDataComboBox(
    point_cloud: *PointCloud,
    comptime T: type,
    selected_data: ?PointCloud.CellData(T),
) SelectionResult(PointCloud.CellData(T)) {
    if (c.ImGui_BeginCombo("", if (selected_data) |data| data.name().ptr else "-- none --", 0)) {
        defer c.ImGui_EndCombo();
        const is_none_selected = selected_data == null;
        if (c.ImGui_SelectableEx("-- none --", is_none_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
            return .cleared;
        }
        if (is_none_selected) {
            c.ImGui_SetItemDefaultFocus();
        }

        var data_it = point_cloud.point_data.typedIterator(T);
        while (data_it.next()) |data| {
            const is_selected = if (selected_data) |sd| sd.data == data else false;
            if (c.ImGui_SelectableEx(data.data_gen.name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                return .{ .changed = .{ .point_cloud = point_cloud, .data = data } };
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
    return .unchanged;
}

pub fn surfaceMeshListBox(
    sm_store: *SurfaceMeshStore,
    height: f32,
) SelectionResult(*SurfaceMesh) {
    if (c.ImGui_BeginListBox("##Surface Meshes", c.ImVec2{ .x = 0, .y = height })) {
        defer c.ImGui_EndListBox();
        var sm_it = sm_store.surface_meshes.iterator();
        while (sm_it.next()) |entry| {
            const sm = entry.value_ptr.*;
            const name = entry.key_ptr.*;
            const is_selected = sm_store.selected_model.modelType() == .surface_mesh and sm_store.selected_model.surface_mesh == sm;
            if (c.ImGui_SelectableEx(name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                if (!is_selected) {
                    return .{ .changed = sm }; // only return if it was not previously selected
                } else {
                    return .cleared; // clicking on the currently selected item clears the selection
                }
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
    return .unchanged;
}

pub fn surfaceMeshCellDataComboBox(
    surface_mesh: *SurfaceMesh,
    comptime cell_type: SurfaceMesh.CellType,
    comptime T: type,
    selected_data: ?SurfaceMesh.CellData(cell_type, T),
) SelectionResult(SurfaceMesh.CellData(cell_type, T)) {
    if (c.ImGui_BeginCombo("", if (selected_data) |data| data.name().ptr else "-- none --", 0)) {
        defer c.ImGui_EndCombo();
        const is_none_selected = selected_data == null;
        if (c.ImGui_SelectableEx("-- none --", is_none_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
            return .cleared;
        }
        if (is_none_selected) {
            c.ImGui_SetItemDefaultFocus();
        }

        var data_container = surface_mesh.dataContainer(cell_type);
        var data_it = data_container.typedIterator(T);
        while (data_it.next()) |data| {
            const is_selected = if (selected_data) |sd| sd.data == data else false;
            if (c.ImGui_SelectableEx(data.data_gen.name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                return .{ .changed = .{ .surface_mesh = surface_mesh, .data = data } };
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
    return .unchanged;
}

pub fn surfaceMeshCellSetComboBox(
    surface_mesh: *SurfaceMesh,
    cell_type: SurfaceMesh.CellType,
    selected_cell_set: ?*SurfaceMesh.CellSet,
) SelectionResult(*SurfaceMesh.CellSet) {
    if (c.ImGui_BeginCombo("", if (selected_cell_set) |cell_set| cell_set.name.ptr else "-- none --", 0)) {
        defer c.ImGui_EndCombo();
        const is_none_selected = selected_cell_set == null;
        if (c.ImGui_SelectableEx("-- none --", is_none_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
            return .cleared;
        }
        if (is_none_selected) {
            c.ImGui_SetItemDefaultFocus();
        }

        const cell_sets = switch (cell_type) {
            .vertex => &surface_mesh.vertex_sets,
            .edge => &surface_mesh.edge_sets,
            .face => &surface_mesh.face_sets,
            else => unreachable,
        };
        var cell_set_it = cell_sets.iterator();
        while (cell_set_it.next()) |entry| {
            const cell_set = entry.value_ptr.*;
            const is_selected = if (selected_cell_set) |scs| scs == cell_set else false;
            if (c.ImGui_SelectableEx(cell_set.name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                return .{ .changed = cell_set };
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
    return .unchanged;
}

pub fn surfaceMeshCellTypeComboBox(
    selected_cell_type: SurfaceMesh.CellType,
) ?SurfaceMesh.CellType {
    if (c.ImGui_BeginCombo("", @tagName(selected_cell_type), 0)) {
        defer c.ImGui_EndCombo();
        inline for (@typeInfo(SurfaceMesh.CellType).@"enum".fields) |cell_type| {
            const is_selected = @intFromEnum(selected_cell_type) == cell_type.value;
            if (c.ImGui_SelectableEx(cell_type.name, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                return @enumFromInt(cell_type.value);
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
    return null;
}

pub fn incidenceGraphListBox(
    ig_store: *IncidenceGraphStore,
    height: f32,
) SelectionResult(*IncidenceGraph) {
    if (c.ImGui_BeginListBox("##Incidence Graphs", c.ImVec2{ .x = 0, .y = height })) {
        defer c.ImGui_EndListBox();
        var ig_it = ig_store.incidence_graphs.iterator();
        while (ig_it.next()) |entry| {
            const ig = entry.value_ptr.*;
            const name = entry.key_ptr.*;
            const is_selected = ig_store.selected_model.modelType() == .incidence_graph and ig_store.selected_model.incidence_graph == ig;
            if (c.ImGui_SelectableEx(name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                if (!is_selected) {
                    return .{ .changed = ig }; // only return if it was not previously selected
                } else {
                    return .cleared; // clicking on the currently selected item clears the selection
                }
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
    return .unchanged;
}

pub fn incidenceGraphCellDataComboBox(
    incidence_graph: *IncidenceGraph,
    comptime cell_type: IncidenceGraph.CellType,
    comptime T: type,
    selected_data: ?IncidenceGraph.CellData(cell_type, T),
) SelectionResult(IncidenceGraph.CellData(cell_type, T)) {
    if (c.ImGui_BeginCombo("", if (selected_data) |data| data.name().ptr else "-- none --", 0)) {
        defer c.ImGui_EndCombo();
        const is_none_selected = selected_data == null;
        if (c.ImGui_SelectableEx("-- none --", is_none_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
            return .cleared;
        }
        if (is_none_selected) {
            c.ImGui_SetItemDefaultFocus();
        }

        var data_container = incidence_graph.dataContainer(cell_type);
        var data_it = data_container.typedIterator(T);
        while (data_it.next()) |data| {
            const is_selected = if (selected_data) |sd| sd.data == data else false;
            if (c.ImGui_SelectableEx(data.data_gen.name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                return .{ .changed = .{ .incidence_graph = incidence_graph, .data = data } };
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
    return .unchanged;
}

pub fn incidenceGraphCellTypeComboBox(
    selected_cell_type: IncidenceGraph.CellType,
) ?IncidenceGraph.CellType {
    if (c.ImGui_BeginCombo("", @tagName(selected_cell_type), 0)) {
        defer c.ImGui_EndCombo();
        inline for (@typeInfo(IncidenceGraph.CellType).@"enum".fields) |cell_type| {
            const is_selected = @intFromEnum(selected_cell_type) == cell_type.value;
            if (c.ImGui_SelectableEx(cell_type.name, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                return @enumFromInt(cell_type.value);
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
    return null;
}
