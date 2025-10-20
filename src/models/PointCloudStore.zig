const PointCloudStore = @This();

const std = @import("std");
const builtin = @import("builtin");

const zgp = @import("../main.zig");
const c = zgp.c;

const imgui_utils = @import("../utils/imgui.zig");
const imgui_log = std.log.scoped(.imgui);
const zgp_log = std.log.scoped(.zgp);

const types_utils = @import("../utils/types.zig");

const PointCloud = @import("point/PointCloud.zig");
const PointCloudStdDatas = @import("point/PointCloudStdDatas.zig");
const PointCloudStdData = PointCloudStdDatas.PointCloudStdData;

const Data = @import("../utils/Data.zig").Data;
const DataGen = @import("../utils/Data.zig").DataGen;

const VBO = @import("../rendering/VBO.zig");
const IBO = @import("../rendering/IBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

/// This struct holds information related to a PointCloud, including:
/// - its standard datas
/// - the IBOs (for rendering).
/// The PointCloudInfo associated with a PointCloud is accessible via the pointCloudInfo function.
const PointCloudInfo = struct {
    std_data: PointCloudStdDatas = .{},
    points_ibo: IBO,

    pub fn init() PointCloudInfo {
        return .{
            .points_ibo = IBO.init(),
        };
    }
    pub fn deinit(self: *PointCloudInfo) void {
        self.points_ibo.deinit();
    }
};

allocator: std.mem.Allocator,

point_clouds: std.StringHashMap(*PointCloud),
point_clouds_info: std.AutoHashMap(*const PointCloud, PointCloudInfo),
selected_point_cloud: ?*PointCloud = null,

data_vbo: std.AutoHashMap(*const DataGen, VBO),
data_last_update: std.AutoHashMap(*const DataGen, std.time.Instant),

pub fn init(allocator: std.mem.Allocator) PointCloudStore {
    return .{
        .allocator = allocator,
        .point_clouds = .init(allocator),
        .point_clouds_info = .init(allocator),
        .data_vbo = .init(allocator),
        .data_last_update = .init(allocator),
    };
}

pub fn deinit(pcs: *PointCloudStore) void {
    var pc_info_it = pcs.point_clouds_info.iterator();
    while (pc_info_it.next()) |entry| {
        var info = entry.value_ptr.*;
        info.deinit();
    }
    pcs.point_clouds_info.deinit();

    var pc_it = pcs.point_clouds.iterator();
    while (pc_it.next()) |entry| {
        var pc = entry.value_ptr.*;
        const name: [:0]const u8 = @ptrCast(entry.key_ptr.*); // the name is a null-terminated string (dupeZ in createPointCloud)
        pcs.allocator.free(name); // free the name
        pc.deinit();
        pcs.allocator.destroy(pc); // destroy the PointCloud
    }
    pcs.point_clouds.deinit();

    var vbo_it = pcs.data_vbo.iterator();
    while (vbo_it.next()) |entry| {
        var vbo = entry.value_ptr.*;
        vbo.deinit();
    }
    pcs.data_vbo.deinit();
    pcs.data_last_update.deinit();
}

pub fn createPointCloud(pcs: *PointCloudStore, name: []const u8) !*PointCloud {
    const maybe_point_cloud = pcs.point_clouds.get(name);
    if (maybe_point_cloud) |_| {
        return error.ModelNameAlreadyExists;
    }
    const pc = try pcs.allocator.create(PointCloud);
    errdefer pcs.allocator.destroy(pc);
    pc.* = try PointCloud.init(pcs.allocator);
    errdefer pc.deinit();
    const owned_name = try pcs.allocator.dupeZ(u8, name);
    errdefer pcs.allocator.free(owned_name);
    try pcs.point_clouds.put(owned_name, pc);
    errdefer _ = pcs.point_clouds.remove(owned_name);
    var info = PointCloudInfo.init();
    errdefer info.deinit();
    try pcs.point_clouds_info.put(pc, info);
    errdefer _ = pcs.point_clouds_info.remove(pc);

    // TODO: find a way to only notify modules that have registered interest in PointCloud
    for (zgp.modules.items) |module| {
        module.pointCloudCreated(pc);
    }

    return pc;
}

pub fn destroyPointCloud(pcs: *PointCloudStore, pc: *PointCloud) void {
    const name = pcs.pointCloudName(pc) orelse {
        zgp_log.err("Could not find name for PointCloud to destroy it", .{});
        return;
    };

    // TODO: find a way to only notify modules that have registered interest in PointCloud
    for (zgp.modules.items) |module| {
        module.pointCloudDestroyed(pc);
    }

    if (pcs.selected_point_cloud == pc) {
        pcs.selected_point_cloud = null;
    }
    _ = pcs.point_clouds.remove(name);
    pcs.allocator.free(name); // free the name
    const info = pcs.point_clouds_info.getPtr(pc).?;
    info.deinit();
    _ = pcs.point_clouds_info.remove(pc);
    pc.deinit();
    pcs.allocator.destroy(pc); // destroy the PointCloud
}

pub fn pointCloudDataUpdated(
    pcs: *PointCloudStore,
    pc: *PointCloud,
    comptime T: type,
    data: PointCloud.CellData(T),
) void {
    // if it exists, update the VBO with the data
    const maybe_vbo = pcs.data_vbo.getPtr(data.gen());
    if (maybe_vbo) |vbo| {
        vbo.fillFrom(T, data.data);
    }

    const now = std.time.Instant.now() catch |err| {
        zgp_log.err("Failed to get current time: {}", .{err});
        return;
    };
    pcs.data_last_update.put(data.gen(), now) catch |err| {
        zgp_log.err("Failed to update last update time for PointCloud data: {}", .{err});
        return;
    };

    // TODO: find a way to only notify modules that have registered interest in PointCloud
    for (zgp.modules.items) |module| {
        module.pointCloudDataUpdated(pc, data.gen());
    }
    zgp.requestRedraw();
}

pub fn pointCloudConnectivityUpdated(pcs: *PointCloudStore, pc: *PointCloud) void {
    const info = pcs.point_clouds_info.getPtr(pc).?;

    info.points_ibo.fillFromPointCloud(pc, pcs.allocator) catch |err| {
        zgp_log.err("Failed to fill points IBO for PointCloud: {}", .{err});
        return;
    };

    // TODO: find a way to only notify modules that have registered interest in PointCloud
    for (zgp.modules.items) |module| {
        module.pointCloudConnectivityUpdated(pc);
    }
    zgp.requestRedraw();
}

pub fn dataVBO(pcs: *PointCloudStore, comptime T: type, data: PointCloud.CellData(T)) VBO {
    const vbo = pcs.data_vbo.getOrPut(data.gen()) catch |err| {
        zgp_log.err("Failed to get or add VBO in the registry: {}", .{err});
        return VBO.init(); // return a dummy VBO
    };
    if (!vbo.found_existing) {
        vbo.value_ptr.* = VBO.init();
        vbo.value_ptr.*.fillFrom(T, data.data); // on VBO creation, fill it with the data
    }
    return vbo.value_ptr.*;
}

pub fn dataLastUpdate(pcs: *PointCloudStore, data_gen: *const DataGen) ?std.time.Instant {
    return pcs.data_last_update.get(data_gen);
}

pub fn pointCloudInfo(pcs: *PointCloudStore, pc: *const PointCloud) *PointCloudInfo {
    return pcs.point_clouds_info.getPtr(pc).?; // should always exist
}

pub fn pointCloudName(pcs: *PointCloudStore, pc: *const PointCloud) ?[:0]const u8 {
    var it = pcs.point_clouds.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* == pc) {
            return @ptrCast(entry.key_ptr.*); // the name is a null-terminated string (dupeZ in createPointCloud)
        }
    }
    return null;
}

pub fn setPointCloudStdData(
    pcs: *PointCloudStore,
    pc: *PointCloud,
    data: PointCloudStdData,
) void {
    const info = pcs.point_clouds_info.getPtr(pc).?;
    switch (data) {
        inline else => |val, tag| {
            @field(info.std_data, @tagName(tag)) = val;
        },
    }

    // TODO: find a way to only notify modules that have registered interest in PointCloud
    for (zgp.modules.items) |module| {
        module.pointCloudStdDataChanged(pc, data);
    }
    zgp.requestRedraw();
}

pub fn menuBar(_: *PointCloudStore) void {}

pub fn uiPanel(pcs: *PointCloudStore) void {
    const CreateDataTypes = union(enum) { f32: f32, Vec3f: Vec3f };
    const CreateDataTypesTag = std.meta.Tag(CreateDataTypes);
    const UiData = struct {
        var selected_data_type: CreateDataTypesTag = .f32;
        var data_name_buf: [32]u8 = undefined;
    };

    c.ImGui_PushIDPtr(pcs); // push a unique ID for this panel
    defer c.ImGui_PopID();

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    c.ImGui_PushStyleColor(c.ImGuiCol_Header, c.IM_COL32(255, 128, 0, 200));
    c.ImGui_PushStyleColor(c.ImGuiCol_HeaderActive, c.IM_COL32(255, 128, 0, 255));
    c.ImGui_PushStyleColor(c.ImGuiCol_HeaderHovered, c.IM_COL32(255, 128, 0, 128));
    if (c.ImGui_CollapsingHeader("Point Clouds", c.ImGuiTreeNodeFlags_DefaultOpen)) {
        c.ImGui_PopStyleColorEx(3);

        const nb_point_clouds_f = @as(f32, @floatFromInt(pcs.point_clouds.count() + 1));
        if (imgui_utils.pointCloudListBox(
            pcs.selected_point_cloud,
            style.*.FontSizeBase * nb_point_clouds_f + style.*.ItemSpacing.y * nb_point_clouds_f,
        )) |pc| {
            pcs.selected_point_cloud = pc;
        }

        const button_width = c.ImGui_CalcTextSize("" ++ c.ICON_FA_DATABASE).x + style.*.ItemSpacing.x;

        if (pcs.selected_point_cloud) |pc| {
            var buf: [64]u8 = undefined; // guess 64 chars is enough for cell counts
            const info = pcs.point_clouds_info.getPtr(pc).?;
            const cells = std.fmt.bufPrintZ(&buf, "Points | {d} |", .{pc.nbPoints()}) catch "";
            c.ImGui_SeparatorText(cells.ptr);
            inline for (@typeInfo(PointCloudStdData).@"union".fields) |*field| {
                c.ImGui_Text(field.name);
                c.ImGui_SameLine();
                // align 2 buttons to the right of the text
                c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + c.ImGui_GetContentRegionAvail().x - 2 * button_width - style.*.ItemSpacing.x);
                const data_selected = @field(info.std_data, field.name) != null;
                if (!data_selected) {
                    c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(128, 128, 128, 200));
                    c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(128, 128, 128, 255));
                    c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(128, 128, 128, 128));
                }
                c.ImGui_PushID(field.name);
                defer c.ImGui_PopID();
                if (c.ImGui_Button("" ++ c.ICON_FA_DATABASE)) {
                    c.ImGui_OpenPopup("select_data_popup", c.ImGuiPopupFlags_NoReopen);
                }
                if (!data_selected) {
                    c.ImGui_PopStyleColorEx(3);
                }
                if (c.ImGui_BeginPopup("select_data_popup", 0)) {
                    defer c.ImGui_EndPopup();
                    c.ImGui_PushID("select_data_combobox");
                    defer c.ImGui_PopID();
                    if (imgui_utils.pointCloudDataComboBox(
                        pc,
                        @typeInfo(field.type).optional.child.DataType,
                        @field(info.std_data, field.name),
                    )) |data| {
                        pcs.setPointCloudStdData(pc, @unionInit(PointCloudStdData, field.name, data));
                    }
                }
            }

            c.ImGui_Separator();

            if (c.ImGui_ButtonEx(c.ICON_FA_DATABASE ++ " Create missing std datas", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                inline for (@typeInfo(PointCloudStdData).@"union".fields) |*field| {
                    if (@field(info.std_data, field.name) == null) {
                        const maybe_data = pc.addData(@typeInfo(field.type).optional.child.DataType, field.name);
                        if (maybe_data) |data| {
                            pcs.setPointCloudStdData(pc, @unionInit(PointCloudStdData, field.name, data));
                        } else |err| {
                            zgp_log.err("Error adding {s} ({s}) data: {}", .{ field.name, @typeName(@typeInfo(field.type).optional.child.DataType), err });
                        }
                    }
                }
            }

            if (c.ImGui_ButtonEx("Create cell data", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                c.ImGui_OpenPopup("Create Cell Data", c.ImGuiPopupFlags_NoReopen);
            }
            if (c.ImGui_BeginPopupModal("Create Cell Data", 0, c.ImGuiWindowFlags_AlwaysAutoResize)) {
                defer c.ImGui_EndPopup();
                c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
                defer c.ImGui_PopItemWidth();
                c.ImGui_Text("Data type:");
                c.ImGui_PushID("data type");
                if (c.ImGui_BeginCombo("", @tagName(UiData.selected_data_type), 0)) {
                    defer c.ImGui_EndCombo();
                    inline for (@typeInfo(CreateDataTypesTag).@"enum".fields) |*data_type| {
                        const is_selected = @intFromEnum(UiData.selected_data_type) == data_type.value;
                        if (c.ImGui_SelectableEx(data_type.name, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                            if (!is_selected) {
                                UiData.selected_data_type = @enumFromInt(data_type.value);
                            }
                        }
                        if (is_selected) {
                            c.ImGui_SetItemDefaultFocus();
                        }
                    }
                }
                c.ImGui_PopID();
                c.ImGui_Text("Name:");
                _ = c.ImGui_InputText("##Name", &UiData.data_name_buf, UiData.data_name_buf.len, c.ImGuiInputTextFlags_CharsNoBlank);
                if (c.ImGui_ButtonEx("Close", c.ImVec2{ .x = 0.5 * c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                    UiData.data_name_buf[0] = 0;
                    c.ImGui_CloseCurrentPopup();
                }
                c.ImGui_SameLine();
                if (c.ImGui_ButtonEx("Create", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                    switch (UiData.selected_data_type) {
                        inline else => |data_type| {
                            _ = pc.addData(@FieldType(CreateDataTypes, @tagName(data_type)), &UiData.data_name_buf) catch |err| {
                                zgp_log.err("Error adding {s} ({s}) data: {}", .{ &UiData.data_name_buf, @tagName(data_type), err });
                            };
                            UiData.data_name_buf[0] = 0;
                        },
                    }
                    c.ImGui_CloseCurrentPopup();
                }
            }
        } else {
            c.ImGui_Text("No Point Cloud selected");
        }
    } else {
        c.ImGui_PopStyleColorEx(3);
    }
}

// TODO: put the IO code in a separate module

pub fn loadPointCloudFromFile(pcs: *PointCloudStore, filename: []const u8) !*PointCloud {
    const pc = try pcs.createPointCloud(filename);
    // read the file and fill the point cloud
    return pc;
}
