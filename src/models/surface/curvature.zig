const std = @import("std");
const assert = std.debug.assert;
const zgp_log = std.log.scoped(.zgp);

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const mat = @import("../../geometry/mat.zig");
const Mat3f = mat.Mat3f;
const geometry_utils = @import("../../geometry/utils.zig");
const eigen = @import("../../geometry/eigen.zig");

const selection = @import("selection.zig");

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

/// Compute and return the principal curvatures magnitudes and directions of the given vertex.
/// Results are returned as (kmin, Kmin, kmax, Kmax).
pub fn vertexCurvature(
    sm: *SurfaceMesh,
    vertex: SurfaceMesh.Vertex,
    vertex_position: SurfaceMesh.VertexData(Vec3f),
    vertex_normal: SurfaceMesh.VertexData(Vec3f),
    edge_dihedral_angle: SurfaceMesh.EdgeData(f32),
    edge_length: SurfaceMesh.EdgeData(f32),
    face_area: SurfaceMesh.FaceData(f32),
    sel_ctx: *selection.WithinSphereSelectionContext,
) !VertexCurvatureValues {
    const p = vertex_position.value(vertex);
    const n = vertex_normal.value(vertex);
    var tensor = mat.zero(Mat3f);
    var area: f32 = 0.0;

    // collect the cells in a sphere of the given radius around the vertex
    try sel_ctx.cellsWithinSphereAroundVertex(vertex);
    // accumulate edge contributions to the curvature tensor
    for (sel_ctx.edge_buffer.items) |e| {
        const d = sm.dart(e);
        const ev = vec.sub(
            vertex_position.value(sm.vertex(sm.phi1(d))),
            vertex_position.value(sm.vertex(d)),
        );
        tensor = mat.add(
            tensor,
            mat.mulScalar(
                mat.outerProduct(ev, ev),
                edge_dihedral_angle.value(e) / edge_length.value(e),
            ),
        );
    }
    // accumulate face areas
    for (sel_ctx.face_buffer.items) |f| {
        area += face_area.value(f);
    }
    // account for the contribution of edges and faces that are crossed by the sphere
    for (sel_ctx.crossed_dart_buffer.items) |d| {
        const p1 = vertex_position.value(sm.vertex(d));
        const p2 = vertex_position.value(sm.vertex(sm.phi1(d)));
        const p3 = vertex_position.value(sm.vertex(sm.phi_1(d)));
        const ev = vec.sub(p2, p1);
        _, const tp1p2 = geometry_utils.intersectionSphereSegment(p, sel_ctx.radius, p1, p2) orelse continue;
        // we know that p1 is inside the sphere and p2 is outside, so tp1p2 is the coordinate of the intersection point
        assert(tp1p2 >= 0.0 and tp1p2 <= 1.0);
        const e = sm.edge(d);
        tensor = mat.add(
            tensor,
            mat.mulScalar(
                mat.outerProduct(ev, ev),
                tp1p2 * edge_dihedral_angle.value(e) / edge_length.value(e),
            ),
        );
        if (!sm.isBoundaryDart(d)) {
            const farea = face_area.value(sm.face(d));
            // we know that p1 is inside the sphere and p2 is outside
            if (geometry_utils.pointInSphere(p3, p, sel_ctx.radius)) { // p3 is inside the sphere
                _, const tp3p2 = geometry_utils.intersectionSphereSegment(p, sel_ctx.radius, p3, p2) orelse continue;
                assert(tp3p2 >= 0.0 and tp3p2 <= 1.0);
                area += (tp1p2 + tp3p2 - tp1p2 * tp3p2) * farea;
            } else { // p3 is outside the sphere
                _, const tp1p3 = geometry_utils.intersectionSphereSegment(p, sel_ctx.radius, p1, p3) orelse continue;
                assert(tp1p3 >= 0.0 and tp1p3 <= 1.0);
                area += (tp1p2 * tp1p3) * farea;
            }
        }
    }

    tensor = mat.mulScalar(tensor, 1.0 / area);
    const proj = mat.sub(mat.identity(Mat3f), mat.outerProduct(n, n));
    tensor = mat.mul(proj, mat.mul(tensor, proj));

    const evals, const evecs = eigen.eigenSolver(mat.cast(f64, tensor));

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
        .Kmin = vec.cast(f32, evecs[imin]),
        .kmax = @floatCast(evals[imax]),
        .Kmax = vec.cast(f32, evecs[imax]),
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
    radius_ratio: f32, // this value is multiplied by the mean edge length to get the neighborhood radius for each vertex
    vertex_curvature: *SurfaceMeshCurvatureDatas,
) !void {
    const Task = struct {
        surface_mesh: *SurfaceMesh,
        vertex_position: SurfaceMesh.VertexData(Vec3f),
        vertex_normal: SurfaceMesh.VertexData(Vec3f),
        edge_dihedral_angle: SurfaceMesh.EdgeData(f32),
        edge_length: SurfaceMesh.EdgeData(f32),
        face_area: SurfaceMesh.FaceData(f32),
        neighborhood_radius: f32,
        vertex_curvature: *SurfaceMeshCurvatureDatas,

        pub fn run(t: *const @This(), sel_ctx: *selection.WithinSphereSelectionContext, vertex: SurfaceMesh.Vertex) void {
            if (!sel_ctx.initialized) {
                sel_ctx.init(t.surface_mesh, t.vertex_position, t.neighborhood_radius) catch |err| {
                    zgp_log.err("Failed to initialize selection context for vertex curvature computation: {}", .{err});
                    return;
                };
            }
            const curvature_values = vertexCurvature(
                t.surface_mesh,
                vertex,
                t.vertex_position,
                t.vertex_normal,
                t.edge_dihedral_angle,
                t.edge_length,
                t.face_area,
                sel_ctx,
            ) catch VertexCurvatureValues{ .kmin = 0.0, .Kmin = vec.zero(Vec3f), .kmax = 0.0, .Kmax = vec.zero(Vec3f) };
            t.vertex_curvature.vertex_kmin.?.valuePtr(vertex).* = curvature_values.kmin;
            t.vertex_curvature.vertex_Kmin.?.valuePtr(vertex).* = curvature_values.Kmin;
            t.vertex_curvature.vertex_kmax.?.valuePtr(vertex).* = curvature_values.kmax;
            t.vertex_curvature.vertex_Kmax.?.valuePtr(vertex).* = curvature_values.Kmax;
        }
    };

    var pctr: SurfaceMesh.ParallelVertexTaskRunnerWithContext(selection.WithinSphereSelectionContext) = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .vertex_position = vertex_position,
        .vertex_normal = vertex_normal,
        .edge_dihedral_angle = edge_dihedral_angle,
        .edge_length = edge_length,
        .face_area = face_area,
        .neighborhood_radius = edge_length.data.meanValue() * radius_ratio,
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
    const d = sm.dart(vertex);
    if (sm.isOrbitIncidentToBoundary(d, .vertex)) {
        base = std.math.pi;
    }
    var angle_sum: f32 = 0.0;
    var dart_it = sm.vertexDartIterator(d);
    while (dart_it.next()) |vd| {
        if (!sm.isBoundaryDart(vd)) {
            angle_sum += corner_angle.value(sm.corner(vd));
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
