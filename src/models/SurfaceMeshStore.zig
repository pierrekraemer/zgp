const SurfaceMeshStore = @This();

const std = @import("std");
const builtin = @import("builtin");

const zgp = @import("../main.zig");
const c = zgp.c;

const imgui_utils = @import("../utils/imgui.zig");
const imgui_log = std.log.scoped(.imgui);
const zgp_log = std.log.scoped(.zgp);

const types_utils = @import("../utils/types.zig");

pub const SurfaceMesh = @import("surface/SurfaceMesh.zig");

const Data = @import("../utils/Data.zig").Data;
const DataGen = @import("../utils/Data.zig").DataGen;

const VBO = @import("../rendering/VBO.zig");
const IBO = @import("../rendering/IBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

/// Standard SurfaceMesh data name & types.
pub const SurfaceMeshStdDatas = struct {
    corner_angle: ?SurfaceMesh.CellData(.corner, f32) = null,
    halfedge_cotan_weight: ?SurfaceMesh.CellData(.halfedge, f32) = null,
    vertex_position: ?SurfaceMesh.CellData(.vertex, Vec3f) = null,
    vertex_area: ?SurfaceMesh.CellData(.vertex, f32) = null,
    vertex_normal: ?SurfaceMesh.CellData(.vertex, Vec3f) = null,
    vertex_gaussian_curvature: ?SurfaceMesh.CellData(.vertex, f32) = null,
    vertex_mean_curvature: ?SurfaceMesh.CellData(.vertex, f32) = null,
    edge_length: ?SurfaceMesh.CellData(.edge, f32) = null,
    edge_dihedral_angle: ?SurfaceMesh.CellData(.edge, f32) = null,
    face_area: ?SurfaceMesh.CellData(.face, f32) = null,
    face_normal: ?SurfaceMesh.CellData(.face, Vec3f) = null,
};
/// This union is generated from the SurfaceMeshStdDatas struct and allows to easily provide a single
/// data entry to the setSurfaceMeshStdData function.
pub const SurfaceMeshStdData = types_utils.UnionFromStruct(SurfaceMeshStdDatas);
pub const SurfaceMeshStdDataTag = std.meta.Tag(SurfaceMeshStdData);

/// This struct holds information related to a SurfaceMesh, including its standard datas, cells sets and the IBOs for rendering.
/// The SurfaceMeshInfo associated with a SurfaceMesh is accessible via the surfaceMeshInfo function.
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

surface_meshes: std.StringHashMap(*SurfaceMesh),
surface_meshes_info: std.AutoHashMap(*const SurfaceMesh, SurfaceMeshInfo),
selected_surface_mesh: ?*SurfaceMesh = null,

data_vbo: std.AutoHashMap(*const DataGen, VBO),
data_last_update: std.AutoHashMap(*const DataGen, std.time.Instant),

pub fn init(allocator: std.mem.Allocator) SurfaceMeshStore {
    return .{
        .allocator = allocator,
        .surface_meshes = std.StringHashMap(*SurfaceMesh).init(allocator),
        .surface_meshes_info = std.AutoHashMap(*const SurfaceMesh, SurfaceMeshInfo).init(allocator),
        .data_vbo = std.AutoHashMap(*const DataGen, VBO).init(allocator),
        .data_last_update = std.AutoHashMap(*const DataGen, std.time.Instant).init(allocator),
    };
}

pub fn deinit(sms: *SurfaceMeshStore) void {
    var sm_info_it = sms.surface_meshes_info.iterator();
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
    sms.surface_meshes_info.deinit();
    var sm_it = sms.surface_meshes.iterator();
    while (sm_it.next()) |entry| {
        var sm = entry.value_ptr.*;
        sm.deinit();
        sms.allocator.destroy(sm);
    }
    sms.surface_meshes.deinit();

    var vbo_it = sms.data_vbo.iterator();
    while (vbo_it.next()) |entry| {
        var vbo = entry.value_ptr.*;
        vbo.deinit();
    }
    sms.data_vbo.deinit();
    sms.data_last_update.deinit();
}

pub fn surfaceMeshDataUpdated(
    sms: *SurfaceMeshStore,
    sm: *SurfaceMesh,
    comptime cell_type: SurfaceMesh.CellType,
    comptime T: type,
    data: SurfaceMesh.CellData(cell_type, T),
) void {
    // if it exists, update the VBO with the data
    const maybe_vbo = sms.data_vbo.getPtr(data.gen());
    if (maybe_vbo) |vbo| {
        vbo.fillFrom(T, data.data);
    }

    const now = std.time.Instant.now() catch |err| {
        zgp_log.err("Failed to get current time: {}", .{err});
        return;
    };
    sms.data_last_update.put(data.gen(), now) catch |err| {
        zgp_log.err("Failed to update last update time for SurfaceMesh data: {}", .{err});
        return;
    };

    // TODO: find a way to only notify modules that have registered interest in SurfaceMesh
    for (zgp.modules.items) |*module| {
        module.surfaceMeshDataUpdated(sm, cell_type, data.gen());
    }
    zgp.requestRedraw();
}

pub fn surfaceMeshConnectivityUpdated(sms: *SurfaceMeshStore, sm: *SurfaceMesh) void {
    if (builtin.mode == .Debug) {
        const ok = sm.checkIntegrity() catch |err| {
            zgp_log.err("Failed to check integrity after connectivity update: {}", .{err});
            return;
        };
        if (!ok) {
            zgp_log.err("SurfaceMesh integrity check failed after connectivity update", .{});
            return;
        }
    }

    const info = sms.surface_meshes_info.getPtr(sm).?;

    info.vertex_set.update() catch |err| {
        zgp_log.err("Failed to update vertex set for SurfaceMesh: {}", .{err});
        return;
    };
    info.edge_set.update() catch |err| {
        zgp_log.err("Failed to update edge set for SurfaceMesh: {}", .{err});
        return;
    };
    info.face_set.update() catch |err| {
        zgp_log.err("Failed to update face set for SurfaceMesh: {}", .{err});
        return;
    };

    info.points_ibo.fillFrom(sm, .vertex, sms.allocator) catch |err| {
        zgp_log.err("Failed to fill points IBO for SurfaceMesh: {}", .{err});
        return;
    };
    info.lines_ibo.fillFrom(sm, .edge, sms.allocator) catch |err| {
        zgp_log.err("Failed to fill lines IBO for SurfaceMesh: {}", .{err});
        return;
    };
    info.triangles_ibo.fillFrom(sm, .face, sms.allocator) catch |err| {
        zgp_log.err("Failed to fill triangles IBO for SurfaceMesh: {}", .{err});
        return;
    };
    info.boundaries_ibo.fillFrom(sm, .boundary, sms.allocator) catch |err| {
        zgp_log.err("Failed to fill boundaries IBO for SurfaceMesh: {}", .{err});
        return;
    };

    // TODO: find a way to only notify modules that have registered interest in SurfaceMesh
    for (zgp.modules.items) |*module| {
        module.surfaceMeshConnectivityUpdated(sm);
    }
    zgp.requestRedraw();
}

pub fn dataVBO(sms: *SurfaceMeshStore, comptime T: type, data: *const Data(T)) VBO {
    const vbo = sms.data_vbo.getOrPut(&data.gen) catch |err| {
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

pub fn dataLastUpdate(sms: *SurfaceMeshStore, data_gen: *const DataGen) ?std.time.Instant {
    return sms.data_last_update.get(data_gen);
}

pub fn surfaceMeshInfo(sms: *SurfaceMeshStore, sm: *const SurfaceMesh) *SurfaceMeshInfo {
    return sms.surface_meshes_info.getPtr(sm).?; // should always exist
}

pub fn surfaceMeshName(sms: *SurfaceMeshStore, sm: *const SurfaceMesh) ?[]const u8 {
    const it = sms.surface_meshes.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* == sm) {
            return entry.key_ptr.*;
        }
    }
    return null;
}

pub fn setSurfaceMeshStdData(
    sms: *SurfaceMeshStore,
    sm: *SurfaceMesh,
    data: SurfaceMeshStdData,
) void {
    const info = sms.surface_meshes_info.getPtr(sm).?;
    switch (data) {
        inline else => |val, tag| {
            @field(info.std_data, @tagName(tag)) = val;
        },
    }

    // TODO: find a way to only notify modules that have registered interest in SurfaceMesh
    for (zgp.modules.items) |*module| {
        module.surfaceMeshStdDataChanged(sm, data);
    }
    zgp.requestRedraw();
}

pub fn menuBar(_: *SurfaceMeshStore) void {}

pub fn uiPanel(sms: *SurfaceMeshStore) void {
    const CreateDataTypes = union(enum) { f32: f32, Vec3f: Vec3f };
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

        const nb_surface_meshes_f = @as(f32, @floatFromInt(sms.surface_meshes.count() + 1));
        if (imgui_utils.surfaceMeshListBox(
            sms.selected_surface_mesh,
            style.*.FontSizeBase * nb_surface_meshes_f + style.*.ItemSpacing.y * nb_surface_meshes_f,
        )) |sm| {
            sms.selected_surface_mesh = sm;
        }

        if (sms.selected_surface_mesh) |sm| {
            var buf: [64]u8 = undefined; // guess 64 chars is enough for cell name + cell count
            const info = sms.surface_meshes_info.getPtr(sm).?;
            inline for (.{ .halfedge, .corner, .vertex, .edge, .face }) |cell_type| {
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
                        sms.setSurfaceMeshStdData(sm, @unionInit(SurfaceMeshStdData, field.name, data));
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
                            sms.setSurfaceMeshStdData(sm, @unionInit(SurfaceMeshStdData, field.name, data));
                        } else |err| {
                            zgp_log.err("Error adding {s} ({s}: {s}) data: {}", .{ field.name, @tagName(@typeInfo(field.type).optional.child.CellType), @typeName(@typeInfo(field.type).optional.child.DataType), err });
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
                                        zgp_log.err("Error adding {s} ({s}: {s}) data: {}", .{ &UiData.data_name_buf, @tagName(cell_type), @tagName(data_type), err });
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
}

pub fn createSurfaceMesh(sms: *SurfaceMeshStore, name: []const u8) !*SurfaceMesh {
    const maybe_surface_mesh = sms.surface_meshes.get(name);
    if (maybe_surface_mesh) |_| {
        return error.ModelNameAlreadyExists;
    }
    var sm = try sms.allocator.create(SurfaceMesh);
    errdefer sms.allocator.destroy(sm);
    sm.* = try SurfaceMesh.init(sms.allocator);
    errdefer sm.deinit();
    try sms.surface_meshes.put(name, sm);
    errdefer _ = sms.surface_meshes.remove(name);
    try sms.surface_meshes_info.put(sm, .{
        .vertex_set = try SurfaceMesh.CellSet(.vertex).init(sm),
        .edge_set = try SurfaceMesh.CellSet(.edge).init(sm),
        .face_set = try SurfaceMesh.CellSet(.face).init(sm),
        .points_ibo = IBO.init(),
        .lines_ibo = IBO.init(),
        .triangles_ibo = IBO.init(),
        .boundaries_ibo = IBO.init(),
    });
    errdefer _ = sms.surface_meshes_info.remove(sm);

    // TODO: find a way to only notify modules that have registered interest in SurfaceMesh
    for (zgp.modules.items) |*module| {
        module.surfaceMeshAdded(sm);
    }

    return sm;
}

// TODO: put the IO code in a separate place

const SurfaceMeshImportData = struct {
    vertices_position: std.ArrayList(Vec3f),
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

pub fn loadSurfaceMeshFromFile(sms: *SurfaceMeshStore, filename: []const u8) !*SurfaceMesh {
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
    defer import_data.deinit(sms.allocator);

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

            try import_data.ensureTotalCapacity(sms.allocator, nb_cells[0], nb_cells[1]);

            var i: u32 = 0;
            while (i < nb_cells[0]) : (i += 1) {
                while (file_reader.interface.takeDelimiterExclusive('\n')) |line| {
                    if (line.len == 0) continue; // skip empty lines
                    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
                    var position: Vec3f = undefined;
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
                    try import_data.vertices_position.append(sms.allocator, position);
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
                            try import_data.faces_vertex_indices.append(sms.allocator, index);
                        }
                    }
                    if (j != face_nb_vertices + 1) {
                        zgp_log.warn("face {d} has less than {d} vertices", .{ i, face_nb_vertices });
                        return error.InvalidFileFormat;
                    }
                    try import_data.faces_nb_vertices.append(sms.allocator, face_nb_vertices);
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

    const sm = try sms.createSurfaceMesh(std.fs.path.basename(filename));

    const vertex_position = try sm.addData(.vertex, Vec3f, "position");
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
