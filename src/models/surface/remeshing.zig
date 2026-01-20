const std = @import("std");
const assert = std.debug.assert;

const zgp_log = std.log.scoped(.zgp);

const SurfaceMesh = @import("SurfaceMesh.zig");
const length = @import("length.zig");
const angle = @import("angle.zig");
const subdivision = @import("subdivision.zig");
const area = @import("area.zig");
const normal = @import("normal.zig");
const curvature = @import("curvature.zig");

const geometry_utils = @import("../../geometry/utils.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const bvh = @import("../../geometry/bvh.zig");

/// Return true if flipping the given edge improves the deviation from degree-6 vertices.
fn edgeShouldFlip(sm: *const SurfaceMesh, edge: SurfaceMesh.Cell) bool {
    assert(edge.cellType() == .edge);

    const d = edge.dart();
    const dd = sm.phi2(d);

    const w: i32 = @intCast(sm.degree(.{ .vertex = d }));
    const x: i32 = @intCast(sm.degree(.{ .vertex = dd }));
    const y: i32 = @intCast(sm.degree(.{ .vertex = sm.phi1(sm.phi1(d)) }));
    const z: i32 = @intCast(sm.degree(.{ .vertex = sm.phi1(sm.phi1(dd)) }));

    if (w < 4 or x < 4)
        return false;

    const deviation_pre: i32 = @intCast(@abs(w - 6) + @abs(x - 6) + @abs(y - 6) + @abs(z - 6));
    const deviation_post: i32 = @intCast(@abs(w - 1 - 6) + @abs(x - 1 - 6) + @abs(y + 1 - 6) + @abs(z + 1 - 6));
    return deviation_post < deviation_pre;
}

/// Remesh the given SurfaceMesh.
/// The obtained mesh will be triangular, with isotropic triangles and edge lengths
/// close to the mean edge length of the initial mesh times the given length factor.
/// If adaptive is true, the remeshing will use a curvature-dependent sizing field (and the given vertex_curvature datas
/// are supposed to be not null). Otherwise, a uniform sizing field will be used.
/// => Adaptive Remeshing for Real-Time Mesh Deformation (https://hal.science/hal-01295339/file/EGshort2013_Dunyach_et_al.pdf)
/// The given dependent datas will be updated accordingly after remeshing.
pub fn pliantRemeshing(
    sm: *SurfaceMesh,
    sm_bvh: bvh.TrianglesBVH,
    edge_length_factor: f32,
    adaptive: bool,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3f),
    edge_length: SurfaceMesh.CellData(.edge, f32),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3f),
    vertex_curvature: *curvature.SurfaceMeshCurvatureDatas,
) !void {
    try subdivision.triangulateFaces(sm);

    var mean_edge_length = geometry_utils.meanValue(f32, edge_length.data);
    const length_goal = mean_edge_length * edge_length_factor;

    var edge_it = try SurfaceMesh.CellIterator(.edge).init(sm);
    defer edge_it.deinit();
    var vertex_it = try SurfaceMesh.CellIterator(.vertex).init(sm);
    defer vertex_it.deinit();

    // detect features
    var feature_edge = try SurfaceMesh.CellMarker(.edge).init(sm);
    defer feature_edge.deinit();
    var feature_vertex = try SurfaceMesh.CellMarker(.vertex).init(sm);
    defer feature_vertex.deinit();
    var feature_corner = try SurfaceMesh.CellMarker(.vertex).init(sm);
    defer feature_corner.deinit();
    const angle_threshold: f32 = 60.0 * (std.math.pi / 180.0);
    while (edge_it.next()) |edge| {
        if (@abs(edge_dihedral_angle.value(edge)) > angle_threshold) {
            feature_edge.valuePtr(edge).* = true;
            const v1: SurfaceMesh.Cell = .{ .vertex = edge.dart() };
            const v2: SurfaceMesh.Cell = .{ .vertex = sm.phi1(edge.dart()) };
            feature_vertex.valuePtr(v1).* = true;
            feature_vertex.valuePtr(v2).* = true;
        }
    }
    while (vertex_it.next()) |vertex| {
        if (feature_vertex.value(vertex)) {
            var nb_incident_feature_edge: u32 = 0;
            var dart_it = sm.cellDartIterator(vertex);
            while (dart_it.next()) |d| {
                const e: SurfaceMesh.Cell = .{ .edge = d };
                if (feature_edge.value(e)) {
                    nb_incident_feature_edge += 1;
                    if (nb_incident_feature_edge > 2) {
                        break;
                    }
                }
            }
            if (nb_incident_feature_edge > 2) {
                feature_corner.valuePtr(vertex).* = true;
            }
        }
    }

    // sizing field for adaptive remeshing
    var vertex_sizing_field = try sm.addData(.vertex, f32, "__vertex_sizing_field");
    defer sm.removeData(.vertex, vertex_sizing_field.gen());

    var edge_marker = try SurfaceMesh.CellMarker(.edge).init(sm);
    defer edge_marker.deinit();

    for (0..5) |iteration| {
        // remove "flat" degree-3 vertices
        try normal.computeFaceNormals(sm, vertex_position, face_normal);
        try angle.computeEdgeDihedralAngles(sm, vertex_position, face_normal, edge_dihedral_angle);
        vertex_it.reset();
        while (vertex_it.next()) |vertex| {
            if (feature_corner.value(vertex)) {
                continue;
            }
            if (sm.degree(vertex) == 3) {
                var dart_it = sm.cellDartIterator(vertex);
                var is_flat: bool = true;
                while (dart_it.next()) |d| {
                    if (@abs(edge_dihedral_angle.value(.{ .edge = d })) > (10.0 * (std.math.pi / 180.0))) {
                        is_flat = false;
                        break;
                    }
                }
                if (is_flat) {
                    sm.removeVertex(vertex);
                    std.debug.print("remove vertex {}\n", .{sm.cellIndex(vertex)});
                }
            }
        }

        // cut long edges
        edge_marker.reset();
        edge_it.reset();
        while (edge_it.next()) |edge| {
            if (edge_marker.value(edge)) {
                continue;
            }
            const d = edge.dart();
            const dd = sm.phi2(d);
            const l = edge_length.value(edge);
            const length_goal_edge = if (adaptive and iteration > 1) @min(
                vertex_sizing_field.value(.{ .vertex = d }),
                vertex_sizing_field.value(.{ .vertex = dd }),
            ) else length_goal;
            if (l > length_goal_edge * 1.75) {
                const new_pos = vec.mulScalar3f(
                    vec.add3f(
                        vertex_position.value(.{ .vertex = d }),
                        vertex_position.value(.{ .vertex = dd }),
                    ),
                    0.5,
                );
                const v = try sm.cutEdge(edge);
                vertex_position.valuePtr(v).* = new_pos;
                edge_length.valuePtr(.{ .edge = d }).* = length.edgeLength(sm, .{ .edge = d }, vertex_position);
                edge_length.valuePtr(.{ .edge = dd }).* = length.edgeLength(sm, .{ .edge = dd }, vertex_position);
                if (feature_edge.value(edge)) {
                    feature_edge.valuePtr(.{ .edge = dd }).* = true;
                    feature_vertex.valuePtr(v).* = true;
                }
                if (adaptive and iteration > 1) {
                    vertex_sizing_field.valuePtr(v).* = 0.5 * (vertex_sizing_field.value(.{ .vertex = d }) +
                        vertex_sizing_field.value(.{ .vertex = dd }));
                }
                // triangulate adjacent (non-boundary) faces
                const d1 = sm.phi1(d);
                const dd1 = sm.phi1(dd);
                if (!sm.isBoundaryDart(d1)) {
                    const e = try sm.cutFace(d1, sm.phi1(sm.phi1(d1)));
                    edge_length.valuePtr(e).* = length.edgeLength(sm, e, vertex_position);
                    edge_marker.valuePtr(e).* = true; // do not process new edges in the same pass
                }
                if (!sm.isBoundaryDart(dd1)) {
                    const e = try sm.cutFace(dd1, sm.phi1(sm.phi1(dd1)));
                    edge_length.valuePtr(e).* = length.edgeLength(sm, e, vertex_position);
                    edge_marker.valuePtr(e).* = true; // do not process new edges in the same pass
                }
            }
            edge_marker.valuePtr(edge).* = true;
            edge_marker.valuePtr(.{ .edge = dd }).* = true;
        }

        // collapse short edges
        edge_it.reset();
        while (edge_it.next()) |edge| {
            const d = edge.dart();
            const d1 = sm.phi1(d);
            const v1: SurfaceMesh.Cell = .{ .vertex = d };
            const v2: SurfaceMesh.Cell = .{ .vertex = d1 };
            if (feature_corner.value(v1) or feature_corner.value(v2)) {
                continue;
            }
            if ((feature_vertex.value(v1) and !feature_vertex.value(v2)) or
                (!feature_vertex.value(v1) and feature_vertex.value(v2)))
            {
                continue;
            }
            const l = edge_length.value(edge);
            const length_goal_edge = if (adaptive and iteration > 1) @min(
                vertex_sizing_field.value(v1),
                vertex_sizing_field.value(v2),
            ) else length_goal;
            if (l < length_goal_edge * 0.6) {
                if (sm.canCollapseEdge(edge)) {
                    var new_pos = vec.mulScalar3f(
                        vec.add3f(vertex_position.value(v1), vertex_position.value(v2)),
                        0.5,
                    );
                    if (!sm.isIncidentToBoundary(edge)) {
                        if (sm.isIncidentToBoundary(v1)) {
                            new_pos = vertex_position.value(v1);
                        } else if (sm.isIncidentToBoundary(v2)) {
                            new_pos = vertex_position.value(v2);
                        }
                    }
                    const new_sizing_field = if (adaptive and iteration > 1) 0.5 * (vertex_sizing_field.value(v1) +
                        vertex_sizing_field.value(v2)) else length_goal;
                    const v = sm.collapseEdge(edge);
                    var dart_it = sm.cellDartIterator(v);
                    while (dart_it.next()) |vd| {
                        const e: SurfaceMesh.Cell = .{ .edge = vd };
                        edge_length.valuePtr(e).* = length.edgeLength(sm, e, vertex_position);
                    }
                    vertex_position.valuePtr(v).* = new_pos;
                    if (adaptive and iteration > 1) {
                        vertex_sizing_field.valuePtr(v).* = new_sizing_field;
                    }
                }
            }
        }

        // equalize degrees with edge flips
        edge_it.reset();
        while (edge_it.next()) |edge| {
            if (feature_edge.value(edge)) {
                continue;
            }
            if (sm.canFlipEdge(edge) and edgeShouldFlip(sm, edge)) {
                sm.flipEdge(edge);
                // not useful here as edge lengths are not used in this loop and will be recomputed right after
                // edge_length.valuePtr(edge).* = length.edgeLength(sm, edge, vertex_position);
            }
        }

        // tangential relaxation
        // first, update datas needed for relaxation after remeshing operations
        try length.computeEdgeLengths(sm, vertex_position, edge_length);
        try angle.computeCornerAngles(sm, vertex_position, corner_angle);
        try area.computeFaceAreas(sm, vertex_position, face_area);
        try normal.computeFaceNormals(sm, vertex_position, face_normal);
        try area.computeVertexAreas(sm, face_area, vertex_area);
        try normal.computeVertexNormals(sm, corner_angle, face_normal, vertex_normal);
        vertex_it.reset();
        while (vertex_it.next()) |vertex| {
            if (sm.isIncidentToBoundary(vertex) or feature_corner.value(vertex) or feature_vertex.value(vertex)) {
                continue;
            }
            var q = vec.zero3f;
            var w: f32 = 0.0;
            if (adaptive and iteration > 1) {
                // in the adaptive case, use area-weighted average of neighbors
                var dart_it = sm.cellDartIterator(vertex);
                while (dart_it.next()) |d| {
                    const f: SurfaceMesh.Cell = .{ .face = d };
                    var avg_sizing_field: f32 = 0.0;
                    var avg_position = vec.zero3f;
                    var count: u32 = 0;
                    var face_dart_it = sm.cellDartIterator(f);
                    while (face_dart_it.next()) |fd| {
                        const iv: SurfaceMesh.Cell = .{ .vertex = fd };
                        avg_sizing_field += vertex_sizing_field.value(iv);
                        avg_position = vec.add3f(avg_position, vertex_position.value(iv));
                        count += 1;
                    }
                    avg_sizing_field /= @floatFromInt(count);
                    avg_position = vec.divScalar3f(avg_position, @floatFromInt(count));
                    const a = face_area.value(f) * avg_sizing_field;
                    q = vec.add3f(q, vec.mulScalar3f(avg_position, a));
                    w += a;
                }
            } else {
                // in the uniform case, use uniform average of neighbors
                var dart_it = sm.cellDartIterator(vertex);
                while (dart_it.next()) |d| {
                    const nv: SurfaceMesh.Cell = .{ .vertex = sm.phi1(d) };
                    const a = vertex_area.value(nv);
                    q = vec.add3f(
                        q,
                        vec.mulScalar3f(vertex_position.value(nv), a),
                    );
                    w += a;
                }
            }
            if (w > 0.0) {
                q = vec.divScalar3f(q, w);
                const n = vertex_normal.value(vertex);
                const p = vertex_position.value(vertex);
                vertex_position.valuePtr(vertex).* = sm_bvh.closestPoint(vec.add3f(
                    q,
                    vec.mulScalar3f(
                        n,
                        vec.dot3f(
                            n,
                            vec.sub3f(p, q),
                        ),
                    ),
                ));
            }
        }

        // in the adaptive case, compute a curvature-based sizing field at the end of iterations 1 and 3
        // (sizing field is not used on iterations 0 and 1 to allow for initial mesh regularization)
        if (adaptive and (iteration == 1 or iteration == 3)) {
            // first, update data needed for sizing field computation
            try length.computeEdgeLengths(sm, vertex_position, edge_length);
            try angle.computeCornerAngles(sm, vertex_position, corner_angle);
            try area.computeFaceAreas(sm, vertex_position, face_area);
            try normal.computeFaceNormals(sm, vertex_position, face_normal);
            try angle.computeEdgeDihedralAngles(sm, vertex_position, face_normal, edge_dihedral_angle);
            try area.computeVertexAreas(sm, face_area, vertex_area);
            try normal.computeVertexNormals(sm, corner_angle, face_normal, vertex_normal);
            try curvature.computeVertexCurvatures(
                sm,
                vertex_position,
                vertex_normal,
                edge_dihedral_angle,
                edge_length,
                face_area,
                vertex_curvature,
            );
            mean_edge_length = geometry_utils.meanValue(f32, edge_length.data);
            const approx_tolerance = mean_edge_length * 0.05;
            vertex_it.reset();
            while (vertex_it.next()) |vertex| {
                const kmin = vertex_curvature.vertex_kmin.?.value(vertex);
                const kmax = vertex_curvature.vertex_kmax.?.value(vertex);
                const k = @max(@abs(kmax), @abs(kmin)) + 1e-4;
                const h = std.math.clamp(
                    (6.0 * approx_tolerance / k) - (3.0 * approx_tolerance * approx_tolerance),
                    1e-5,
                    2e-3,
                );
                vertex_sizing_field.valuePtr(vertex).* = @sqrt(h);
            }
        }
    }

    // update all given dependent datas one last time after remeshing
    try length.computeEdgeLengths(sm, vertex_position, edge_length);
    try angle.computeCornerAngles(sm, vertex_position, corner_angle);
    try area.computeFaceAreas(sm, vertex_position, face_area);
    try normal.computeFaceNormals(sm, vertex_position, face_normal);
    try angle.computeEdgeDihedralAngles(sm, vertex_position, face_normal, edge_dihedral_angle);
    try area.computeVertexAreas(sm, face_area, vertex_area);
    try normal.computeVertexNormals(sm, corner_angle, face_normal, vertex_normal);
    if (adaptive) {
        try curvature.computeVertexCurvatures(
            sm,
            vertex_position,
            vertex_normal,
            edge_dihedral_angle,
            edge_length,
            face_area,
            vertex_curvature,
        );
    }
}
