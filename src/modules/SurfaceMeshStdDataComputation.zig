const SurfaceMeshStdDataComputation = @This();

const std = @import("std");

const imgui_utils = @import("../utils/imgui.zig");

const zgp = @import("../main.zig");
const c = zgp.c;

const Module = @import("Module.zig");
const SurfaceMeshStore = @import("../models/SurfaceMeshStore.zig");
const SurfaceMesh = SurfaceMeshStore.SurfaceMesh;
const SurfaceMeshStdDatas = SurfaceMeshStore.SurfaceMeshStdDatas;
const SurfaceMeshStdDataTag = SurfaceMeshStore.SurfaceMeshStdDataTag;

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const angle = @import("../models/surface/angle.zig");
const area = @import("../models/surface/area.zig");
const curvature = @import("../models/surface/curvature.zig");
const laplacian = @import("../models/surface/laplacian.zig");
const length = @import("../models/surface/length.zig");
const normal = @import("../models/surface/normal.zig");

pub fn init() !SurfaceMeshStdDataComputation {
    return .{};
}

pub fn deinit(_: *SurfaceMeshStdDataComputation) void {}

/// Return a Module interface for the SurfaceMeshStdDataComputation.
pub fn module(smsdc: *SurfaceMeshStdDataComputation) Module {
    return Module.init(smsdc);
}

/// Part of the Module interface.
/// Return the name of the module.
pub fn name(_: *SurfaceMeshStdDataComputation) []const u8 {
    return "Surface Mesh Std Data Computation";
}

fn computeCornerAngles(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    corner_angle: SurfaceMesh.CellData(.corner, f32),
) !void {
    try angle.computeCornerAngles(sm, vertex_position, corner_angle);
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .corner, f32, corner_angle);
}

fn computeHalfedgeCotanWeights(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
) !void {
    try laplacian.computeHalfedgeCotanWeights(sm, vertex_position, halfedge_cotan_weight);
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .halfedge, f32, halfedge_cotan_weight);
}

fn computeEdgeLengths(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    edge_length: SurfaceMesh.CellData(.edge, f32),
) !void {
    try length.computeEdgeLengths(sm, vertex_position, edge_length);
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .edge, f32, edge_length);
}

fn computeEdgeDihedralAngles(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
) !void {
    try angle.computeEdgeDihedralAngles(sm, vertex_position, face_normal, edge_dihedral_angle);
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .edge, f32, edge_dihedral_angle);
}

fn computeFaceAreas(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
) !void {
    try area.computeFaceAreas(sm, vertex_position, face_area);
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .face, f32, face_area);
}

fn computeFaceNormals(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
) !void {
    try normal.computeFaceNormals(sm, vertex_position, face_normal);
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .face, Vec3f, face_normal);
}

fn computeVertexAreas(
    sm: *SurfaceMesh,
    face_area: SurfaceMesh.CellData(.face, f32),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
) !void {
    try area.computeVertexAreas(sm, face_area, vertex_area);
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_area);
}

fn computeVertexNormals(
    sm: *SurfaceMesh,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
) !void {
    try normal.computeVertexNormals(sm, corner_angle, face_normal, vertex_normal);
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, Vec3f, vertex_normal);
}

fn computeVertexGaussianCurvatures(
    sm: *SurfaceMesh,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    vertex_gaussian_curvature: SurfaceMesh.CellData(.vertex, f32),
) !void {
    try curvature.computeVertexGaussianCurvatures(sm, corner_angle, vertex_gaussian_curvature);
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_gaussian_curvature);
}

fn computeVertexMeanCurvatures(
    sm: *SurfaceMesh,
    edge_length: SurfaceMesh.CellData(.edge, f32),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
    vertex_mean_curvature: SurfaceMesh.CellData(.vertex, f32),
) !void {
    try curvature.computeVertexMeanCurvatures(sm, edge_length, edge_dihedral_angle, vertex_mean_curvature);
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_mean_curvature);
}

const StdDataComputation = struct {
    reads: []const SurfaceMeshStdDataTag,
    computes: SurfaceMeshStdDataTag,
    func: *const anyopaque,

    // fn ComputesCellType(comptime self: *const StdDataComputation) SurfaceMesh.CellType {
    //     return @typeInfo(@FieldType(SurfaceMeshStdDatas, @tagName(self.computes))).optional.child.CellType;
    // }
    // fn ComputesDataType(comptime self: *const StdDataComputation) type {
    //     return @typeInfo(@FieldType(SurfaceMeshStdDatas, @tagName(self.computes))).optional.child.DataType;
    // }
    fn ComputeFuncType(comptime self: *const StdDataComputation) type {
        const nbparams = self.reads.len + 2; // SurfaceMesh + read datas + computed data
        var params: [nbparams]std.builtin.Type.Fn.Param = undefined;
        params[0] = .{
            .is_generic = false,
            .is_noalias = false,
            .type = *SurfaceMesh,
        };
        inline for (self.reads, 0..self.reads.len) |read_tag, i| {
            params[i + 1] = .{
                .is_generic = false,
                .is_noalias = false,
                .type = @typeInfo(@FieldType(SurfaceMeshStdDatas, @tagName(read_tag))).optional.child,
            };
        }
        params[nbparams - 1] = .{
            .is_generic = false,
            .is_noalias = false,
            .type = @typeInfo(@FieldType(SurfaceMeshStdDatas, @tagName(self.computes))).optional.child,
        };
        return @Type(.{ .@"fn" = .{
            .calling_convention = .auto,
            .is_generic = false,
            .is_var_args = false,
            .return_type = anyerror!void,
            .params = &params,
        } });
    }

    fn compute(comptime self: *const StdDataComputation, sm: *SurfaceMesh) void {
        const info = zgp.surface_mesh_store.surfaceMeshInfo(sm);
        const func: *const self.ComputeFuncType() = @ptrCast(@alignCast(self.func));
        var args: std.meta.ArgsTuple(self.ComputeFuncType()) = undefined;
        args[0] = sm;
        inline for (self.reads, 0..) |reads_tag, i| {
            args[i + 1] = @field(info.std_data, @tagName(reads_tag)).?;
        }
        args[self.reads.len + 1] = @field(info.std_data, @tagName(self.computes)).?;
        @call(
            .auto,
            func,
            args,
        ) catch |err| {
            std.debug.print("Error computing {s}: {}\n", .{ @tagName(self.computes), err });
        };
    }
};

/// Declaration of standard data computations.
/// The order of declaration matters: some computations depend on the result of previous ones
/// (e.g. vertex normal depends on face normal) and the "Update outdated std datas" button computes them
/// in the order of declaration.
const std_data_computations: []const StdDataComputation = &.{
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
        .reads = &.{.corner_angle},
        .computes = .vertex_gaussian_curvature,
        .func = &computeVertexGaussianCurvatures,
    },
    .{
        .reads = &.{ .edge_length, .edge_dihedral_angle },
        .computes = .vertex_mean_curvature,
        .func = &computeVertexMeanCurvatures,
    },
};

pub fn uiPanel(_: *SurfaceMeshStdDataComputation) void {
    const style = c.ImGui_GetStyle();

    const sms = &zgp.surface_mesh_store;

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (sms.selected_surface_mesh) |sm| {
        const info = sms.surfaceMeshInfo(sm);

        inline for (std_data_computations) |dc| {
            var disabled = false;
            var outdated = false;
            const computes_data = @field(info.std_data, @tagName(dc.computes));
            if (computes_data == null) {
                disabled = true;
            }
            const computes_last_update = if (computes_data) |d| sms.dataLastUpdate(d.gen()) else null;
            if (computes_last_update == null) {
                outdated = true;
            }
            const reads_tags = dc.reads;
            inline for (reads_tags) |reads_tag| {
                const reads_data = @field(info.std_data, @tagName(reads_tag));
                if (reads_data == null) {
                    disabled = true;
                }
                const reads_last_update = if (reads_data) |d| sms.dataLastUpdate(d.gen()) else null;
                if (computes_last_update == null or reads_last_update == null or computes_last_update.?.order(reads_last_update.?) == .lt) {
                    outdated = true;
                }
            }
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (outdated) {
                c.ImGui_PushStyleColor(c.ImGuiCol_Button, c.IM_COL32(255, 128, 128, 200));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonHovered, c.IM_COL32(255, 128, 128, 255));
                c.ImGui_PushStyleColor(c.ImGuiCol_ButtonActive, c.IM_COL32(255, 128, 128, 128));
            }
            if (c.ImGui_ButtonEx(@tagName(dc.computes), c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                dc.compute(sm);
            }
            if (outdated) {
                c.ImGui_PopStyleColorEx(3);
            }
            if (disabled) {
                c.ImGui_EndDisabled();
            }

            // TODO: generate tooltip from reads_tags & computes_tag
            // imgui_utils.tooltip(
            //     \\ Read:
            //     \\ - vertex_position
            //     \\ Write:
            //     \\ - corner_angle
            // );
        }
        c.ImGui_Separator();
        if (c.ImGui_ButtonEx("Update outdated std datas", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            inline for (std_data_computations) |dc| {
                var disabled = false;
                var outdated = false;
                const computes_data = @field(info.std_data, @tagName(dc.computes));
                if (computes_data == null) {
                    disabled = true;
                }
                const computes_last_update = if (computes_data) |d| sms.dataLastUpdate(d.gen()) else null;
                if (computes_last_update == null) {
                    outdated = true;
                }
                const reads_tags = dc.reads;
                inline for (reads_tags) |reads_tag| {
                    const reads_data = @field(info.std_data, @tagName(reads_tag));
                    if (reads_data == null) {
                        disabled = true;
                    }
                    const reads_last_update = if (reads_data) |d| sms.dataLastUpdate(d.gen()) else null;
                    if (computes_last_update == null or reads_last_update == null or computes_last_update.?.order(reads_last_update.?) == .lt) {
                        outdated = true;
                    }
                }
                if (!disabled and outdated) {
                    dc.compute(sm);
                }
            }
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }
}
