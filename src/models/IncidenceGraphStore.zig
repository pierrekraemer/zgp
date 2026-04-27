const IncidenceGraphStore = @This();

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
const IncidenceGraph = @import("incidenceGraph/IncidenceGraph.zig");

const Data = @import("../utils/data.zig").Data;
const DataGen = @import("../utils/data.zig").DataGen;
const BufferPool = @import("../utils/BufferPool.zig").BufferPool;

const VBO = @import("../rendering/VBO.zig");
const IBO = @import("../rendering/IBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

/// This struct defines the standard datas of a IncidenceGraph
pub const IncidenceGraphStdDatas = struct {
    vertex_position: ?IncidenceGraph.CellData(.vertex, Vec3f) = null,
};
/// This tagged union is generated from the IncidenceGraphStdDatas struct and allows to
/// easily provide a single data entry to the setIncidenceGraphStdData function
pub const IncidenceGraphStdData = types_utils.UnionFromStruct(IncidenceGraphStdDatas);
pub const IncidenceGraphStdDataTag = std.meta.Tag(IncidenceGraphStdData);

/// This struct holds information related to a IncidenceGraph, including:
/// - its standard datas
/// - the IBOs (for rendering).
/// The IncidenceGraphInfo associated with a IncidenceGraph is accessible via the incidenceGraphInfo function.
const IncidenceGraphInfo = struct {
    std_datas: IncidenceGraphStdDatas = .{},

    points_ibo: IBO,
    lines_ibo: IBO,
    triangles_ibo: IBO,

    pub fn init() IncidenceGraphInfo {
        return .{
            .points_ibo = .init(),
            .lines_ibo = .init(),
            .triangles_ibo = .init(),
        };
    }
    pub fn deinit(self: *IncidenceGraphInfo) void {
        self.points_ibo.deinit();
        self.lines_ibo.deinit();
        self.triangles_ibo.deinit();
    }
};

io: std.Io,
allocator: std.mem.Allocator,

// list of Modules that have registered interest in IncidenceGraph events
listeners: std.ArrayList(*Module),

incidence_graphs: std.StringArrayHashMapUnmanaged(*IncidenceGraph),
incidence_graphs_info: std.AutoArrayHashMapUnmanaged(*const IncidenceGraph, IncidenceGraphInfo),
selected_model: *ModelSelection = undefined, // set in AppContext wireUp

// each DataGen can be associated with a VBO
// once a VBO has been requested for a Data (in dataVBO) it is stored in this map
// and updated upon calls to incidenceGraphDataUpdated
data_vbo: std.AutoHashMapUnmanaged(*const DataGen, VBO),
// stores the last update time for each DataGen
// updated upon calls to incidenceGraphDataUpdated
data_last_update: std.AutoHashMapUnmanaged(*const DataGen, std.Io.Timestamp),

cell_buffer_pool: BufferPool(IncidenceGraph.Cell),

pub fn init(io: std.Io, allocator: std.mem.Allocator) !IncidenceGraphStore {
    return .{
        .io = io,
        .allocator = allocator,
        .listeners = .empty,
        .incidence_graphs = .empty,
        .incidence_graphs_info = .empty,
        .data_vbo = .empty,
        .data_last_update = .empty,
        .cell_buffer_pool = try .init(io, allocator, 2048, 64, 32),
    };
}

pub fn deinit(igs: *IncidenceGraphStore) void {
    igs.listeners.deinit(igs.allocator);

    for (igs.incidence_graphs_info.values()) |*info| {
        info.deinit();
    }
    igs.incidence_graphs_info.deinit(igs.allocator);

    for (igs.incidence_graphs.keys(), igs.incidence_graphs.values()) |name, ig| {
        const nameZ: [:0]const u8 = @ptrCast(name); // the name is a null-terminated string (dupeZ in createIncidenceGraph)
        igs.allocator.free(nameZ); // free the name
        ig.deinit();
        igs.allocator.destroy(ig); // destroy the IncidenceGraph
    }
    igs.incidence_graphs.deinit(igs.allocator);

    var vbo_it = igs.data_vbo.iterator();
    while (vbo_it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    igs.data_vbo.deinit(igs.allocator);

    igs.data_last_update.deinit(igs.allocator);

    igs.cell_buffer_pool.deinit();
}

pub fn addListener(igs: *IncidenceGraphStore, module: *Module) !void {
    try igs.listeners.append(igs.allocator, module);
}

pub fn createIncidenceGraph(igs: *IncidenceGraphStore, name: []const u8) !*IncidenceGraph {
    if (igs.incidence_graphs.contains(name)) {
        return error.ModelNameAlreadyExists;
    }

    // create and init the IncidenceGraph
    const ig = try igs.allocator.create(IncidenceGraph);
    errdefer igs.allocator.destroy(ig);
    try ig.init(igs.allocator, &igs.cell_buffer_pool);
    errdefer ig.deinit();

    // duplicate name and store the IncidenceGraph pointer in the map
    const owned_name = try igs.allocator.dupeZ(u8, name);
    errdefer igs.allocator.free(owned_name);
    try igs.incidence_graphs.put(igs.allocator, owned_name, ig);
    errdefer _ = igs.incidence_graphs.swapRemove(owned_name);

    // store the IncidenceGraphInfo in the map
    try igs.incidence_graphs_info.put(igs.allocator, ig, .init());

    for (igs.listeners.items) |module| {
        module.incidenceGraphCreated(ig);
    }

    return ig;
}

pub fn destroyIncidenceGraph(igs: *IncidenceGraphStore, ig: *IncidenceGraph) void {
    const name = igs.incidenceGraphName(ig) orelse {
        zgp_log.err("Could not find name for IncidenceGraph to destroy it", .{});
        return;
    };

    switch (igs.selected_model.*) {
        .incidence_graph => |selected_ig| {
            if (selected_ig == ig) {
                igs.selected_model.* = .none;
            }
        },
        else => {},
    }

    for (igs.listeners.items) |module| {
        module.incidenceGraphDestroyed(ig);
    }

    igs.incidence_graphs_info.getPtr(ig).?.deinit();
    _ = igs.incidence_graphs_info.swapRemove(ig);

    _ = igs.incidence_graphs.swapRemove(name);
    igs.allocator.free(name); // free the name

    ig.deinit();
    igs.allocator.destroy(ig); // destroy the IncidenceGraph
}

pub fn incidenceGraphDataUpdated(
    igs: *IncidenceGraphStore,
    ig: *IncidenceGraph,
    comptime cell_type: IncidenceGraph.CellType,
    comptime T: type,
    data: IncidenceGraph.CellData(cell_type, T),
) void {
    // if it exists, update the VBO with the data
    const maybe_vbo = igs.data_vbo.getPtr(data.gen());
    if (maybe_vbo) |vbo| {
        vbo.fillFrom(T, data.data);
    }

    // update the last known data update time
    igs.data_last_update.put(igs.allocator, data.gen(), std.Io.Timestamp.now(igs.io, .real)) catch |err| {
        zgp_log.err("Failed to update last update time for IncidenceGraph data: {}", .{err});
        return;
    };

    // dispatch call to listeners
    for (igs.listeners.items) |module| {
        module.incidenceGraphDataUpdated(ig, cell_type, data.gen());
    }
}

pub fn incidenceGraphConnectivityUpdated(igs: *IncidenceGraphStore, ig: *IncidenceGraph) void {
    const info = igs.incidence_graphs_info.getPtr(ig).?;

    info.points_ibo.fillFromIncidenceGraph(ig, .vertex, igs.allocator) catch |err| {
        zgp_log.err("Failed to fill points IBO for IncidenceGraph: {}", .{err});
        return;
    };
    info.lines_ibo.fillFromIncidenceGraph(ig, .edge, igs.allocator) catch |err| {
        zgp_log.err("Failed to fill lines IBO for IncidenceGraph: {}", .{err});
        return;
    };
    info.triangles_ibo.fillFromIncidenceGraph(ig, .face, igs.allocator) catch |err| {
        zgp_log.err("Failed to fill triangles IBO for IncidenceGraph: {}", .{err});
        return;
    };

    for (igs.listeners.items) |module| {
        module.incidenceGraphConnectivityUpdated(ig);
    }
}

pub fn dataVBO(
    igs: *IncidenceGraphStore,
    comptime cell_type: IncidenceGraph.CellType,
    comptime T: type,
    data: IncidenceGraph.CellData(cell_type, T),
) VBO {
    const vbo = igs.data_vbo.getOrPut(igs.allocator, data.gen()) catch |err| {
        zgp_log.err("Failed to get or add VBO in the registry: {}", .{err});
        return VBO.init(); // return a dummy VBO
    };
    if (!vbo.found_existing) {
        vbo.value_ptr.* = VBO.init();
        vbo.value_ptr.*.fillFrom(T, data.data); // on VBO creation, fill it with the data
    }
    return vbo.value_ptr.*;
}

pub fn dataLastUpdate(igs: *IncidenceGraphStore, data_gen: *const DataGen) ?std.Io.Timestamp {
    return igs.data_last_update.get(data_gen);
}

pub fn incidenceGraphInfo(igs: *IncidenceGraphStore, ig: *const IncidenceGraph) *IncidenceGraphInfo {
    return igs.incidence_graphs_info.getPtr(ig).?; // should always exist
}

pub fn incidenceGraphName(igs: *IncidenceGraphStore, ig: *const IncidenceGraph) ?[:0]const u8 {
    for (igs.incidence_graphs.keys(), igs.incidence_graphs.values()) |name, ig_ptr| {
        if (ig_ptr == ig) {
            return @ptrCast(name); // the name is a null-terminated string (dupeZ in createIncidenceGraph)
        }
    }
    return null;
}

pub fn setIncidenceGraphStdData(
    igs: *IncidenceGraphStore,
    ig: *IncidenceGraph,
    data: IncidenceGraphStdData,
) void {
    const info = igs.incidence_graphs_info.getPtr(ig).?;
    switch (data) {
        inline else => |val, tag| {
            @field(info.std_datas, @tagName(tag)) = val;
        },
    }

    for (igs.listeners.items) |module| {
        module.incidenceGraphStdDataChanged(ig, data);
    }
}

pub fn menuBar(_: *IncidenceGraphStore) void {}

pub fn leftPanel(igs: *IncidenceGraphStore) void {
    assert(igs.selected_model.modelType() == .incidence_graph);

    const CreateDataTypes = union(enum) { bool: bool, u32: u32, f32: f32, Vec3f: Vec3f };
    const CreateDataTypesTag = std.meta.Tag(CreateDataTypes);
    const UiData = struct {
        var selected_incidence_graph_cell_type: IncidenceGraph.CellType = .vertex;
        var selected_data_type: CreateDataTypesTag = .f32;
        var data_name_buf: [32]u8 = @splat(0);
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const ig = igs.selected_model.incidence_graph;

    if (c.ImGui_BeginTable("CellStats", 3, c.ImGuiTableFlags_Borders | c.ImGuiTableFlags_RowBg)) {
        defer c.ImGui_EndTable();

        c.ImGui_TableSetupColumn("CellType", c.ImGuiTableColumnFlags_WidthStretch);
        c.ImGui_TableSetupColumn("Count", c.ImGuiTableColumnFlags_WidthFixed);
        c.ImGui_TableSetupColumn("ContainerDensity", c.ImGuiTableColumnFlags_WidthFixed);
        c.ImGui_TableHeadersRow();

        inline for ([_]IncidenceGraph.CellType{ .vertex, .edge, .face }) |cell_type| {
            var buf_name: [32]u8 = undefined;
            var buf_count: [16]u8 = undefined;
            var buf_density: [16]u8 = undefined;

            const cells = std.fmt.bufPrintZ(&buf_name, "{s}", .{@tagName(cell_type)}) catch "";
            const count = std.fmt.bufPrintZ(&buf_count, "{d}", .{ig.nbCells(cell_type)}) catch "";
            const density = std.fmt.bufPrintZ(&buf_density, "{d:.1}%", .{ig.dataContainerPtr(cell_type).density() * 100}) catch "";

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
        if (imgui_utils.incidenceGraphCellTypeComboBox(UiData.selected_incidence_graph_cell_type)) |cell_type| {
            UiData.selected_incidence_graph_cell_type = cell_type;
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
            UiData.data_name_buf = @splat(0);
            c.ImGui_CloseCurrentPopup();
        }
        c.ImGui_SameLine();
        if (c.ImGui_ButtonEx("Create", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            switch (UiData.selected_incidence_graph_cell_type) {
                inline else => |cell_type| {
                    switch (UiData.selected_data_type) {
                        inline else => |data_type| {
                            const data_name = std.mem.sliceTo(&UiData.data_name_buf, 0);
                            _ = ig.addData(cell_type, @FieldType(CreateDataTypes, @tagName(data_type)), data_name) catch |err| {
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
        c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(255, 128, 128, 200));
        c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(255, 128, 128, 255));
        c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(255, 128, 128, 128));
        if (c.ImGui_ButtonEx(c.ICON_FA_TRASH ++ " Delete", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            igs.destroyIncidenceGraph(ig);
        }
        c.ImGui_PopStyleColorEx(3);
    }
}

// TODO: put the IO code in a separate module

pub fn loadIncidenceGraphFromFile(igs: *IncidenceGraphStore, filename: []const u8) !*IncidenceGraph {
    const ig = try igs.createIncidenceGraph(filename);
    // read the file and fill the incidence graph
    return ig;
}
