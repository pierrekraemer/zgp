const ModelsRegistry = @This();

const std = @import("std");
const builtin = @import("builtin");

const zgp = @import("../main.zig");
const c = zgp.c;

const imgui_utils = @import("../utils/imgui.zig");
const imgui_log = std.log.scoped(.imgui);
const zgp_log = std.log.scoped(.zgp);

const types_utils = @import("../utils/types.zig");

pub const PointCloud = @import("point/PointCloud.zig");
pub const SurfaceMesh = @import("surface/SurfaceMesh.zig");

const Data = @import("../utils/Data.zig").Data;
const DataGen = @import("../utils/Data.zig").DataGen;

const VBO = @import("../rendering/VBO.zig");
const IBO = @import("../rendering/IBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3 = vec.Vec3;

/// Standard PointCloud data name & types.
pub const PointCloudStdDatas = struct {
    position: ?PointCloud.CellData(Vec3) = null,
    normal: ?PointCloud.CellData(Vec3) = null,
    color: ?PointCloud.CellData(Vec3) = null,
};
/// This union is generated from the PointCloudStdDatas struct and allows to easily provide a single
/// data entry to the setPointCloudStdData function.
pub const PointCloudStdData = types_utils.UnionFromStruct(PointCloudStdDatas);
pub const PointCloudStdDataTag = std.meta.Tag(PointCloudStdData);

/// This struct holds all the information related to a PointCloud, including the standard datas and the IBOs for rendering.
/// Each PointCloud in the ModelsRegistry has an associated PointCloudInfo which can be accessed via the pointCloudInfo function.
const PointCloudInfo = struct {
    std_data: PointCloudStdDatas = .{},
    points_ibo: IBO,
};

/// Standard SurfaceMesh data name & types.
pub const SurfaceMeshStdDatas = struct {
    corner_angle: ?SurfaceMesh.CellData(.corner, f32) = null,
    halfedge_cotan_weight: ?SurfaceMesh.CellData(.halfedge, f32) = null,
    vertex_position: ?SurfaceMesh.CellData(.vertex, Vec3) = null,
    vertex_area: ?SurfaceMesh.CellData(.vertex, f32) = null,
    vertex_normal: ?SurfaceMesh.CellData(.vertex, Vec3) = null,
    vertex_gaussian_curvature: ?SurfaceMesh.CellData(.vertex, f32) = null,
    vertex_mean_curvature: ?SurfaceMesh.CellData(.vertex, f32) = null,
    edge_length: ?SurfaceMesh.CellData(.edge, f32) = null,
    edge_dihedral_angle: ?SurfaceMesh.CellData(.edge, f32) = null,
    face_area: ?SurfaceMesh.CellData(.face, f32) = null,
    face_normal: ?SurfaceMesh.CellData(.face, Vec3) = null,
};
/// This union is generated from the SurfaceMeshStdDatas struct and allows to easily provide a single
/// data entry to the setSurfaceMeshStdData function.
pub const SurfaceMeshStdData = types_utils.UnionFromStruct(SurfaceMeshStdDatas);
pub const SurfaceMeshStdDataTag = std.meta.Tag(SurfaceMeshStdData);

/// This struct holds all the information related to a SurfaceMesh, including the standard datas, cells sets and the IBOs for rendering.
/// Each SurfaceMesh in the ModelsRegistry has an associated SurfaceMeshInfo which can be accessed via the surfaceMeshInfo function.
const SurfaceMeshInfo = struct {
    std_data: SurfaceMeshStdDatas = .{},

    vertex_set: SurfaceMesh.CellSet(.vertex),
    edge_set: SurfaceMesh.CellSet(.edge),
    face_set: SurfaceMesh.CellSet(.face),

    points_ibo: IBO,
    lines_ibo: IBO,
    triangles_ibo: IBO,
    boundaries_ibo: IBO,
};

allocator: std.mem.Allocator,

point_clouds: std.StringHashMap(*PointCloud),
surface_meshes: std.StringHashMap(*SurfaceMesh),

point_clouds_info: std.AutoHashMap(*const PointCloud, PointCloudInfo),
surface_meshes_info: std.AutoHashMap(*const SurfaceMesh, SurfaceMeshInfo),

data_vbo: std.AutoHashMap(*const DataGen, VBO),
data_last_update: std.AutoHashMap(*const DataGen, std.time.Instant),

selected_point_cloud: ?*PointCloud = null,
selected_surface_mesh: ?*SurfaceMesh = null,

pub fn init(allocator: std.mem.Allocator) ModelsRegistry {
    return .{
        .allocator = allocator,
        .point_clouds = std.StringHashMap(*PointCloud).init(allocator),
        .surface_meshes = std.StringHashMap(*SurfaceMesh).init(allocator),
        .point_clouds_info = std.AutoHashMap(*const PointCloud, PointCloudInfo).init(allocator),
        .surface_meshes_info = std.AutoHashMap(*const SurfaceMesh, SurfaceMeshInfo).init(allocator),
        .data_vbo = std.AutoHashMap(*const DataGen, VBO).init(allocator),
        .data_last_update = std.AutoHashMap(*const DataGen, std.time.Instant).init(allocator),
    };
}

pub fn deinit(mr: *ModelsRegistry) void {
    var pc_info_it = mr.point_clouds_info.iterator();
    while (pc_info_it.next()) |entry| {
        var info = entry.value_ptr.*;
        info.points_ibo.deinit();
    }
    mr.point_clouds_info.deinit();
    var pc_it = mr.point_clouds.iterator();
    while (pc_it.next()) |entry| {
        var pc = entry.value_ptr.*;
        pc.deinit();
        mr.allocator.destroy(pc);
    }
    mr.point_clouds.deinit();

    var sm_info_it = mr.surface_meshes_info.iterator();
    while (sm_info_it.next()) |entry| {
        var info = entry.value_ptr.*;
        info.vertex_set.deinit();
        info.edge_set.deinit();
        info.face_set.deinit();
        info.points_ibo.deinit();
        info.lines_ibo.deinit();
        info.triangles_ibo.deinit();
        info.boundaries_ibo.deinit();
    }
    mr.surface_meshes_info.deinit();
    var sm_it = mr.surface_meshes.iterator();
    while (sm_it.next()) |entry| {
        var sm = entry.value_ptr.*;
        sm.deinit();
        mr.allocator.destroy(sm);
    }
    mr.surface_meshes.deinit();

    var vbo_it = mr.data_vbo.iterator();
    while (vbo_it.next()) |entry| {
        var vbo = entry.value_ptr.*;
        vbo.deinit();
    }
    mr.data_vbo.deinit();

    mr.data_last_update.deinit();
}

pub fn pointCloudDataUpdated(
    mr: *ModelsRegistry,
    pc: *PointCloud,
    comptime T: type,
    data: PointCloud.CellData(T),
) void {
    // if it exists, update the VBO with the data
    const maybe_vbo = mr.data_vbo.getPtr(data.gen());
    if (maybe_vbo) |vbo| {
        vbo.fillFrom(T, data.data) catch |err| {
            std.debug.print("Failed to update VBO for PointCloud data: {}\n", .{err});
            return;
        };
    }

    const now = std.time.Instant.now() catch |err| {
        std.debug.print("Failed to get current time: {}\n", .{err});
        return;
    };
    mr.data_last_update.put(data.gen(), now) catch |err| {
        std.debug.print("Failed to update last update time for PointCloud data: {}\n", .{err});
        return;
    };

    for (zgp.modules.items) |*module| {
        module.pointCloudDataUpdated(pc, data.gen());
    }
    zgp.requestRedraw();
}

pub fn surfaceMeshDataUpdated(
    mr: *ModelsRegistry,
    sm: *SurfaceMesh,
    comptime cell_type: SurfaceMesh.CellType,
    comptime T: type,
    data: SurfaceMesh.CellData(cell_type, T),
) void {
    // if it exists, update the VBO with the data
    const maybe_vbo = mr.data_vbo.getPtr(data.gen());
    if (maybe_vbo) |vbo| {
        vbo.fillFrom(T, data.data) catch |err| {
            std.debug.print("Failed to update VBO for SurfaceMesh data: {}\n", .{err});
            return;
        };
    }

    const now = std.time.Instant.now() catch |err| {
        std.debug.print("Failed to get current time: {}\n", .{err});
        return;
    };
    mr.data_last_update.put(data.gen(), now) catch |err| {
        std.debug.print("Failed to update last update time for SurfaceMesh data: {}\n", .{err});
        return;
    };

    for (zgp.modules.items) |*module| {
        module.surfaceMeshDataUpdated(sm, cell_type, data.gen());
    }
    zgp.requestRedraw();
}

pub fn surfaceMeshConnectivityUpdated(mr: *ModelsRegistry, sm: *SurfaceMesh) void {
    if (builtin.mode == .Debug) {
        const ok = sm.checkIntegrity() catch |err| {
            std.debug.print("Failed to check integrity after connectivity update: {}\n", .{err});
            return;
        };
        if (!ok) {
            std.debug.print("SurfaceMesh integrity check failed after connectivity update\n", .{});
            return;
        }
    }

    const info = mr.surface_meshes_info.getPtr(sm).?;

    info.vertex_set.update() catch |err| {
        std.debug.print("Failed to update vertex set for SurfaceMesh: {}\n", .{err});
        return;
    };
    info.edge_set.update() catch |err| {
        std.debug.print("Failed to update edge set for SurfaceMesh: {}\n", .{err});
        return;
    };
    info.face_set.update() catch |err| {
        std.debug.print("Failed to update face set for SurfaceMesh: {}\n", .{err});
        return;
    };

    info.points_ibo.fillFrom(sm, .vertex, mr.allocator) catch |err| {
        std.debug.print("Failed to fill points IBO for SurfaceMesh: {}\n", .{err});
        return;
    };
    info.lines_ibo.fillFrom(sm, .edge, mr.allocator) catch |err| {
        std.debug.print("Failed to fill lines IBO for SurfaceMesh: {}\n", .{err});
        return;
    };
    info.triangles_ibo.fillFrom(sm, .face, mr.allocator) catch |err| {
        std.debug.print("Failed to fill triangles IBO for SurfaceMesh: {}\n", .{err});
        return;
    };
    info.boundaries_ibo.fillFrom(sm, .boundary, mr.allocator) catch |err| {
        std.debug.print("Failed to fill boundaries IBO for SurfaceMesh: {}\n", .{err});
        return;
    };

    for (zgp.modules.items) |*module| {
        module.surfaceMeshConnectivityUpdated(sm);
    }
    zgp.requestRedraw();
}

pub fn dataVBO(mr: *ModelsRegistry, comptime T: type, data: *const Data(T)) !VBO {
    const vbo = try mr.data_vbo.getOrPut(&data.gen);
    if (!vbo.found_existing) {
        vbo.value_ptr.* = VBO.init();
        // if the VBO was just created, fill it with the data
        try vbo.value_ptr.*.fillFrom(T, data);
    }
    return vbo.value_ptr.*;
}

pub fn dataLastUpdate(mr: *ModelsRegistry, data_gen: *const DataGen) ?std.time.Instant {
    return mr.data_last_update.get(data_gen);
}

pub fn pointCloudInfo(mr: *ModelsRegistry, pc: *const PointCloud) *PointCloudInfo {
    return mr.point_clouds_info.getPtr(pc).?; // should always exist
}

pub fn pointCloudName(mr: *ModelsRegistry, pc: *const PointCloud) ?[]const u8 {
    const it = mr.point_clouds.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* == pc) {
            return entry.key_ptr.*;
        }
    }
    return null;
}

pub fn surfaceMeshInfo(mr: *ModelsRegistry, sm: *const SurfaceMesh) *SurfaceMeshInfo {
    return mr.surface_meshes_info.getPtr(sm).?; // should always exist
}

pub fn surfaceMeshName(mr: *ModelsRegistry, sm: *const SurfaceMesh) ?[]const u8 {
    const it = mr.surface_meshes.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* == sm) {
            return entry.key_ptr.*;
        }
    }
    return null;
}

pub fn setPointCloudStdData(
    mr: *ModelsRegistry,
    pc: *PointCloud,
    data: PointCloudStdData,
) void {
    const info = mr.point_clouds_info.getPtr(pc).?;
    switch (data) {
        inline else => |val, tag| {
            @field(info.std_data, @tagName(tag)) = val;
        },
    }

    for (zgp.modules.items) |*module| {
        module.pointCloudStdDataChanged(pc, data);
    }
    zgp.requestRedraw();
}

pub fn setSurfaceMeshStdData(
    mr: *ModelsRegistry,
    sm: *SurfaceMesh,
    data: SurfaceMeshStdData,
) void {
    const info = mr.surface_meshes_info.getPtr(sm).?;
    switch (data) {
        inline else => |val, tag| {
            @field(info.std_data, @tagName(tag)) = val;
        },
    }

    for (zgp.modules.items) |*module| {
        module.surfaceMeshStdDataChanged(sm, data);
    }
    zgp.requestRedraw();
}

pub fn menuBar(_: *ModelsRegistry) void {}

pub fn uiPanel(mr: *ModelsRegistry) void {
    const CreateDataTypes = union(enum) { f32: f32, Vec3: Vec3 };
    const CreateDataTypesTag = std.meta.Tag(CreateDataTypes);
    const UiData = struct {
        var selected_surface_mesh_cell_type: SurfaceMesh.CellType = .vertex;
        var selected_data_type: CreateDataTypesTag = .f32;
        var data_name_buf: [32]u8 = undefined;
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    c.ImGui_PushStyleColor(c.ImGuiCol_Header, c.IM_COL32(255, 128, 0, 200));
    c.ImGui_PushStyleColor(c.ImGuiCol_HeaderActive, c.IM_COL32(255, 128, 0, 255));
    c.ImGui_PushStyleColor(c.ImGuiCol_HeaderHovered, c.IM_COL32(255, 128, 0, 128));
    if (c.ImGui_CollapsingHeader("Surface Meshes", c.ImGuiTreeNodeFlags_DefaultOpen)) {
        c.ImGui_PopStyleColorEx(3);

        const nb_surface_meshes_f = @as(f32, @floatFromInt(mr.surface_meshes.count() + 1));
        if (imgui_utils.surfaceMeshListBox(
            mr.selected_surface_mesh,
            style.*.FontSizeBase * nb_surface_meshes_f + style.*.ItemSpacing.y * nb_surface_meshes_f,
        )) |sm| {
            mr.selected_surface_mesh = sm;
        }

        if (mr.selected_surface_mesh) |sm| {
            var buf: [64]u8 = undefined; // guess 64 chars is enough for cell name + cell count
            const info = mr.surface_meshes_info.getPtr(sm).?;
            inline for (.{ .corner, .vertex, .edge, .face }) |cell_type| {
                const cells = std.fmt.bufPrintZ(&buf, @tagName(cell_type) ++ " | {d} |", .{sm.nbCells(cell_type)}) catch "";
                c.ImGui_SeparatorText(cells.ptr);
                inline for (@typeInfo(SurfaceMeshStdData).@"union".fields) |*field| {
                    if (@typeInfo(field.type).optional.child.CellType != cell_type) continue;
                    c.ImGui_Text(field.name);
                    // c.ImGui_SameLine();
                    c.ImGui_PushID(field.name);
                    // const combobox_width = @min(c.ImGui_GetWindowWidth() * 0.5, c.ImGui_GetContentRegionAvail().x);
                    // c.ImGui_SetNextItemWidth(combobox_width);
                    // c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + @max(0.0, c.ImGui_GetContentRegionAvail().x - combobox_width));
                    if (imgui_utils.surfaceMeshCellDataComboBox(
                        sm,
                        @typeInfo(field.type).optional.child.CellType,
                        @typeInfo(field.type).optional.child.DataType,
                        @field(info.std_data, field.name),
                    )) |data| {
                        mr.setSurfaceMeshStdData(sm, @unionInit(SurfaceMeshStdData, field.name, data));
                    }
                    c.ImGui_PopID();
                }
            }

            c.ImGui_Separator();

            if (c.ImGui_ButtonEx("Create missing std datas", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                inline for (@typeInfo(SurfaceMeshStdData).@"union".fields) |*field| {
                    if (@field(info.std_data, field.name) == null) {
                        const maybe_data = sm.addData(@typeInfo(field.type).optional.child.CellType, @typeInfo(field.type).optional.child.DataType, field.name);
                        if (maybe_data) |data| {
                            mr.setSurfaceMeshStdData(sm, @unionInit(SurfaceMeshStdData, field.name, data));
                        } else |err| {
                            std.debug.print("Error adding {s} ({s}: {s}) data: {}\n", .{ field.name, @tagName(@typeInfo(field.type).optional.child.CellType), @typeName(@typeInfo(field.type).optional.child.DataType), err });
                        }
                    }
                }
            }

            if (c.ImGui_ButtonEx("Create cell data", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                c.ImGui_OpenPopup("Create SurfaceMesh Cell Data", c.ImGuiPopupFlags_NoReopen);
            }
            if (c.ImGui_BeginPopupModal("Create SurfaceMesh Cell Data", 0, 0)) {
                defer c.ImGui_EndPopup();
                c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
                defer c.ImGui_PopItemWidth();
                c.ImGui_Text("Cell type:");
                c.ImGui_PushID("cell type");
                if (imgui_utils.surfaceMeshCellTypeComboBox(UiData.selected_surface_mesh_cell_type)) |cell_type| {
                    UiData.selected_surface_mesh_cell_type = cell_type;
                }
                c.ImGui_PopID();
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
                    switch (UiData.selected_surface_mesh_cell_type) {
                        inline else => |cell_type| {
                            switch (UiData.selected_data_type) {
                                inline else => |data_type| {
                                    _ = sm.addData(cell_type, @FieldType(CreateDataTypes, @tagName(data_type)), &UiData.data_name_buf) catch |err| {
                                        imgui_log.err("Error adding {s} ({s}: {s}) data: {}\n", .{ &UiData.data_name_buf, @tagName(cell_type), @tagName(data_type), err });
                                    };
                                    UiData.data_name_buf[0] = 0;
                                },
                            }
                        },
                    }
                    c.ImGui_CloseCurrentPopup();
                }
            }
        } else {
            c.ImGui_Text("No Surface Mesh selected");
        }
    } else {
        c.ImGui_PopStyleColorEx(3);
    }

    c.ImGui_PushStyleColor(c.ImGuiCol_Header, c.IM_COL32(255, 128, 0, 200));
    c.ImGui_PushStyleColor(c.ImGuiCol_HeaderActive, c.IM_COL32(255, 128, 0, 255));
    c.ImGui_PushStyleColor(c.ImGuiCol_HeaderHovered, c.IM_COL32(255, 128, 0, 128));
    if (c.ImGui_CollapsingHeader("Point Clouds", c.ImGuiTreeNodeFlags_DefaultOpen)) {
        c.ImGui_PopStyleColorEx(3);

        const nb_point_clouds_f = @as(f32, @floatFromInt(mr.point_clouds.count() + 1));
        if (imgui_utils.pointCloudListBox(
            mr.selected_point_cloud,
            style.*.FontSizeBase * nb_point_clouds_f + style.*.ItemSpacing.y * nb_point_clouds_f,
        )) |pc| {
            mr.selected_point_cloud = pc;
        }

        if (mr.selected_point_cloud) |pc| {
            var buf: [16]u8 = undefined; // guess 16 chars is enough for cell counts
            const info = mr.point_clouds_info.getPtr(pc).?;
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
                        mr.setPointCloudStdData(pc, @unionInit(PointCloudStdData, field.name, data));
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
                            mr.setPointCloudStdData(pc, @unionInit(PointCloudStdData, field.name, data));
                        }
                    } else |err| {
                        std.debug.print("Error adding {s} ({s}) data: {}\n", .{ field.name, @typeName(@typeInfo(field.type).optional.child.DataType), err });
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

pub fn createPointCloud(mr: *ModelsRegistry, name: []const u8) !*PointCloud {
    const maybe_point_cloud = mr.point_clouds.get(name);
    if (maybe_point_cloud) |_| {
        return error.ModelNameAlreadyExists;
    }
    const pc = try mr.allocator.create(PointCloud);
    errdefer mr.allocator.destroy(pc);
    pc.* = try PointCloud.init(mr.allocator);
    errdefer pc.deinit();
    try mr.point_clouds.put(name, pc);
    errdefer _ = mr.point_clouds.remove(name);
    try mr.point_clouds_info.put(pc, .{
        .points_ibo = IBO.init(),
    });
    errdefer _ = mr.point_clouds_info.remove(pc);

    for (zgp.modules.items) |*module| {
        module.pointCloudAdded(pc);
    }

    return pc;
}

pub fn createSurfaceMesh(mr: *ModelsRegistry, name: []const u8) !*SurfaceMesh {
    const maybe_surface_mesh = mr.surface_meshes.get(name);
    if (maybe_surface_mesh) |_| {
        return error.ModelNameAlreadyExists;
    }
    var sm = try mr.allocator.create(SurfaceMesh);
    errdefer mr.allocator.destroy(sm);
    sm.* = try SurfaceMesh.init(mr.allocator);
    errdefer sm.deinit();
    try mr.surface_meshes.put(name, sm);
    errdefer _ = mr.surface_meshes.remove(name);
    try mr.surface_meshes_info.put(sm, .{
        .vertex_set = try SurfaceMesh.CellSet(.vertex).init(sm),
        .edge_set = try SurfaceMesh.CellSet(.edge).init(sm),
        .face_set = try SurfaceMesh.CellSet(.face).init(sm),
        .points_ibo = IBO.init(),
        .lines_ibo = IBO.init(),
        .triangles_ibo = IBO.init(),
        .boundaries_ibo = IBO.init(),
    });
    errdefer _ = mr.surface_meshes_info.remove(sm);

    for (zgp.modules.items) |*module| {
        module.surfaceMeshAdded(sm);
    }

    return sm;
}

// TODO: put the IO code in a separate module

pub fn loadPointCloudFromFile(mr: *ModelsRegistry, filename: []const u8) !*PointCloud {
    const pc = try mr.createPointCloud(filename);
    // read the file and fill the point cloud
    return pc;
}

const SurfaceMeshImportData = struct {
    vertices_position: std.ArrayList(Vec3),
    faces_nb_vertices: std.ArrayList(u32),
    faces_vertex_indices: std.ArrayList(u32),

    const init: SurfaceMeshImportData = .{
        .vertices_position = .empty,
        .faces_nb_vertices = .empty,
        .faces_vertex_indices = .empty,
    };

    pub fn deinit(self: *SurfaceMeshImportData, allocator: std.mem.Allocator) void {
        self.vertices_position.deinit(allocator);
        self.faces_nb_vertices.deinit(allocator);
        self.faces_vertex_indices.deinit(allocator);
    }

    pub fn ensureTotalCapacity(self: *SurfaceMeshImportData, allocator: std.mem.Allocator, nb_vertices: u32, nb_faces: u32) !void {
        try self.vertices_position.ensureTotalCapacity(allocator, nb_vertices);
        try self.faces_nb_vertices.ensureTotalCapacity(allocator, nb_faces);
        try self.faces_vertex_indices.ensureTotalCapacity(allocator, nb_faces * 4);
    }
};

pub fn loadSurfaceMeshFromFile(mr: *ModelsRegistry, filename: []const u8) !*SurfaceMesh {
    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buffer: [1024]u8 = undefined;
    var file_reader = file.reader(&buffer);

    const supported_filetypes = enum {
        off,
        obj,
        ply,
    };

    var ext = std.fs.path.extension(filename);
    if (ext.len == 0) {
        return error.UnsupportedFile;
    } else {
        ext = ext[1..]; // remove the starting dot
    }
    const filetype = std.meta.stringToEnum(supported_filetypes, ext) orelse {
        return error.UnsupportedFile;
    };

    var import_data: SurfaceMeshImportData = .init;
    defer import_data.deinit(mr.allocator);

    switch (filetype) {
        .off => {
            zgp_log.info("reading OFF file", .{});

            while (file_reader.interface.takeDelimiterExclusive('\n')) |line| {
                if (line.len == 0) continue; // skip empty lines
                if (std.mem.startsWith(u8, line, "OFF")) break;
            } else |err| switch (err) {
                error.EndOfStream => {
                    zgp_log.warn("reached end of file before finding the header", .{});
                    return error.InvalidFileFormat;
                },
                else => return err,
            }

            var nb_cells: [3]u32 = undefined; // [vertices, faces, edges]
            while (file_reader.interface.takeDelimiterExclusive('\n')) |line| {
                if (line.len == 0) continue; // skip empty lines
                var tokens = std.mem.tokenizeScalar(u8, line, ' ');
                var i: u32 = 0;
                while (tokens.next()) |token| : (i += 1) {
                    if (i >= nb_cells.len) return error.InvalidFileFormat;
                    const value = try std.fmt.parseInt(u32, token, 10);
                    nb_cells[i] = value;
                }
                if (i != nb_cells.len) {
                    zgp_log.warn("failed to read the number of cells", .{});
                    return error.InvalidFileFormat;
                }
                break;
            } else |err| switch (err) {
                error.EndOfStream => {
                    zgp_log.warn("reached end of file before reading the number of cells", .{});
                    return error.InvalidFileFormat;
                },
                else => return err,
            }
            zgp_log.info("nb_cells: {d} vertices / {d} faces / {d} edges", .{ nb_cells[0], nb_cells[1], nb_cells[2] });

            try import_data.ensureTotalCapacity(mr.allocator, nb_cells[0], nb_cells[1]);

            var i: u32 = 0;
            while (i < nb_cells[0]) : (i += 1) {
                while (file_reader.interface.takeDelimiterExclusive('\n')) |line| {
                    if (line.len == 0) continue; // skip empty lines
                    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
                    var position: Vec3 = undefined;
                    var j: u32 = 0;
                    while (tokens.next()) |token| : (j += 1) {
                        if (j >= 3) {
                            zgp_log.warn("vertex {d} position has more than 3 coordinates", .{i});
                            return error.InvalidFileFormat;
                        }
                        const value = try std.fmt.parseFloat(f32, token);
                        position[j] = value;
                    }
                    if (j != 3) {
                        zgp_log.warn("vertex {d} position has less than 3 coordinates", .{i});
                        return error.InvalidFileFormat;
                    }
                    try import_data.vertices_position.append(mr.allocator, position);
                    break;
                } else |err| switch (err) {
                    error.EndOfStream => {
                        zgp_log.warn("reached end of file before reading all vertices", .{});
                        return error.InvalidFileFormat;
                    },
                    else => return err,
                }
            }
            zgp_log.info("read {d} vertices", .{import_data.vertices_position.items.len});

            i = 0;
            while (i < nb_cells[1]) : (i += 1) {
                while (file_reader.interface.takeDelimiterExclusive('\n')) |line| {
                    if (line.len == 0) continue; // skip empty lines
                    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
                    var face_nb_vertices: u32 = undefined;
                    var j: u32 = 0;
                    while (tokens.next()) |token| : (j += 1) {
                        if (j == 0) {
                            face_nb_vertices = try std.fmt.parseInt(u32, token, 10);
                        } else if (j > face_nb_vertices + 1) {
                            zgp_log.warn("face {d} has more than {d} vertices", .{ i, face_nb_vertices });
                            return error.InvalidFileFormat;
                        } else {
                            const index = try std.fmt.parseInt(u32, token, 10);
                            try import_data.faces_vertex_indices.append(mr.allocator, index);
                        }
                    }
                    if (j != face_nb_vertices + 1) {
                        zgp_log.warn("face {d} has less than {d} vertices", .{ i, face_nb_vertices });
                        return error.InvalidFileFormat;
                    }
                    try import_data.faces_nb_vertices.append(mr.allocator, face_nb_vertices);
                    break;
                } else |err| switch (err) {
                    error.EndOfStream => {
                        zgp_log.warn("reached end of file before reading all faces", .{});
                        return error.InvalidFileFormat;
                    },
                    else => return err,
                }
            }
            zgp_log.info("read {d} faces", .{import_data.faces_nb_vertices.items.len});
        },
        else => return error.InvalidFileExtension,
    }

    const sm = try mr.createSurfaceMesh(std.fs.path.basename(filename));

    const vertex_position = try sm.addData(.vertex, Vec3, "position");
    const darts_of_vertex = try sm.addData(.vertex, std.ArrayList(SurfaceMesh.Dart), "darts_of_vertex");
    defer sm.removeData(.vertex, darts_of_vertex.gen());

    for (import_data.vertices_position.items) |pos| {
        const vertex_index = try sm.newDataIndex(.vertex);
        vertex_position.data.valuePtr(vertex_index).* = pos;
        darts_of_vertex.data.valuePtr(vertex_index).* = .empty;
    }

    var i: u32 = 0;
    for (import_data.faces_nb_vertices.items) |face_nb_vertices| {
        const face = try sm.addUnboundedFace(face_nb_vertices);
        var d = face.dart();
        for (import_data.faces_vertex_indices.items[i .. i + face_nb_vertices]) |index| {
            // sm.dart_vertex_index.valuePtr(d).* = index;
            sm.setDartCellIndex(d, .vertex, index);
            try darts_of_vertex.data.valuePtr(index).append(darts_of_vertex.data.arena(), d);
            d = sm.phi1(d);
        }
        i += face_nb_vertices;
    }

    var nb_boundary_edges: u32 = 0;

    var dart_it = sm.dartIterator();
    while (dart_it.next()) |d| {
        if (sm.phi2(d) == d) {
            const vertex_index = sm.dartCellIndex(d, .vertex);
            const next_vertex_index = sm.dartCellIndex(sm.phi1(d), .vertex);
            const next_vertex_darts = darts_of_vertex.data.valuePtr(next_vertex_index).*;
            const opposite_dart = for (next_vertex_darts.items) |d2| {
                if (sm.dartCellIndex(sm.phi1(d2), .vertex) == vertex_index) {
                    break d2;
                }
            } else null;
            if (opposite_dart) |d2| {
                sm.phi2Sew(d, d2);
            } else {
                nb_boundary_edges += 1;
            }
        }
    }

    if (nb_boundary_edges > 0) {
        zgp_log.info("found {d} boundary edges", .{nb_boundary_edges});
        const nb_boundary_faces = try sm.close();
        zgp_log.info("closed {d} boundary faces", .{nb_boundary_faces});
    }

    // vertices were already indexed above
    try sm.indexCells(.halfedge);
    try sm.indexCells(.corner);
    try sm.indexCells(.edge);
    try sm.indexCells(.face);

    if (builtin.mode == .Debug) {
        const ok = try sm.checkIntegrity();
        if (!ok) {
            zgp_log.err("SurfaceMesh integrity check failed after loading from file", .{});
            return error.InvalidSurfaceMesh;
        }
    }

    return sm;
}
