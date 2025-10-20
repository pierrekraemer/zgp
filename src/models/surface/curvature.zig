const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const geometry_utils = @import("../../geometry/utils.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const mat = @import("../../geometry/mat.zig");
const Mat3f = mat.Mat3f;
const eigen = @import("../../geometry/eigen.zig");

fn addEdgeContributionToTensor(
    sm: *const SurfaceMesh,
    d: SurfaceMesh.Dart,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
    edge_length: SurfaceMesh.CellData(.edge, f32),
    n: Vec3f,
    tensor: *Mat3f,
) void {
    const d2 = sm.phi2(d);
    const e: SurfaceMesh.Cell = .{ .edge = d };
    const ev = vec.sub3f(
        vertex_position.value(.{ .vertex = d2 }),
        vertex_position.value(.{ .vertex = d }),
    );
    const proj_ev = geometry_utils.removeComponent(ev, n);
    tensor.* = mat.add3f(
        tensor.*,
        mat.mulScalar3f(
            mat.outerProduct3f(proj_ev, proj_ev),
            edge_dihedral_angle.value(e) / edge_length.value(e),
        ),
    );
}

/// Compute and return the principal curvatures magnitudes and directions of the given vertex.
/// Results are returned as (kmin, Kmin, kmax, Kmax).
pub fn vertexCurvature(
    sm: *SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
    edge_length: SurfaceMesh.CellData(.edge, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
) !struct { f32, Vec3f, f32, Vec3f } {
    assert(vertex.cellType() == .vertex);

    const n = vertex_normal.value(vertex);

    var tensor = mat.zero3f;
    var area: f32 = 0.0;

    // accumulate edge contributions to the curvature tensor & face area
    // in the 2-ring around the vertex
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        var d_it = sm.phi2(d);
        const d_end = sm.phi2(sm.phi_1(d_it));
        var i: u32 = 0;
        while (d_it != d_end) : ({
            d_it = sm.phi1(sm.phi2(d_it));
            i += 1;
        }) {
            addEdgeContributionToTensor(sm, d_it, vertex_position, edge_dihedral_angle, edge_length, n, &tensor);
            const d_it2 = sm.phi2(d_it);
            if (d_it2 != d and !sm.isBoundaryDart(d_it)) {
                area += face_area.value(.{ .face = d_it });
            }
            if (i >= 3) { // gather exterior 2-ring edges
                addEdgeContributionToTensor(sm, sm.phi1(d_it), vertex_position, edge_dihedral_angle, edge_length, n, &tensor);
            }
        }
    }

    tensor = mat.mulScalar3f(tensor, 1.0 / area);

    const evals, const evecs = eigen.eigenSolver(mat.mat3dFromMat3f(tensor));

    // Eigen values sorting:
    // 1) The eigenvector associated to the smallest absolute eigenvalue is the normal direction.
    // 2) The two remaining eigenpairs are tangent and ordered so that kmin <= kmax.
    var inormal: usize = 0;
    if (@abs(evals[1]) < @abs(evals[inormal])) {
        inormal = 1;
    }
    if (@abs(evals[2]) < @abs(evals[inormal])) {
        inormal = 2;
    }
    // Order tangent eigenpairs by eigenvalue
    var imin: usize = (inormal + 1) % 3;
    var imax: usize = (inormal + 2) % 3;
    if (evals[imin] > evals[imax]) {
        const tmp = imin;
        imin = imax;
        imax = tmp;
    }

    return .{
        @floatCast(evals[imin]), // kmin
        vec.vec3fFromVec3d(evecs[imax]), // Kmin
        @floatCast(evals[imax]), // kmax
        vec.vec3fFromVec3d(evecs[imin]), // Kmax
    };
}

/// Compute the principal curvatures magnitudes and directions of all vertices of the given SurfaceMesh
/// and store the results in the given datas.
pub fn computeVertexCurvatures(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
    edge_length: SurfaceMesh.CellData(.edge, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
    vertex_kmin: SurfaceMesh.CellData(.vertex, f32),
    vertex_Kmin: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_kmax: SurfaceMesh.CellData(.vertex, f32),
    vertex_Kmax: SurfaceMesh.CellData(.vertex, Vec3f),
) !void {
    var it = try SurfaceMesh.CellIterator(.vertex).init(sm);
    defer it.deinit();
    while (it.next()) |vertex| {
        const kmin, const Kmin, const kmax, const Kmax = try vertexCurvature(
            sm,
            vertex,
            vertex_position,
            vertex_normal,
            edge_dihedral_angle,
            edge_length,
            face_area,
        );
        vertex_kmin.valuePtr(vertex).* = kmin;
        vertex_Kmin.valuePtr(vertex).* = Kmin;
        vertex_kmax.valuePtr(vertex).* = kmax;
        vertex_Kmax.valuePtr(vertex).* = Kmax;
    }
}

/// Compute and return the Gaussian curvature of the given vertex
/// computed as the angle defect.
pub fn vertexGaussianCurvature(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
) f32 {
    assert(vertex.cellType() == .vertex);
    var base: f32 = 2.0 * std.math.pi;
    if (sm.isIncidentToBoundary(vertex)) {
        base = std.math.pi;
    }
    var angle_sum: f32 = 0.0;
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (!sm.isBoundaryDart(d)) {
            angle_sum += corner_angle.value(.{ .corner = d });
        }
    }
    return base - angle_sum;
}

/// Compute the Gaussian curvatures of all vertices of the given SurfaceMesh
/// and store the results in the given vertex_gaussian_curvature data.
pub fn computeVertexGaussianCurvatures(
    sm: *SurfaceMesh,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    vertex_gaussian_curvature: SurfaceMesh.CellData(.vertex, f32),
) !void {
    var it = try SurfaceMesh.CellIterator(.vertex).init(sm);
    defer it.deinit();
    while (it.next()) |vertex| {
        vertex_gaussian_curvature.valuePtr(vertex).* = vertexGaussianCurvature(
            sm,
            vertex,
            corner_angle,
        );
    }
}
