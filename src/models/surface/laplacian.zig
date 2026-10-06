const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

/// Compute and return the cotan weight of the given halfedge,
/// i.e. cotan(theta)/2 where theta is the angle opposite to the halfedge in its incident face.
pub fn halfedgeCotanWeight(
    sm: *const SurfaceMesh,
    halfedge: SurfaceMesh.Halfedge,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
) f32 {
    const d = sm.dart(halfedge);
    if (sm.isBoundaryDart(d)) {
        return 0.0;
    }

    const p1 = vertex_position.value(sm.vertex(d));
    const p2 = vertex_position.value(sm.vertex(sm.phi1(d)));
    const p3 = vertex_position.value(sm.vertex(sm.phi_1(d)));
    const vecR = vec.sub3f(p1, p3);
    const vecL = vec.sub3f(p2, p3);
    // cotan(theta_i^jk) = (u . v) / ||u x v||
    return 0.5 * (vec.dot3f(vecR, vecL) / vec.norm3f(vec.cross3f(vecR, vecL)));
    // cotan(theta_i^jk) = (|ij|2 + |ik|2 - |jk|2) / (4 * Area(ijk))
}

/// Compute the cotan weights of all halfedges of the given SurfaceMesh
/// and store them in the given halfedge_cotan_weight data.
pub fn computeHalfedgeCotanWeights(
    io: std.Io,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    halfedge_cotan_weight: *SurfaceMesh.HalfedgeData(f32),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        vertex_position: SurfaceMesh.VertexData(Vec3f),
        halfedge_cotan_weight: *SurfaceMesh.HalfedgeData(f32),

        pub fn run(t: *const @This(), halfedge: SurfaceMesh.Halfedge) void {
            t.halfedge_cotan_weight.valuePtr(halfedge).* = halfedgeCotanWeight(
                t.surface_mesh,
                halfedge,
                t.vertex_position,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelHalfedgeTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
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
    halfedge: SurfaceMesh.Halfedge,
    edge_length: SurfaceMesh.EdgeData(f32),
    face_area: SurfaceMesh.FaceData(f32),
) f32 {
    const d = sm.dart(halfedge);
    if (sm.isBoundaryDart(d)) {
        return 0.0;
    }

    const l_ij = edge_length.value(sm.edge(d));
    const l_jk = edge_length.value(sm.edge(sm.phi1(d)));
    const l_ki = edge_length.value(sm.edge(sm.phi_1(d)));
    const area = face_area.value(sm.face(d));
    return (-l_ij * l_ij + l_jk * l_jk + l_ki * l_ki) / (4.0 * area);
}

/// Compute the cotan weights of all halfedges of the given SurfaceMesh
/// and store them in the given halfedge_cotan_weight data.
/// This version uses intrinsic geometry (edge lengths and face areas) instead of extrinsic vertex positions.
pub fn computeHalfedgeCotanWeightsIntrinsic(
    io: std.Io,
    sm: *SurfaceMesh,
    edge_length: SurfaceMesh.EdgeData(f32),
    face_area: SurfaceMesh.FaceData(f32),
    halfedge_cotan_weight: *SurfaceMesh.HalfedgeData(f32),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        edge_length: SurfaceMesh.EdgeData(f32),
        face_area: SurfaceMesh.FaceData(f32),
        halfedge_cotan_weight: *SurfaceMesh.HalfedgeData(f32),

        pub fn run(t: *const @This(), halfedge: SurfaceMesh.Halfedge) void {
            t.halfedge_cotan_weight.valuePtr(halfedge).* = halfedgeCotanWeightIntrinsic(
                t.surface_mesh,
                halfedge,
                t.edge_length,
                t.face_area,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelHalfedgeTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .edge_length = edge_length,
        .face_area = face_area,
        .halfedge_cotan_weight = halfedge_cotan_weight,
    });
}

/// Compute and return the cotan weight of the given edge.
pub fn edgeCotanWeight(
    sm: *const SurfaceMesh,
    edge: SurfaceMesh.Edge,
    halfedge_cotan_weight: SurfaceMesh.HalfedgeData(f32),
) f32 {
    var w: f32 = 0.0;
    const d = sm.dart(edge);
    if (!sm.isBoundaryDart(d)) {
        w += halfedge_cotan_weight.value(sm.halfedge(d));
    }
    const dd = sm.phi2(d);
    if (!sm.isBoundaryDart(dd)) {
        w += halfedge_cotan_weight.value(sm.halfedge(dd));
    }
    return w;
}
