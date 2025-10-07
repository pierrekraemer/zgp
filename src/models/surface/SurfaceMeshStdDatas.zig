const SurfaceMeshStdDatas = @This();

const std = @import("std");

const zgp = @import("../../main.zig");
const zgp_log = std.log.scoped(.zgp);

const SurfaceMesh = @import("SurfaceMesh.zig");

const types_utils = @import("../../utils/types.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const angle = @import("angle.zig");
const area = @import("area.zig");
const curvature = @import("curvature.zig");
const laplacian = @import("laplacian.zig");
const length = @import("length.zig");
const normal = @import("normal.zig");
const tangentBasis = @import("tangentBasis.zig");

/// Standard SurfaceMesh data name & types.
corner_angle: ?SurfaceMesh.CellData(.corner, f32) = null,
halfedge_cotan_weight: ?SurfaceMesh.CellData(.halfedge, f32) = null,
vertex_position: ?SurfaceMesh.CellData(.vertex, Vec3f) = null,
vertex_area: ?SurfaceMesh.CellData(.vertex, f32) = null,
vertex_normal: ?SurfaceMesh.CellData(.vertex, Vec3f) = null,
vertex_tangent_basis: ?SurfaceMesh.CellData(.vertex, [2]Vec3f) = null,
vertex_gaussian_curvature: ?SurfaceMesh.CellData(.vertex, f32) = null,
vertex_mean_curvature: ?SurfaceMesh.CellData(.vertex, f32) = null,
edge_length: ?SurfaceMesh.CellData(.edge, f32) = null,
edge_dihedral_angle: ?SurfaceMesh.CellData(.edge, f32) = null,
face_area: ?SurfaceMesh.CellData(.face, f32) = null,
face_normal: ?SurfaceMesh.CellData(.face, Vec3f) = null,

/// This tagged union is generated from the SurfaceMeshStdDatas struct and allows to easily provide a single
/// data entry to the setSurfaceMeshStdData function (in SurfaceMeshStore)
pub const SurfaceMeshStdData = types_utils.UnionFromStruct(SurfaceMeshStdDatas);
pub const SurfaceMeshStdDataTag = std.meta.Tag(SurfaceMeshStdData);

/// This struct describes a standard data computation:
/// - which standard datas are read,
/// - which standard data is computed,
/// - the function that performs the computation.
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

    // get the standard datas to read and the one to compute from the SurfaceMeshStdDatas of the given SurfaceMesh
    pub fn compute(comptime self: *const StdDataComputation, sm: *SurfaceMesh) void {
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

pub fn dataComputableAndUpToDate(
    sm: *SurfaceMesh,
    comptime tag: SurfaceMeshStdDataTag,
) struct { bool, bool } {
    const sms = &zgp.surface_mesh_store;
    const info = sms.surfaceMeshInfo(sm);
    inline for (std_data_computations) |comp| {
        if (comp.computes == tag) {
            // found a computation for this data
            const computes_data = @field(info.std_data, @tagName(comp.computes));
            if (computes_data == null) {
                return .{ false, false }; // computed data is not present in mesh info, so not computable nor up-to-date
            }
            var upToDate = true;
            const computes_last_update = sms.dataLastUpdate(computes_data.?.gen());
            inline for (comp.reads) |reads_tag| {
                const reads_data = @field(info.std_data, @tagName(reads_tag));
                if (reads_data == null) {
                    return .{ false, false }; // a read data is not present in mesh info, so not computable nor up-to-date
                }
                // the computed data is up-to-date only if the last update of the computed data is after the last update of all read data
                // and all read data are themselves up-to-date (recursive call)
                const reads_last_update = sms.dataLastUpdate(reads_data.?.gen());
                if (computes_last_update == null or reads_last_update == null or computes_last_update.?.order(reads_last_update.?) == .lt) {
                    upToDate = false;
                } else {
                    _, upToDate = dataComputableAndUpToDate(sm, reads_tag);
                }
                if (!upToDate) break;
            }
            return .{ true, upToDate };
        }
    }
    return .{ true, true }; // no computation found for this data, so always computable & up-to-date (end of recursion)
}

fn computeCornerAngles(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    corner_angle: SurfaceMesh.CellData(.corner, f32),
) !void {
    var timer = try std.time.Timer.start();
    try angle.computeCornerAngles(sm, vertex_position, corner_angle);
    const elapsed: f64 = @floatFromInt(timer.read());
    zgp_log.info("Corner angles computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
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

fn computeVertexTangentBases(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_tangent_basis: SurfaceMesh.CellData(.vertex, [2]Vec3f),
) !void {
    try tangentBasis.computeVertexTangentBases(sm, vertex_position, vertex_normal, vertex_tangent_basis);
    zgp.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, [2]Vec3f, vertex_tangent_basis);
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
