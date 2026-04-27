const PointCloudStore = @This();

const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const c = @import("../main.zig").c;

const imgui_log = std.log.scoped(.imgui);
const zgp_log = std.log.scoped(.zgp);

const imgui_utils = @import("../ui/imgui.zig");
const types_utils = @import("../utils/types.zig");

const Module = @import("../modules/Module.zig");
const ModelSelection = @import("../main.zig").ModelSelection;
const PointCloud = @import("point/PointCloud.zig");

const Data = @import("../utils/data.zig").Data;
const DataGen = @import("../utils/data.zig").DataGen;
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
/// This tagged union is generated from the PointCloudStdDatas struct and allows to
/// easily provide a single data entry to the setPointCloudStdData function
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

io: std.Io,
allocator: std.mem.Allocator,

// list of Modules that have registered interest in PointCloud events
listeners: std.ArrayList(*Module),

point_clouds: std.StringArrayHashMapUnmanaged(*PointCloud),
point_clouds_info: std.AutoArrayHashMapUnmanaged(*const PointCloud, PointCloudInfo),
selected_model: *ModelSelection = undefined, // set in AppContext wireUp

// each DataGen can be associated with a VBO
// once a VBO has been requested for a Data (in dataVBO) it is stored in this map
// and updated upon calls to pointCloudDataUpdated
data_vbo: std.AutoHashMapUnmanaged(*const DataGen, VBO),
// stores the last update time for each DataGen
// updated upon calls to pointCloudDataUpdated
data_last_update: std.AutoHashMapUnmanaged(*const DataGen, std.Io.Timestamp),

point_buffer_pool: BufferPool(PointCloud.Point),

pub fn init(io: std.Io, allocator: std.mem.Allocator) !PointCloudStore {
    return .{
        .io = io,
        .allocator = allocator,
        .listeners = .empty,
        .point_clouds = .empty,
        .point_clouds_info = .empty,
        .data_vbo = .empty,
        .data_last_update = .empty,
        .point_buffer_pool = try .init(io, allocator, 2048, 64, 32),
    };
}

pub fn deinit(pcs: *PointCloudStore) void {
    pcs.listeners.deinit(pcs.allocator);

    for (pcs.point_clouds_info.values()) |*info| {
        info.deinit();
    }
    pcs.point_clouds_info.deinit(pcs.allocator);

    for (pcs.point_clouds.keys(), pcs.point_clouds.values()) |name, pc| {
        const nameZ: [:0]const u8 = @ptrCast(name); // the name is a null-terminated string (dupeZ in createPointCloud)
        pcs.allocator.free(nameZ); // free the name
        pc.deinit();
        pcs.allocator.destroy(pc); // destroy the PointCloud
    }
    pcs.point_clouds.deinit(pcs.allocator);

    var vbo_it = pcs.data_vbo.iterator();
    while (vbo_it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    pcs.data_vbo.deinit(pcs.allocator);

    pcs.data_last_update.deinit(pcs.allocator);

    pcs.point_buffer_pool.deinit();
}

pub fn addListener(pcs: *PointCloudStore, module: *Module) !void {
    try pcs.listeners.append(pcs.allocator, module);
}

pub fn createPointCloud(pcs: *PointCloudStore, name: []const u8) !*PointCloud {
    if (pcs.point_clouds.contains(name)) {
        return error.ModelNameAlreadyExists;
    }

    // create and init the PointCloud
    const pc = try pcs.allocator.create(PointCloud);
    errdefer pcs.allocator.destroy(pc);
    try pc.init(pcs.allocator, &pcs.point_buffer_pool);
    errdefer pc.deinit();

    // duplicate name and store the PointCloud pointer in the map
    const owned_name = try pcs.allocator.dupeZ(u8, name);
    errdefer pcs.allocator.free(owned_name);
    try pcs.point_clouds.put(pcs.allocator, owned_name, pc);
    errdefer _ = pcs.point_clouds.swapRemove(owned_name);

    // store the PointCloudInfo in the map
    try pcs.point_clouds_info.put(pcs.allocator, pc, .init());

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

    switch (pcs.selected_model.*) {
        .point_cloud => |selected_pc| {
            if (selected_pc == pc) {
                pcs.selected_model.* = .none;
            }
        },
        else => {},
    }

    for (pcs.listeners.items) |module| {
        module.pointCloudDestroyed(pc);
    }

    pcs.point_clouds_info.getPtr(pc).?.deinit();
    _ = pcs.point_clouds_info.swapRemove(pc);

    _ = pcs.point_clouds.swapRemove(name);
    pcs.allocator.free(name); // free the name

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

    // update the last known data update time
    pcs.data_last_update.put(pcs.allocator, data.gen(), std.Io.Timestamp.now(pcs.io, .real)) catch |err| {
        zgp_log.err("Failed to update last update time for PointCloud data: {}", .{err});
        return;
    };

    // dispatch call to listeners
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
    const vbo = pcs.data_vbo.getOrPut(pcs.allocator, data.gen()) catch |err| {
        zgp_log.err("Failed to get or add VBO in the registry: {}", .{err});
        return VBO.init(); // return a dummy VBO
    };
    if (!vbo.found_existing) {
        vbo.value_ptr.* = VBO.init();
        vbo.value_ptr.*.fillFrom(T, data.data); // on VBO creation, fill it with the data
    }
    return vbo.value_ptr.*;
}

pub fn dataLastUpdate(pcs: *PointCloudStore, data_gen: *const DataGen) ?std.Io.Timestamp {
    return pcs.data_last_update.get(data_gen);
}

pub fn pointCloudInfo(pcs: *PointCloudStore, pc: *const PointCloud) *PointCloudInfo {
    return pcs.point_clouds_info.getPtr(pc).?; // should always exist
}

pub fn pointCloudName(pcs: *PointCloudStore, pc: *const PointCloud) ?[:0]const u8 {
    for (pcs.point_clouds.keys(), pcs.point_clouds.values()) |name, pc_ptr| {
        if (pc_ptr == pc) {
            return @ptrCast(name); // the name is a null-terminated string (dupeZ in createPointCloud)
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
    assert(pcs.selected_model.modelType() == .point_cloud);

    const CreateDataTypes = union(enum) { bool: bool, u32: u32, f32: f32, Vec3f: Vec3f };
    const CreateDataTypesTag = std.meta.Tag(CreateDataTypes);
    const UiData = struct {
        var selected_data_type: CreateDataTypesTag = .f32;
        var data_name_buf: [32]u8 = @splat(0);
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const pc = pcs.selected_model.point_cloud;

    if (c.ImGui_BeginTable("CellStats", 3, c.ImGuiTableFlags_Borders | c.ImGuiTableFlags_RowBg)) {
        defer c.ImGui_EndTable();

        c.ImGui_TableSetupColumn("CellType", c.ImGuiTableColumnFlags_WidthStretch);
        c.ImGui_TableSetupColumn("Count", c.ImGuiTableColumnFlags_WidthFixed);
        c.ImGui_TableSetupColumn("ContainerDensity", c.ImGuiTableColumnFlags_WidthFixed);
        c.ImGui_TableHeadersRow();

        var buf_count: [16]u8 = undefined;
        var buf_density: [16]u8 = undefined;

        const count = std.fmt.bufPrintZ(&buf_count, "{d}", .{pc.nbPoints()}) catch "";
        const density = std.fmt.bufPrintZ(&buf_density, "{d:.1}%", .{pc.point_data.density() * 100}) catch "";

        c.ImGui_TableNextRow();
        _ = c.ImGui_TableNextColumn();
        c.ImGui_Text("Points");
        _ = c.ImGui_TableNextColumn();
        c.ImGui_Text(count.ptr);
        _ = c.ImGui_TableNextColumn();
        c.ImGui_Text(density.ptr);
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
            UiData.data_name_buf = @splat(0);
            c.ImGui_CloseCurrentPopup();
        }
        c.ImGui_SameLine();
        if (c.ImGui_ButtonEx("Create", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            switch (UiData.selected_data_type) {
                inline else => |data_type| {
                    const data_name = std.mem.sliceTo(&UiData.data_name_buf, 0);
                    _ = pc.addData(@FieldType(CreateDataTypes, @tagName(data_type)), data_name) catch |err| {
                        zgp_log.err("Error adding {s} ({s}) data: {}", .{ data_name, @tagName(data_type), err });
                    };
                    UiData.data_name_buf = @splat(0);
                },
            }
        }
    }

    {
        c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(255, 128, 128, 200));
        c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(255, 128, 128, 255));
        c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(255, 128, 128, 128));
        if (c.ImGui_ButtonEx(c.ICON_FA_TRASH ++ " Delete", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            pcs.destroyPointCloud(pc);
        }
        c.ImGui_PopStyleColorEx(3);
    }
}

// TODO: put the IO code in a separate module

pub fn loadPointCloudFromFile(pcs: *PointCloudStore, filename: []const u8) !*PointCloud {
    const pc = try pcs.createPointCloud(filename);
    // read the file and fill the point cloud
    return pc;
}
