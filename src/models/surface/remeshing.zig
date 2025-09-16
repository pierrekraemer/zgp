const std = @import("std");
const assert = std.debug.assert;

const zgp_log = std.log.scoped(.zgp);

const SurfaceMesh = @import("SurfaceMesh.zig");
const length = @import("length.zig");
const angle = @import("angle.zig");
const subdivision = @import("subdivision.zig");
const area = @import("area.zig");
const normal = @import("normal.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

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
/// TODO: adaptive sampling guided by a curvature dependent sizing field.
pub fn pliantRemeshing(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
    edge_dihedral_angle: SurfaceMesh.CellData(.edge, f32),
    vertex_area: SurfaceMesh.CellData(.vertex, f32),
    vertex_normal: SurfaceMesh.CellData(.vertex, Vec3),
    length_factor: f32,
) !void {
    try subdivision.triangulateFaces(sm);

    const mean_edge_length = try length.meanEdgeLength(sm, vertex_position);
    const length_goal_squared = mean_edge_length * mean_edge_length * length_factor * length_factor;

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

    var edge_marker = try SurfaceMesh.CellMarker(.edge).init(sm);
    defer edge_marker.deinit();

    for (0..5) |_| {
        // reset edge marker & iterators
        edge_marker.reset();
        edge_it.reset();
        vertex_it.reset();

        // cut long edges
        while (edge_it.next()) |edge| {
            if (!edge_marker.value(edge)) {
                const d = edge.dart();
                const dd = sm.phi2(d);
                const v1: SurfaceMesh.Cell = .{ .vertex = d };
                const v2: SurfaceMesh.Cell = .{ .vertex = dd };
                const length_squared = vec.squaredNorm3(vec.sub3(vertex_position.value(v2), vertex_position.value(v1)));
                if (length_squared > length_goal_squared * 4.0) {
                    const new_pos = vec.mulScalar3(
                        vec.add3(vertex_position.value(v1), vertex_position.value(v2)),
                        0.5,
                    );
                    const v = try sm.cutEdge(edge);
                    vertex_position.valuePtr(v).* = new_pos;
                    // triangulate adjacent (non-boundary) faces
                    const d1 = sm.phi1(d);
                    const dd1 = sm.phi1(dd);
                    if (feature_edge.value(edge)) {
                        feature_edge.valuePtr(.{ .edge = dd }).* = true;
                        feature_vertex.valuePtr(v).* = true;
                    }
                    if (!sm.isBoundaryDart(d1)) {
                        const e = try sm.cutFace(d1, sm.phi1(sm.phi1(d1)));
                        edge_marker.valuePtr(e).* = true; // do not process new edges in the same pass
                    }
                    if (!sm.isBoundaryDart(dd1)) {
                        const e = try sm.cutFace(dd1, sm.phi1(sm.phi1(dd1)));
                        edge_marker.valuePtr(e).* = true; // do not process new edges in the same pass
                    }
                }
                edge_marker.valuePtr(edge).* = true;
                edge_marker.valuePtr(.{ .edge = dd }).* = true;
            }
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
            const length_squared = vec.squaredNorm3(vec.sub3(vertex_position.value(v2), vertex_position.value(v1)));
            if (length_squared < length_goal_squared * 0.25) {
                if (sm.canCollapseEdge(edge)) {
                    var new_pos = vec.mulScalar3(
                        vec.add3(vertex_position.value(v1), vertex_position.value(v2)),
                        0.5,
                    );
                    if (!sm.isIncidentToBoundary(edge)) {
                        if (sm.isIncidentToBoundary(v1)) {
                            new_pos = vertex_position.value(v1);
                        } else if (sm.isIncidentToBoundary(v2)) {
                            new_pos = vertex_position.value(v2);
                        }
                    }
                    const v = sm.collapseEdge(edge);
                    vertex_position.valuePtr(v).* = new_pos;
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
            }
        }

        // tangential relaxation
        try angle.computeCornerAngles(sm, vertex_position, corner_angle);
        try area.computeFaceAreas(sm, vertex_position, face_area);
        try normal.computeFaceNormals(sm, vertex_position, face_normal);
        try area.computeVertexAreas(sm, face_area, vertex_area);
        try normal.computeVertexNormals(sm, corner_angle, face_normal, vertex_normal);
        while (vertex_it.next()) |vertex| {
            if (sm.isIncidentToBoundary(vertex) or feature_corner.value(vertex) or feature_vertex.value(vertex)) {
                continue;
            }
            var q = vec.zero3;
            var w: f32 = 0.0;
            var dart_it = sm.cellDartIterator(vertex);
            while (dart_it.next()) |dart| {
                const nv: SurfaceMesh.Cell = .{ .vertex = sm.phi1(dart) };
                const a = vertex_area.value(nv);
                q = vec.add3(
                    q,
                    vec.mulScalar3(vertex_position.value(nv), a),
                );
                w += a;
            }
            if (w > 0.0) {
                q = vec.divScalar3(q, w);
                const n = vertex_normal.value(vertex);
                const p = vertex_position.value(vertex);
                vertex_position.valuePtr(vertex).* = vec.add3(
                    q,
                    vec.mulScalar3(
                        n,
                        vec.dot3(
                            n,
                            vec.sub3(p, q),
                        ),
                    ),
                );
            }
        }
    }

    // update dependent datas one last time after remeshing
    try angle.computeCornerAngles(sm, vertex_position, corner_angle);
    try area.computeFaceAreas(sm, vertex_position, face_area);
    try normal.computeFaceNormals(sm, vertex_position, face_normal);
    try angle.computeEdgeDihedralAngles(sm, vertex_position, face_normal, edge_dihedral_angle);
    try area.computeVertexAreas(sm, face_area, vertex_area);
    try normal.computeVertexNormals(sm, corner_angle, face_normal, vertex_normal);
}
