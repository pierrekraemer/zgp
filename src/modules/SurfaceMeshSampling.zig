const SurfaceMeshSampling = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("c");

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfacePoint = @import("../models/surface/SurfacePoint.zig");
const PointCloud = @import("../models/point/PointCloud.zig");

const Data = @import("../utils/data.zig").Data;
const DataGen = @import("../utils/data.zig").DataGen;

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const bvh = @import("../geometry/bvh.zig");

const sampling = @import("../models/surface/sampling.zig");

const SamplingData = struct {
    app_ctx: *AppContext,

    samples: *PointCloud = undefined,
    position: PointCloud.CellData(Vec3f) = undefined,
    surface_point: PointCloud.CellData(SurfacePoint) = undefined,
    initialized: bool = false,

    fn init(sd: *SamplingData, pointcloud_name: []const u8) !void {
        if (!sd.initialized) {
            sd.samples = try sd.app_ctx.point_cloud_store.createPointCloud(pointcloud_name);
            sd.surface_point = try sd.samples.addData(SurfacePoint, "surface_point");
            sd.position = try sd.samples.addData(Vec3f, "position");
            sd.app_ctx.point_cloud_store.setPointCloudStdData(sd.samples, .{ .position = sd.position });
        } else {
            sd.samples.clearRetainingCapacity();
        }
        sd.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(sd.samples);
        sd.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples, Vec3f, sd.position);
        sd.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples, SurfacePoint, sd.surface_point);
        sd.initialized = true;
    }

    // do not destroy the PointCloud here
    // this function is only called after having being notified of the PointCloud destruction
    fn deinit(sd: *SamplingData) void {
        sd.samples = undefined;
        sd.position = undefined;
        sd.surface_point = undefined;
        sd.initialized = false;
    }

    fn pushDataToPointCloud(
        sd: *SamplingData,
        comptime T: type,
        comptime cell_type: SurfaceMesh.CellType,
        src_data: SurfaceMesh.CellData(cell_type, T),
    ) !void {
        assert(sd.initialized);

        const dst_data = try sd.samples.getOrAddData(T, src_data.name());
        var point_it = sd.samples.pointIterator();
        while (point_it.next()) |point| {
            dst_data.valuePtr(point).* = sd.surface_point.value(point).readData(T, cell_type, src_data);
        }
        sd.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples, T, dst_data);
        sd.app_ctx.requestRedraw();
    }
};

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Sampling",
    .supported_models = .{ .surface_mesh = true },
    .vtable = &.{
        .pointCloudDestroyed = pointCloudDestroyed,
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .rightPanel = rightPanel,
    },
},
surface_meshes_data: std.AutoHashMapUnmanaged(*SurfaceMesh, SamplingData) = .empty,

pub fn init(app_ctx: *AppContext) SurfaceMeshSampling {
    return .{
        .app_ctx = app_ctx,
    };
}

pub fn deinit(sms: *SurfaceMeshSampling) void {
    sms.surface_meshes_data.deinit(sms.app_ctx.allocator);
}

/// Part of the Module interface.
/// Deinit the SamplingData associated to the destroyed PointCloud.
pub fn pointCloudDestroyed(m: *Module, point_cloud: *PointCloud) void {
    const sms: *SurfaceMeshSampling = @alignCast(@fieldParentPtr("module", m));
    var it = sms.surface_meshes_data.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.samples == point_cloud) {
            entry.value_ptr.deinit();
            break;
        }
    }
}

/// Part of the Module interface.
/// Create and store a SamplingData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const sms: *SurfaceMeshSampling = @alignCast(@fieldParentPtr("module", m));
    sms.surface_meshes_data.put(sms.app_ctx.allocator, surface_mesh, .{ .app_ctx = sms.app_ctx }) catch |err| {
        std.debug.print("Failed to store SamplingData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Remove the SamplingData associated to the destroyed SurfaceMesh
/// and remove the associated SurfacePoint data from the PointCloud (if it exists).
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const sms: *SurfaceMeshSampling = @alignCast(@fieldParentPtr("module", m));
    const sd = sms.surface_meshes_data.getPtr(surface_mesh).?;
    if (sd.initialized) {
        // the SurfacePoint data is no longer valid after the SurfaceMesh is destroyed
        sd.samples.removeData(SurfacePoint, sd.surface_point);
    }
    _ = sms.surface_meshes_data.remove(surface_mesh);
}

fn uniformSampling(
    sms: *SurfaceMeshSampling,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_area: SurfaceMesh.CellData(.face, f32),
    nb_points: usize,
    pointcloud_name: []const u8,
) !void {
    const t = std.Io.Timestamp.now(sms.app_ctx.io, .real);

    const sd = sms.surface_meshes_data.getPtr(sm).?;
    try sd.init(pointcloud_name);

    try sampling.uniformlySamplePointsOnSurface(
        sms.app_ctx,
        sm,
        vertex_position,
        face_area,
        sd.samples,
        sd.position,
        sd.surface_point,
        nb_points,
    );
    sms.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(sd.samples);
    sms.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples, Vec3f, sd.position);
    sms.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples, SurfacePoint, sd.surface_point);

    sms.app_ctx.requestRedraw();

    const elapsed: f64 = @floatFromInt(std.Io.Timestamp.untilNow(t, sms.app_ctx.io, .real).nanoseconds);
    zgp_log.info("Uniform sampling computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
}

fn poissonDiskSampling(
    sms: *SurfaceMeshSampling,
    sm: *SurfaceMesh,
    sm_bvh: *bvh.TrianglesBVH,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    poisson_radius: f32,
    pointcloud_name: []const u8,
) !void {
    const t = std.Io.Timestamp.now(sms.app_ctx.io, .real);

    const sd = sms.surface_meshes_data.getPtr(sm).?;
    try sd.init(pointcloud_name);

    try sampling.poissonDiskSamplePointsOnSurface(
        sms.app_ctx,
        sm,
        sm_bvh,
        vertex_position,
        face_normal,
        sd.samples,
        sd.position,
        sd.surface_point,
        poisson_radius,
    );
    sms.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(sd.samples);
    sms.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples, Vec3f, sd.position);
    sms.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples, SurfacePoint, sd.surface_point);

    sms.app_ctx.requestRedraw();

    const elapsed: f64 = @floatFromInt(std.Io.Timestamp.untilNow(t, sms.app_ctx.io, .real).nanoseconds);
    zgp_log.info("Poisson disk sampling computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
}

/// Part of the Module interface.
/// Show a UI panel to control the sampling of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const sms: *SurfaceMeshSampling = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &sms.app_ctx.surface_mesh_store;

    assert(sms.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = sms.app_ctx.selected_model.surface_mesh;

    const DataTypes = union(enum) { u32: u32, f32: f32, Vec3f: Vec3f };
    const DataTypesTag = std.meta.Tag(DataTypes);
    const UiData = struct {
        var nb_points: usize = 1000;
        var poisson_radius: f32 = 0.02;
        var pointcloud_name_buf: [32]u8 = @splat(0);
        var selected_surface_mesh_cell_type: SurfaceMesh.CellType = .vertex;
        var selected_data_type: DataTypesTag = .Vec3f;
        var selected_data_gen: ?*DataGen = null;
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    const info = sm_store.surfaceMeshInfo(sm);
    const sd = sms.surface_meshes_data.getPtr(sm).?;

    if (!sd.initialized) {
        c.ImGui_Text("Samples PointCloud name:");
        _ = c.ImGui_InputText("##Name", &UiData.pointcloud_name_buf, UiData.pointcloud_name_buf.len, c.ImGuiInputTextFlags_CharsNoBlank);
    } else {
        c.ImGui_TextDisabled("Samples Point Cloud: ");
        c.ImGui_SameLine();
        c.ImGui_Text(sms.app_ctx.point_cloud_store.pointCloudName(sd.samples).?);
        c.ImGui_Separator();
    }
    const pointcloud_name = if (!sd.initialized) std.mem.sliceTo(&UiData.pointcloud_name_buf, 0) else "_"; // only used when not initialized

    {
        c.ImGui_SeparatorText("Uniform sampling");
        c.ImGui_Text("Number of points");
        c.ImGui_PushID("Number of points");
        _ = c.ImGui_InputInt("", @ptrCast(&UiData.nb_points));
        c.ImGui_PopID();
        const disabled =
            info.std_datas.vertex_position == null or
            info.std_datas.face_area == null or
            pointcloud_name.len == 0;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx("Uniform sampling", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            sms.uniformSampling(
                sm,
                info.std_datas.vertex_position.?,
                info.std_datas.face_area.?,
                UiData.nb_points,
                pointcloud_name,
            ) catch |err| {
                std.debug.print("Error during uniform sampling: {}\n", .{err});
            };
            UiData.pointcloud_name_buf = @splat(0);
        }
        if (disabled) {
            imgui_utils.tooltip(
                \\ Requires:
                \\ - an already sampled PointCloud or a name
                \\ Following data should be available:
                \\ - std vertex_position
                \\ - std face_area
            );
            c.ImGui_EndDisabled();
        }
    }

    {
        c.ImGui_SeparatorText("Poisson disk sampling");
        c.ImGui_Text("Minimum distance");
        c.ImGui_PushID("Minimum distance");
        _ = c.ImGui_InputFloat("", @ptrCast(&UiData.poisson_radius));
        c.ImGui_PopID();
        const disabled =
            !info.bvh.initialized or
            info.std_datas.vertex_position == null or
            info.std_datas.face_normal == null or
            pointcloud_name.len == 0;
        if (disabled) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_ButtonEx("Poisson disk sampling", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
            sms.poissonDiskSampling(
                sm,
                &info.bvh,
                info.std_datas.vertex_position.?,
                info.std_datas.face_normal.?,
                UiData.poisson_radius,
                pointcloud_name,
            ) catch |err| {
                std.debug.print("Error during Poisson disk sampling: {}\n", .{err});
            };
            UiData.pointcloud_name_buf = @splat(0);
        }
        if (disabled) {
            imgui_utils.tooltip(
                \\ Requires:
                \\ - an already sampled PointCloud or a name
                \\ - a BVH
                \\ Following data should be available:
                \\ - std vertex_position
                \\ - std face_normal
            );
            c.ImGui_EndDisabled();
        }
    }

    if (sd.initialized) {
        c.ImGui_SeparatorText("Push data SurfaceMesh -> PointCloud");

        c.ImGui_Text("Cell type:");
        c.ImGui_PushID("cell type");
        if (c.ImGui_BeginCombo("", @tagName(UiData.selected_surface_mesh_cell_type), 0)) {
            defer c.ImGui_EndCombo();
            inline for ([_]SurfaceMesh.CellType{ .vertex, .edge, .face }) |cell_type| {
                const is_selected = UiData.selected_surface_mesh_cell_type == cell_type;
                if (c.ImGui_SelectableEx(@tagName(cell_type), is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                    UiData.selected_surface_mesh_cell_type = cell_type;
                    UiData.selected_data_gen = null;
                }
                if (is_selected) {
                    c.ImGui_SetItemDefaultFocus();
                }
            }
        }
        c.ImGui_PopID();
        c.ImGui_Text("Data type:");
        c.ImGui_PushID("data type");
        if (c.ImGui_BeginCombo("", @tagName(UiData.selected_data_type), 0)) {
            defer c.ImGui_EndCombo();
            inline for (@typeInfo(DataTypesTag).@"enum".fields) |data_type| {
                const is_selected = @intFromEnum(UiData.selected_data_type) == data_type.value;
                if (c.ImGui_SelectableEx(data_type.name, is_selected, 0, c.ImVec2{ .x = 0, .y = 0 })) {
                    if (!is_selected) {
                        UiData.selected_data_type = @enumFromInt(data_type.value);
                        UiData.selected_data_gen = null;
                    }
                }
                if (is_selected) {
                    c.ImGui_SetItemDefaultFocus();
                }
            }
        }
        c.ImGui_PopID();
        c.ImGui_Text("Source data:");
        inline for ([_]SurfaceMesh.CellType{ .vertex, .edge, .face }) |cell_type| {
            if (UiData.selected_surface_mesh_cell_type == cell_type) {
                inline for (@typeInfo(DataTypesTag).@"enum".fields) |data_type| {
                    if (UiData.selected_data_type == @as(DataTypesTag, @enumFromInt(data_type.value))) {
                        const T = @FieldType(DataTypes, data_type.name);
                        const selected_cell_data: ?SurfaceMesh.CellData(cell_type, T) = if (UiData.selected_data_gen) |data_gen| blk: {
                            const selected_data: *Data(T) = @fieldParentPtr("data_gen", data_gen);
                            break :blk .{
                                .surface_mesh = sm,
                                .data = selected_data,
                            };
                        } else null;
                        switch (imgui_utils.surfaceMeshCellDataComboBox(sm, cell_type, @FieldType(DataTypes, data_type.name), selected_cell_data)) {
                            .unchanged => {},
                            .cleared => UiData.selected_data_gen = null,
                            .changed => |data| UiData.selected_data_gen = &data.data.data_gen,
                        }
                        const disabled = selected_cell_data == null;
                        if (disabled) {
                            c.ImGui_BeginDisabled(true);
                        }
                        if (c.ImGui_ButtonEx(c.ICON_FA_DATABASE ++ " Push data", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                            sd.pushDataToPointCloud(T, cell_type, selected_cell_data.?) catch |err| {
                                std.debug.print("Error pushing data from SurfaceMesh to PointCloud: {}\n", .{err});
                            };
                        }
                        if (disabled) {
                            imgui_utils.tooltip(
                                \\ Requires:
                                \\ - an already sampled PointCloud
                                \\ - a selected source data
                            );
                            c.ImGui_EndDisabled();
                        }
                    }
                }
            }
        }
    }
}
