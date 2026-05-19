const std = @import("std");
const assert = std.debug.assert;

const AppContext = @import("../../main.zig").AppContext;
const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

/// Compute and return the cotan weight of the given halfedge,
/// i.e. cotan(theta)/2 where theta is the angle opposite to the halfedge in its incident face.
pub fn halfedgeCotanWeight(
    sm: *const SurfaceMesh,
    halfedge: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
) f32 {
    assert(halfedge.cellType() == .halfedge);

    if (sm.isBoundaryDart(halfedge.dart())) {
        return 0.0;
    }

    const d = halfedge.dart();
    const d1 = sm.phi1(d);
    const d_1 = sm.phi_1(d);
    const p1 = vertex_position.value(.{ .vertex = d });
    const p2 = vertex_position.value(.{ .vertex = d1 });
    const p3 = vertex_position.value(.{ .vertex = d_1 });
    const vecR = vec.sub3f(p1, p3);
    const vecL = vec.sub3f(p2, p3);
    // cotan(theta_i^jk) = (u . v) / ||u x v||
    return 0.5 * (vec.dot3f(vecR, vecL) / vec.norm3f(vec.cross3f(vecR, vecL)));
    // cotan(theta_i^jk) = (|ij|2 + |ik|2 - |jk|2) / (4 * Area(ijk))
}

/// Compute the cotan weights of all halfedges of the given SurfaceMesh
/// and store them in the given halfedge_cotan_weight data.
pub fn computeHalfedgeCotanWeights(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
) !void {
    const Task = struct {
        const Task = @This();

        surface_mesh: *const SurfaceMesh,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
        halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),

        pub fn run(t: *const Task, halfedge: SurfaceMesh.Cell) void {
            t.halfedge_cotan_weight.valuePtr(halfedge).* = halfedgeCotanWeight(
                t.surface_mesh,
                halfedge,
                t.vertex_position,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelCellTaskRunner = try .init(sm, .halfedge);
    defer pctr.deinit();
    try pctr.run(app_ctx, Task{
        .surface_mesh = sm,
        .vertex_position = vertex_position,
        .halfedge_cotan_weight = halfedge_cotan_weight,
    });
}

/// Compute and return the cotan weight of the given halfedge,
/// i.e. cotan(theta)/2 where theta is the angle opposite to the halfedge in its incident face.
/// This version uses intrinsic geometry (edge lengths and face areas) instead of extrinsic vertex positions.
pub fn halfedgeCotanWeightIntrinsic(
    sm: *const SurfaceMesh,
    halfedge: SurfaceMesh.Cell,
    edge_length: SurfaceMesh.CellData(.edge, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
) f32 {
    assert(halfedge.cellType() == .halfedge);

    if (sm.isBoundaryDart(halfedge.dart())) {
        return 0.0;
    }

    const d = halfedge.dart();
    const d1 = sm.phi1(d);
    const d_1 = sm.phi_1(d);
    const l_ij = edge_length.value(.{ .edge = d });
    const l_jk = edge_length.value(.{ .edge = d1 });
    const l_ki = edge_length.value(.{ .edge = d_1 });
    const area = face_area.value(.{ .face = d });
    return (-l_ij * l_ij + l_jk * l_jk + l_ki * l_ki) / (4.0 * area);
}

/// Compute the cotan weights of all halfedges of the given SurfaceMesh
/// and store them in the given halfedge_cotan_weight data.
/// This version uses intrinsic geometry (edge lengths and face areas) instead of extrinsic vertex positions.
pub fn computeHalfedgeCotanWeightsIntrinsic(
    app_ctx: *AppContext,
    sm: *SurfaceMesh,
    edge_length: SurfaceMesh.CellData(.edge, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
) !void {
    const Task = struct {
        const Task = @This();

        surface_mesh: *const SurfaceMesh,
        edge_length: SurfaceMesh.CellData(.edge, f32),
        face_area: SurfaceMesh.CellData(.face, f32),
        halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),

        pub fn run(t: *const Task, halfedge: SurfaceMesh.Cell) void {
            t.halfedge_cotan_weight.valuePtr(halfedge).* = halfedgeCotanWeightIntrinsic(
                t.surface_mesh,
                halfedge,
                t.edge_length,
                t.face_area,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelCellTaskRunner = try .init(sm, .halfedge);
    defer pctr.deinit();
    try pctr.run(app_ctx, Task{
        .surface_mesh = sm,
        .edge_length = edge_length,
        .face_area = face_area,
        .halfedge_cotan_weight = halfedge_cotan_weight,
    });
}

/// Compute and return the cotan weight of the given edge.
pub fn edgeCotanWeight(
    sm: *const SurfaceMesh,
    edge: SurfaceMesh.Cell,
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
) f32 {
    assert(edge.cellType() == .edge);

    var w: f32 = 0.0;
    const d = edge.dart();
    if (!sm.isBoundaryDart(d)) {
        w += halfedge_cotan_weight.value(.{ .halfedge = d });
    }
    const dd = sm.phi2(d);
    if (!sm.isBoundaryDart(dd)) {
        w += halfedge_cotan_weight.value(.{ .halfedge = dd });
    }
    return w;
}
