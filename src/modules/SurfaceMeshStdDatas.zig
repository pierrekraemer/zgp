const SurfaceMeshStdDatas = @This();

const std = @import("std");

const zgp_log = std.log.scoped(.zgp);

const c = @import("../main.zig").c;

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfaceMeshStore = @import("../models/SurfaceMeshStore.zig");
const SurfaceMeshStdData = SurfaceMeshStore.SurfaceMeshStdData;
const SurfaceMeshStdDataTag = SurfaceMeshStore.SurfaceMeshStdDataTag;

const imgui_utils = @import("../ui/imgui.zig");
const types_utils = @import("../utils/types.zig");
const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const angle = @import("../models/surface/angle.zig");
const area = @import("../models/surface/area.zig");
const curvature = @import("../models/surface/curvature.zig");
const laplacian = @import("../models/surface/laplacian.zig");
const length = @import("../models/surface/length.zig");
const normal = @import("../models/surface/normal.zig");
const tangentBasis = @import("../models/surface/tangentBasis.zig");

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Std Datas",
    .vtable = &.{
        .leftPanel = leftPanel,
    },
},

pub fn init(app_ctx: *AppContext) SurfaceMeshStdDatas {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(_: *SurfaceMeshStdDatas) void {}

/// Part of the Module interface.
/// Show a UI panel to control the standard datas of the selected SurfaceMesh.
pub fn leftPanel(m: *Module) void {
    const smsd: *SurfaceMeshStdDatas = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &smsd.app_ctx.surface_mesh_store;

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const button_width = c.ImGui_CalcTextSize("" ++ c.ICON_FA_DATABASE).x + style.*.ItemSpacing.x;

    if (sm_store.selected_surface_mesh) |sm| {
        var buf: [64]u8 = undefined; // guess 64 chars is enough for cell name
        const info = sm_store.surfaceMeshInfo(sm);

        inline for ([_]SurfaceMesh.CellType{ .halfedge, .corner, .vertex, .edge, .face }) |cell_type| {
            const cells = std.fmt.bufPrintZ(&buf, @tagName(cell_type), .{}) catch "";
            c.ImGui_SeparatorText(cells.ptr);
            inline for (@typeInfo(SurfaceMeshStdData).@"union".fields) |*field| {
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
                    if (imgui_utils.surfaceMeshCellDataComboBox(
                        sm,
                        @typeInfo(field.type).optional.child.CellType,
                        @typeInfo(field.type).optional.child.DataType,
                        @field(info.std_datas, field.name),
                    )) |data| {
                        sm_store.setSurfaceMeshStdData(sm, @unionInit(SurfaceMeshStdData, field.name, data));
                        smsd.app_ctx.requestRedraw();
                    }
                }
                const data_tag = @field(SurfaceMeshStdDataTag, field.name);
                inline for (std_data_computations) |comp| {
                    if (comp.computes == data_tag) {
                        c.ImGui_SameLine();
                        const computable, const upToDate = dataComputableAndUpToDate(sm_store, sm, data_tag);
                        if (!computable) {
                            c.ImGui_BeginDisabled(true);
                        }
                        if (!upToDate) {
                            c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(255, 128, 128, 200));
                            c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(255, 128, 128, 255));
                            c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(255, 128, 128, 128));
                        } else {
                            c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(128, 200, 128, 200));
                            c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(128, 200, 128, 255));
                            c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(128, 200, 128, 128));
                        }
                        if (c.ImGui_Button("" ++ c.ICON_FA_GEARS)) {
                            if (computable) {
                                comp.compute(smsd.app_ctx, sm);
                            } else {
                                zgp_log.err("No computation found for {s} data", .{field.name});
                            }
                        }
                        c.ImGui_PopStyleColorEx(3);
                        if (!computable) {
                            c.ImGui_EndDisabled();
                        }
                        // TODO: generate tooltip from reads & computes
                        // imgui_utils.tooltip(
                        //     \\ Read:
                        //     \\ - vertex_position
                        //     \\ Write:
                        //     \\ - corner_angle
                        // );
                    }
                }
            }
        }

        c.ImGui_Separator();

        if (c.ImGui_ButtonEx(c.ICON_FA_DATABASE ++ " Create missing std datas", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            inline for (@typeInfo(SurfaceMeshStdData).@"union".fields) |*field| {
                if (@field(info.std_datas, field.name) == null) {
                    const maybe_data = sm.addData(@typeInfo(field.type).optional.child.CellType, @typeInfo(field.type).optional.child.DataType, field.name);
                    if (maybe_data) |data| {
                        sm_store.setSurfaceMeshStdData(sm, @unionInit(SurfaceMeshStdData, field.name, data));
                        smsd.app_ctx.requestRedraw();
                    } else |err| {
                        zgp_log.err("Error adding {s} ({s}: {s}) data: {}", .{ field.name, @tagName(@typeInfo(field.type).optional.child.CellType), @typeName(@typeInfo(field.type).optional.child.DataType), err });
                    }
                }
            }
        }

        if (c.ImGui_ButtonEx(c.ICON_FA_GEAR ++ " Update outdated std datas", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            inline for (std_data_computations) |comp| {
                const computable, const upToDate = dataComputableAndUpToDate(sm_store, sm, comp.computes);
                if (computable and !upToDate) {
                    comp.compute(smsd.app_ctx, sm);
                }
            }
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }
}

/// This struct describes a standard data computation:
/// - which standard datas are read,
/// - which standard data is computed,
/// - the function that performs the computation.
/// The function must have the following signature:
/// fn(
///     sm: *SurfaceMesh,
///     read_data_1: SurfaceMesh.CellData(...),
///     read_data_2: SurfaceMesh.CellData(...),
///     ...
///     computed_data: SurfaceMesh.CellData(...),
/// ) !void
const StdDataComputation = struct {
    reads: []const SurfaceMeshStdDataTag,
    computes: SurfaceMeshStdDataTag,
    func: *const anyopaque,

    fn ComputeFuncType(comptime self: *const StdDataComputation) type {
        const nbparams = self.reads.len + 3; // AppContext + SurfaceMesh + read datas + computed data
        var params: [nbparams]std.builtin.Type.Fn.Param = undefined;
        params[0] = .{ .is_generic = false, .is_noalias = false, .type = *AppContext };
        params[1] = .{ .is_generic = false, .is_noalias = false, .type = *SurfaceMesh };
        inline for (self.reads, 0..self.reads.len) |read_tag, i| {
            params[i + 2] = .{
                .is_generic = false,
                .is_noalias = false,
                .type = @typeInfo(@FieldType(SurfaceMeshStore.SurfaceMeshStdDatas, @tagName(read_tag))).optional.child,
            };
        }
        params[nbparams - 1] = .{
            .is_generic = false,
            .is_noalias = false,
            .type = @typeInfo(@FieldType(SurfaceMeshStore.SurfaceMeshStdDatas, @tagName(self.computes))).optional.child,
        };
        return @Type(.{ .@"fn" = .{
            .calling_convention = .auto,
            .is_generic = false,
            .is_var_args = false,
            .return_type = anyerror!void,
            .params = &params,
        } });
    }

    // actually calls the computation function with the right arguments
    // taken from the StdDatas of the given SurfaceMesh.
    pub fn compute(comptime self: *const StdDataComputation, app_ctx: *AppContext, sm: *SurfaceMesh) void {
        const info = app_ctx.surface_mesh_store.surfaceMeshInfo(sm);
        const func: *const self.ComputeFuncType() = @ptrCast(@alignCast(self.func));
        var args: std.meta.ArgsTuple(self.ComputeFuncType()) = undefined;
        args[0] = app_ctx;
        args[1] = sm;
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
/// (e.g. vertex normal depends on face normal) and the "Update outdated std datas" button of the SurfaceMeshStore
/// computes them in the order of declaration.
pub const std_data_computations: []const StdDataComputation = &.{
    .{
        .reads = &.{.vertex_position},
        .computes = .corner_angle,
        .func = &computeCornerAngles,
    },
    .{
        .reads = &.{.vertex_position},
        .computes = .halfedge_cotan_weight,
        .func = &computeHalfedgeCotanWeights,
    },
    .{
        .reads = &.{.vertex_position},
        .computes = .face_area,
        .func = &computeFaceAreas,
    },
    .{
        .reads = &.{.vertex_position},
        .computes = .face_normal,
        .func = &computeFaceNormals,
    },
    .{
        .reads = &.{.vertex_position},
        .computes = .edge_length,
        .func = &computeEdgeLengths,
    },
    .{
        .reads = &.{ .vertex_position, .face_normal },
        .computes = .edge_dihedral_angle,
        .func = &computeEdgeDihedralAngles,
    },
    .{
        .reads = &.{.face_area},
        .computes = .vertex_area,
        .func = &computeVertexAreas,
    },
    .{
        .reads = &.{ .corner_angle, .face_normal },
        .computes = .vertex_normal,
        .func = &computeVertexNormals,
    },
    .{
        .reads = &.{ .vertex_position, .vertex_normal },
        .computes = .vertex_tangent_basis,
        .func = &computeVertexTangentBases,
    },
};

pub fn dataComputableAndUpToDate(
    sms: *SurfaceMeshStore,
    sm: *SurfaceMesh,
    comptime tag: SurfaceMeshStdDataTag,
) struct { bool, bool } {
    const info = sms.surfaceMeshInfo(sm);
    inline for (std_data_computations) |comp| {
        if (comp.computes == tag) {
            // found a computation for this data
            const computes_data = @field(info.std_datas, @tagName(comp.computes));
            if (computes_data == null) {
                return .{ false, false }; // computed data is not present in mesh info, so not computable nor up-to-date
            }
            var upToDate = true;
            const computes_last_update = sms.dataLastUpdate(computes_data.?.gen());
            inline for (comp.reads) |reads_tag| {
                const reads_data = @field(info.std_datas, @tagName(reads_tag));
                if (reads_data == null) {
                    return .{ false, false }; // a read data is not present in mesh info, so not computable nor up-to-date
                }
                // the computed data is up-to-date only if the last update of the computed data is after the last update of all read data
                // and all read data are themselves up-to-date (recursive call)
                const reads_last_update = sms.dataLastUpdate(reads_data.?.gen());
                if (computes_last_update == null or reads_last_update == null or computes_last_update.?.order(reads_last_update.?) == .lt) {
                    upToDate = false;
                } else {
                    _, upToDate = dataComputableAndUpToDate(sms, sm, reads_tag);
                }
                if (!upToDate) break;
            }
            return .{ true, upToDate };
        }
    }
    return .{ true, true }; // no computation found for this data, so always computable & up-to-date (end of recursion)
}

fn computeCornerAngles(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    corner_angle: SurfaceMesh.CellData(.corner, f32),
) !void {
    try angle.computeCornerAngles(app_ctx, sm, vertex_position, corner_angle);
    app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .corner, f32, corner_angle);
}

fn computeHalfedgeCotanWeights(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
) !void {
    try laplacian.computeHalfedgeCotanWeights(app_ctx, sm, vertex_position, halfedge_cotan_weight);
    app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .halfedge, f32, halfedge_cotan_weight);
}

fn computeEdgeLengths(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    edge_length: SurfaceMesh.CellData(.edge, f32),
) !void {
    try length.computeEdgeLengths(app_ctx, sm, vertex_position, edge_length);
    app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .edge, f32, edge_length);
}

fn computeEdgeDihedralAngles(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
) !void {
    var timer = try std.time.Timer.start();
    try angle.computeEdgeDihedralAngles(app_ctx, sm, vertex_position, face_normal, edge_dihedral_angle);
    const elapsed: f64 = @floatFromInt(timer.read());
    zgp_log.info("Edge dihedral angles computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
    app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .edge, f32, edge_dihedral_angle);
}

fn computeFaceAreas(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
) !void {
    try area.computeFaceAreas(app_ctx, sm, vertex_position, face_area);
    app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .face, f32, face_area);
}

fn computeFaceNormals(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
) !void {
    var timer = try std.time.Timer.start();
    try normal.computeFaceNormals(app_ctx, sm, vertex_position, face_normal);
    const elapsed: f64 = @floatFromInt(timer.read());
    zgp_log.info("Face normals computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
    app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .face, Vec3f, face_normal);
}

fn computeVertexAreas(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    face_area: SurfaceMesh.CellData(.face, f32),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
) !void {
    try area.computeVertexAreas(app_ctx, sm, face_area, vertex_area);
    app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_area);
}

fn computeVertexNormals(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
) !void {
    var timer = try std.time.Timer.start();
    try normal.computeVertexNormals(app_ctx, sm, corner_angle, face_normal, vertex_normal);
    const elapsed: f64 = @floatFromInt(timer.read());
    zgp_log.info("Vertex normals computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
    app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, vertex_normal);
}

fn computeVertexTangentBases(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
) !void {
    try tangentBasis.computeVertexTangentBases(app_ctx, sm, vertex_position, vertex_normal, vertex_tangent_basis);
    app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, [2]Vec3f, vertex_tangent_basis);
}
