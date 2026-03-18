const SurfaceMeshSampling = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("../main.zig").c;

const AppContext = @import("../main.zig").AppContext;
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfacePoint = @import("../models/surface/SurfacePoint.zig");
const PointCloud = @import("../models/point/PointCloud.zig");

const Data = @import("../utils/Data.zig").Data;
const DataGen = @import("../utils/Data.zig").DataGen;

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const bvh = @import("../geometry/bvh.zig");

const sampling = @import("../models/surface/sampling.zig");

const SamplingData = struct {
    app_ctx: *AppContext,

    samples: ?*PointCloud = null,
    position: ?PointCloud.CellData(Vec3f) = null,
    surface_point: ?PointCloud.CellData(SurfacePoint) = null,
    initialized: bool = false,

    fn init(sd: *SamplingData, pointcloud_name: []const u8) !void {
        if (!sd.initialized) {
            sd.samples = try sd.app_ctx.point_cloud_store.createPointCloud(pointcloud_name);
            sd.surface_point = try sd.samples.?.addData(SurfacePoint, "surface_point");
            sd.position = try sd.samples.?.addData(Vec3f, "position");
            sd.app_ctx.point_cloud_store.setPointCloudStdData(sd.samples.?, .{ .position = sd.position.? });
        } else {
            sd.samples.?.clearRetainingCapacity();
        }
        sd.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(sd.samples.?);
        sd.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples.?, Vec3f, sd.position.?);
        sd.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples.?, SurfacePoint, sd.surface_point.?);
        sd.initialized = true;
    }

    fn deinit(sd: *SamplingData) void {
        if (sd.initialized) {
            sd.app_ctx.point_cloud_store.destroyPointCloud(sd.samples.?);
        }
        sd.initialized = false;
    }

    fn readDataFromSurfaceMesh(
        sd: *SamplingData,
        comptime T: type,
        comptime cell_type: SurfaceMesh.CellType,
        src_data: SurfaceMesh.CellData(cell_type, T),
    ) !void {
        if (!sd.initialized) return;
        const dst_data = try sd.samples.?.getOrAddData(T, src_data.name());
        var point_it = sd.samples.?.pointIterator();
        while (point_it.next()) |point| {
            dst_data.valuePtr(point).* = sd.surface_point.?.value(point).readData(T, cell_type, src_data);
        }
        sd.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples.?, T, dst_data);
        sd.app_ctx.requestRedraw();
    }
};

app_ctx: *AppContext,
module: Module = .{
    .name = "Surface Mesh Sampling",
    .supported_models = .{ .surface_mesh = true },
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .rightClickMenu = rightClickMenu,
        .rightPanel = rightPanel,
    },
},
surface_meshes_data: std.AutoHashMap(*SurfaceMesh, SamplingData),

pub fn init(app_ctx: *AppContext) SurfaceMeshSampling {
    return .{
        .app_ctx = app_ctx,
        .surface_meshes_data = .init(app_ctx.allocator),
    };
}

pub fn deinit(sms: *SurfaceMeshSampling) void {
    sms.surface_meshes_data.deinit();
}

/// Part of the Module interface.
/// Create and store a SamplingData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const sms: *SurfaceMeshSampling = @alignCast(@fieldParentPtr("module", m));
    sms.surface_meshes_data.put(surface_mesh, .{ .app_ctx = sms.app_ctx }) catch |err| {
        std.debug.print("Failed to store SamplingData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Remove the SamplingData associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const sms: *SurfaceMeshSampling = @alignCast(@fieldParentPtr("module", m));
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
    var timer = try std.time.Timer.start();

    const sd = sms.surface_meshes_data.getPtr(sm).?;
    try sd.init(pointcloud_name);

    try sampling.uniformlySamplePointsOnSurface(sms.app_ctx, sm, vertex_position, face_area, sd.samples.?, sd.position.?, sd.surface_point.?, nb_points);
    sms.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(sd.samples.?);
    sms.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples.?, Vec3f, sd.position.?);
    sms.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples.?, SurfacePoint, sd.surface_point.?);

    sms.app_ctx.requestRedraw();

    const elapsed: f64 = @floatFromInt(timer.read());
    zgp_log.info("Uniform sampling computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
}

fn poissonDiskSampling(
    sms: *SurfaceMeshSampling,
    sm: *SurfaceMesh,
    sm_bvh: bvh.TrianglesBVH,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    min_distance: f32,
    pointcloud_name: []const u8,
) !void {
    var timer = try std.time.Timer.start();

    const sd = sms.surface_meshes_data.getPtr(sm).?;
    try sd.init(pointcloud_name);

    try sampling.poissonDiskSamplePointsOnSurface(sms.app_ctx, sm, sm_bvh, vertex_position, face_normal, sd.samples.?, sd.position.?, sd.surface_point.?, min_distance);
    sms.app_ctx.point_cloud_store.pointCloudConnectivityUpdated(sd.samples.?);
    sms.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples.?, Vec3f, sd.position.?);
    sms.app_ctx.point_cloud_store.pointCloudDataUpdated(sd.samples.?, SurfacePoint, sd.surface_point.?);

    sms.app_ctx.requestRedraw();

    const elapsed: f64 = @floatFromInt(timer.read());
    zgp_log.info("Poisson disk sampling computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
}

/// Part of the Module interface.
/// Describe the right-click menu interface.
pub fn rightClickMenu(m: *Module) void {
    const sms: *SurfaceMeshSampling = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &sms.app_ctx.surface_mesh_store;

    assert(sms.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = sms.app_ctx.selected_model.surface_mesh;

    const UiData = struct {
        var nb_points: usize = 1000;
        var min_distance: f32 = 0.02;
        var pointcloud_name_buf: [32]u8 = @splat(0);
    };

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (c.ImGui_BeginMenu(m.name.ptr)) {
        defer c.ImGui_EndMenu();

        const info = sm_store.surfaceMeshInfo(sm);
        const sd = sms.surface_meshes_data.getPtr(sm).?;

        if (c.ImGui_BeginMenu("Uniform sampling")) {
            defer c.ImGui_EndMenu();
            c.ImGui_Text("Number of points");
            c.ImGui_PushID("Number of points");
            _ = c.ImGui_InputInt("", @ptrCast(&UiData.nb_points));
            c.ImGui_PopID();
            if (!sd.initialized) {
                c.ImGui_Text("PointCloud name:");
                _ = c.ImGui_InputText("##Name", &UiData.pointcloud_name_buf, UiData.pointcloud_name_buf.len, c.ImGuiInputTextFlags_CharsNoBlank);
            }
            const pointcloud_name = if (!sd.initialized) std.mem.sliceTo(&UiData.pointcloud_name_buf, 0) else "_"; // only used when not initialized
            const disabled =
                info.std_datas.vertex_position == null or
                info.std_datas.face_area == null or
                pointcloud_name.len == 0;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Sample", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                sms.uniformSampling(
                    sm,
                    info.std_datas.vertex_position.?,
                    info.std_datas.face_area.?,
                    UiData.nb_points,
                    pointcloud_name,
                ) catch |err| {
                    std.debug.print("Error sampling: {}\n", .{err});
                };
                UiData.pointcloud_name_buf = @splat(0);
            }
            if (disabled) {
                c.ImGui_EndDisabled();
            }
        }

        if (c.ImGui_BeginMenu("Poisson disk sampling")) {
            defer c.ImGui_EndMenu();
            c.ImGui_Text("Minimum distance");
            c.ImGui_PushID("Minimum distance");
            _ = c.ImGui_InputFloat("", @ptrCast(&UiData.min_distance));
            c.ImGui_PopID();
            if (!sd.initialized) {
                c.ImGui_Text("PointCloud name:");
                _ = c.ImGui_InputText("##Name", &UiData.pointcloud_name_buf, UiData.pointcloud_name_buf.len, c.ImGuiInputTextFlags_CharsNoBlank);
            }
            const pointcloud_name = if (!sd.initialized) std.mem.sliceTo(&UiData.pointcloud_name_buf, 0) else "_"; // only used when not initialized
            const disabled =
                info.bvh.bvh_ptr == null or
                info.std_datas.vertex_position == null or
                info.std_datas.face_normal == null or
                pointcloud_name.len == 0;
            if (disabled) {
                c.ImGui_BeginDisabled(true);
            }
            if (c.ImGui_ButtonEx("Sample", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                sms.poissonDiskSampling(
                    sm,
                    info.bvh,
                    info.std_datas.vertex_position.?,
                    info.std_datas.face_normal.?,
                    UiData.min_distance,
                    pointcloud_name,
                ) catch |err| {
                    std.debug.print("Error sampling: {}\n", .{err});
                };
                UiData.pointcloud_name_buf = @splat(0);
            }
            if (disabled) {
                c.ImGui_EndDisabled();
            }
        }
    }
}

/// Part of the Module interface.
/// Show a UI panel to control the sampling data of the selected SurfaceMesh.
pub fn rightPanel(m: *Module) void {
    const sms: *SurfaceMeshSampling = @alignCast(@fieldParentPtr("module", m));
    // const sm_store = &sms.app_ctx.surface_mesh_store;

    assert(sms.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = sms.app_ctx.selected_model.surface_mesh;

    const DataTypes = union(enum) { u32: u32, f32: f32, Vec3f: Vec3f };
    const DataTypesTag = std.meta.Tag(DataTypes);
    const UiData = struct {
        var selected_surface_mesh_cell_type: SurfaceMesh.CellType = .vertex;
        var selected_data_type: DataTypesTag = .Vec3f;
        var selected_data_gen: ?*DataGen = null;
        var data_name_buf: [32]u8 = @splat(0);
    };

    const sd = sms.surface_meshes_data.getPtr(sm).?;
    if (sd.initialized) {
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
                            .cleared => {},
                            .changed => |data| {
                                UiData.selected_data_gen = &data.data.data_gen;
                            },
                        }
                        if (c.ImGui_Button("Read data")) {
                            sd.readDataFromSurfaceMesh(T, cell_type, selected_cell_data.?) catch |err| {
                                std.debug.print("Error reading SurfacePoint data: {}\n", .{err});
                            };
                        }
                    }
                }
            }
        }
    } else {
        c.ImGui_TextWrapped("No sampling data available. Use the right-click menu to create samples on this SurfaceMesh.");
    }
}
