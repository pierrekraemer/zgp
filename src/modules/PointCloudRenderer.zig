const PointCloudRenderer = @This();

const std = @import("std");
const gl = @import("gl");

const zgp = @import("../main.zig");
const c = zgp.c;

const imgui_utils = @import("../utils/imgui.zig");
const imgui_log = std.log.scoped(.imgui);

const Module = @import("Module.zig");
const PointCloudStore = @import("../models/PointCloudStore.zig");
const PointCloud = PointCloudStore.PointCloud;
const PointCloudStdData = PointCloudStore.PointCloudStdData;

const PointSphere = @import("../rendering/shaders/point_sphere/PointSphere.zig");
const PointSphereColorPerVertex = @import("../rendering/shaders/point_sphere_color_per_vertex/PointSphereColorPerVertex.zig");
const VBO = @import("../rendering/VBO.zig");

const vec = @import("../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;

const ColorDefinedOn = enum {
    global,
    point,
};
const ColorType = enum {
    scalar,
    vector,
};
const ColorParameters = struct {
    defined_on: ColorDefinedOn,
    type: ColorType = .vector,
    point_vector_data: ?PointCloud.CellData(Vec3f) = null, // data used if definedOn is point & type is vector
    point_scalar_data: ?PointCloud.CellData(f32) = null, // data used if definedOn is point & type is scalar
};

const PointCloudRendererParameters = struct {
    point_sphere_shader_parameters: PointSphere.Parameters,
    point_sphere_color_per_vertex_shader_parameters: PointSphereColorPerVertex.Parameters,

    draw_points: bool = true,

    draw_points_color: ColorParameters = .{
        .defined_on = .global,
    },

    pub fn init() PointCloudRendererParameters {
        return .{
            .point_sphere_shader_parameters = PointSphere.Parameters.init(),
            .point_sphere_color_per_vertex_shader_parameters = PointSphereColorPerVertex.Parameters.init(),
        };
    }

    pub fn deinit(self: *PointCloudRendererParameters) void {
        self.point_sphere_shader_parameters.deinit();
        self.point_sphere_color_per_vertex_shader_parameters.deinit();
    }
};

parameters: std.AutoHashMap(*const PointCloud, PointCloudRendererParameters),

pub fn init(allocator: std.mem.Allocator) !PointCloudRenderer {
    return .{
        .parameters = std.AutoHashMap(*const PointCloud, PointCloudRendererParameters).init(allocator),
    };
}

pub fn deinit(pcr: *PointCloudRenderer) void {
    var p_it = pcr.parameters.iterator();
    while (p_it.next()) |entry| {
        var p = entry.value_ptr.*;
        p.deinit();
    }
    pcr.parameters.deinit();
}

/// Return a Module interface for the PointCloudRenderer.
pub fn module(pcr: *PointCloudRenderer) Module {
    return Module.init(pcr);
}

/// Part of the Module interface.
/// Return the name of the module.
pub fn name(_: *PointCloudRenderer) []const u8 {
    return "Point Cloud Renderer";
}

/// Part of the Module interface.
/// Create and store a PointCloudRendererParameters for the new PointCloud.
pub fn pointCloudAdded(pcr: *PointCloudRenderer, point_cloud: *PointCloud) void {
    pcr.parameters.put(point_cloud, PointCloudRendererParameters.init()) catch |err| {
        std.debug.print("Failed to create PointCloudRendererParameters for new PointCloud: {}\n", .{err});
        return;
    };
}

/// Part of the Module interface.
/// Update the PointCloudRendererParameters when a standard data of the PointCloud changes.
pub fn pointCloudStdDataChanged(
    pcr: *PointCloudRenderer,
    point_cloud: *PointCloud,
    std_data: PointCloudStdData,
) void {
    const p = pcr.parameters.getPtr(point_cloud) orelse return;
    switch (std_data) {
        .position => |maybe_position| {
            if (maybe_position) |position| {
                const position_vbo = zgp.point_cloud_store.dataVBO(Vec3f, position.data);
                p.point_sphere_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
                p.point_sphere_color_per_vertex_shader_parameters.setVertexAttribArray(.position, position_vbo, 0, 0);
            } else {
                p.point_sphere_shader_parameters.unsetVertexAttribArray(.position);
                p.point_sphere_color_per_vertex_shader_parameters.unsetVertexAttribArray(.position);
            }
        },
        else => return, // Ignore other standard data changes
    }
}

fn setPointCloudDrawPointsColorData(
    smr: *PointCloudRenderer,
    point_cloud: *PointCloud,
    T: type,
    data: ?PointCloud.CellData(T),
) void {
    const p = smr.parameters.getPtr(point_cloud) orelse return;
    switch (@typeInfo(T)) {
        .float => {
            // Not supported yet
            // p.draw_points_color.point_scalar_data = data;
            // if (p.draw_points_color.point_scalar_data) |scalar| {
            //     const scalar_vbo = zgp.point_cloud_store.dataVBO(f32, scalar.data);
            //     p.point_sphere_scalar_per_vertex_shader_parameters.setVertexAttribArray(.scalar, scalar_vbo, 0, 0);
            // } else {
            //     p.point_sphere_scalar_per_vertex_shader_parameters.unsetVertexAttribArray(.scalar);
            // }
        },
        .array => {
            if (@typeInfo(@typeInfo(T).array.child) != .float) {
                @compileError("SurfaceMeshRenderer bad vertex color data type");
            }
            p.draw_points_color.point_vector_data = data;
            if (p.draw_points_color.point_vector_data) |vector| {
                const vector_vbo = zgp.point_cloud_store.dataVBO(Vec3f, vector.data);
                p.point_sphere_color_per_vertex_shader_parameters.setVertexAttribArray(.color, vector_vbo, 0, 0);
            } else {
                p.point_sphere_color_per_vertex_shader_parameters.unsetVertexAttribArray(.color);
            }
        },
        else => @compileError("PointCloudRenderer bad vertex color data type"),
    }
    zgp.requestRedraw();
}

/// Part of the Module interface.
/// Render all PointClouds with their PointCloudRendererParameters and the given view and projection matrices.
pub fn draw(pcr: *PointCloudRenderer, view_matrix: Mat4f, projection_matrix: Mat4f) void {
    var pc_it = zgp.point_cloud_store.point_clouds.iterator();
    while (pc_it.next()) |entry| {
        const pc = entry.value_ptr.*;
        const info = zgp.point_cloud_store.pointCloudInfo(pc);
        const p = pcr.parameters.getPtr(pc) orelse continue;
        if (p.draw_points) {
            switch (p.draw_points_color.defined_on) {
                .global => {
                    p.point_sphere_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                    p.point_sphere_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                    p.point_sphere_shader_parameters.draw(info.points_ibo);
                },
                .point => {
                    switch (p.draw_points_color.type) {
                        .scalar => {
                            // Not supported yet
                            // TODO: write PointSphereScalarPerVertex
                        },
                        .vector => {
                            p.point_sphere_color_per_vertex_shader_parameters.model_view_matrix = @bitCast(view_matrix);
                            p.point_sphere_color_per_vertex_shader_parameters.projection_matrix = @bitCast(projection_matrix);
                            p.point_sphere_color_per_vertex_shader_parameters.draw(info.points_ibo);
                        },
                    }
                },
            }
        }
    }
}

/// Part of the Module interface.
/// Show a UI panel to control the PointCloudRendererParameters of the selected PointCloud.
pub fn uiPanel(pcr: *PointCloudRenderer) void {
    const style = c.ImGui_GetStyle();

    c.ImGui_PushItemWidth(c.ImGui_GetWindowWidth() - style.*.ItemSpacing.x * 2);
    defer c.ImGui_PopItemWidth();

    if (zgp.point_cloud_store.selected_point_cloud) |pc| {
        const surface_mesh_renderer_parameters = pcr.parameters.getPtr(pc);
        if (surface_mesh_renderer_parameters) |p| {
            if (c.ImGui_Checkbox("draw points", &p.draw_points)) {
                zgp.requestRedraw();
            }
            if (p.draw_points) {
                c.ImGui_Text("Size");
                c.ImGui_PushID("DrawPointsSize");
                if (c.ImGui_SliderFloatEx("", &p.point_sphere_shader_parameters.point_size, 0.0001, 0.1, "%.4f", c.ImGuiSliderFlags_Logarithmic)) {
                    // sync value to color per vertex shader
                    p.point_sphere_color_per_vertex_shader_parameters.point_size = p.point_sphere_shader_parameters.point_size;
                    zgp.requestRedraw();
                }
                c.ImGui_PopID();

                c.ImGui_Text("Color");
                {
                    c.ImGui_BeginGroup();
                    defer c.ImGui_EndGroup();
                    if (c.ImGui_RadioButton("Global##DrawPointsColorGlobal", p.draw_points_color.defined_on == .global)) {
                        p.draw_points_color.defined_on = .global;
                        zgp.requestRedraw();
                    }
                    c.ImGui_SameLine();
                    if (c.ImGui_RadioButton("Per point##DrawPointsColorPerPoint", p.draw_points_color.defined_on == .point)) {
                        p.draw_points_color.defined_on = .point;
                        zgp.requestRedraw();
                    }
                }
                switch (p.draw_points_color.defined_on) {
                    .global => {
                        if (c.ImGui_ColorEdit3("Global color##DrawPointsColorGlobalEdit", &p.point_sphere_shader_parameters.point_color, c.ImGuiColorEditFlags_NoInputs)) {
                            zgp.requestRedraw();
                        }
                    },
                    .point => {
                        {
                            c.ImGui_BeginGroup();
                            defer c.ImGui_EndGroup();
                            c.ImGui_SameLine();
                            if (c.ImGui_RadioButton("Scalar##DrawPointsColorPointScalar", p.draw_points_color.type == .scalar)) {
                                p.draw_points_color.type = .scalar;
                                zgp.requestRedraw();
                            }
                            if (c.ImGui_RadioButton("Vector##DrawPointsColorPointVector", p.draw_points_color.type == .vector)) {
                                p.draw_points_color.type = .vector;
                                zgp.requestRedraw();
                            }
                        }
                        c.ImGui_PushID("DrawPointsColorPointData");
                        switch (p.draw_points_color.type) {
                            .scalar => if (imgui_utils.pointCloudDataComboBox(
                                pc,
                                f32,
                                p.draw_points_color.point_scalar_data,
                            )) |data| {
                                pcr.setPointCloudDrawPointsColorData(pc, f32, data);
                            },
                            .vector => if (imgui_utils.pointCloudDataComboBox(
                                pc,
                                Vec3f,
                                p.draw_points_color.point_vector_data,
                            )) |data| {
                                pcr.setPointCloudDrawPointsColorData(pc, Vec3f, data);
                            },
                        }
                        c.ImGui_PopID();
                    },
                }
            }
        } else {
            c.ImGui_Text("No parameters found for the selected Point Cloud");
        }
    } else {
        c.ImGui_Text("No Point Cloud selected");
    }
}
