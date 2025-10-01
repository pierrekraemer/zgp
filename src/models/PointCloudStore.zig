const PointCloudStore = @This();

const std = @import("std");
const builtin = @import("builtin");

const zgp = @import("../main.zig");
const c = zgp.c;

const imgui_utils = @import("../utils/imgui.zig");
const imgui_log = std.log.scoped(.imgui);
const zgp_log = std.log.scoped(.zgp);

const types_utils = @import("../utils/types.zig");

pub const PointCloud = @import("point/PointCloud.zig");

const Data = @import("../utils/Data.zig").Data;
const DataGen = @import("../utils/Data.zig").DataGen;

const VBO = @import("../rendering/VBO.zig");
const IBO = @import("../rendering/IBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

/// Standard PointCloud data name & types.
pub const PointCloudStdDatas = struct {
    position: ?PointCloud.CellData(Vec3f) = null,
    normal: ?PointCloud.CellData(Vec3f) = null,
};
/// This union is generated from the PointCloudStdDatas struct and allows to easily provide a single
/// data entry to the setPointCloudStdData function.
pub const PointCloudStdData = types_utils.UnionFromStruct(PointCloudStdDatas);
pub const PointCloudStdDataTag = std.meta.Tag(PointCloudStdData);

/// This struct holds information related to a PointCloud, including its standard datas, cells sets and the IBOs for rendering.
/// The PointCloudInfo associated with a PointCloud is accessible via the pointCloudInfo function.
const PointCloudInfo = struct {
    std_data: PointCloudStdDatas = .{},
    points_ibo: IBO, // TODO: really needed?
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
        .point_clouds = std.StringHashMap(*PointCloud).init(allocator),
        .point_clouds_info = std.AutoHashMap(*const PointCloud, PointCloudInfo).init(allocator),
        .data_vbo = std.AutoHashMap(*const DataGen, VBO).init(allocator),
        .data_last_update = std.AutoHashMap(*const DataGen, std.time.Instant).init(allocator),
    };
}

pub fn deinit(pcs: *PointCloudStore) void {
    var pc_info_it = pcs.point_clouds_info.iterator();
    while (pc_info_it.next()) |entry| {
        var info = entry.value_ptr.*;
        info.points_ibo.deinit();
    }
    pcs.point_clouds_info.deinit();
    var pc_it = pcs.point_clouds.iterator();
    while (pc_it.next()) |entry| {
        var pc = entry.value_ptr.*;
        pc.deinit();
        pcs.allocator.destroy(pc);
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
    for (zgp.modules.items) |*module| {
        module.pointCloudDataUpdated(pc, data.gen());
    }
    zgp.requestRedraw();
}

pub fn dataVBO(pcs: *PointCloudStore, comptime T: type, data: *const Data(T)) VBO {
    const vbo = pcs.data_vbo.getOrPut(&data.gen) catch |err| {
        zgp_log.err("Failed to get or add VBO in the registry: {}", .{err});
        return VBO.init(); // return a dummy VBO
    };
    if (!vbo.found_existing) {
        vbo.value_ptr.* = VBO.init();
        // if the VBO was just created, fill it with the data
        vbo.value_ptr.*.fillFrom(T, data);
    }
    return vbo.value_ptr.*;
}

pub fn dataLastUpdate(pcs: *PointCloudStore, data_gen: *const DataGen) ?std.time.Instant {
    return pcs.data_last_update.get(data_gen);
}

pub fn pointCloudInfo(pcs: *PointCloudStore, pc: *const PointCloud) *PointCloudInfo {
    return pcs.point_clouds_info.getPtr(pc).?; // should always exist
}

pub fn pointCloudName(pcs: *PointCloudStore, pc: *const PointCloud) ?[]const u8 {
    const it = pcs.point_clouds.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* == pc) {
            return entry.key_ptr.*;
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
    for (zgp.modules.items) |*module| {
        module.pointCloudStdDataChanged(pc, data);
    }
    zgp.requestRedraw();
}

pub fn menuBar(_: *PointCloudStore) void {}

pub fn uiPanel(pcs: *PointCloudStore) void {
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

        if (pcs.selected_point_cloud) |pc| {
            var buf: [16]u8 = undefined; // guess 16 chars is enough for cell counts
            const info = pcs.point_clouds_info.getPtr(pc).?;
            inline for (.{.point}) |cell_type| { // a bit silly with only one cell type for now
                c.ImGui_SeparatorText(@tagName(cell_type));
                c.ImGui_Text("# = ");
                c.ImGui_SameLine();
                const nb_cells = std.fmt.bufPrintZ(&buf, "{d}", .{pc.nbPoints()}) catch "";
                c.ImGui_Text(nb_cells.ptr);
                inline for (@typeInfo(PointCloudStdDatas).@"struct".fields) |*field| {
                    c.ImGui_Text(field.name);
                    c.ImGui_SameLine();
                    c.ImGui_PushID(field.name);
                    const combobox_width = @min(c.ImGui_GetWindowWidth() * 0.5, c.ImGui_GetContentRegionAvail().x);
                    c.ImGui_SetNextItemWidth(combobox_width);
                    c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + @max(0.0, c.ImGui_GetContentRegionAvail().x - combobox_width));
                    if (imgui_utils.pointCloudDataComboBox(
                        pc,
                        @typeInfo(field.type).optional.child.DataType,
                        @field(info.std_data, field.name),
                    )) |data| {
                        pcs.setPointCloudStdData(pc, @unionInit(PointCloudStdData, field.name, data));
                    }
                    c.ImGui_PopID();
                }
            }
            c.ImGui_Separator();
            if (c.ImGui_ButtonEx("Create missing std datas", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                inline for (@typeInfo(PointCloudStdData).@"union".fields) |*field| {
                    const maybe_data = pc.addData(@typeInfo(field.type).optional.child.DataType, field.name);
                    if (maybe_data) |data| {
                        if (@field(info.std_data, field.name) == null) {
                            pcs.setPointCloudStdData(pc, @unionInit(PointCloudStdData, field.name, data));
                        }
                    } else |err| {
                        zgp_log.err("Error adding {s} ({s}) data: {}", .{ field.name, @typeName(@typeInfo(field.type).optional.child.DataType), err });
                    }
                }
            }
        } else {
            c.ImGui_Text("No Point Cloud selected");
        }
    } else {
        c.ImGui_PopStyleColorEx(3);
    }
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
    try pcs.point_clouds.put(name, pc);
    errdefer _ = pcs.point_clouds.remove(name);
    try pcs.point_clouds_info.put(pc, .{
        .points_ibo = IBO.init(),
    });
    errdefer _ = pcs.point_clouds_info.remove(pc);

    // TODO: find a way to only notify modules that have registered interest in PointCloud
    for (zgp.modules.items) |*module| {
        module.pointCloudAdded(pc);
    }

    return pc;
}

// TODO: put the IO code in a separate module

pub fn loadPointCloudFromFile(pcs: *PointCloudStore, filename: []const u8) !*PointCloud {
    const pc = try pcs.createPointCloud(filename);
    // read the file and fill the point cloud
    return pc;
}
