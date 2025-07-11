const std = @import("std");

const c = @cImport({
    @cInclude("dcimgui.h");
    @cInclude("backends/dcimgui_impl_sdl3.h");
    @cInclude("backends/dcimgui_impl_opengl3.h");
});

const Self = @This();
const zgp = @import("../main.zig");

pub const PointCloud = @import("point/PointCloud.zig");
pub const SurfaceMesh = @import("surface/SurfaceMesh.zig");

const Data = @import("../utils/Data.zig").Data;
const DataGen = @import("../utils/Data.zig").DataGen;
const VBO = @import("../rendering/VBO.zig");
const IBO = @import("../rendering/IBO.zig");

const Vec3 = @import("../numerical/types.zig").Vec3;

pub const PointCloudStandardData = enum {
    vertex_position,
    vertex_normal,
    vertex_color,
};

const PointCloudInfo = struct {
    vertex_position: ?*Data(Vec3) = null,
    vertex_normal: ?*Data(Vec3) = null,
    vertex_color: ?*Data(Vec3) = null,

    points_ibo: IBO,
};

pub const SurfaceMeshStandardData = enum {
    vertex_position,
    vertex_normal,
    vertex_color,
};

const SurfaceMeshInfo = struct {
    vertex_position: ?*Data(Vec3) = null,
    vertex_normal: ?*Data(Vec3) = null,
    vertex_color: ?*Data(Vec3) = null,

    triangles_ibo: IBO,
    lines_ibo: IBO,
    points_ibo: IBO,
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
        info.triangles_ibo.deinit();
        info.lines_ibo.deinit();
        info.points_ibo.deinit();
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

pub fn connectivityUpdated(self: *Self, surface_mesh: *SurfaceMesh) !void {
    const maybe_info = self.surface_meshes_info.getPtr(surface_mesh);
    if (maybe_info) |info| {
        try info.points_ibo.fillFrom(surface_mesh, .vertex, self.allocator);
        try info.lines_ibo.fillFrom(surface_mesh, .edge, self.allocator);
        try info.triangles_ibo.fillFrom(surface_mesh, .face, self.allocator);
    }
}

pub fn dataUpdated(self: *Self, comptime T: type, data: *const Data(T)) !void {
    const vbo = try self.vbo_registry.getOrPut(&data.gen);
    if (!vbo.found_existing) {
        vbo.value_ptr.* = VBO.init();
    }
    try vbo.value_ptr.*.fillFrom(T, data);
}

pub fn setSurfaceMeshStandardData(
    self: *Self,
    surface_mesh: *SurfaceMesh,
    std_data: SurfaceMeshStandardData,
    comptime T: type,
    data: ?*Data(T),
) !void {
    const maybe_info = self.surface_meshes_info.getPtr(surface_mesh);
    if (maybe_info) |info| {
        switch (std_data) {
            .vertex_position => info.vertex_position = data,
            .vertex_normal => info.vertex_normal = data,
            .vertex_color => info.vertex_color = data,
        }
        if (data) |d| {
            try self.dataUpdated(T, d);
        }
    }

    for (zgp.modules.items) |*module| {
        module.surfaceMeshStandardDataChanged(surface_mesh, std_data);
    }
}

pub fn uiPanel(self: *Self) void {
    const UiData = struct {
        var selected_point_cloud: ?*PointCloud = null;
        var selected_surface_mesh: ?*SurfaceMesh = null;
    };

    _ = c.ImGui_Begin("Models Registry", null, 0);
    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - c.ImGui_GetStyle().*.ItemSpacing.x * 2);

    c.ImGui_SeparatorText("Surface Meshes");
    if (c.ImGui_BeginListBox("##Surface Meshes", c.ImVec2{ .x = 0, .y = 0 })) {
        var sm_it = self.surface_meshes.iterator();
        while (sm_it.next()) |entry| {
            const surface_mesh = entry.value_ptr.*;
            const name = entry.key_ptr.*;
            const selected = if (UiData.selected_surface_mesh == surface_mesh) true else false;
            if (c.ImGui_SelectableEx(name.ptr, selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                UiData.selected_surface_mesh = surface_mesh;
            }
            if (selected) {
                c.ImGui_SetItemDefaultFocus();
            }
        }
        c.ImGui_EndListBox();
    }

    if (UiData.selected_surface_mesh) |surface_mesh| {
        const maybe_info = self.surface_meshes_info.getPtr(surface_mesh);
        if (maybe_info) |info| {
            c.ImGui_Text("Vertex Position");
            if (c.ImGui_BeginCombo("##Vertex Position", if (info.vertex_position) |pos| pos.gen.name.ptr else "--none--", 0)) {
                const none_selected = if (info.vertex_position) |_| false else true;
                if (c.ImGui_SelectableEx("--none--", none_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                    if (!none_selected) {
                        self.setSurfaceMeshStandardData(surface_mesh, .vertex_position, Vec3, null) catch |err| {
                            zgp.imgui_log.err("Error setting vertex position data: {}\n", .{err});
                        };
                    }
                }
                if (none_selected) {
                    c.ImGui_SetItemDefaultFocus();
                }
                var vec3_data_it = surface_mesh.vertex_data.typedIterator(Vec3);
                while (vec3_data_it.next()) |data| {
                    const is_selected = if (info.vertex_position == data) true else false;
                    if (c.ImGui_SelectableEx(data.gen.name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                        if (!is_selected) {
                            self.setSurfaceMeshStandardData(surface_mesh, .vertex_position, Vec3, data) catch |err| {
                                zgp.imgui_log.err("Error setting vertex position data: {}", .{err});
                            };
                        }
                    }
                    if (is_selected) {
                        c.ImGui_SetItemDefaultFocus();
                    }
                }
                c.ImGui_EndCombo();
            }
            c.ImGui_Text("Vertex Color");
            if (c.ImGui_BeginCombo("##Vertex Color", if (info.vertex_color) |pos| pos.gen.name.ptr else "--none--", 0)) {
                const none_selected = if (info.vertex_color) |_| false else true;
                if (c.ImGui_SelectableEx("--none--", none_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                    if (!none_selected) {
                        self.setSurfaceMeshStandardData(surface_mesh, .vertex_color, Vec3, null) catch |err| {
                            zgp.imgui_log.err("Error setting vertex color data: {}\n", .{err});
                        };
                    }
                }
                if (none_selected) {
                    c.ImGui_SetItemDefaultFocus();
                }
                var vec3_data_it = surface_mesh.vertex_data.typedIterator(Vec3);
                while (vec3_data_it.next()) |data| {
                    const is_selected = if (info.vertex_color == data) true else false;
                    if (c.ImGui_SelectableEx(data.gen.name.ptr, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                        if (!is_selected) {
                            self.setSurfaceMeshStandardData(surface_mesh, .vertex_color, Vec3, data) catch |err| {
                                zgp.imgui_log.err("Error setting vertex color data: {}", .{err});
                            };
                        }
                    }
                    if (is_selected) {
                        c.ImGui_SetItemDefaultFocus();
                    }
                }
                c.ImGui_EndCombo();
            }
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }

    c.ImGui_Separator();

    c.ImGui_SeparatorText("Point Clouds");
    if (c.ImGui_BeginListBox("##Point Clouds", c.ImVec2{ .x = 0, .y = 0 })) {
        var pc_it = self.point_clouds.iterator();
        while (pc_it.next()) |entry| {
            const point_cloud = entry.value_ptr.*;
            const name = entry.key_ptr.*;
            var selected = if (UiData.selected_point_cloud == point_cloud) true else false;
            if (c.ImGui_SelectableBoolPtr(name.ptr, &selected, 0)) {
                UiData.selected_point_cloud = point_cloud;
            }
        }
        c.ImGui_EndListBox();
    }

    c.ImGui_PopItemWidth();
    c.ImGui_End();
}

pub fn createPointCloud(self: *Self, name: []const u8) !*PointCloud {
    const maybe_point_cloud = self.point_clouds.get(name);
    if (maybe_point_cloud) |_| {
        return error.ModelNameAlreadyExists;
    }
    const pc = try self.allocator.create(PointCloud);
    pc.* = try PointCloud.init(self.allocator);
    try self.point_clouds.put(name, pc);
    try self.point_clouds_info.put(pc, .{
        .points_ibo = IBO.init(),
    });

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
    sm.* = try SurfaceMesh.init(self.allocator);
    try self.surface_meshes.put(name, sm);
    try self.surface_meshes_info.put(sm, .{
        .triangles_ibo = IBO.init(),
        .lines_ibo = IBO.init(),
        .points_ibo = IBO.init(),
    });

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
            std.debug.print("reading OFF file\n", .{});

            while (reader.streamUntilDelimiter(line_writer, '\n', null)) {
                if (line.items.len == 0) continue; // skip empty lines
                defer line.clearRetainingCapacity();
                if (std.mem.startsWith(u8, line.items, "OFF")) break;
            } else |err| switch (err) {
                error.EndOfStream => {
                    std.debug.print("reached end of file before finding the header\n", .{});
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
                    std.debug.print("failed to read the number of cells\n", .{});
                    return error.InvalidFileFormat;
                }
                break;
            } else |err| switch (err) {
                error.EndOfStream => {
                    std.debug.print("reached end of file before reading the number of cells\n", .{});
                    return error.InvalidFileFormat;
                },
                else => return err,
            }
            std.debug.print("nb_cells: {d} {d} {d}\n", .{ nb_cells[0], nb_cells[1], nb_cells[2] });

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
                            std.debug.print("vertex {d} position has more than 3 coordinates\n", .{i});
                            return error.InvalidFileFormat;
                        }
                        const value = try std.fmt.parseFloat(f32, token);
                        position[j] = value;
                    }
                    if (j != 3) {
                        std.debug.print("vertex {d} position has less than 3 coordinates\n", .{i});
                        return error.InvalidFileFormat;
                    }
                    try import_data.vertices_position.append(position);
                    break;
                } else |err| switch (err) {
                    error.EndOfStream => {
                        std.debug.print("reached end of file before reading all vertices\n", .{});
                        return error.InvalidFileFormat;
                    },
                    else => return err,
                }
            }
            std.debug.print("read {d} vertices\n", .{import_data.vertices_position.items.len});

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
                            std.debug.print("face {d} has more than {d} vertices\n", .{ i, face_nb_vertices });
                            return error.InvalidFileFormat;
                        } else {
                            const index = try std.fmt.parseInt(u32, token, 10);
                            try import_data.faces_vertex_indices.append(index);
                        }
                    }
                    if (j != face_nb_vertices + 1) {
                        std.debug.print("face {d} has less than {d} vertices\n", .{ i, face_nb_vertices });
                        return error.InvalidFileFormat;
                    }
                    try import_data.faces_nb_vertices.append(face_nb_vertices);
                    break;
                } else |err| switch (err) {
                    error.EndOfStream => {
                        std.debug.print("reached end of file before reading all faces\n", .{});
                        return error.InvalidFileFormat;
                    },
                    else => return err,
                }
            }
            std.debug.print("read {d} faces\n", .{import_data.faces_nb_vertices.items.len});
        },
        else => return error.InvalidFileExtension,
    }

    const sm = try self.createSurfaceMesh(std.fs.path.basename(filename));

    const vertex_position = try sm.addData(.vertex, Vec3, "position");
    const halfedges_of_vertex = try sm.addData(.vertex, std.ArrayList(SurfaceMesh.HalfEdge), "halfedges_of_vertex");
    defer sm.removeData(.vertex, &halfedges_of_vertex.gen);

    for (import_data.vertices_position.items) |pos| {
        const vertex_index = try sm.newDataIndex(.vertex);
        vertex_position.value(vertex_index).* = pos;
        halfedges_of_vertex.value(vertex_index).* = std.ArrayList(SurfaceMesh.HalfEdge).init(halfedges_of_vertex.arena());
    }

    var i: u32 = 0;
    for (import_data.faces_nb_vertices.items) |face_nb_vertices| {
        const face = try sm.addUnboundedFace(face_nb_vertices);
        var he = SurfaceMesh.halfEdge(face);
        for (import_data.faces_vertex_indices.items[i .. i + face_nb_vertices]) |index| {
            sm.he_vertex_index.value(he).* = index;
            try halfedges_of_vertex.value(index).append(he);
            he = sm.phi1(he);
        }
        i += face_nb_vertices;
    }

    var nb_boundary_edges: u32 = 0;

    var halfedge_it = try SurfaceMesh.CellIterator(.halfedge).init(sm);
    defer halfedge_it.deinit();
    while (halfedge_it.next()) |he| {
        if (sm.phi2(he) == he) {
            const vertex_index = sm.indexOf(.{ .vertex = he });
            const next_vertex_index = sm.indexOf(.{ .vertex = sm.phi1(he) });
            const next_vertex_halfedges = halfedges_of_vertex.value(next_vertex_index).*;
            const opposite_halfedge = for (next_vertex_halfedges.items) |he2| {
                if (sm.indexOf(.{ .vertex = sm.phi1(he2) }) == vertex_index) {
                    break he2;
                }
            } else null;
            if (opposite_halfedge) |he2| {
                sm.phi2Sew(he, he2);
            } else {
                nb_boundary_edges += 1;
            }
        }
    }

    return sm;
}
