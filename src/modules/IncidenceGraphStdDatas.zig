const IncidenceGraphStdDatas = @This();

const std = @import("std");
const assert = std.debug.assert;

const zgp_log = std.log.scoped(.zgp);

const c = @import("../main.zig").c;

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const IncidenceGraph = @import("../models/incidenceGraph/IncidenceGraph.zig");
const IncidenceGraphStore = @import("../models/IncidenceGraphStore.zig");
const IncidenceGraphStdData = IncidenceGraphStore.IncidenceGraphStdData;
const IncidenceGraphStdDataTag = IncidenceGraphStore.IncidenceGraphStdDataTag;

const imgui_utils = @import("../ui/imgui.zig");
const types_utils = @import("../utils/types.zig");
const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

app_ctx: *AppContext,
module: Module = .{
    .name = "Incidence Graph Std Datas",
    .supported_models = .{ .incidence_graph = true },
    .vtable = &.{
        .leftPanel = leftPanel,
    },
},

pub fn init(app_ctx: *AppContext) IncidenceGraphStdDatas {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(_: *IncidenceGraphStdDatas) void {}

/// Part of the Module interface.
/// Show a UI panel to control the standard datas of the selected IncidenceGraph.
pub fn leftPanel(m: *Module) void {
    const igsd: *IncidenceGraphStdDatas = @alignCast(@fieldParentPtr("module", m));
    const ig_store = &igsd.app_ctx.incidence_graph_store;

    assert(igsd.app_ctx.selected_model.modelType() == .incidence_graph);
    const ig = igsd.app_ctx.selected_model.incidence_graph;

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const button_width = c.ImGui_CalcTextSize("" ++ c.ICON_FA_DATABASE).x + style.*.ItemSpacing.x;

    var buf: [64]u8 = undefined; // guess 64 chars is enough for cell name
    const info = ig_store.incidence_graphs_info.getPtr(ig).?;

    inline for ([_]IncidenceGraph.CellType{ .vertex, .edge, .face }) |cell_type| {
        const cells = std.fmt.bufPrintZ(&buf, @tagName(cell_type), .{}) catch "";
        c.ImGui_SeparatorText(cells.ptr);
        inline for (@typeInfo(IncidenceGraphStdData).@"union".fields) |*field| {
            if (@typeInfo(field.type).optional.child.CellType != cell_type) continue;
            c.ImGui_Text(field.name);
            c.ImGui_SameLine();
            // align 2 buttons to the right of the text
            c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + c.ImGui_GetContentRegionAvail().x - 2 * button_width - style.*.ItemSpacing.x);
            const data_selected = @field(info.std_datas, field.name) != null;
            if (!data_selected) {
                c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(128, 128, 128, 200));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(128, 128, 128, 255));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(128, 128, 128, 128));
            }
            c.ImGui_PushID(field.name);
            defer c.ImGui_PopID();
            if (c.ImGui_Button("" ++ c.ICON_FA_DATABASE)) {
                c.ImGui_OpenPopup("select_data_popup", c.ImGuiPopupFlags_NoReopen);
            }
            if (!data_selected) {
                c.ImGui_PopStyleColorEx(3);
            }
            if (c.ImGui_BeginPopup("select_data_popup", 0)) {
                defer c.ImGui_EndPopup();
                c.ImGui_PushID("select_data_combobox");
                defer c.ImGui_PopID();
                switch (imgui_utils.incidenceGraphCellDataComboBox(
                    ig,
                    @typeInfo(field.type).optional.child.CellType,
                    @typeInfo(field.type).optional.child.DataType,
                    @field(info.std_datas, field.name),
                )) {
                    .unchanged => {},
                    .cleared => {
                        ig_store.setIncidenceGraphStdData(ig, @unionInit(IncidenceGraphStdData, field.name, null));
                        igsd.app_ctx.requestRedraw();
                    },
                    .changed => |data| {
                        ig_store.setIncidenceGraphStdData(ig, @unionInit(IncidenceGraphStdData, field.name, data));
                        igsd.app_ctx.requestRedraw();
                    },
                }
            }
        }
    }

    c.ImGui_Separator();

    if (c.ImGui_ButtonEx(c.ICON_FA_DATABASE ++ " Create missing std datas", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
        inline for (@typeInfo(IncidenceGraphStdData).@"union".fields) |*field| {
            if (@field(info.std_datas, field.name) == null) {
                const maybe_data = ig.addData(@typeInfo(field.type).optional.child.CellType, @typeInfo(field.type).optional.child.DataType, field.name);
                if (maybe_data) |data| {
                    ig_store.setIncidenceGraphStdData(ig, @unionInit(IncidenceGraphStdData, field.name, data));
                    igsd.app_ctx.requestRedraw();
                } else |err| {
                    zgp_log.err("Error adding {s} ({s}: {s}) data: {}", .{ field.name, @tagName(@typeInfo(field.type).optional.child.CellType), @typeName(@typeInfo(field.type).optional.child.DataType), err });
                }
            }
        }
    }
}

/// This struct describes a standard data computation:
/// - which standard datas are read,
/// - which standard data is computed,
/// - the function that performs the computation.
/// The function must have the following signature:
/// fn(
///     ig: *IncidenceGraph,
///     read_data_1: IncidenceGraph.CellData(...),
///     read_data_2: IncidenceGraph.CellData(...),
///     ...
///     computed_data: IncidenceGraph.CellData(...),
/// ) !void
const StdDataComputation = struct {
    reads: []const IncidenceGraphStdDataTag,
    computes: IncidenceGraphStdDataTag,
    func: *const anyopaque,

    fn ComputeFuncType(comptime self: *const StdDataComputation) type {
        const nbparams = self.reads.len + 3; // AppContext + IncidenceGraph + read datas + computed data
        var params: [nbparams]type = undefined;
        params[0] = *AppContext;
        params[1] = *IncidenceGraph;
        inline for (self.reads, 0..self.reads.len) |read_tag, i| {
            params[i + 2] = @typeInfo(@FieldType(IncidenceGraphStore.IncidenceGraphStdDatas, @tagName(read_tag))).optional.child;
        }
        params[nbparams - 1] = @typeInfo(@FieldType(IncidenceGraphStore.IncidenceGraphStdDatas, @tagName(self.computes))).optional.child;
        return @Fn(params, &@splat(.{}), anyerror!void, .{.@"callconv"(.auto)});
    }

    // get the standard datas to read and the one to compute from the IncidenceGraphStdDatas of the given IncidenceGraph
    pub fn compute(comptime self: *const StdDataComputation, app_ctx: *AppContext, ig: *IncidenceGraph) void {
        const info = app_ctx.incidence_graph_store.incidenceGraphInfo(ig);
        const func: *const self.ComputeFuncType() = @ptrCast(@alignCast(self.func));
        var args: std.meta.ArgsTuple(self.ComputeFuncType()) = undefined;
        args[0] = app_ctx;
        args[1] = ig;
        inline for (self.reads, 0..) |reads_tag, i| {
            args[i + 2] = @field(info.std_datas, @tagName(reads_tag)).?;
        }
        args[self.reads.len + 2] = @field(info.std_datas, @tagName(self.computes)).?;
        @call(.auto, func, args) catch |err| {
            std.debug.print("Error computing {s}: {}\n", .{ @tagName(self.computes), err });
        };
    }
};

/// Declaration of standard data computations.
/// The order of declaration matters: some computations depend on the result of previous ones
/// and the "Update outdated std datas" button of the IncidenceGraphStore
/// computes them in the order of declaration.
pub const std_data_computations: []const StdDataComputation = &.{};

pub fn dataComputableAndUpToDate(
    igs: *IncidenceGraphStore,
    ig: *IncidenceGraph,
    comptime tag: IncidenceGraphStdDataTag,
) struct { bool, bool } {
    const info = igs.incidenceGraphInfo(ig);
    inline for (std_data_computations) |comp| {
        if (comp.computes == tag) {
            // found a computation for this data
            const computes_data = @field(info.std_datas, @tagName(comp.computes));
            if (computes_data == null) {
                return .{ false, false }; // computed data is not present in mesh info, so not computable nor up-to-date
            }
            var upToDate = true;
            const computes_last_update = igs.dataLastUpdate(computes_data.?.gen());
            inline for (comp.reads) |reads_tag| {
                const reads_data = @field(info.std_datas, @tagName(reads_tag));
                if (reads_data == null) {
                    return .{ false, false }; // a read data is not present in mesh info, so not computable nor up-to-date
                }
                // the computed data is up-to-date only if the last update of the computed data is after the last update of all read data
                // and all read data are themselves up-to-date (recursive call)
                const reads_last_update = igs.dataLastUpdate(reads_data.?.gen());
                if (computes_last_update == null or reads_last_update == null or computes_last_update.?.order(reads_last_update.?) == .lt) {
                    upToDate = false;
                } else {
                    _, upToDate = dataComputableAndUpToDate(igs, ig, reads_tag);
                }
                if (!upToDate) break;
            }
            return .{ true, upToDate };
        }
    }
    return .{ true, true }; // no computation found for this data, so always computable & up-to-date (end of recursion)
}
