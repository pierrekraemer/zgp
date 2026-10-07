const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const mat = @import("../../geometry/mat.zig");
const Mat3f = mat.Mat3f;
const geometry_utils = @import("../../geometry/utils.zig");
const eigen = @import("../../geometry/eigen.zig");

const VertexCurvatureValues = struct {
    kmin: f32,
    Kmin: Vec3f,
    kmax: f32,
    Kmax: Vec3f,
};

pub const SurfaceMeshCurvatureDatas = struct {
    vertex_kmin: ?SurfaceMesh.VertexData(f32) = null,
    vertex_Kmin: ?SurfaceMesh.VertexData(Vec3f) = null,
    vertex_kmax: ?SurfaceMesh.VertexData(f32) = null,
    vertex_Kmax: ?SurfaceMesh.VertexData(Vec3f) = null,
};

fn addEdgeContributionToTensor(
    sm: *const SurfaceMesh,
    d: SurfaceMesh.Dart,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    edge_dihedral_angle: SurfaceMesh.EdgeData(f32),
    edge_length: SurfaceMesh.EdgeData(f32),
    n: Vec3f,
    tensor: *Mat3f,
) void {
    const d2 = sm.phi2(d);
    const ev = vec.sub3f(
        vertex_position.value(sm.vertex(d2)),
        vertex_position.value(sm.vertex(d)),
    );
    const proj_ev = geometry_utils.removeComponent(ev, n);
    const e = sm.edge(d);
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
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Vertex,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    vertex_normal: SurfaceMesh.VertexData(Vec3f),
    edge_dihedral_angle: SurfaceMesh.EdgeData(f32),
    edge_length: SurfaceMesh.EdgeData(f32),
    face_area: SurfaceMesh.FaceData(f32),
) !VertexCurvatureValues {
    const n = vertex_normal.value(vertex);

    var tensor = mat.zero3f;
    var area: f32 = 0.0;

    // accumulate edge contributions to the curvature tensor & face area
    // in the 2-ring around the vertex
    // TODO: compare to the results obtained using selection.cellsWithinSphereAroundVertex (multithread warning for markers)
    var dart_it = sm.vertexDartIterator(sm.dart(vertex));
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
                area += face_area.value(sm.face(d_it));
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
        .kmin = @floatCast(evals[imin]),
        .Kmin = vec.vec3fFromVec3d(evecs[imin]),
        .kmax = @floatCast(evals[imax]),
        .Kmax = vec.vec3fFromVec3d(evecs[imax]),
    };
}

/// Compute the principal curvatures magnitudes and directions of all vertices of the given SurfaceMesh
/// and store the results in the given datas (which are supposed to be not null).
pub fn computeVertexCurvatures(
    io: std.Io,
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    vertex_normal: SurfaceMesh.VertexData(Vec3f),
    edge_dihedral_angle: SurfaceMesh.EdgeData(f32),
    edge_length: SurfaceMesh.EdgeData(f32),
    face_area: SurfaceMesh.FaceData(f32),
    vertex_curvature: *SurfaceMeshCurvatureDatas,
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        vertex_position: SurfaceMesh.VertexData(Vec3f),
        vertex_normal: SurfaceMesh.VertexData(Vec3f),
        edge_dihedral_angle: SurfaceMesh.EdgeData(f32),
        edge_length: SurfaceMesh.EdgeData(f32),
        face_area: SurfaceMesh.FaceData(f32),
        vertex_curvature: *SurfaceMeshCurvatureDatas,

        pub fn run(t: *const @This(), vertex: SurfaceMesh.Vertex) void {
            const curvature_values = try vertexCurvature(
                t.surface_mesh,
                vertex,
                t.vertex_position,
                t.vertex_normal,
                t.edge_dihedral_angle,
                t.edge_length,
                t.face_area,
            );
            t.vertex_curvature.vertex_kmin.?.valuePtr(vertex).* = curvature_values.kmin;
            t.vertex_curvature.vertex_Kmin.?.valuePtr(vertex).* = curvature_values.Kmin;
            t.vertex_curvature.vertex_kmax.?.valuePtr(vertex).* = curvature_values.kmax;
            t.vertex_curvature.vertex_Kmax.?.valuePtr(vertex).* = curvature_values.Kmax;
        }
    };

    var pctr: SurfaceMesh.ParallelVertexTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .vertex_position = vertex_position,
        .vertex_normal = vertex_normal,
        .edge_dihedral_angle = edge_dihedral_angle,
        .edge_length = edge_length,
        .face_area = face_area,
        .vertex_curvature = vertex_curvature,
    });
}

/// Compute and return the Gaussian curvature of the given vertex
/// computed as the angle defect.
pub fn vertexGaussianCurvature(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Vertex,
    corner_angle: SurfaceMesh.CornerData(f32),
) f32 {
    var base: f32 = std.math.tau;
    if (sm.isIncidentToBoundary(vertex)) {
        base = std.math.pi;
    }
    var angle_sum: f32 = 0.0;
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (!sm.isBoundaryDart(d)) {
            angle_sum += corner_angle.value(sm.corner(d));
        }
    }
    return base - angle_sum;
}

/// Compute the Gaussian curvatures of all vertices of the given SurfaceMesh
/// and store the results in the given vertex_gaussian_curvature data.
pub fn computeVertexGaussianCurvatures(
    io: std.Io,
    sm: *SurfaceMesh,
    corner_angle: SurfaceMesh.CornerData(f32),
    vertex_gaussian_curvature: *SurfaceMesh.VertexData(f32),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        corner_angle: SurfaceMesh.CornerData(f32),
        vertex_gaussian_curvature: *SurfaceMesh.VertexData(f32),

        pub fn run(t: *const @This(), vertex: SurfaceMesh.Vertex) void {
            t.vertex_gaussian_curvature.valuePtr(vertex).* = vertexGaussianCurvature(
                t.surface_mesh,
                vertex,
                t.corner_angle,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelVertexTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .corner_angle = corner_angle,
        .vertex_gaussian_curvature = vertex_gaussian_curvature,
    });
}
