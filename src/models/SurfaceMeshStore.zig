const SurfaceMeshStore = @This();

const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const c = @import("c");
const zgp_log = std.log.scoped(.zgp);

const imgui_utils = @import("../ui/imgui.zig");
const types_utils = @import("../utils/types.zig");

const Module = @import("../modules/Module.zig");
const ModelSelection = @import("../main.zig").ModelSelection;
const SurfaceMesh = @import("surface/SurfaceMesh.zig");

const Data = @import("../utils/data.zig").Data;
const DataGen = @import("../utils/data.zig").DataGen;
const BufferPool = @import("../utils/BufferPool.zig").BufferPool;

const VBO = @import("../rendering/VBO.zig");
const IBO = @import("../rendering/IBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const bvh = @import("../geometry/bvh.zig");

/// This struct defines the standard datas of a SurfaceMesh
pub const SurfaceMeshStdDatas = struct {
    corner_angle: ?SurfaceMesh.CellData(.corner, f32) = null,
    halfedge_cotan_weight: ?SurfaceMesh.CellData(.halfedge, f32) = null,
    vertex_position: ?SurfaceMesh.CellData(.vertex, Vec3f) = null,
    vertex_area: ?SurfaceMesh.CellData(.vertex, f32) = null,
    vertex_normal: ?SurfaceMesh.CellData(.vertex, Vec3f) = null,
    vertex_tangent_basis: ?SurfaceMesh.CellData(.vertex, [2]Vec3f) = null,
    edge_length: ?SurfaceMesh.CellData(.edge, f32) = null,
    edge_dihedral_angle: ?SurfaceMesh.CellData(.edge, f32) = null,
    face_area: ?SurfaceMesh.CellData(.face, f32) = null,
    face_normal: ?SurfaceMesh.CellData(.face, Vec3f) = null,
};
/// This tagged union is generated from the SurfaceMeshStdDatas struct and allows to
/// easily provide a single data entry to the setSurfaceMeshStdData function
pub const SurfaceMeshStdData = types_utils.UnionFromStruct(SurfaceMeshStdDatas);
pub const SurfaceMeshStdDataTag = std.meta.Tag(SurfaceMeshStdData);

/// This struct holds information related to a SurfaceMesh, including:
/// - standard datas,
/// - BVH,
/// - primitve IBOs (for rendering).
/// The SurfaceMeshInfo associated with a SurfaceMesh is accessible via the surfaceMeshInfo function.
const SurfaceMeshInfo = struct {
    std_datas: SurfaceMeshStdDatas = .{},

    bvh: bvh.TrianglesBVH = .{},
    bvh_last_update: ?std.Io.Timestamp = null,

    points_ibo: IBO,
    lines_ibo: IBO,
    triangles_ibo: IBO,
    boundaries_ibo: IBO,

    pub fn init() SurfaceMeshInfo {
        return .{
            .points_ibo = .init(),
            .lines_ibo = .init(),
            .triangles_ibo = .init(),
            .boundaries_ibo = .init(),
        };
    }
    pub fn deinit(smi: *SurfaceMeshInfo) void {
        smi.bvh.deinit();
        smi.points_ibo.deinit();
        smi.lines_ibo.deinit();
        smi.triangles_ibo.deinit();
        smi.boundaries_ibo.deinit();
    }
};

io: std.Io,
allocator: std.mem.Allocator,

// list of Modules that have registered interest in SurfaceMesh events
listeners: std.ArrayList(*Module),

surface_meshes: std.StringArrayHashMapUnmanaged(*SurfaceMesh),
surface_meshes_info: std.AutoHashMapUnmanaged(*const SurfaceMesh, SurfaceMeshInfo),
selected_model: *ModelSelection = undefined, // set in AppContext wireUp

// each DataGen can be associated with a VBO
// once a VBO has been requested for a Data (in dataVBO function) it is stored in this map
// and updated upon calls to surfaceMeshDataUpdated function
data_vbo: std.AutoHashMapUnmanaged(*const DataGen, VBO),
// each CellSet can be associated with an IBO
// once an IBO has been requested for a CellSet (in cellSetIBO function) it is stored in this map
// and updated upon calls to surfaceMeshCellSetUpdated function
cell_set_ibo: std.AutoHashMapUnmanaged(*const SurfaceMesh.CellSet, IBO),
// stores the last update time for each DataGen
// updated upon calls to surfaceMeshDataUpdated
data_last_update: std.AutoHashMapUnmanaged(*const DataGen, std.Io.Timestamp),

cell_buffer_pool: BufferPool(SurfaceMesh.Cell),

pub fn init(io: std.Io, allocator: std.mem.Allocator) !SurfaceMeshStore {
    return .{
        .io = io,
        .allocator = allocator,
        .listeners = .empty,
        .surface_meshes = .empty,
        .surface_meshes_info = .empty,
        .data_vbo = .empty,
        .cell_set_ibo = .empty,
        .data_last_update = .empty,
        .cell_buffer_pool = try .init(io, allocator, 2048, 64, 32),
    };
}

pub fn deinit(sms: *SurfaceMeshStore) void {
    sms.listeners.deinit(sms.allocator);

    var info_it = sms.surface_meshes_info.valueIterator();
    while (info_it.next()) |info| {
        info.deinit();
    }
    sms.surface_meshes_info.deinit(sms.allocator);

    for (sms.surface_meshes.keys(), sms.surface_meshes.values()) |name, sm| {
        const nameZ: [:0]const u8 = @ptrCast(name); // the name is a null-terminated string (dupeZ in createSurfaceMesh)
        sms.allocator.free(nameZ); // free the name
        sm.deinit();
        sms.allocator.destroy(sm); // destroy the SurfaceMesh
    }
    sms.surface_meshes.deinit(sms.allocator);

    var vbo_it = sms.data_vbo.iterator();
    while (vbo_it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    sms.data_vbo.deinit(sms.allocator);

    var cell_set_ibo_it = sms.cell_set_ibo.iterator();
    while (cell_set_ibo_it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    sms.cell_set_ibo.deinit(sms.allocator);

    sms.data_last_update.deinit(sms.allocator);

    sms.cell_buffer_pool.deinit();
}

pub fn addListener(sms: *SurfaceMeshStore, module: *Module) !void {
    try sms.listeners.append(sms.allocator, module);
}

pub fn createSurfaceMesh(sms: *SurfaceMeshStore, name: []const u8) !*SurfaceMesh {
    if (sms.surface_meshes.contains(name)) {
        return error.ModelNameAlreadyExists;
    }

    // create and init the SurfaceMesh
    var sm = try sms.allocator.create(SurfaceMesh);
    errdefer sms.allocator.destroy(sm);
    try sm.init(sms.allocator, &sms.cell_buffer_pool);
    errdefer sm.deinit();

    // duplicate name and store the SurfaceMesh pointer in the map
    const owned_name = try sms.allocator.dupeZ(u8, name);
    errdefer sms.allocator.free(owned_name);
    try sms.surface_meshes.put(sms.allocator, owned_name, sm);
    errdefer _ = sms.surface_meshes.swapRemove(owned_name);

    // store the SurfaceMeshInfo in the map
    try sms.surface_meshes_info.put(sms.allocator, sm, .init());

    for (sms.listeners.items) |module| {
        module.surfaceMeshCreated(sm);
    }

    return sm;
}

pub fn destroySurfaceMesh(sms: *SurfaceMeshStore, sm: *SurfaceMesh) void {
    const name = sms.surfaceMeshName(sm) orelse {
        zgp_log.err("Could not find name for SurfaceMesh to destroy it", .{});
        return;
    };

    switch (sms.selected_model.*) {
        .surface_mesh => |selected_sm| {
            if (selected_sm == sm) {
                sms.selected_model.* = .none;
            }
        },
        else => {},
    }

    for (sms.listeners.items) |module| {
        module.surfaceMeshDestroyed(sm);
    }

    sms.surface_meshes_info.getPtr(sm).?.deinit();
    _ = sms.surface_meshes_info.remove(sm);

    _ = sms.surface_meshes.swapRemove(name);
    sms.allocator.free(name); // free the name

    sm.deinit();
    sms.allocator.destroy(sm); // destroy the SurfaceMesh
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

    // update the last known data update time
    sms.data_last_update.put(sms.allocator, data.gen(), std.Io.Timestamp.now(sms.io, .real)) catch |err| {
        zgp_log.err("Failed to update last update time for SurfaceMesh data: {}", .{err});
    };

    // dispatch call to listeners
    for (sms.listeners.items) |module| {
        module.surfaceMeshDataUpdated(sm, cell_type, data.gen());
    }
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

    // update the cached number of boundary darts in the SurfaceMesh
    var nb_boundary_darts: u32 = 0;
    var dart_it = sm.dartIterator();
    while (dart_it.next()) |d| {
        if (sm.isBoundaryDart(d)) {
            nb_boundary_darts += 1;
        }
    }
    sm.nb_boundary_darts = nb_boundary_darts;

    // update the different primitives IBO
    info.points_ibo.fillFromSurfaceMesh(sm, .vertex, sms.allocator) catch |err| {
        zgp_log.err("Failed to fill points IBO for SurfaceMesh: {}", .{err});
        return;
    };
    info.lines_ibo.fillFromSurfaceMesh(sm, .edge, sms.allocator) catch |err| {
        zgp_log.err("Failed to fill lines IBO for SurfaceMesh: {}", .{err});
        return;
    };
    info.triangles_ibo.fillFromSurfaceMesh(sm, .face, sms.allocator) catch |err| {
        zgp_log.err("Failed to fill triangles IBO for SurfaceMesh: {}", .{err});
        return;
    };
    info.boundaries_ibo.fillFromSurfaceMesh(sm, .boundary, sms.allocator) catch |err| {
        zgp_log.err("Failed to fill boundaries IBO for SurfaceMesh: {}", .{err});
        return;
    };

    // update the cells sets
    var vertex_sets_it = sm.vertex_sets.iterator();
    while (vertex_sets_it.next()) |entry| {
        entry.value_ptr.update() catch |err| {
            zgp_log.err("Failed to update vertex set for SurfaceMesh: {}", .{err});
        };
        sms.surfaceMeshCellSetUpdated(sm, entry.value_ptr);
    }
    var edge_sets_it = sm.edge_sets.iterator();
    while (edge_sets_it.next()) |entry| {
        entry.value_ptr.update() catch |err| {
            zgp_log.err("Failed to update edge set for SurfaceMesh: {}", .{err});
        };
        sms.surfaceMeshCellSetUpdated(sm, entry.value_ptr);
    }
    var face_sets_it = sm.face_sets.iterator();
    while (face_sets_it.next()) |entry| {
        entry.value_ptr.update() catch |err| {
            zgp_log.err("Failed to update face set for SurfaceMesh: {}", .{err});
        };
        sms.surfaceMeshCellSetUpdated(sm, entry.value_ptr);
    }

    // dispatch call to listeners
    for (sms.listeners.items) |module| {
        module.surfaceMeshConnectivityUpdated(sm);
    }
}

pub fn surfaceMeshCellSetUpdated(
    sms: *SurfaceMeshStore,
    sm: *SurfaceMesh,
    cell_set: *const SurfaceMesh.CellSet,
) void {
    // if it exists, update the IBO with the data
    const maybe_ibo = sms.cell_set_ibo.getPtr(cell_set);
    if (maybe_ibo) |ibo| {
        ibo.fillFromSurfaceMeshCellSlice(sm, cell_set.cells.items, sms.allocator) catch |err| {
            zgp_log.err("Failed to fill cell set IBO for SurfaceMesh: {}", .{err});
            return;
        };
    }

    // dispatch call to listeners
    for (sms.listeners.items) |module| {
        module.surfaceMeshCellSetUpdated(sm, cell_set);
    }
}

pub fn dataVBO(
    sms: *SurfaceMeshStore,
    comptime cell_type: SurfaceMesh.CellType,
    comptime T: type,
    data: SurfaceMesh.CellData(cell_type, T),
) VBO {
    const vbo = sms.data_vbo.getOrPut(sms.allocator, data.gen()) catch |err| {
        zgp_log.err("Failed to get or add VBO in the registry: {}", .{err});
        return VBO.init(); // return a dummy VBO
    };
    if (!vbo.found_existing) {
        vbo.value_ptr.* = VBO.init();
        vbo.value_ptr.fillFrom(T, data.data); // on VBO creation, fill it with the data
    }
    return vbo.value_ptr.*;
}

pub fn cellSetIBO(sms: *SurfaceMeshStore, cell_set: *const SurfaceMesh.CellSet) IBO {
    const ibo = sms.cell_set_ibo.getOrPut(sms.allocator, cell_set) catch |err| {
        zgp_log.err("Failed to get or add IBO in the registry: {}", .{err});
        return IBO.init(); // return a dummy IBO
    };
    if (!ibo.found_existing) {
        ibo.value_ptr.* = IBO.init();
        ibo.value_ptr.fillFromSurfaceMeshCellSlice(cell_set.surface_mesh, cell_set.cells.items, sms.allocator) catch |err| {
            zgp_log.err("Failed to fill cell set IBO for SurfaceMesh: {}", .{err});
            return IBO.init(); // return a dummy IBO
        };
    }
    return ibo.value_ptr.*;
}

pub fn dataLastUpdate(sms: *SurfaceMeshStore, data_gen: *const DataGen) ?std.Io.Timestamp {
    return sms.data_last_update.get(data_gen);
}

pub fn surfaceMeshInfo(sms: *SurfaceMeshStore, sm: *const SurfaceMesh) *SurfaceMeshInfo {
    return sms.surface_meshes_info.getPtr(sm).?; // should always exist
}

pub fn surfaceMeshName(sms: *SurfaceMeshStore, sm: *const SurfaceMesh) ?[:0]const u8 {
    for (sms.surface_meshes.keys(), sms.surface_meshes.values()) |name, sm_ptr| {
        if (sm_ptr == sm) {
            return @ptrCast(name); // the name is a null-terminated string (dupeZ in createSurfaceMesh)
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
            @field(info.std_datas, @tagName(tag)) = val;
        },
    }

    // dispatch call to listeners
    for (sms.listeners.items) |module| {
        module.surfaceMeshStdDataChanged(sm, data);
    }
}

pub fn menuBar(_: *SurfaceMeshStore) void {}

pub fn leftPanel(sms: *SurfaceMeshStore) void {
    assert(sms.selected_model.modelType() == .surface_mesh);

    const CreateDataTypes = union(enum) { bool: bool, u32: u32, f32: f32, Vec3f: Vec3f };
    const CreateDataTypesTag = std.meta.Tag(CreateDataTypes);
    const UiData = struct {
        var selected_surface_mesh_cell_type: SurfaceMesh.CellType = .vertex;
        var selected_data_type: CreateDataTypesTag = .f32;
        var data_name_buf: [32]u8 = @splat(0);
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const sm = sms.selected_model.surface_mesh;

    if (c.ImGui_BeginTable("CellStats", 3, c.ImGuiTableFlags_Borders | c.ImGuiTableFlags_RowBg)) {
        defer c.ImGui_EndTable();

        c.ImGui_TableSetupColumn("CellType", c.ImGuiTableColumnFlags_WidthStretch);
        c.ImGui_TableSetupColumn("Count", c.ImGuiTableColumnFlags_WidthFixed);
        c.ImGui_TableSetupColumn("ContainerDensity", c.ImGuiTableColumnFlags_WidthFixed);
        c.ImGui_TableHeadersRow();

        inline for ([_]SurfaceMesh.CellType{ .halfedge, .corner, .vertex, .edge, .face }) |cell_type| {
            var buf_name: [32]u8 = undefined;
            var buf_count: [16]u8 = undefined;
            var buf_density: [16]u8 = undefined;

            const cells = std.fmt.bufPrintZ(&buf_name, "{s}", .{@tagName(cell_type)}) catch "";
            const count = std.fmt.bufPrintZ(&buf_count, "{d}", .{sm.nbCells(cell_type)}) catch "";
            const density = std.fmt.bufPrintZ(&buf_density, "{d:.1}%", .{sm.dataContainerPtr(cell_type).density() * 100}) catch "";

            c.ImGui_TableNextRow();
            _ = c.ImGui_TableNextColumn();
            c.ImGui_Text(cells.ptr);
            _ = c.ImGui_TableNextColumn();
            c.ImGui_Text(count.ptr);
            _ = c.ImGui_TableNextColumn();
            c.ImGui_Text(density.ptr);
        }
    }

    if (c.ImGui_ButtonEx("Create cell data", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
        c.ImGui_OpenPopup("Create Cell Data", c.ImGuiPopupFlags_NoReopen);
    }
    if (c.ImGui_BeginPopupModal("Create Cell Data", 0, c.ImGuiWindowFlags_AlwaysAutoResize)) {
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
            inline for (@typeInfo(CreateDataTypesTag).@"enum".fields) |data_type| {
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
            switch (UiData.selected_surface_mesh_cell_type) {
                inline else => |cell_type| {
                    switch (UiData.selected_data_type) {
                        inline else => |data_type| {
                            const data_name = std.mem.sliceTo(&UiData.data_name_buf, 0);
                            _ = sm.addData(cell_type, @FieldType(CreateDataTypes, @tagName(data_type)), data_name) catch |err| {
                                zgp_log.err("Error adding {s} ({s}: {s}) data: {}", .{ data_name, @tagName(cell_type), @tagName(data_type), err });
                            };
                            UiData.data_name_buf = @splat(0);
                        },
                    }
                },
            }
        }
    }

    {
        const info = sms.surface_meshes_info.getPtr(sm).?;

        var bvh_computable = true;
        if (info.std_datas.vertex_position == null) {
            bvh_computable = false;
        }
        var bvh_upToDate = true;
        if (!bvh_computable or info.bvh_last_update == null or std.math.order(info.bvh_last_update.?.nanoseconds, sms.dataLastUpdate(info.std_datas.vertex_position.?.gen()).?.nanoseconds) == .lt) {
            bvh_upToDate = false;
        }
        if (!bvh_computable) {
            c.ImGui_BeginDisabled(true);
        }
        if (!bvh_upToDate) {
            c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(255, 128, 128, 200));
            c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(255, 128, 128, 255));
            c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(255, 128, 128, 128));
        } else {
            c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(128, 200, 128, 200));
            c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(128, 200, 128, 255));
            c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(128, 200, 128, 128));
        }
        var buf_bvh_button: [32]u8 = undefined;
        const bvh_button = std.fmt.bufPrintZ(&buf_bvh_button, c.ICON_FA_SITEMAP ++ " {s} BVH", .{if (info.bvh.initialized) "Update" else "Build"}) catch "";
        if (c.ImGui_ButtonEx(bvh_button, c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            info.bvh.deinit();
            info.bvh = bvh.TrianglesBVH.init(sm, info.std_datas.vertex_position.?) catch |err| blk: {
                zgp_log.err("Failed to build BVH: {}", .{err});
                break :blk .{};
            };
            if (info.bvh.initialized) {
                info.bvh_last_update = std.Io.Timestamp.now(sms.io, .real);
            }
        }
        c.ImGui_PopStyleColorEx(3);
        if (!bvh_computable) {
            c.ImGui_EndDisabled();
        }
    }

    {
        c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(255, 128, 128, 200));
        c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(255, 128, 128, 255));
        c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(255, 128, 128, 128));
        if (c.ImGui_ButtonEx(c.ICON_FA_TRASH ++ " Delete", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            sms.destroySurfaceMesh(sm);
        }
        c.ImGui_PopStyleColorEx(3);
    }
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
    var file = try std.Io.Dir.cwd().openFile(sms.io, filename, .{});
    defer file.close(sms.io);

    var buffer: [1024]u8 = undefined;
    var file_reader = file.reader(sms.io, &buffer);

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

            while (try file_reader.interface.takeDelimiter('\n')) |line| {
                if (line.len == 0) continue; // skip empty lines
                if (std.mem.startsWith(u8, line, "OFF")) break;
            } else {
                zgp_log.warn("reached end of file before finding the header", .{});
                return error.InvalidFileFormat;
            }
            zgp_log.info("found OFF header", .{});

            var nb_cells: [3]u32 = undefined; // [vertices, faces, edges]
            while (try file_reader.interface.takeDelimiter('\n')) |line| {
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
            } else {
                zgp_log.warn("reached end of file before reading the number of cells", .{});
                return error.InvalidFileFormat;
            }
            zgp_log.info("nb_cells: {d} vertices / {d} faces / {d} edges", .{ nb_cells[0], nb_cells[1], nb_cells[2] });

            try import_data.ensureTotalCapacity(sms.allocator, nb_cells[0], nb_cells[1]);

            var i: u32 = 0;
            while (i < nb_cells[0]) : (i += 1) {
                while (try file_reader.interface.takeDelimiter('\n')) |line| {
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
                } else {
                    zgp_log.warn("reached end of file before reading all vertices", .{});
                    return error.InvalidFileFormat;
                }
            }
            zgp_log.info("read {d} vertices", .{import_data.vertices_position.items.len});

            i = 0;
            while (i < nb_cells[1]) : (i += 1) {
                while (try file_reader.interface.takeDelimiter('\n')) |line| {
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
                } else {
                    zgp_log.warn("reached end of file before reading all faces", .{});
                    return error.InvalidFileFormat;
                }
            }
            zgp_log.info("read {d} faces", .{import_data.faces_nb_vertices.items.len});
        },
        else => return error.InvalidFileExtension,
    }

    const sm = try sms.createSurfaceMesh(std.fs.path.basename(filename));

    const vertex_position = try sm.addData(.vertex, Vec3f, "position");
    const darts_of_vertex = try sm.addData(.vertex, std.ArrayList(SurfaceMesh.Dart), "darts_of_vertex");
    defer sm.removeData(.vertex, std.ArrayList(SurfaceMesh.Dart), darts_of_vertex);
    var darts_array_lists_arena = std.heap.ArenaAllocator.init(sms.allocator);
    defer darts_array_lists_arena.deinit();

    for (import_data.vertices_position.items) |pos| {
        const vertex_index = try sm.getDataIndex(.vertex);
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
            try darts_of_vertex.data.valuePtr(index).append(darts_array_lists_arena.allocator(), d);
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
