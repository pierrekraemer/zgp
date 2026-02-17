const PointCloudStdDatas = @This();

const std = @import("std");

const zgp_log = std.log.scoped(.zgp);

const c = @import("../main.zig").c;

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const PointCloud = @import("../models/point/PointCloud.zig");
const PointCloudStore = @import("../models/PointCloudStore.zig");
const PointCloudStdData = PointCloudStore.PointCloudStdData;
const PointCloudStdDataTag = PointCloudStore.PointCloudStdDataTag;

const imgui_utils = @import("../ui/imgui.zig");
const types_utils = @import("../utils/types.zig");
const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

app_ctx: *AppContext,
module: Module = .{
    .name = "Point Cloud Std Datas",
    .vtable = &.{
        .leftPanel = leftPanel,
    },
},

pub fn init(app_ctx: *AppContext) PointCloudStdDatas {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(_: *PointCloudStdDatas) void {}

/// Part of the Module interface.
/// Show a UI panel to control the standard datas of the selected PointCloud.
pub fn leftPanel(m: *Module) void {
    const pcsd: *PointCloudStdDatas = @alignCast(@fieldParentPtr("module", m));
    const pc_store = &pcsd.app_ctx.point_cloud_store;

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const button_width = c.ImGui_CalcTextSize("" ++ c.ICON_FA_DATABASE).x + style.*.ItemSpacing.x;

    if (pc_store.selected_point_cloud) |pc| {
        var buf: [64]u8 = undefined; // guess 64 chars is enough for cell name
        const info = pc_store.point_clouds_info.getPtr(pc).?;
        const cells = std.fmt.bufPrintZ(&buf, "Points", .{}) catch "";
        c.ImGui_SeparatorText(cells.ptr);
        inline for (@typeInfo(PointCloudStdData).@"union".fields) |*field| {
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
                if (imgui_utils.pointCloudDataComboBox(
                    pc,
                    @typeInfo(field.type).optional.child.DataType,
                    @field(info.std_datas, field.name),
                )) |data| {
                    pc_store.setPointCloudStdData(pc, @unionInit(PointCloudStdData, field.name, data));
                    pcsd.app_ctx.requestRedraw();
                }
            }
        }

        c.ImGui_Separator();

        if (c.ImGui_ButtonEx(c.ICON_FA_DATABASE ++ " Create missing std datas", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            inline for (@typeInfo(PointCloudStdData).@"union".fields) |*field| {
                if (@field(info.std_datas, field.name) == null) {
                    const maybe_data = pc.addData(@typeInfo(field.type).optional.child.DataType, field.name);
                    if (maybe_data) |data| {
                        pc_store.setPointCloudStdData(pc, @unionInit(PointCloudStdData, field.name, data));
                        pcsd.app_ctx.requestRedraw();
                    } else |err| {
                        zgp_log.err("Error adding {s} ({s}) data: {}", .{ field.name, @typeName(@typeInfo(field.type).optional.child.DataType), err });
                    }
                }
            }
        }
    } else {
        c.ImGui_Text("No Point Cloud selected");
    }
}

/// This struct describes a standard data computation:
/// - which standard datas are read,
/// - which standard data is computed,
/// - the function that performs the computation.
/// The function must have the following signature:
/// fn(
///     pc: *PointCloud,
///     read_data_1: PointCloud.CellData(...),
///     read_data_2: PointCloud.CellData(...),
///     ...
///     computed_data: PointCloud.CellData(...),
/// ) !void
const StdDataComputation = struct {
    reads: []const PointCloudStdDataTag,
    computes: PointCloudStdDataTag,
    func: *const anyopaque,

    fn ComputeFuncType(comptime self: *const StdDataComputation) type {
        const nbparams = self.reads.len + 3; // AppContext + PointCloud + read datas + computed data
        var params: [nbparams]std.builtin.Type.Fn.Param = undefined;
        params[0] = .{ .is_generic = false, .is_noalias = false, .type = *AppContext };
        params[1] = .{ .is_generic = false, .is_noalias = false, .type = *PointCloud };
        inline for (self.reads, 0..self.reads.len) |read_tag, i| {
            params[i + 2] = .{
                .is_generic = false,
                .is_noalias = false,
                .type = @typeInfo(@FieldType(PointCloudStore.PointCloudStdDatas, @tagName(read_tag))).optional.child,
            };
        }
        params[nbparams - 1] = .{
            .is_generic = false,
            .is_noalias = false,
            .type = @typeInfo(@FieldType(PointCloudStore.PointCloudStdDatas, @tagName(self.computes))).optional.child,
        };
        return @Type(.{ .@"fn" = .{
            .calling_convention = .auto,
            .is_generic = false,
            .is_var_args = false,
            .return_type = anyerror!void,
            .params = &params,
        } });
    }

    // get the standard datas to read and the one to compute from the PointCloudStdDatas of the given PointCloud
    pub fn compute(comptime self: *const StdDataComputation, app_ctx: *AppContext, pc: *PointCloud) void {
        const info = app_ctx.point_cloud_store.pointCloudInfo(pc);
        const func: *const self.ComputeFuncType() = @ptrCast(@alignCast(self.func));
        var args: std.meta.ArgsTuple(self.ComputeFuncType()) = undefined;
        args[0] = app_ctx;
        args[1] = pc;
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
/// and the "Update outdated std datas" button of the PointCloudStore
/// computes them in the order of declaration.
pub const std_data_computations: []const StdDataComputation = &.{};

pub fn dataComputableAndUpToDate(
    pcs: *PointCloudStore,
    pc: *PointCloud,
    comptime tag: PointCloudStdDataTag,
) struct { bool, bool } {
    const info = pcs.pointCloudInfo(pc);
    inline for (std_data_computations) |comp| {
        if (comp.computes == tag) {
            // found a computation for this data
            const computes_data = @field(info.std_datas, @tagName(comp.computes));
            if (computes_data == null) {
                return .{ false, false }; // computed data is not present in mesh info, so not computable nor up-to-date
            }
            var upToDate = true;
            const computes_last_update = pcs.dataLastUpdate(computes_data.?.gen());
            inline for (comp.reads) |reads_tag| {
                const reads_data = @field(info.std_datas, @tagName(reads_tag));
                if (reads_data == null) {
                    return .{ false, false }; // a read data is not present in mesh info, so not computable nor up-to-date
                }
                // the computed data is up-to-date only if the last update of the computed data is after the last update of all read data
                // and all read data are themselves up-to-date (recursive call)
                const reads_last_update = pcs.dataLastUpdate(reads_data.?.gen());
                if (computes_last_update == null or reads_last_update == null or computes_last_update.?.order(reads_last_update.?) == .lt) {
                    upToDate = false;
                } else {
                    _, upToDate = dataComputableAndUpToDate(pcs, pc, reads_tag);
                }
                if (!upToDate) break;
            }
            return .{ true, upToDate };
        }
    }
    return .{ true, true }; // no computation found for this data, so always computable & up-to-date (end of recursion)
}
