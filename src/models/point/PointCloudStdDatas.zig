const PointCloudStdDatas = @This();

const std = @import("std");

const zgp = @import("../../main.zig");
const zgp_log = std.log.scoped(.zgp);

const PointCloud = @import("PointCloud.zig");

const types_utils = @import("../../utils/types.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

/// Standard PointCloud data name & types.
position: ?PointCloud.CellData(Vec3f) = null,
normal: ?PointCloud.CellData(Vec3f) = null,

/// This tagged union is generated from the PointCloudStdDatas struct and allows to easily provide a single
/// data entry to the setPointCloudStdData function (in PointCloudStore)
pub const PointCloudStdData = types_utils.UnionFromStruct(PointCloudStdDatas);
pub const PointCloudStdDataTag = std.meta.Tag(PointCloudStdData);

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

    // fn ComputesDataType(comptime self: *const StdDataComputation) type {
    //     return @typeInfo(@FieldType(PointCloudStdDatas, @tagName(self.computes))).optional.child.DataType;
    // }
    fn ComputeFuncType(comptime self: *const StdDataComputation) type {
        const nbparams = self.reads.len + 2; // PointCloud + read datas + computed data
        var params: [nbparams]std.builtin.Type.Fn.Param = undefined;
        params[0] = .{
            .is_generic = false,
            .is_noalias = false,
            .type = *PointCloud,
        };
        inline for (self.reads, 0..self.reads.len) |read_tag, i| {
            params[i + 1] = .{
                .is_generic = false,
                .is_noalias = false,
                .type = @typeInfo(@FieldType(PointCloudStdDatas, @tagName(read_tag))).optional.child,
            };
        }
        params[nbparams - 1] = .{
            .is_generic = false,
            .is_noalias = false,
            .type = @typeInfo(@FieldType(PointCloudStdDatas, @tagName(self.computes))).optional.child,
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
    pub fn compute(comptime self: *const StdDataComputation, pc: *PointCloud) void {
        const info = zgp.point_cloud_store.pointCloudInfo(pc);
        const func: *const self.ComputeFuncType() = @ptrCast(@alignCast(self.func));
        var args: std.meta.ArgsTuple(self.ComputeFuncType()) = undefined;
        args[0] = pc;
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
/// (e.g. vertex normal depends on face normal) and the "Update outdated std datas" button of the PointCloudStore
/// computes them in the order of declaration.
pub const std_data_computations: []const StdDataComputation = &.{};

pub fn dataComputableAndUpToDate(
    pc: *PointCloud,
    comptime tag: PointCloudStdDataTag,
) struct { bool, bool } {
    const pcs = &zgp.point_cloud_store;
    const info = pcs.pointCloudInfo(pc);
    inline for (std_data_computations) |comp| {
        if (comp.computes == tag) {
            // found a computation for this data
            const computes_data = @field(info.std_data, @tagName(comp.computes));
            if (computes_data == null) {
                return .{ false, false }; // computed data is not present in mesh info, so not computable nor up-to-date
            }
            var upToDate = true;
            const computes_last_update = pcs.dataLastUpdate(computes_data.?.gen());
            inline for (comp.reads) |reads_tag| {
                const reads_data = @field(info.std_data, @tagName(reads_tag));
                if (reads_data == null) {
                    return .{ false, false }; // a read data is not present in mesh info, so not computable nor up-to-date
                }
                // the computed data is up-to-date only if the last update of the computed data is after the last update of all read data
                // and all read data are themselves up-to-date (recursive call)
                const reads_last_update = pcs.dataLastUpdate(reads_data.?.gen());
                if (computes_last_update == null or reads_last_update == null or computes_last_update.?.order(reads_last_update.?) == .lt) {
                    upToDate = false;
                } else {
                    _, upToDate = dataComputableAndUpToDate(pc, reads_tag);
                }
                if (!upToDate) break;
            }
            return .{ true, upToDate };
        }
    }
    return .{ true, true }; // no computation found for this data, so always computable & up-to-date (end of recursion)
}
