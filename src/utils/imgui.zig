const std = @import("std");

const zgp = @import("../main.zig");
const c = zgp.c;

const PointCloud = @import("../models/point/PointCloud.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");

const Data = @import("../utils/Data.zig").Data;

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

pub fn surfaceMeshListBox(
    selected_surface_mesh: ?*SurfaceMesh,
    height: f32,
) ?*SurfaceMesh {
    if (c.ImGui_BeginListBox("##Surface Meshes", c.ImVec2{ .x = 0, .y = height })) {
        defer c.ImGui_EndListBox();
        var sm_it = zgp.surface_mesh_store.surface_meshes.iterator();
        while (sm_it.next()) |entry| {
            const sm = entry.value_ptr.*;
            const name = entry.key_ptr.*;
            const is_selected = selected_surface_mesh == sm;
            if (c.ImGui_SelectableEx(name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                if (!is_selected) {
                    return sm; // only return if it was not previously selected
                }
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
    return null;
}

pub fn pointCloudListBox(
    selected_point_cloud: ?*PointCloud,
    height: f32,
) ?*PointCloud {
    if (c.ImGui_BeginListBox("##Point Clouds", c.ImVec2{ .x = 0, .y = height })) {
        defer c.ImGui_EndListBox();
        var pc_it = zgp.point_cloud_store.point_clouds.iterator();
        while (pc_it.next()) |entry| {
            const pc = entry.value_ptr.*;
            const name = entry.key_ptr.*;
            const is_selected = selected_point_cloud == pc;
            if (c.ImGui_SelectableEx(name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                if (!is_selected) {
                    return pc; // only return if it was not previously selected
                }
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
    return null;
}

// TODO: find a way to support "-- none --" selection
// (cannot simply return null because it is used as a return value to indicate that nothing has been selected)
pub fn surfaceMeshCellDataComboBox(
    surface_mesh: *SurfaceMesh,
    comptime cell_type: SurfaceMesh.CellType,
    comptime T: type,
    selected_data: ?SurfaceMesh.CellData(cell_type, T),
) ?SurfaceMesh.CellData(cell_type, T) {
    if (c.ImGui_BeginCombo("", if (selected_data) |data| data.name().ptr else "-- none --", 0)) {
        defer c.ImGui_EndCombo();
        var data_container = switch (cell_type) {
            .halfedge, .corner => surface_mesh.dart_data,
            .vertex => surface_mesh.vertex_data,
            .edge => surface_mesh.edge_data,
            .face => surface_mesh.face_data,
            else => unreachable,
        };
        var data_it = data_container.typedIterator(T);
        while (data_it.next()) |data| {
            const is_selected = if (selected_data) |sd| sd.data == data else false;
            if (c.ImGui_SelectableEx(data.data_gen.name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                if (!is_selected) { // only return if it was not previously selected
                    return .{ .surface_mesh = surface_mesh, .data = data };
                }
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
    return null;
}

pub fn pointCloudDataComboBox(
    point_cloud: *PointCloud,
    comptime T: type,
    selected_data: ?PointCloud.CellData(T),
) ?PointCloud.CellData(T) {
    if (c.ImGui_BeginCombo("", if (selected_data) |data| data.name().ptr else "-- none --", 0)) {
        defer c.ImGui_EndCombo();
        var data_it = point_cloud.point_data.typedIterator(T);
        while (data_it.next()) |data| {
            const is_selected = if (selected_data) |sd| sd.data == data else false;
            if (c.ImGui_SelectableEx(data.data_gen.name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                if (!is_selected) { // only call on_selected if it was not previously selected
                    return .{ .point_cloud = point_cloud, .data = data };
                }
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
    return null;
}

pub fn surfaceMeshCellTypeComboBox(
    selected_cell_type: SurfaceMesh.CellType,
) ?SurfaceMesh.CellType {
    if (c.ImGui_BeginCombo("", @tagName(selected_cell_type), 0)) {
        defer c.ImGui_EndCombo();
        inline for (@typeInfo(SurfaceMesh.CellType).@"enum".fields) |cell_type| {
            const is_selected = @intFromEnum(selected_cell_type) == cell_type.value;
            if (c.ImGui_SelectableEx(cell_type.name, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                if (!is_selected) {
                    return @enumFromInt(cell_type.value); // only return if it was not previously selected
                }
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
    return null;
}
