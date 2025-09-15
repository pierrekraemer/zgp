const ModelsRegistry = @This();

const std = @import("std");

const c = @cImport({
    @cInclude("dcimgui.h");
});
const imgui_utils = @import("../utils/imgui.zig");
const imgui_log = std.log.scoped(.imgui);

const types_utils = @import("../utils/types.zig");

const zgp = @import("../main.zig");
const zgp_log = std.log.scoped(.zgp);

pub const PointCloud = @import("point/PointCloud.zig");
pub const SurfaceMesh = @import("surface/SurfaceMesh.zig");

const Data = @import("../utils/Data.zig").Data;
const DataGen = @import("../utils/Data.zig").DataGen;

const VBO = @import("../rendering/VBO.zig");
const IBO = @import("../rendering/IBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3 = vec.Vec3;

/// Declare the standard PointCloud datas.
/// For each PointCloud, these datas can be set via the setPointCloudStdData function
/// and accessed in the PointCloudInfo.std_data field (the PointCloudInfo is available via the pointCloudInfo function)
pub const PointCloudStdData = union(enum) {
    position: ?PointCloud.CellData(Vec3),
    normal: ?PointCloud.CellData(Vec3),
    color: ?PointCloud.CellData(Vec3),
};
pub const PointCloudStdDataTag = std.meta.Tag(PointCloudStdData);
// the following function generates a struct with one field for each entry of the given union
// fun but does not allow completion in the IDE
// const PointCloudStdDatas = types_utils.StructFromUnion(PointCloudStdData);
const PointCloudStdDatas = struct {
    position: ?PointCloud.CellData(Vec3) = null,
    normal: ?PointCloud.CellData(Vec3) = null,
    color: ?PointCloud.CellData(Vec3) = null,
};
const PointCloudInfo = struct {
    std_data: PointCloudStdDatas = .{},
    points_ibo: IBO,
};

/// Declare the standard SurfaceMesh data name & types.
/// For each SurfaceMesh, these datas can be set via the setSurfaceMeshStdData function
/// and accessed in the SurfaceMeshInfo.std_data field (the SurfaceMeshInfo is available via the surfaceMeshInfo function)
pub const SurfaceMeshStdData = union(enum) {
    corner_angle: ?SurfaceMesh.CellData(.corner, f32),
    vertex_position: ?SurfaceMesh.CellData(.vertex, Vec3),
    vertex_area: ?SurfaceMesh.CellData(.vertex, f32),
    vertex_normal: ?SurfaceMesh.CellData(.vertex, Vec3),
    vertex_color: ?SurfaceMesh.CellData(.vertex, Vec3),
    edge_length: ?SurfaceMesh.CellData(.edge, f32),
    edge_dihedral_angle: ?SurfaceMesh.CellData(.edge, f32),
    face_area: ?SurfaceMesh.CellData(.face, f32),
    face_normal: ?SurfaceMesh.CellData(.face, Vec3),
};
pub const SurfaceMeshStdDataTag = std.meta.Tag(SurfaceMeshStdData);
// the following function generates a struct with one field for each entry of the given union
// fun but does not allow completion in the IDE
// const SurfaceMeshStdDatas = types_utils.StructFromUnion(SurfaceMeshStdData);
const SurfaceMeshStdDatas = struct {
    corner_angle: ?SurfaceMesh.CellData(.corner, f32) = null,
    vertex_position: ?SurfaceMesh.CellData(.vertex, Vec3) = null,
    vertex_area: ?SurfaceMesh.CellData(.vertex, f32) = null,
    vertex_normal: ?SurfaceMesh.CellData(.vertex, Vec3) = null,
    vertex_color: ?SurfaceMesh.CellData(.vertex, Vec3) = null,
    edge_length: ?SurfaceMesh.CellData(.edge, f32) = null,
    edge_dihedral_angle: ?SurfaceMesh.CellData(.edge, f32) = null,
    face_area: ?SurfaceMesh.CellData(.face, f32) = null,
    face_normal: ?SurfaceMesh.CellData(.face, Vec3) = null,
};
const SurfaceMeshInfo = struct {
    std_data: SurfaceMeshStdDatas = .{},
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
        vbo.fillFrom(T, data.data) catch {
            std.debug.print("Failed to update VBO for PointCloud data\n", .{});
            return;
        };
    }

    const now = std.time.Instant.now() catch {
        std.debug.print("Failed to get current time\n", .{});
        return;
    };
    mr.data_last_update.put(data.gen(), now) catch {
        std.debug.print("Failed to update last update time for PointCloud data\n", .{});
        return;
    };

    for (zgp.modules.items) |*module| {
        module.pointCloudDataUpdated(pc, data.gen());
    }
    zgp.requestRedraw();
}

pub fn surfaceMeshConnectivityUpdated(mr: *ModelsRegistry, sm: *SurfaceMesh) void {
    const info = mr.surface_meshes_info.getPtr(sm).?;
    info.points_ibo.fillFrom(sm, .vertex, mr.allocator) catch {
        std.debug.print("Failed to fill points IBO for SurfaceMesh\n", .{});
        return;
    };
    info.lines_ibo.fillFrom(sm, .edge, mr.allocator) catch {
        std.debug.print("Failed to fill lines IBO for SurfaceMesh\n", .{});
        return;
    };
    info.triangles_ibo.fillFrom(sm, .face, mr.allocator) catch {
        std.debug.print("Failed to fill triangles IBO for SurfaceMesh\n", .{});
        return;
    };
    info.boundaries_ibo.fillFrom(sm, .boundary, mr.allocator) catch {
        std.debug.print("Failed to fill boundaries IBO for SurfaceMesh\n", .{});
        return;
    };

    for (zgp.modules.items) |*module| {
        module.surfaceMeshConnectivityUpdated(sm);
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
        vbo.fillFrom(T, data.data) catch {
            std.debug.print("Failed to update VBO for SurfaceMesh data\n", .{});
            return;
        };
    }

    const now = std.time.Instant.now() catch {
        std.debug.print("Failed to get current time\n", .{});
        return;
    };
    mr.data_last_update.put(data.gen(), now) catch {
        std.debug.print("Failed to update last update time for SurfaceMesh data\n", .{});
        return;
    };

    for (zgp.modules.items) |*module| {
        module.surfaceMeshDataUpdated(sm, cell_type, data.gen());
    }
    zgp.requestRedraw();
}

// pub fn updateDataVBO(mr: *ModelsRegistry, comptime T: type, data: *const Data(T)) !void {
//     const vbo = try mr.data_vbo.getOrPut(&data.gen);
//     if (!vbo.found_existing) {
//         vbo.value_ptr.* = VBO.init();
//     }
//     try vbo.value_ptr.*.fillFrom(T, data);
// }

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

pub fn surfaceMeshInfo(mr: *ModelsRegistry, sm: *const SurfaceMesh) *SurfaceMeshInfo {
    return mr.surface_meshes_info.getPtr(sm).?; // should always exist
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
    const UiCB = struct {
        const SurfaceMeshSelectedContext = struct {
            models_registry: *ModelsRegistry,
        };
        fn onSurfaceMeshSelected(sm: ?*SurfaceMesh, ctx: SurfaceMeshSelectedContext) void {
            ctx.models_registry.selected_surface_mesh = sm;
        }
        fn SurfaceMeshDataSelectedContext(sdt: SurfaceMeshStdDataTag) type {
            return struct {
                const std_data_type = sdt;
                models_registry: *ModelsRegistry,
                surface_mesh: *SurfaceMesh,
            };
        }
        fn onSurfaceMeshStdDataSelected(
            comptime cell_type: SurfaceMesh.CellType,
            comptime T: type,
            data: ?SurfaceMesh.CellData(cell_type, T),
            ctx: anytype,
        ) void {
            ctx.models_registry.setSurfaceMeshStdData(
                ctx.surface_mesh,
                @unionInit(SurfaceMeshStdData, @tagName(@TypeOf(ctx).std_data_type), data),
            );
        }
        const PointCloudSelectedContext = struct {
            models_registry: *ModelsRegistry,
        };
        fn onPointCloudSelected(pc: ?*PointCloud, ctx: PointCloudSelectedContext) void {
            ctx.models_registry.selected_point_cloud = pc;
        }
        fn PointCloudDataSelectedContext(sdt: PointCloudStdDataTag) type {
            return struct {
                const std_data_type = sdt;
                models_registry: *ModelsRegistry,
                point_cloud: *PointCloud,
            };
        }
        fn onPointCloudStdDataSelected(
            comptime T: type,
            data: ?PointCloud.CellData(T),
            ctx: anytype,
        ) void {
            ctx.models_registry.setPointCloudStdData(
                ctx.point_cloud,
                @unionInit(PointCloudStdData, @tagName(@TypeOf(ctx).std_data_type), data),
            );
        }
    };

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - c.ImGui_GetStyle().*.ItemSpacing.x * 2);

    c.ImGui_PushStyleColor(c.ImGuiCol_Header, c.IM_COL32(255, 128, 0, 200));
    c.ImGui_PushStyleColor(c.ImGuiCol_HeaderActive, c.IM_COL32(255, 128, 0, 255));
    c.ImGui_PushStyleColor(c.ImGuiCol_HeaderHovered, c.IM_COL32(255, 128, 0, 128));
    if (c.ImGui_CollapsingHeader("Surface Meshes", c.ImGuiTreeNodeFlags_DefaultOpen)) {
        c.ImGui_PopStyleColorEx(3);

        imgui_utils.surfaceMeshListBox(
            mr.selected_surface_mesh,
            UiCB.SurfaceMeshSelectedContext{ .models_registry = mr },
            &UiCB.onSurfaceMeshSelected,
        );

        if (mr.selected_surface_mesh) |sm| {
            c.ImGui_SeparatorText("#Cells");
            var buf: [16]u8 = undefined; // guess 16 chars is enough for cell counts
            c.ImGui_Text("Corner");
            c.ImGui_SameLine();
            const nbcorners = std.fmt.bufPrintZ(&buf, "{d}", .{sm.nbCells(.corner)}) catch "";
            c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + @max(0.0, c.ImGui_GetContentRegionAvail().x - c.ImGui_CalcTextSize(nbcorners.ptr).x));
            c.ImGui_Text(nbcorners.ptr);
            c.ImGui_Text("Vertex");
            c.ImGui_SameLine();
            const nbvertices = std.fmt.bufPrintZ(&buf, "{d}", .{sm.nbCells(.vertex)}) catch "";
            c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + @max(0.0, c.ImGui_GetContentRegionAvail().x - c.ImGui_CalcTextSize(nbvertices.ptr).x));
            c.ImGui_Text(nbvertices.ptr);
            c.ImGui_Text("Edge");
            c.ImGui_SameLine();
            const nbedges = std.fmt.bufPrintZ(&buf, "{d}", .{sm.nbCells(.edge)}) catch "";
            c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + @max(0.0, c.ImGui_GetContentRegionAvail().x - c.ImGui_CalcTextSize(nbedges.ptr).x));
            c.ImGui_Text(nbedges.ptr);
            c.ImGui_Text("Face");
            c.ImGui_SameLine();
            const nbfaces = std.fmt.bufPrintZ(&buf, "{d}", .{sm.nbCells(.face)}) catch "";
            c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + @max(0.0, c.ImGui_GetContentRegionAvail().x - c.ImGui_CalcTextSize(nbfaces.ptr).x));
            c.ImGui_Text(nbfaces.ptr);

            c.ImGui_SeparatorText("Standard Data");
            const info = mr.surface_meshes_info.getPtr(sm).?;
            inline for (@typeInfo(SurfaceMeshStdDatas).@"struct".fields) |*field| {
                c.ImGui_Text(field.name);
                c.ImGui_PushID(field.name);
                imgui_utils.surfaceMeshCellDataComboBox(
                    sm,
                    @typeInfo(field.type).optional.child.CellType,
                    @typeInfo(field.type).optional.child.DataType,
                    @field(info.std_data, field.name),
                    UiCB.SurfaceMeshDataSelectedContext(@field(SurfaceMeshStdDataTag, field.name)){ .models_registry = mr, .surface_mesh = sm },
                    &UiCB.onSurfaceMeshStdDataSelected,
                );
                c.ImGui_PopID();
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

        imgui_utils.pointCloudListBox(
            mr.selected_point_cloud,
            UiCB.PointCloudSelectedContext{ .models_registry = mr },
            &UiCB.onPointCloudSelected,
        );

        if (mr.selected_point_cloud) |pc| {
            c.ImGui_SeparatorText("#Cells");
            var buf: [16]u8 = undefined; // guess 16 chars is enough for cell counts
            c.ImGui_Text("Point");
            c.ImGui_SameLine();
            const nbpoints = std.fmt.bufPrintZ(&buf, "{d}", .{pc.nbPoints()}) catch "";
            c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + @max(0.0, c.ImGui_GetContentRegionAvail().x - c.ImGui_CalcTextSize(nbpoints.ptr).x));
            c.ImGui_Text(nbpoints.ptr);

            c.ImGui_SeparatorText("Standard Data");
            const info = mr.point_clouds_info.getPtr(pc).?;
            inline for (@typeInfo(PointCloudStdDatas).@"struct".fields) |*field| {
                c.ImGui_Text(field.name);
                c.ImGui_PushID(field.name);
                imgui_utils.pointCloudDataComboBox(
                    pc,
                    @typeInfo(field.type).optional.child.DataType,
                    @field(info.std_data, field.name),
                    UiCB.PointCloudDataSelectedContext(@field(PointCloudStdDataTag, field.name)){ .models_registry = mr, .point_cloud = pc },
                    &UiCB.onPointCloudStdDataSelected,
                );
                c.ImGui_PopID();
            }
        } else {
            c.ImGui_Text("No Point Cloud selected");
        }
    } else {
        c.ImGui_PopStyleColorEx(3);
    }

    c.ImGui_PopItemWidth();
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
    const sm = try mr.allocator.create(SurfaceMesh);
    errdefer mr.allocator.destroy(sm);
    sm.* = try SurfaceMesh.init(mr.allocator);
    errdefer sm.deinit();
    try mr.surface_meshes.put(name, sm);
    errdefer _ = mr.surface_meshes.remove(name);
    try mr.surface_meshes_info.put(sm, .{
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
    try sm.indexCells(.corner);
    try sm.indexCells(.edge);
    try sm.indexCells(.face);

    // TODO: only check in debug builds
    try sm.checkIntegrity();

    return sm;
}
