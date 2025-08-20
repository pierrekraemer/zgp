const std = @import("std");

const c = @cImport({
    @cInclude("dcimgui.h");
});
const imgui_utils = @import("../utils/imgui.zig");

const Self = @This();
const zgp = @import("../main.zig");

pub const PointCloud = @import("point/PointCloud.zig");
const PointCloudData = PointCloud.PointCloudData;
pub const SurfaceMesh = @import("surface/SurfaceMesh.zig");
const SurfaceMeshData = SurfaceMesh.SurfaceMeshData;

const Data = @import("../utils/Data.zig").Data;
const DataGen = @import("../utils/Data.zig").DataGen;

const VBO = @import("../rendering/VBO.zig");
const IBO = @import("../rendering/IBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3 = vec.Vec3;

pub const PointCloudStandardData = enum {
    position,
    normal,
    color,
};

const PointCloudInfo = struct {
    position: ?PointCloudData(Vec3) = null,
    normal: ?PointCloudData(Vec3) = null,
    color: ?PointCloudData(Vec3) = null,

    points_ibo: IBO,
};

pub const SurfaceMeshStandardData = enum {
    vertex_position,
    vertex_normal,
    vertex_color,
};

const SurfaceMeshInfo = struct {
    vertex_position: ?SurfaceMeshData(.vertex, Vec3) = null,
    vertex_normal: ?SurfaceMeshData(.vertex, Vec3) = null,
    vertex_color: ?SurfaceMeshData(.vertex, Vec3) = null,

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

vbo_registry: std.AutoHashMap(*const DataGen, VBO),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
        .point_clouds = std.StringHashMap(*PointCloud).init(allocator),
        .surface_meshes = std.StringHashMap(*SurfaceMesh).init(allocator),
        .point_clouds_info = std.AutoHashMap(*const PointCloud, PointCloudInfo).init(allocator),
        .surface_meshes_info = std.AutoHashMap(*const SurfaceMesh, SurfaceMeshInfo).init(allocator),
        .vbo_registry = std.AutoHashMap(*const DataGen, VBO).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var pc_info_it = self.point_clouds_info.iterator();
    while (pc_info_it.next()) |entry| {
        var info = entry.value_ptr.*;
        info.points_ibo.deinit();
    }
    self.point_clouds_info.deinit();
    var pc_it = self.point_clouds.iterator();
    while (pc_it.next()) |entry| {
        var pc = entry.value_ptr.*;
        pc.deinit();
        self.allocator.destroy(pc);
    }
    self.point_clouds.deinit();

    var sm_info_it = self.surface_meshes_info.iterator();
    while (sm_info_it.next()) |entry| {
        var info = entry.value_ptr.*;
        info.points_ibo.deinit();
        info.lines_ibo.deinit();
        info.triangles_ibo.deinit();
        info.boundaries_ibo.deinit();
    }
    self.surface_meshes_info.deinit();
    var sm_it = self.surface_meshes.iterator();
    while (sm_it.next()) |entry| {
        var sm = entry.value_ptr.*;
        sm.deinit();
        self.allocator.destroy(sm);
    }
    self.surface_meshes.deinit();

    var vbo_it = self.vbo_registry.iterator();
    while (vbo_it.next()) |entry| {
        var vbo = entry.value_ptr.*;
        vbo.deinit();
    }
    self.vbo_registry.deinit();
}

pub fn surfaceMeshConnectivityUpdated(self: *Self, surface_mesh: *SurfaceMesh) !void {
    const info = self.surface_meshes_info.getPtr(surface_mesh).?;
    try info.points_ibo.fillFrom(surface_mesh, .vertex, self.allocator);
    try info.lines_ibo.fillFrom(surface_mesh, .edge, self.allocator);
    try info.triangles_ibo.fillFrom(surface_mesh, .face, self.allocator);
    try info.boundaries_ibo.fillFrom(surface_mesh, .boundary, self.allocator);

    for (zgp.modules.items) |*module| {
        try module.surfaceMeshConnectivityUpdated(surface_mesh);
    }
}

pub fn surfaceMeshDataUpdated(self: *Self, surface_mesh: *SurfaceMesh, comptime cell_type: SurfaceMesh.CellType, comptime T: type, data: SurfaceMeshData(cell_type, T)) !void {
    // If it exists, update the VBO with the data
    const maybe_vbo = self.vbo_registry.getPtr(data.gen());
    if (maybe_vbo) |vbo| {
        try vbo.fillFrom(T, data.data);
    }

    for (zgp.modules.items) |*module| {
        try module.surfaceMeshDataUpdated(surface_mesh, cell_type, data.gen());
    }
}

pub fn updateDataVBO(self: *Self, comptime T: type, data: *const Data(T)) !void {
    const vbo = try self.vbo_registry.getOrPut(&data.gen);
    if (!vbo.found_existing) {
        vbo.value_ptr.* = VBO.init();
    }
    try vbo.value_ptr.*.fillFrom(T, data);
}

pub fn getDataVBO(self: *Self, comptime T: type, data: *const Data(T)) !VBO {
    const vbo = try self.vbo_registry.getOrPut(&data.gen);
    if (!vbo.found_existing) {
        vbo.value_ptr.* = VBO.init();
        // if the VBO was just created, fill it with the data
        try vbo.value_ptr.*.fillFrom(T, data);
    }
    return vbo.value_ptr.*;
}

pub fn getPointCloudInfo(self: *Self, point_cloud: *const PointCloud) ?*PointCloudInfo {
    return self.point_clouds_info.getPtr(point_cloud);
}

pub fn getSurfaceMeshInfo(self: *Self, surface_mesh: *const SurfaceMesh) ?*SurfaceMeshInfo {
    return self.surface_meshes_info.getPtr(surface_mesh);
}

pub fn setPointCloudStandardData(
    self: *Self,
    point_cloud: *PointCloud,
    std_data: PointCloudStandardData,
    comptime T: type,
    data: ?PointCloudData(T),
) !void {
    const info = self.point_clouds_info.getPtr(point_cloud).?;
    switch (std_data) {
        .position => info.position = data,
        .normal => info.normal = data,
        .color => info.color = data,
    }

    for (zgp.modules.items) |*module| {
        try module.pointCloudStandardDataChanged(point_cloud, std_data);
    }
}

pub fn setSurfaceMeshStandardData(
    self: *Self,
    surface_mesh: *SurfaceMesh,
    std_data: SurfaceMeshStandardData,
    comptime cell_type: SurfaceMesh.CellType,
    comptime T: type,
    data: ?SurfaceMeshData(cell_type, T),
) !void {
    const info = self.surface_meshes_info.getPtr(surface_mesh).?;
    switch (std_data) {
        .vertex_position => info.vertex_position = data,
        .vertex_normal => info.vertex_normal = data,
        .vertex_color => info.vertex_color = data,
    }

    for (zgp.modules.items) |*module| {
        try module.surfaceMeshStandardDataChanged(surface_mesh, std_data);
    }
}

pub fn menuBar(self: *Self) void {
    _ = self;
}

pub fn uiPanel(self: *Self) void {
    const UiData = struct {
        var selected_point_cloud: ?*PointCloud = null;
        var selected_surface_mesh: ?*SurfaceMesh = null;
    };

    const UiCB = struct {
        fn onSurfaceMeshSelected(sm: ?*SurfaceMesh) void {
            UiData.selected_surface_mesh = sm;
        }
        fn onPointCloudSelected(pc: ?*PointCloud) void {
            UiData.selected_point_cloud = pc;
        }
        const SurfaceMeshDataSelectedContext = struct {
            models_registry: *Self,
            surface_mesh: *SurfaceMesh,
            std_data: SurfaceMeshStandardData,
        };
        fn onSurfaceMeshStandardDataSelected(comptime cell_type: SurfaceMesh.CellType, comptime T: type, data: ?SurfaceMeshData(cell_type, T), ctx: SurfaceMeshDataSelectedContext) void {
            ctx.models_registry.setSurfaceMeshStandardData(ctx.surface_mesh, ctx.std_data, cell_type, T, data) catch |err| {
                zgp.imgui_log.err("Error setting surface mesh standard data: {}\n", .{err});
            };
        }
        const PointCloudDataSelectedContext = struct {
            models_registry: *Self,
            point_cloud: *PointCloud,
            std_data: PointCloudStandardData,
        };
        fn onPointCloudStandardDataSelected(comptime T: type, data: ?PointCloudData(T), ctx: PointCloudDataSelectedContext) void {
            ctx.models_registry.setPointCloudStandardData(ctx.point_cloud, ctx.std_data, T, data) catch |err| {
                zgp.imgui_log.err("Error setting point cloud standard data: {}\n", .{err});
            };
        }
    };

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - c.ImGui_GetStyle().*.ItemSpacing.x * 2);

    c.ImGui_PushStyleColor(c.ImGuiCol_Header, c.IM_COL32(255, 128, 0, 200));
    c.ImGui_PushStyleColor(c.ImGuiCol_HeaderActive, c.IM_COL32(255, 128, 0, 255));
    c.ImGui_PushStyleColor(c.ImGuiCol_HeaderHovered, c.IM_COL32(255, 128, 0, 128));
    if (c.ImGui_CollapsingHeader("Surface Meshes", c.ImGuiTreeNodeFlags_DefaultOpen)) {
        c.ImGui_PopStyleColorEx(3);

        imgui_utils.surfaceMeshListBox(UiData.selected_surface_mesh, &UiCB.onSurfaceMeshSelected);

        if (UiData.selected_surface_mesh) |sm| {
            c.ImGui_SeparatorText("#Cells");

            var buf: [16]u8 = undefined; // guess 16 chars is enough for cell counts

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

            const maybe_info = self.surface_meshes_info.getPtr(sm);
            if (maybe_info) |info| {
                c.ImGui_Text("Vertex Position");
                c.ImGui_PushID("Vertex Position");
                imgui_utils.surfaceMeshCellDataComboBox(
                    sm,
                    .vertex,
                    Vec3,
                    info.vertex_position,
                    UiCB.SurfaceMeshDataSelectedContext{ .models_registry = self, .surface_mesh = sm, .std_data = .vertex_position },
                    &UiCB.onSurfaceMeshStandardDataSelected,
                );
                c.ImGui_PopID();
                c.ImGui_Text("Vertex Color");
                c.ImGui_PushID("Vertex Color");
                imgui_utils.surfaceMeshCellDataComboBox(
                    sm,
                    .vertex,
                    Vec3,
                    info.vertex_color,
                    UiCB.SurfaceMeshDataSelectedContext{ .models_registry = self, .surface_mesh = sm, .std_data = .vertex_color },
                    &UiCB.onSurfaceMeshStandardDataSelected,
                );
                c.ImGui_PopID();
                c.ImGui_Text("Vertex Normal");
                c.ImGui_PushID("Vertex Normal");
                imgui_utils.surfaceMeshCellDataComboBox(
                    sm,
                    .vertex,
                    Vec3,
                    info.vertex_normal,
                    UiCB.SurfaceMeshDataSelectedContext{ .models_registry = self, .surface_mesh = sm, .std_data = .vertex_normal },
                    &UiCB.onSurfaceMeshStandardDataSelected,
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
        imgui_utils.pointCloudListBox(UiData.selected_point_cloud, &UiCB.onPointCloudSelected);

        if (UiData.selected_point_cloud) |pc| {
            const maybe_info = self.point_clouds_info.getPtr(pc);
            if (maybe_info) |info| {
                c.ImGui_Text("Vertex Position");
                c.ImGui_PushID("Vertex Position");
                imgui_utils.pointCloudDataComboBox(
                    pc,
                    Vec3,
                    info.position,
                    UiCB.PointCloudDataSelectedContext{ .models_registry = self, .point_cloud = pc, .std_data = .position },
                    &UiCB.onPointCloudStandardDataSelected,
                );
                c.ImGui_PopID();
                c.ImGui_Text("Vertex Color");
                c.ImGui_PushID("Vertex Color");
                imgui_utils.pointCloudDataComboBox(
                    pc,
                    Vec3,
                    info.color,
                    UiCB.PointCloudDataSelectedContext{ .models_registry = self, .point_cloud = pc, .std_data = .color },
                    &UiCB.onPointCloudStandardDataSelected,
                );
                c.ImGui_PopID();
                c.ImGui_Text("Vertex Normal");
                c.ImGui_PushID("Vertex Normal");
                imgui_utils.pointCloudDataComboBox(
                    pc,
                    Vec3,
                    info.normal,
                    UiCB.PointCloudDataSelectedContext{ .models_registry = self, .point_cloud = pc, .std_data = .normal },
                    &UiCB.onPointCloudStandardDataSelected,
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

pub fn createPointCloud(self: *Self, name: []const u8) !*PointCloud {
    const maybe_point_cloud = self.point_clouds.get(name);
    if (maybe_point_cloud) |_| {
        return error.ModelNameAlreadyExists;
    }
    const pc = try self.allocator.create(PointCloud);
    errdefer self.allocator.destroy(pc);
    pc.* = try PointCloud.init(self.allocator);
    errdefer pc.deinit();
    try self.point_clouds.put(name, pc);
    errdefer _ = self.point_clouds.remove(name);
    try self.point_clouds_info.put(pc, .{
        .points_ibo = IBO.init(),
    });
    errdefer _ = self.point_clouds_info.remove(pc);

    for (zgp.modules.items) |*module| {
        try module.pointCloudAdded(pc);
    }

    return pc;
}

pub fn createSurfaceMesh(self: *Self, name: []const u8) !*SurfaceMesh {
    const maybe_surface_mesh = self.surface_meshes.get(name);
    if (maybe_surface_mesh) |_| {
        return error.ModelNameAlreadyExists;
    }
    const sm = try self.allocator.create(SurfaceMesh);
    errdefer self.allocator.destroy(sm);
    sm.* = try SurfaceMesh.init(self.allocator);
    errdefer sm.deinit();
    try self.surface_meshes.put(name, sm);
    errdefer _ = self.surface_meshes.remove(name);
    try self.surface_meshes_info.put(sm, .{
        .points_ibo = IBO.init(),
        .lines_ibo = IBO.init(),
        .triangles_ibo = IBO.init(),
        .boundaries_ibo = IBO.init(),
    });
    errdefer _ = self.surface_meshes_info.remove(sm);

    for (zgp.modules.items) |*module| {
        try module.surfaceMeshAdded(sm);
    }

    return sm;
}

pub fn loadPointCloudFromFile(self: *Self, filename: []const u8) !*PointCloud {
    const pc = try self.createPointCloud(filename);
    // read the file and fill the point cloud
    return pc;
}

const SurfaceMeshImportData = struct {
    vertices_position: std.ArrayList(Vec3),
    faces_nb_vertices: std.ArrayList(u32),
    faces_vertex_indices: std.ArrayList(u32),

    pub fn init(allocator: std.mem.Allocator) SurfaceMeshImportData {
        return .{
            .vertices_position = std.ArrayList(Vec3).init(allocator),
            .faces_nb_vertices = std.ArrayList(u32).init(allocator),
            .faces_vertex_indices = std.ArrayList(u32).init(allocator),
        };
    }
    pub fn deinit(self: *SurfaceMeshImportData) void {
        self.vertices_position.deinit();
        self.faces_nb_vertices.deinit();
        self.faces_vertex_indices.deinit();
    }
    pub fn ensureTotalCapacity(self: *SurfaceMeshImportData, nb_vertices: u32, nb_faces: u32) !void {
        try self.vertices_position.ensureTotalCapacity(nb_vertices);
        try self.faces_nb_vertices.ensureTotalCapacity(nb_faces);
        try self.faces_vertex_indices.ensureTotalCapacity(nb_faces * 4);
    }
};

pub fn loadSurfaceMeshFromFile(self: *Self, filename: []const u8) !*SurfaceMesh {
    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    var line = std.ArrayList(u8).init(self.allocator);
    defer line.deinit();
    const line_writer = line.writer();

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

    var import_data = SurfaceMeshImportData.init(self.allocator);
    defer import_data.deinit();

    switch (filetype) {
        .off => {
            zgp.zgp_log.info("reading OFF file", .{});

            while (reader.streamUntilDelimiter(line_writer, '\n', null)) {
                if (line.items.len == 0) continue; // skip empty lines
                defer line.clearRetainingCapacity();
                if (std.mem.startsWith(u8, line.items, "OFF")) break;
            } else |err| switch (err) {
                error.EndOfStream => {
                    zgp.zgp_log.warn("reached end of file before finding the header", .{});
                    return error.InvalidFileFormat;
                },
                else => return err,
            }

            var nb_cells: [3]u32 = undefined; // [vertices, faces, edges]
            while (reader.streamUntilDelimiter(line_writer, '\n', null)) {
                if (line.items.len == 0) continue; // skip empty lines
                defer line.clearRetainingCapacity();
                var tokens = std.mem.tokenizeScalar(u8, line.items, ' ');
                var i: u32 = 0;
                while (tokens.next()) |token| : (i += 1) {
                    if (i >= nb_cells.len) return error.InvalidFileFormat;
                    const value = try std.fmt.parseInt(u32, token, 10);
                    nb_cells[i] = value;
                }
                if (i != nb_cells.len) {
                    zgp.zgp_log.warn("failed to read the number of cells", .{});
                    return error.InvalidFileFormat;
                }
                break;
            } else |err| switch (err) {
                error.EndOfStream => {
                    zgp.zgp_log.warn("reached end of file before reading the number of cells", .{});
                    return error.InvalidFileFormat;
                },
                else => return err,
            }
            zgp.zgp_log.info("nb_cells: {d} vertices / {d} faces / {d} edges", .{ nb_cells[0], nb_cells[1], nb_cells[2] });

            try import_data.ensureTotalCapacity(nb_cells[0], nb_cells[1]);

            var i: u32 = 0;
            while (i < nb_cells[0]) : (i += 1) {
                while (reader.streamUntilDelimiter(line_writer, '\n', null)) {
                    if (line.items.len == 0) continue; // skip empty lines
                    defer line.clearRetainingCapacity();
                    var tokens = std.mem.tokenizeScalar(u8, line.items, ' ');
                    var position: Vec3 = undefined;
                    var j: u32 = 0;
                    while (tokens.next()) |token| : (j += 1) {
                        if (j >= 3) {
                            zgp.zgp_log.warn("vertex {d} position has more than 3 coordinates", .{i});
                            return error.InvalidFileFormat;
                        }
                        const value = try std.fmt.parseFloat(f32, token);
                        position[j] = value;
                    }
                    if (j != 3) {
                        zgp.zgp_log.warn("vertex {d} position has less than 3 coordinates", .{i});
                        return error.InvalidFileFormat;
                    }
                    try import_data.vertices_position.append(position);
                    break;
                } else |err| switch (err) {
                    error.EndOfStream => {
                        zgp.zgp_log.warn("reached end of file before reading all vertices", .{});
                        return error.InvalidFileFormat;
                    },
                    else => return err,
                }
            }
            zgp.zgp_log.info("read {d} vertices", .{import_data.vertices_position.items.len});

            i = 0;
            while (i < nb_cells[1]) : (i += 1) {
                while (reader.streamUntilDelimiter(line_writer, '\n', null)) {
                    if (line.items.len == 0) continue; // skip empty lines
                    defer line.clearRetainingCapacity();
                    var tokens = std.mem.tokenizeScalar(u8, line.items, ' ');
                    var face_nb_vertices: u32 = undefined;
                    var j: u32 = 0;
                    while (tokens.next()) |token| : (j += 1) {
                        if (j == 0) {
                            face_nb_vertices = try std.fmt.parseInt(u32, token, 10);
                        } else if (j > face_nb_vertices + 1) {
                            zgp.zgp_log.warn("face {d} has more than {d} vertices", .{ i, face_nb_vertices });
                            return error.InvalidFileFormat;
                        } else {
                            const index = try std.fmt.parseInt(u32, token, 10);
                            try import_data.faces_vertex_indices.append(index);
                        }
                    }
                    if (j != face_nb_vertices + 1) {
                        zgp.zgp_log.warn("face {d} has less than {d} vertices", .{ i, face_nb_vertices });
                        return error.InvalidFileFormat;
                    }
                    try import_data.faces_nb_vertices.append(face_nb_vertices);
                    break;
                } else |err| switch (err) {
                    error.EndOfStream => {
                        zgp.zgp_log.warn("reached end of file before reading all faces", .{});
                        return error.InvalidFileFormat;
                    },
                    else => return err,
                }
            }
            zgp.zgp_log.info("read {d} faces", .{import_data.faces_nb_vertices.items.len});
        },
        else => return error.InvalidFileExtension,
    }

    const sm = try self.createSurfaceMesh(std.fs.path.basename(filename));

    const vertex_position = try sm.addData(.vertex, Vec3, "position");
    const darts_of_vertex = try sm.addData(.vertex, std.ArrayList(SurfaceMesh.Dart), "darts_of_vertex");
    defer sm.removeData(.vertex, darts_of_vertex.gen());

    for (import_data.vertices_position.items) |pos| {
        const vertex_index = try sm.newDataIndex(.vertex);
        vertex_position.data.valuePtr(vertex_index).* = pos;
        darts_of_vertex.data.valuePtr(vertex_index).* = std.ArrayList(SurfaceMesh.Dart).init(darts_of_vertex.data.arena());
    }

    var i: u32 = 0;
    for (import_data.faces_nb_vertices.items) |face_nb_vertices| {
        const face = try sm.addUnboundedFace(face_nb_vertices);
        var d = face.dart();
        for (import_data.faces_vertex_indices.items[i .. i + face_nb_vertices]) |index| {
            sm.dart_vertex_index.valuePtr(d).* = index;
            try darts_of_vertex.data.valuePtr(index).append(d);
            d = sm.phi1(d);
        }
        i += face_nb_vertices;
    }

    var nb_boundary_edges: u32 = 0;

    var dart_it = sm.dartIterator();
    while (dart_it.next()) |d| {
        if (sm.phi2(d) == d) {
            const vertex_index = sm.dartIndex(d, .vertex);
            const next_vertex_index = sm.dartIndex(sm.phi1(d), .vertex);
            const next_vertex_darts = darts_of_vertex.data.valuePtr(next_vertex_index).*;
            const opposite_dart = for (next_vertex_darts.items) |d2| {
                if (sm.dartIndex(sm.phi1(d2), .vertex) == vertex_index) {
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
        zgp.zgp_log.info("found {d} boundary edges", .{nb_boundary_edges});
        const nb_boundary_faces = try sm.close();
        zgp.zgp_log.info("closed {d} boundary faces", .{nb_boundary_faces});
    }

    // vertices were already indexed above
    try sm.indexCells(.corner);
    try sm.indexCells(.edge);
    try sm.indexCells(.face);

    return sm;
}
