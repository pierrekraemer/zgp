const SurfaceMeshFiltering = @This();

const std = @import("std");
const assert = std.debug.assert;

const imgui_utils = @import("../ui/imgui.zig");
const zgp_log = std.log.scoped(.zgp);

const c = @import("c");

const AppContext = @import("../AppContext.zig");
const Module = @import("Module.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const filtering = @import("../models/surface/filtering.zig");

fn scalarDiscrepancy(comptime T: type) fn (a: T, b: T) f64 {
    return struct {
        pub fn discrepancy(a: T, b: T) f64 {
            const a_f64 = @as(f64, a);
            const b_f64 = @as(f64, b);
            return @abs(a_f64 - b_f64);
        }
    }.discrepancy;
}

fn vectorDiscrepancy(comptime T: type) fn (a: T, b: T) f64 {
    return struct {
        pub fn discrepancy(a: T, b: T) f64 {
            const diff = vec.sub(a, b);
            return @floatCast(vec.norm(diff));
        }
    }.discrepancy;
}

const FilteringData = struct {
    scalar_data_to_filter: ?SurfaceMesh.VertexData(f32) = null,
    vector_data_to_filter: ?SurfaceMesh.VertexData(Vec3f) = null,
    sigma_r: f32 = 1.0, // data discrepancy above which smoothing is damped
    sigma_g: f32 = 0.3, // sine of the slope angle above which smoothing is damped
    time_step_factor: f32 = 1.0, // time step = factor * mean_edge_length^2
};

app_ctx: *AppContext = undefined,
module: Module = .{
    .name = "Surface Mesh Filtering",
    .supported_models = .{ .surface_mesh = true },
    .vtable = &.{
        .surfaceMeshCreated = surfaceMeshCreated,
        .surfaceMeshDestroyed = surfaceMeshDestroyed,
        .rightClickMenu = rightClickMenu,
    },
},
surface_meshes_data: std.AutoHashMapUnmanaged(*SurfaceMesh, FilteringData) = .empty,

/// Modules are default-constructed in AppContext init function, and then initialized in AppContext wireUp function.
pub fn init(smf: *SurfaceMeshFiltering, app_ctx: *AppContext) !void {
    smf.app_ctx = app_ctx;
    try app_ctx.surface_mesh_store.addListener(&smf.module);
}

pub fn deinit(smf: *SurfaceMeshFiltering) void {
    // var it = smf.surface_meshes_data.valueIterator();
    // while (it.next()) |dfd| {
    //     dfd.deinit();
    // }
    smf.surface_meshes_data.deinit(smf.app_ctx.allocator);
    smf.app_ctx.surface_mesh_store.removeListener(&smf.module);
}

/// Part of the Module interface.
/// Create and store a FilteringData for the created SurfaceMesh.
pub fn surfaceMeshCreated(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smf: *SurfaceMeshFiltering = @alignCast(@fieldParentPtr("module", m));
    smf.surface_meshes_data.put(smf.app_ctx.allocator, surface_mesh, .{}) catch |err| {
        std.debug.print("Failed to store FilteringData for new SurfaceMesh: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Remove the FilteringData associated to the destroyed SurfaceMesh.
pub fn surfaceMeshDestroyed(m: *Module, surface_mesh: *SurfaceMesh) void {
    const smf: *SurfaceMeshFiltering = @alignCast(@fieldParentPtr("module", m));
    // if (smf.surface_meshes_data.getPtr(surface_mesh)) |dfd| {
    //     dfd.deinit();
    // }
    _ = smf.surface_meshes_data.remove(surface_mesh);
}

/// Part of the Module interface.
/// Describe the right-click menu interface.
pub fn rightClickMenu(m: *Module) void {
    const smf: *SurfaceMeshFiltering = @alignCast(@fieldParentPtr("module", m));
    const sm_store = &smf.app_ctx.surface_mesh_store;

    assert(smf.app_ctx.selected_model.modelType() == .surface_mesh);
    const sm = smf.app_ctx.selected_model.surface_mesh;
    const fd = smf.surface_meshes_data.getPtr(sm).?;
    const info = sm_store.surfaceMeshInfo(sm);

    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (c.ImGui_BeginMenu(m.name.ptr)) {
        defer c.ImGui_EndMenu();

        inline for ([_]type{ f32, Vec3f }) |t| {
            if (c.ImGui_BeginMenu(if (t == f32) "Filter scalar field" else "Filter vector field")) {
                defer c.ImGui_EndMenu();
                c.ImGui_Text("Data to filter:");
                c.ImGui_PushID("DataComboBox");
                switch (imgui_utils.surfaceMeshCellDataComboBox(sm, .vertex, t, if (t == f32) fd.scalar_data_to_filter else fd.vector_data_to_filter)) {
                    .unchanged => {},
                    .cleared => {
                        if (t == f32) {
                            fd.scalar_data_to_filter = null;
                        } else {
                            fd.vector_data_to_filter = null;
                        }
                    },
                    .changed => |data| {
                        if (t == f32) {
                            fd.scalar_data_to_filter = data;
                        } else {
                            fd.vector_data_to_filter = data;
                        }
                    },
                }
                c.ImGui_PopID();

                c.ImGui_Text("Data discrepancy threshold");
                c.ImGui_PushID("SigmaR");
                _ = c.ImGui_SliderFloatEx("", &fd.sigma_r, 0.01, 10.0, "%.2f", c.ImGuiSliderFlags_Logarithmic);
                c.ImGui_PopID();
                c.ImGui_Text("Geometry threshold (slope)");
                c.ImGui_PushID("SigmaG");
                _ = c.ImGui_SliderFloatEx("", &fd.sigma_g, 0.01, 1.0, "%.2f", c.ImGuiSliderFlags_Logarithmic);
                c.ImGui_PopID();
                c.ImGui_Text("Time step");
                c.ImGui_PushID("TimeStep");
                _ = c.ImGui_SliderFloatEx("", &fd.time_step_factor, 0.01, 10.0, "%.2f", c.ImGuiSliderFlags_Logarithmic);
                c.ImGui_PopID();

                const disabled =
                    info.std_datas.halfedge_cotan_weight == null or
                    info.std_datas.vertex_position == null or
                    info.std_datas.vertex_normal == null or
                    info.std_datas.vertex_area == null or
                    info.std_datas.edge_length == null or
                    (if (t == f32) fd.scalar_data_to_filter == null else fd.vector_data_to_filter == null);
                if (disabled) {
                    c.ImGui_BeginDisabled(true);
                }
                if (c.ImGui_ButtonEx("Filter", c.ImVec2{ .x = c.ImGui_GetContentRegionAvail().x, .y = 0.0 })) {
                    const ts = std.Io.Timestamp.now(smf.app_ctx.io, .real);

                    filtering.anisotropicLaplacianFiltering(
                        smf.app_ctx.allocator,
                        sm,
                        info.std_datas.halfedge_cotan_weight.?,
                        info.std_datas.vertex_position.?,
                        info.std_datas.vertex_normal.?,
                        info.std_datas.vertex_area.?,
                        info.std_datas.edge_length.?,
                        fd.sigma_r,
                        fd.sigma_g,
                        fd.time_step_factor,
                        t,
                        if (t == f32) scalarDiscrepancy(f32) else vectorDiscrepancy(Vec3f),
                        (if (t == f32) &fd.scalar_data_to_filter.? else &fd.vector_data_to_filter.?),
                    ) catch |err| {
                        std.debug.print("Failed to initialize Laplacian filtering context: {}\n", .{err});
                    };
                    smf.app_ctx.surface_mesh_store.surfaceMeshDataUpdated(sm, .vertex, t, (if (t == f32) fd.scalar_data_to_filter else fd.vector_data_to_filter).?);
                    smf.app_ctx.view.requestRedraw();

                    const elapsed: f64 = @floatFromInt(std.Io.Timestamp.untilNow(ts, smf.app_ctx.io, .real).nanoseconds);
                    zgp_log.info("Filtering computed in : {d:.3}ms", .{elapsed / std.time.ns_per_ms});
                }
                if (disabled) {
                    imgui_utils.tooltip(
                        \\ Following data should be available:
                        \\ - std halfedge_cotan_weight
                        \\ - std vertex_position
                        \\ - std vertex_normal
                        \\ - std vertex_area
                        \\ - std edge_length
                        \\ - selected scalar field
                    );
                    c.ImGui_EndDisabled();
                }
            }
        }
    }
}
