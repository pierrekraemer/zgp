const SurfaceMeshProcessing = @This();

const std = @import("std");
const builtin = @import("builtin");

const imgui_utils = @import("../utils/imgui.zig");

const zgp = @import("../main.zig");
const c = zgp.c;

const Module = @import("Module.zig");
const ModelsRegistry = @import("../models/ModelsRegistry.zig");
const SurfaceMesh = ModelsRegistry.SurfaceMesh;
const SurfaceMeshStdData = ModelsRegistry.SurfaceMeshStdData;
const SurfaceMeshStdDatas = ModelsRegistry.SurfaceMeshStdDatas;
const SurfaceMeshStdDataTag = ModelsRegistry.SurfaceMeshStdDataTag;

const vec = @import("../geometry/vec.zig");
const Vec3 = vec.Vec3;

const angle = @import("../models/surface/angle.zig");
const area = @import("../models/surface/area.zig");
const curvature = @import("../models/surface/curvature.zig");
const length = @import("../models/surface/length.zig");
const normal = @import("../models/surface/normal.zig");
const subdivision = @import("../models/surface/subdivision.zig");
const remeshing = @import("../models/surface/remeshing.zig");

/// Return a Module interface for the SurfaceMeshProcessing.
pub fn module(smp: *SurfaceMeshProcessing) Module {
    return Module.init(smp);
}

/// Part of the Module interface.
/// Return the name of the module.
pub fn name(_: *SurfaceMeshProcessing) []const u8 {
    return "Surface Mesh Processing";
}

fn cutAllEdges(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
) !void {
    try subdivision.cutAllEdges(sm, vertex_position);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_position);
    zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
    if (builtin.mode == .Debug) {
        try sm.checkIntegrity();
    }
}

fn triangulateFaces(sm: *SurfaceMesh) !void {
    try subdivision.triangulateFaces(sm);
    zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
    if (builtin.mode == .Debug) {
        try sm.checkIntegrity();
    }
}

fn remesh(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
    edge_length: SurfaceMesh.CellData(.edge, f32),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3),
    edge_length_factor: f32,
) !void {
    try remeshing.pliantRemeshing(
        sm,
        vertex_position,
        corner_angle,
        face_area,
        face_normal,
        edge_length,
        edge_dihedral_angle,
        vertex_area,
        vertex_normal,
        edge_length_factor,
    );
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_position);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .corner, f32, corner_angle);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .face, f32, face_area);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .face, Vec3, face_normal);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .edge, f32, edge_length);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .edge, f32, edge_dihedral_angle);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_area);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_normal);
    zgp.models_registry.surfaceMeshConnectivityUpdated(sm);
    if (builtin.mode == .Debug) {
        try sm.checkIntegrity();
    }
}

fn computeCornerAngles(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    corner_angle: SurfaceMesh.CellData(.corner, f32),
) !void {
    try angle.computeCornerAngles(sm, vertex_position, corner_angle);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .corner, f32, corner_angle);
}

fn computeEdgeLengths(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    edge_length: SurfaceMesh.CellData(.edge, f32),
) !void {
    try length.computeEdgeLengths(sm, vertex_position, edge_length);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .edge, f32, edge_length);
}

fn computeEdgeDihedralAngles(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
) !void {
    try angle.computeEdgeDihedralAngles(sm, vertex_position, face_normal, edge_dihedral_angle);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .edge, f32, edge_dihedral_angle);
}

fn computeFaceAreas(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face_area: SurfaceMesh.CellData(.face, f32),
) !void {
    try area.computeFaceAreas(sm, vertex_position, face_area);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .face, f32, face_area);
}

fn computeFaceNormals(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
) !void {
    try normal.computeFaceNormals(sm, vertex_position, face_normal);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .face, Vec3, face_normal);
}

fn computeVertexAreas(
    sm: *SurfaceMesh,
    face_area: SurfaceMesh.CellData(.face, f32),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
) !void {
    try area.computeVertexAreas(sm, face_area, vertex_area);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_area);
}

fn computeVertexNormals(
    sm: *SurfaceMesh,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3),
) !void {
    try normal.computeVertexNormals(sm, corner_angle, face_normal, vertex_normal);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, Vec3, vertex_normal);
}

fn computeVertexGaussianCurvatures(
    sm: *SurfaceMesh,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    vertex_gaussian_curvature: SurfaceMesh.CellData(.vertex, f32),
) !void {
    try curvature.computeVertexGaussianCurvatures(sm, corner_angle, vertex_gaussian_curvature);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_gaussian_curvature);
}

fn computeVertexMeanCurvatures(
    sm: *SurfaceMesh,
    edge_length: SurfaceMesh.CellData(.edge, f32),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
    vertex_mean_curvature: SurfaceMesh.CellData(.vertex, f32),
) !void {
    try curvature.computeVertexMeanCurvatures(sm, edge_length, edge_dihedral_angle, vertex_mean_curvature);
    zgp.models_registry.surfaceMeshDataUpdated(sm, .vertex, f32, vertex_mean_curvature);
}

const StdDataComputation = struct {
    reads: []const SurfaceMeshStdDataTag,
    computes: SurfaceMeshStdDataTag,
    func: *const anyopaque,

    fn compute(comptime self: *const StdDataComputation, sm: *SurfaceMesh) void {
        const info = zgp.models_registry.surfaceMeshInfo(sm);
        const func: *const self.ComputeFuncType() = @ptrCast(@alignCast(self.func));
        var args: self.ComputeFuncArgsType() = undefined;
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
    fn ComputesCellType(comptime self: *const StdDataComputation) SurfaceMesh.CellType {
        return @typeInfo(@FieldType(SurfaceMeshStdDatas, @tagName(self.computes))).optional.child.CellType;
    }
    fn ComputesDataType(comptime self: *const StdDataComputation) type {
        return @typeInfo(@FieldType(SurfaceMeshStdDatas, @tagName(self.computes))).optional.child.DataType;
    }
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
    fn ComputeFuncArgsType(comptime self: *const StdDataComputation) type {
        const nbparams = self.reads.len + 2; // SurfaceMesh + read datas + computed data
        var args_fields: [nbparams]std.builtin.Type.StructField = undefined;
        args_fields[0] = .{
            .name = "0",
            .type = *SurfaceMesh,
            .alignment = @alignOf(*SurfaceMesh),
            .default_value_ptr = null,
            .is_comptime = false,
        };
        inline for (self.reads, 0..self.reads.len) |read_tag, i| {
            args_fields[i + 1] = .{
                .name = std.fmt.comptimePrint("{d}", .{i + 1}),
                .type = @typeInfo(@FieldType(SurfaceMeshStdDatas, @tagName(read_tag))).optional.child,
                .alignment = @alignOf(@FieldType(SurfaceMeshStdDatas, @tagName(read_tag))),
                .default_value_ptr = null,
                .is_comptime = false,
            };
        }
        args_fields[nbparams - 1] = .{
            .name = std.fmt.comptimePrint("{d}", .{nbparams - 1}),
            .type = @typeInfo(@FieldType(SurfaceMeshStdDatas, @tagName(self.computes))).optional.child,
            .alignment = @alignOf(@FieldType(SurfaceMeshStdDatas, @tagName(self.computes))),
            .default_value_ptr = null,
            .is_comptime = false,
        };
        return @Type(.{ .@"struct" = .{
            .fields = &args_fields,
            .decls = &.{},
            .is_tuple = true,
            .layout = .auto,
        } });
    }
};

const std_data_computations: []const StdDataComputation = &.{
    .{
        .reads = &.{.vertex_position},
        .computes = .corner_angle,
        .func = &computeCornerAngles,
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

pub fn uiPanel(_: *SurfaceMeshProcessing) void {
    const UiData = struct {
        var edge_length_factor: f32 = 1.0;
        var button_text_buf: [64]u8 = undefined;
        var new_data_name: [32]u8 = undefined;
    };

    const mr = &zgp.models_registry;

    const item_spacing = c.ImGui_GetStyle().*.ItemSpacing.x;
    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - item_spacing * 2);

    if (mr.selected_surface_mesh) |sm| {
        const info = mr.surfaceMeshInfo(sm);

        c.ImGui_SeparatorText("Mesh Operations");

        {
            const disabled = info.std_data.vertex_position == null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Cut all edges", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                cutAllEdges(sm, info.std_data.vertex_position.?) catch |err| {
                    std.debug.print("Error cutting all edges: {}\n", .{err});
                };
            }
            imgui_utils.tooltip(
                \\ Read:
                \\ - vertex_position
                \\ Update connectivity
            );
            if (disabled) {
                c.ImGui_EndDisabled();
            }
        }

        {
            if (c.ImGui_ButtonEx("Triangulate faces", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                triangulateFaces(sm) catch |err| {
                    std.debug.print("Error triangulating faces: {}\n", .{err});
                };
            }
            imgui_utils.tooltip("Update connectivity");
        }

        {
            c.ImGui_Text("Edge length factor");
            c.ImGui_PushID("Edge length factor");
            _ = c.ImGui_SliderFloatEx("", &UiData.edge_length_factor, 0.1, 10.0, "%.2f", c.ImGuiSliderFlags_Logarithmic);
            c.ImGui_PopID();
            const disabled = info.std_data.vertex_position == null or
                info.std_data.corner_angle == null or
                info.std_data.face_area == null or
                info.std_data.face_normal == null or
                info.std_data.edge_length == null or
                info.std_data.edge_dihedral_angle == null or
                info.std_data.vertex_area == null or
                info.std_data.vertex_normal == null;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Remesh", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                remesh(
                    sm,
                    info.std_data.vertex_position.?,
                    info.std_data.corner_angle.?,
                    info.std_data.face_area.?,
                    info.std_data.face_normal.?,
                    info.std_data.edge_length.?,
                    info.std_data.edge_dihedral_angle.?,
                    info.std_data.vertex_area.?,
                    info.std_data.vertex_normal.?,
                    UiData.edge_length_factor,
                ) catch |err| {
                    std.debug.print("Error remeshing: {}\n", .{err});
                };
            }
            imgui_utils.tooltip(
                \\ Read:
                \\ - vertex_position
                \\ - corner_angle
                \\ - face_area
                \\ - face_normal
                \\ - edge_length
                \\ - edge_dihedral_angle
                \\ - vertex_area
                \\ - vertex_normal
                \\ Write:
                \\ - vertex_position
                \\ - corner_angle
                \\ - face_area
                \\ - face_normal
                \\ - edge_length
                \\ - edge_dihedral_angle
                \\ - vertex_area
                \\ - vertex_normal
                \\ Update connectivity
            );
            if (disabled) {
                c.ImGui_EndDisabled();
            }
        }

        c.ImGui_SeparatorText("Geometry Computations");

        inline for (std_data_computations) |dc| {
            var disabled = false;
            var outdated = false;
            const computes_data = @field(info.std_data, @tagName(dc.computes));
            if (computes_data == null) {
                disabled = true;
            }
            const computes_last_update = if (computes_data) |d| mr.dataLastUpdate(d.gen()) else null;
            if (computes_last_update == null) {
                outdated = true;
            }
            const reads_tags = dc.reads;
            inline for (reads_tags) |reads_tag| {
                const reads_data = @field(info.std_data, @tagName(reads_tag));
                if (reads_data == null) {
                    disabled = true;
                }
                const reads_last_update = if (reads_data) |d| mr.dataLastUpdate(d.gen()) else null;
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
            if (c.ImGui_ButtonEx(@tagName(dc.computes), c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x - 30.0, .y = 0.0 })) {
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
            c.ImGui_SameLine();
            c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + @max(0.0, c.ImGui_GetContentRegionAvail().x - 20.0));
            const button_text = std.fmt.bufPrintZ(
                &UiData.button_text_buf,
                "Add {s} data ({s})",
                .{ @tagName(dc.ComputesCellType()), @typeName(dc.ComputesDataType()) },
            ) catch "";
            _ = std.fmt.bufPrintZ(&UiData.new_data_name, @tagName(dc.computes), .{}) catch "";
            if (imgui_utils.addDataButton(@tagName(dc.computes), button_text, &UiData.new_data_name)) {
                const maybe_data = sm.addData(dc.ComputesCellType(), dc.ComputesDataType(), &UiData.new_data_name);
                if (maybe_data) |data| {
                    if (computes_data == null) {
                        mr.setSurfaceMeshStdData(sm, @unionInit(SurfaceMeshStdData, @tagName(dc.computes), data));
                    }
                } else |err| {
                    std.debug.print("Error adding {s} {s} data: {}\n", .{ @tagName(dc.ComputesCellType()), @typeName(dc.ComputesDataType()), err });
                }
                UiData.new_data_name[0] = 0;
            }
        }
    } else {
        c.ImGui_Text("No Surface Mesh selected");
    }

    c.ImGui_PopItemWidth();
}
