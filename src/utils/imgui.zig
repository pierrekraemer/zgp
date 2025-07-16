const std = @import("std");

const c = @cImport({
    @cInclude("dcimgui.h");
});

const zgp = @import("../main.zig");

pub const PointCloud = @import("../models/point/PointCloud.zig");
pub const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");

const Data = @import("../utils/Data.zig").Data;

pub fn surfaceMeshListBox(
    selected_surface_mesh: ?*SurfaceMesh,
    on_selected: *const fn (?*SurfaceMesh) void,
) void {
    if (c.ImGui_BeginListBox("##Surface Meshes", c.ImVec2{ .x = 0, .y = 0 })) {
        defer c.ImGui_EndListBox();
        var sm_it = zgp.models_registry.surface_meshes.iterator();
        while (sm_it.next()) |entry| {
            const sm = entry.value_ptr.*;
            const name = entry.key_ptr.*;
            const selected = selected_surface_mesh == sm;
            if (c.ImGui_SelectableEx(name.ptr, selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                on_selected(sm);
            }
            if (selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
}

pub fn pointCloudListBox(
    selected_point_cloud: ?*PointCloud,
    on_selected: *const fn (?*PointCloud) void,
) void {
    if (c.ImGui_BeginListBox("##Point Clouds", c.ImVec2{ .x = 0, .y = 0 })) {
        defer c.ImGui_EndListBox();
        var pc_it = zgp.models_registry.point_clouds.iterator();
        while (pc_it.next()) |entry| {
            const pc = entry.value_ptr.*;
            const name = entry.key_ptr.*;
            const selected = selected_point_cloud == pc;
            if (c.ImGui_SelectableEx(name.ptr, selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                on_selected(pc);
            }
            if (selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
}

pub fn surfaceMeshCellDataComboBox(
    surface_mesh: *SurfaceMesh,
    cell_type: SurfaceMesh.CellType,
    comptime T: type,
    selected_data: ?*Data(T),
    context: anytype,
    on_selected: *const fn (comptime T: type, ?*Data(T), @TypeOf(context)) void,
) void {
    if (c.ImGui_BeginCombo("", if (selected_data) |data| data.gen.name.ptr else "--none--", 0)) {
        defer c.ImGui_EndCombo();
        const none_selected = if (selected_data) |_| false else true;
        if (c.ImGui_SelectableEx("--none--", none_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
            if (!none_selected) {
                on_selected(T, null, context);
            }
        }
        if (none_selected) {
            c.ImGui_SetItemDefaultFocus();
        }
        var data_container = switch (cell_type) {
            .halfedge => &surface_mesh.halfedge_data,
            .vertex => &surface_mesh.vertex_data,
            .edge => &surface_mesh.edge_data,
            .face => &surface_mesh.face_data,
        };
        var data_it = data_container.typedIterator(T);
        while (data_it.next()) |data| {
            const is_selected = selected_data == data;
            if (c.ImGui_SelectableEx(data.gen.name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                if (!is_selected) {
                    on_selected(T, data, context);
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
    selected_data: ?*Data(T),
    context: anytype,
    on_selected: *const fn (comptime T: type, ?*Data(T), @TypeOf(context)) void,
) void {
    if (c.ImGui_BeginCombo("", if (selected_data) |data| data.gen.name.ptr else "--none--", 0)) {
        defer c.ImGui_EndCombo();
        const none_selected = if (selected_data) |_| false else true;
        if (c.ImGui_SelectableEx("--none--", none_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
            if (!none_selected) {
                on_selected(T, null, context);
            }
        }
        if (none_selected) {
            c.ImGui_SetItemDefaultFocus();
        }
        var data_it = point_cloud.point_data.typedIterator(T);
        while (data_it.next()) |data| {
            const is_selected = selected_data == data;
            if (c.ImGui_SelectableEx(data.gen.name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                if (!is_selected) {
                    on_selected(T, data, context);
                }
            }
            if (is_selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
    }
}
