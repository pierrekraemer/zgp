const std = @import("std");

const c = @cImport({
    @cInclude("dcimgui.h");
});

const zgp = @import("../main.zig");

const PointCloud = @import("../models/point/PointCloud.zig");
const PointCloudData = PointCloud.PointCloudData;
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfaceMeshData = SurfaceMesh.SurfaceMeshData;

const Data = @import("../utils/Data.zig").Data;

pub fn helpMarker(desc: []const u8) void {
    c.ImGui_TextDisabled("(?)");
    if (c.ImGui_BeginItemTooltip()) {
        c.ImGui_PushTextWrapPos(c.ImGui_GetFontSize() * 35.0);
        c.ImGui_TextUnformatted(desc.ptr);
        c.ImGui_PopTextWrapPos();
        c.ImGui_EndTooltip();
    }
}

pub fn surfaceMeshListBox(
    selected_surface_mesh: ?*SurfaceMesh,
    context: anytype,
    on_selected: *const fn (?*SurfaceMesh, @TypeOf(context)) void,
) void {
    if (c.ImGui_BeginListBox("##Surface Meshes", c.ImVec2{ .x = 0, .y = 0 })) {
        defer c.ImGui_EndListBox();
        var sm_it = zgp.models_registry.surface_meshes.iterator();
        while (sm_it.next()) |entry| {
            const sm = entry.value_ptr.*;
            const name = entry.key_ptr.*;
            const is_selected = selected_surface_mesh == sm;
            if (c.ImGui_SelectableEx(name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                if (!is_selected) {
                    on_selected(sm, context); // only call on_selected if it was not previously selected
                }
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
}

pub fn pointCloudListBox(
    selected_point_cloud: ?*PointCloud,
    context: anytype,
    on_selected: *const fn (?*PointCloud, @TypeOf(context)) void,
) void {
    if (c.ImGui_BeginListBox("##Point Clouds", c.ImVec2{ .x = 0, .y = 0 })) {
        defer c.ImGui_EndListBox();
        var pc_it = zgp.models_registry.point_clouds.iterator();
        while (pc_it.next()) |entry| {
            const pc = entry.value_ptr.*;
            const name = entry.key_ptr.*;
            const is_selected = selected_point_cloud == pc;
            if (c.ImGui_SelectableEx(name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                if (!is_selected) {
                    on_selected(pc, context); // only call on_selected if it was not previously selected
                }
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
}

pub fn surfaceMeshCellDataComboBox(
    surface_mesh: *SurfaceMesh,
    comptime cell_type: SurfaceMesh.CellType,
    comptime T: type,
    selected_data: ?SurfaceMeshData(cell_type, T),
    context: anytype,
    on_selected: *const fn (comptime cell_type: SurfaceMesh.CellType, comptime T: type, ?SurfaceMeshData(cell_type, T), @TypeOf(context)) void,
) void {
    if (c.ImGui_BeginCombo("", if (selected_data) |data| data.name().ptr else "--none--", 0)) {
        defer c.ImGui_EndCombo();
        const none_selected = if (selected_data) |_| false else true;
        if (c.ImGui_SelectableEx("--none--", none_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
            if (!none_selected) {
                on_selected(cell_type, T, null, context); // only call on_selected if it was not previously selected
            }
        }
        if (none_selected) {
            c.ImGui_SetItemDefaultFocus();
        }
        var data_container = switch (cell_type) {
            .corner => &surface_mesh.corner_data,
            .vertex => &surface_mesh.vertex_data,
            .edge => &surface_mesh.edge_data,
            .face => &surface_mesh.face_data,
            else => unreachable,
        };
        var data_it = data_container.typedIterator(T);
        while (data_it.next()) |data| {
            const is_selected = if (selected_data) |sd| sd.data == data else false;
            if (c.ImGui_SelectableEx(data.gen.name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                if (!is_selected) {
                    on_selected(cell_type, T, .{ .surface_mesh = surface_mesh, .data = data }, context); // only call on_selected if it was not previously selected
                }
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
}

pub fn pointCloudDataComboBox(
    point_cloud: *PointCloud,
    comptime T: type,
    selected_data: ?PointCloudData(T),
    context: anytype,
    on_selected: *const fn (comptime T: type, ?PointCloudData(T), @TypeOf(context)) void,
) void {
    if (c.ImGui_BeginCombo("", if (selected_data) |data| data.name().ptr else "--none--", 0)) {
        defer c.ImGui_EndCombo();
        const none_selected = if (selected_data) |_| false else true;
        if (c.ImGui_SelectableEx("--none--", none_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
            if (!none_selected) {
                on_selected(T, null, context); // only call on_selected if it was not previously selected
            }
        }
        if (none_selected) {
            c.ImGui_SetItemDefaultFocus();
        }
        var data_it = point_cloud.point_data.typedIterator(T);
        while (data_it.next()) |data| {
            const is_selected = if (selected_data) |sd| sd.data == data else false;
            if (c.ImGui_SelectableEx(data.gen.name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                if (!is_selected) {
                    on_selected(T, .{ .point_cloud = point_cloud, .data = data }, context); // only call on_selected if it was not previously selected
                }
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
}
