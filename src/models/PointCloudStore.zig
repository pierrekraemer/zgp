const PointCloudStore = @This();

const std = @import("std");
const builtin = @import("builtin");

const c = @import("../main.zig").c;

const imgui_log = std.log.scoped(.imgui);
const zgp_log = std.log.scoped(.zgp);

const imgui_utils = @import("../ui/imgui.zig");
const types_utils = @import("../utils/types.zig");

const Module = @import("../modules/Module.zig");
const PointCloud = @import("point/PointCloud.zig");

const Data = @import("../utils/Data.zig").Data;
const DataGen = @import("../utils/Data.zig").DataGen;
const BufferPool = @import("../utils/BufferPool.zig").BufferPool;

const VBO = @import("../rendering/VBO.zig");
const IBO = @import("../rendering/IBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

/// This struct defines the standard datas of a PointCloud
pub const PointCloudStdDatas = struct {
    position: ?PointCloud.CellData(Vec3f) = null,
    normal: ?PointCloud.CellData(Vec3f) = null,
    radius: ?PointCloud.CellData(f32) = null,
    // color: ?PointCloud.CellData(Vec3f) = null,
};

/// This tagged union is generated from the PointCloudStdDatas struct and allows to easily provide a single
/// data entry to the setPointCloudStdData function (in PointCloudStore)
pub const PointCloudStdData = types_utils.UnionFromStruct(PointCloudStdDatas);
pub const PointCloudStdDataTag = std.meta.Tag(PointCloudStdData);

/// This struct holds information related to a PointCloud, including:
/// - its standard datas
/// - the IBOs (for rendering).
/// The PointCloudInfo associated with a PointCloud is accessible via the pointCloudInfo function.
const PointCloudInfo = struct {
    std_datas: PointCloudStdDatas = .{},

    points_ibo: IBO,

    pub fn init() PointCloudInfo {
        return .{
            .points_ibo = .init(),
        };
    }
    pub fn deinit(self: *PointCloudInfo) void {
        self.points_ibo.deinit();
    }
};

allocator: std.mem.Allocator,

// list of Modules that have registered interest in PointCloud events
listeners: std.ArrayList(*Module),

point_clouds: std.StringHashMap(*PointCloud),
point_clouds_info: std.AutoHashMap(*const PointCloud, PointCloudInfo),
selected_point_cloud: ?*PointCloud = null,

data_vbo: std.AutoHashMap(*const DataGen, VBO),
data_last_update: std.AutoHashMap(*const DataGen, std.time.Instant),

point_buffer_pool: BufferPool(PointCloud.Point),

pub fn init(allocator: std.mem.Allocator) !PointCloudStore {
    return .{
        .allocator = allocator,
        .listeners = .empty,
        .point_clouds = .init(allocator),
        .point_clouds_info = .init(allocator),
        .data_vbo = .init(allocator),
        .data_last_update = .init(allocator),
        .point_buffer_pool = try .init(allocator, 1024, 64, 32),
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

    pcs.point_buffer_pool.deinit();

    pcs.listeners.deinit(pcs.allocator);
}

pub fn addListener(pcs: *PointCloudStore, module: *Module) !void {
    try pcs.listeners.append(pcs.allocator, module);
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

    for (pcs.listeners.items) |module| {
        module.pointCloudCreated(pc);
    }

    return pc;
}

pub fn destroyPointCloud(pcs: *PointCloudStore, pc: *PointCloud) void {
    const name = pcs.pointCloudName(pc) orelse {
        zgp_log.err("Could not find name for PointCloud to destroy it", .{});
        return;
    };

    for (pcs.listeners.items) |module| {
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

    for (pcs.listeners.items) |module| {
        module.pointCloudDataUpdated(pc, data.gen());
    }
}

pub fn pointCloudConnectivityUpdated(pcs: *PointCloudStore, pc: *PointCloud) void {
    const info = pcs.point_clouds_info.getPtr(pc).?;

    info.points_ibo.fillFromPointCloud(pc, pcs.allocator) catch |err| {
        zgp_log.err("Failed to fill points IBO for PointCloud: {}", .{err});
        return;
    };

    for (pcs.listeners.items) |module| {
        module.pointCloudConnectivityUpdated(pc);
    }
}

pub fn dataVBO(
    pcs: *PointCloudStore,
    comptime T: type,
    data: PointCloud.CellData(T),
) VBO {
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
            @field(info.std_datas, @tagName(tag)) = val;
        },
    }

    for (pcs.listeners.items) |module| {
        module.pointCloudStdDataChanged(pc, data);
    }
}

pub fn menuBar(_: *PointCloudStore) void {}

pub fn leftPanel(pcs: *PointCloudStore) void {
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
            pcs,
            style.*.FontSizeBase * nb_point_clouds_f + style.*.ItemSpacing.y * nb_point_clouds_f,
        )) |pc| {
            pcs.selected_point_cloud = pc;
        }

        if (pcs.selected_point_cloud) |pc| {
            var buf: [64]u8 = undefined; // guess 64 chars is enough for cell counts
            const cells = std.fmt.bufPrintZ(&buf, "Points | {d} | ({d:.1}%)", .{ pc.nbPoints(), pc.point_data.density() * 100 }) catch "";
            c.ImGui_Text(cells.ptr);

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
