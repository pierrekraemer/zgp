const std = @import("std");
const assert = std.debug.assert;

const PriorityQueue = @import("../../utils/PriorityQueue.zig").PriorityQueue;

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const length = @import("length.zig");
const angle = @import("angle.zig");
const subdivision = @import("subdivision.zig");
const area = @import("area.zig");
const normal = @import("normal.zig");
const curvature = @import("curvature.zig");

const bvh = @import("../../geometry/bvh.zig");

/// Return true if flipping the given edge improves the deviation from degree-6 vertices.
fn edgeShouldFlip(sm: *const SurfaceMesh, edge: SurfaceMesh.Edge) bool {
    const d = sm.dart(edge);
    const dd = sm.phi2(d);

    const w: i32 = @intCast(sm.degree(sm.vertex(d)));
    const x: i32 = @intCast(sm.degree(sm.vertex(dd)));
    const y: i32 = @intCast(sm.degree(sm.vertex(sm.phi_1(d))));
    const z: i32 = @intCast(sm.degree(sm.vertex(sm.phi_1(dd))));

    if (w < 4 or x < 4)
        return false;

    const deviation_pre: i32 = @intCast(@abs(w - 6) + @abs(x - 6) + @abs(y - 6) + @abs(z - 6));
    const deviation_post: i32 = @intCast(@abs(w - 1 - 6) + @abs(x - 1 - 6) + @abs(y + 1 - 6) + @abs(z + 1 - 6));
    return deviation_post < deviation_pre;
}

/// Remesh the given SurfaceMesh.
/// The obtained mesh will be triangular, with isotropic triangles and edge lengths
/// close to the mean edge length of the initial mesh times the given length factor.
/// If preserve_features is true, detected feature edges & corners will be preserved.
/// If adaptive is true, the remeshing will use a curvature-dependent sizing field (and the given vertex_curvature datas
/// are supposed to be not null). Otherwise, a uniform sizing field will be used.
/// => Adaptive Remeshing for Real-Time Mesh Deformation (https://hal.science/hal-01295339/file/EGshort2013_Dunyach_et_al.pdf)
/// The given dependent datas will be updated accordingly after remeshing.
pub fn isotropicRemeshing(
    allocator: std.mem.Allocator,
    io: std.Io,
    sm: *SurfaceMesh,
    sm_bvh: *bvh.TrianglesBVH,
    edge_length_factor: f32,
    preserve_features: bool,
    adaptive: bool,
    vertex_position: *SurfaceMesh.VertexData(Vec3f),
    corner_angle: *SurfaceMesh.CornerData(f32),
    face_area: *SurfaceMesh.FaceData(f32),
    face_normal: *SurfaceMesh.FaceData(Vec3f),
    edge_length: *SurfaceMesh.EdgeData(f32),
    edge_dihedral_angle: *SurfaceMesh.EdgeData(f32),
    vertex_area: *SurfaceMesh.VertexData(f32),
    vertex_normal: *SurfaceMesh.VertexData(Vec3f),
    vertex_curvature: *curvature.SurfaceMeshCurvatureDatas,
) !void {
    try subdivision.triangulateFaces(allocator, sm);

    var mean_edge_length = edge_length.data.meanValue();
    const length_goal = mean_edge_length * edge_length_factor;

    var edge_it = sm.edgeIterator();
    var vertex_it = sm.vertexIterator();

    // feature edges are edges with a dihedral angle above a certain threshold
    var feature_edge: SurfaceMesh.EdgeMarker = try .init(sm);
    defer feature_edge.deinit();
    // feature vertices are vertices incident to at least one feature edge
    var feature_vertex: SurfaceMesh.VertexMarker = try .init(sm);
    defer feature_vertex.deinit();
    // feature corners are vertices incident to more than 2 feature edges
    var feature_corner: SurfaceMesh.VertexMarker = try .init(sm);
    defer feature_corner.deinit();

    if (preserve_features) {
        const angle_threshold: f32 = 75.0 * (std.math.pi / 180.0); // should be a parameter
        while (edge_it.next()) |edge| {
            if (@abs(edge_dihedral_angle.value(edge)) > angle_threshold) {
                feature_edge.mark(edge);
                const d = sm.dart(edge);
                feature_vertex.mark(sm.vertex(d));
                feature_vertex.mark(sm.vertex(sm.phi1(d)));
            }
        }
        while (vertex_it.next()) |vertex| {
            if (feature_vertex.isMarked(vertex)) {
                var nb_incident_feature_edge: u32 = 0;
                var dart_it = sm.vertexDartIterator(sm.dart(vertex));
                while (dart_it.next()) |d| {
                    const e = sm.edge(d);
                    if (feature_edge.isMarked(e)) {
                        nb_incident_feature_edge += 1;
                        if (nb_incident_feature_edge > 2) {
                            break;
                        }
                    }
                }
                if (nb_incident_feature_edge > 2) {
                    feature_corner.mark(vertex);
                }
            }
        }
    }

    // sizing field for adaptive remeshing
    var vertex_sizing_field = try sm.addData(.vertex, f32, "__vertex_sizing_field");
    defer sm.removeData(vertex_sizing_field);

    // Priority queue types for edge cut & collapse, ordered by edge length (descending for cut, ascending for collapse)
    const EdgeQueueContext = struct {
        edge_queue_index: *SurfaceMesh.EdgeData(?usize),
    };
    const EdgeInfo = struct {
        const EdgeInfo = @This();
        edge: SurfaceMesh.Edge,
        length: f32,
        pub fn cmpAsc(_: EdgeQueueContext, a: EdgeInfo, b: EdgeInfo) std.math.Order {
            const length_order = std.math.order(a.length, b.length);
            if (length_order != .eq) return length_order;
            // tie-breaker: use edge indices to order edges
            return std.math.order(a.edge.index, b.edge.index);
        }
        pub fn cmpDesc(_: EdgeQueueContext, a: EdgeInfo, b: EdgeInfo) std.math.Order {
            const length_order = std.math.order(b.length, a.length);
            if (length_order != .eq) return length_order;
            // tie-breaker: use edge indices to order edges
            return std.math.order(a.edge.index, b.edge.index);
        }
        pub fn setEdgeIndexInQueue(ctx: EdgeQueueContext, a: EdgeInfo, index: usize) void {
            ctx.edge_queue_index.valuePtr(a.edge).* = index;
        }
    };
    const EdgeQueueAsc = PriorityQueue(EdgeInfo, EdgeQueueContext, EdgeInfo.cmpAsc, EdgeInfo.setEdgeIndexInQueue);
    const EdgeQueueDesc = PriorityQueue(EdgeInfo, EdgeQueueContext, EdgeInfo.cmpDesc, EdgeInfo.setEdgeIndexInQueue);
    const EdgeQueueUtil = struct {
        fn removeEdgeFromQueue(queue: anytype, edge: SurfaceMesh.Edge) void {
            if (queue.context.edge_queue_index.value(edge)) |index| {
                _ = queue.popIndex(index);
            }
            queue.context.edge_queue_index.valuePtr(edge).* = null;
        }
    };

    var cut_edge_queue_index = try sm.addData(.edge, ?usize, "__cut_edge_queue_index");
    defer sm.removeData(cut_edge_queue_index);
    var cut_edge_queue: EdgeQueueDesc = .initContext(.{
        .edge_queue_index = &cut_edge_queue_index,
    });
    defer cut_edge_queue.deinit(allocator);

    var collapse_edge_queue_index = try sm.addData(.edge, ?usize, "__collapse_edge_queue_index");
    defer sm.removeData(collapse_edge_queue_index);
    var collapse_edge_queue: EdgeQueueAsc = .initContext(.{
        .edge_queue_index = &collapse_edge_queue_index,
    });
    defer collapse_edge_queue.deinit(allocator);

    // 2 iterations are performed in the adaptive case:
    // - 1st iteration is uniform
    // - a curvature-based sizing field is computed after this iteration
    // - 2nd iteration uses the sizing field
    for (0..2) |iteration| {
        if (!adaptive and iteration > 0) break;

        // remove "flat" degree-3 vertices
        try normal.computeFaceNormals(io, sm, vertex_position.*, face_normal);
        try angle.computeEdgeDihedralAngles(io, sm, vertex_position.*, face_normal.*, edge_dihedral_angle);
        vertex_it.reset();
        while (vertex_it.nextSafe()) |vertex| {
            const d = sm.dart(vertex);
            if (sm.degree(vertex) != 3 or feature_vertex.isMarked(vertex) or sm.isOrbitIncidentToBoundary(d, .vertex)) {
                continue;
            }
            var dart_it = sm.vertexDartIterator(d);
            const remove: bool = while (dart_it.next()) |dd| {
                if (sm.degree(sm.vertex(sm.phi1(dd))) < 4 or
                    @abs(edge_dihedral_angle.value(sm.edge(dd))) > (10.0 * (std.math.pi / 180.0)))
                {
                    break false;
                }
            } else true;
            if (remove) {
                try sm.removeVertex(vertex);
            }
        }

        // cut long edges
        edge_it.reset();
        cut_edge_queue.clearRetainingCapacity();
        cut_edge_queue_index.data.fill(null);
        while (edge_it.next()) |edge| {
            const d = sm.dart(edge);
            const l = edge_length.value(edge);
            const length_goal_edge = if (adaptive and iteration > 0) @min(
                vertex_sizing_field.value(sm.vertex(d)),
                vertex_sizing_field.value(sm.vertex(sm.phi1(d))),
            ) else length_goal;
            if (l > length_goal_edge * 1.33) {
                try cut_edge_queue.push(allocator, .{ .edge = edge, .length = l });
            }
        }
        while (cut_edge_queue.items.len > 0) {
            const info = cut_edge_queue.popIndex(0);
            const edge = info.edge;

            const d = sm.dart(edge);
            const dd = sm.phi2(d);
            const vd = sm.vertex(d);
            const vdd = sm.vertex(dd);
            const new_pos = vec.mulScalar3f(
                vec.add3f(
                    vertex_position.value(vd),
                    vertex_position.value(vdd),
                ),
                0.5,
            );
            const v = try sm.cutEdge(edge);
            vertex_position.valuePtr(v).* = new_pos;
            const ed = sm.edge(d);
            const edd = sm.edge(dd);
            if (preserve_features and feature_edge.isMarked(ed)) {
                feature_edge.mark(edd);
                feature_vertex.mark(v);
            }
            const new_length = info.length / 2.0;
            edge_length.valuePtr(ed).* = new_length;
            edge_length.valuePtr(edd).* = new_length;
            if (new_length > length_goal * 1.33) {
                try cut_edge_queue.push(allocator, .{ .edge = ed, .length = new_length });
                try cut_edge_queue.push(allocator, .{ .edge = edd, .length = new_length });
            }
            if (adaptive and iteration > 0) {
                vertex_sizing_field.valuePtr(v).* = 0.5 * (vertex_sizing_field.value(vd) + vertex_sizing_field.value(vdd));
            }
            // triangulate adjacent (non-boundary) faces
            const d1 = sm.phi1(d);
            const dd1 = sm.phi1(dd);
            if (!sm.isBoundaryDart(d1)) {
                const e = try sm.cutFace(d1, sm.phi1(sm.phi1(d1)));
                const l = length.edgeLength(sm, e, vertex_position.*);
                edge_length.valuePtr(e).* = l;
                if (l > length_goal * 1.33) {
                    try cut_edge_queue.push(allocator, .{ .edge = e, .length = l });
                }
            }
            if (!sm.isBoundaryDart(dd1)) {
                const e = try sm.cutFace(dd1, sm.phi1(sm.phi1(dd1)));
                const l = length.edgeLength(sm, e, vertex_position.*);
                edge_length.valuePtr(e).* = l;
                if (l > length_goal * 1.33) {
                    try cut_edge_queue.push(allocator, .{ .edge = e, .length = l });
                }
            }
        }

        // collapse short edges
        edge_it.reset();
        collapse_edge_queue.clearRetainingCapacity();
        collapse_edge_queue_index.data.fill(null);
        while (edge_it.next()) |edge| {
            const l = edge_length.value(edge);
            const d = sm.dart(edge);
            const v1 = sm.vertex(d);
            const v2 = sm.vertex(sm.phi1(d));
            const length_goal_edge = if (adaptive and iteration > 0) @min(
                vertex_sizing_field.value(v1),
                vertex_sizing_field.value(v2),
            ) else length_goal;
            if (l < length_goal_edge * 0.75) {
                try collapse_edge_queue.push(allocator, .{ .edge = edge, .length = l });
            }
        }
        while (collapse_edge_queue.items.len > 0) {
            const info = collapse_edge_queue.popIndex(0);
            const edge = info.edge;
            // the edge may not collapse and remain in the mesh after popping from the queue,
            // so its index in the queue must be set to null
            collapse_edge_queue_index.valuePtr(edge).* = null;

            const d = sm.dart(edge);
            const d1 = sm.phi1(d);
            const v1 = sm.vertex(d);
            const v2 = sm.vertex(d1);
            if (preserve_features) {
                if (feature_corner.isMarked(v1) or feature_corner.isMarked(v2)) {
                    continue;
                }
                if ((feature_vertex.isMarked(v1) and !feature_vertex.isMarked(v2)) or
                    (!feature_vertex.isMarked(v1) and feature_vertex.isMarked(v2)))
                {
                    continue;
                }
            }
            if (!sm.canCollapseEdge(edge)) continue;

            var new_pos = vec.mulScalar3f(
                vec.add3f(vertex_position.value(v1), vertex_position.value(v2)),
                0.5,
            );
            if (!sm.isOrbitIncidentToBoundary(d, .edge)) {
                if (sm.isOrbitIncidentToBoundary(d, .vertex)) {
                    new_pos = vertex_position.value(v1);
                } else if (sm.isOrbitIncidentToBoundary(d1, .vertex)) {
                    new_pos = vertex_position.value(v2);
                }
            }
            const new_sizing_field = if (adaptive and iteration > 0) 0.5 * (vertex_sizing_field.value(v1) +
                vertex_sizing_field.value(v2)) else length_goal;

            // the collapse will destroy the two incident triangles of the edge
            // if any of the edges of these triangles (other than collapsed edge) is in the collapse queue,
            // remove them from the queue
            // (edges incident to the resulting vertex will be re-inserted after collapsing if they satisfy collapse conditions)
            if (!sm.isBoundaryDart(d)) {
                EdgeQueueUtil.removeEdgeFromQueue(&collapse_edge_queue, sm.edge(sm.phi1(d)));
                EdgeQueueUtil.removeEdgeFromQueue(&collapse_edge_queue, sm.edge(sm.phi_1(d)));
            }
            const dd = sm.phi2(d);
            if (!sm.isBoundaryDart(dd)) {
                EdgeQueueUtil.removeEdgeFromQueue(&collapse_edge_queue, sm.edge(sm.phi1(dd)));
                EdgeQueueUtil.removeEdgeFromQueue(&collapse_edge_queue, sm.edge(sm.phi_1(dd)));
            }

            const v = sm.collapseEdge(edge);
            vertex_position.valuePtr(v).* = new_pos;
            if (adaptive and iteration > 0) {
                vertex_sizing_field.valuePtr(v).* = new_sizing_field;
            }

            // after collapsing, iterate over all the edges incident to the new vertex and update their length
            // if any of these edges is in the collapse queue, start by removing it from the queue and then
            // insert it if it is still satisfying the collapse conditions
            var dart_it = sm.vertexDartIterator(sm.dart(v));
            while (dart_it.next()) |dv| {
                const e = sm.edge(dv);
                const el = length.edgeLength(sm, e, vertex_position.*);
                edge_length.valuePtr(e).* = el;
                EdgeQueueUtil.removeEdgeFromQueue(&collapse_edge_queue, e);
                const ev1 = sm.vertex(dv);
                const ev2 = sm.vertex(sm.phi1(dv));
                const length_goal_edge = if (adaptive and iteration >= 1) @min(
                    vertex_sizing_field.value(ev1),
                    vertex_sizing_field.value(ev2),
                ) else length_goal;
                if (el < length_goal_edge * 0.75) {
                    try collapse_edge_queue.push(allocator, .{ .edge = e, .length = el });
                }
            }
        }

        // equalize degrees with edge flips
        edge_it.reset();
        while (edge_it.next()) |edge| {
            if (preserve_features and feature_edge.isMarked(edge)) {
                continue;
            }
            if (sm.canFlipEdge(edge) and edgeShouldFlip(sm, edge)) {
                sm.flipEdge(edge);
                // no need to update edge length here as they are not used in this loop and will be recomputed right after
            }
        }

        // tangential relaxation
        // first, update datas needed for relaxation after remeshing operations
        try length.computeEdgeLengths(sm, vertex_position.*, edge_length);
        try angle.computeCornerAngles(io, sm, vertex_position.*, corner_angle);
        try area.computeFaceAreas(io, sm, vertex_position.*, face_area);
        try normal.computeFaceNormals(io, sm, vertex_position.*, face_normal);
        try area.computeVertexAreas(sm, face_area.*, vertex_area);
        try normal.computeVertexNormals(io, sm, corner_angle.*, face_normal.*, vertex_normal);
        vertex_it.reset();
        while (vertex_it.next()) |vertex| {
            const vd = sm.dart(vertex);
            if (sm.isOrbitIncidentToBoundary(vd, .vertex) or (preserve_features and feature_vertex.isMarked(vertex))) {
                continue;
            }
            var q = vec.zero3f;
            var w: f32 = 0.0;
            if (adaptive and iteration > 0) {
                var dart_it = sm.vertexDartIterator(vd);
                while (dart_it.next()) |d| {
                    const f = sm.face(d);
                    var avg_sizing_field: f32 = 0.0;
                    var avg_position = vec.zero3f;
                    var count: u32 = 0;
                    var face_dart_it = sm.faceDartIterator(d);
                    while (face_dart_it.next()) |fd| {
                        const iv = sm.vertex(fd);
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
                var dart_it = sm.vertexDartIterator(vd);
                while (dart_it.next()) |d| {
                    const nv = sm.vertex(sm.phi1(d));
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

        // in the adaptive case, compute a curvature-based sizing field at the end of iterations 0
        if (adaptive and (iteration == 0)) {
            // first, update data needed for sizing field computation
            try length.computeEdgeLengths(sm, vertex_position.*, edge_length);
            try angle.computeCornerAngles(io, sm, vertex_position.*, corner_angle);
            try area.computeFaceAreas(io, sm, vertex_position.*, face_area);
            try normal.computeFaceNormals(io, sm, vertex_position.*, face_normal);
            try angle.computeEdgeDihedralAngles(io, sm, vertex_position.*, face_normal.*, edge_dihedral_angle);
            try area.computeVertexAreas(sm, face_area.*, vertex_area);
            try normal.computeVertexNormals(io, sm, corner_angle.*, face_normal.*, vertex_normal);
            try curvature.computeVertexCurvatures(io, sm, vertex_position.*, vertex_normal.*, edge_dihedral_angle.*, edge_length.*, face_area.*, vertex_curvature);
            mean_edge_length = edge_length.data.meanValue();
            const approx_tolerance = mean_edge_length * 0.025; // TODO: this value could be tuned
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
    // try length.computeEdgeLengths(sm, vertex_position, edge_length);
    // try angle.computeCornerAngles(io, sm, vertex_position, corner_angle);
    // try area.computeFaceAreas(io, sm, vertex_position, face_area);
    // try normal.computeFaceNormals(io, sm, vertex_position, face_normal);
    // try angle.computeEdgeDihedralAngles(io, sm, vertex_position, face_normal, edge_dihedral_angle);
    // try area.computeVertexAreas(sm, face_area, vertex_area);
    // try normal.computeVertexNormals(sm, corner_angle, face_normal, vertex_normal);
    // if (adaptive) {
    //     try curvature.computeVertexCurvatures(io, sm, vertex_position, vertex_normal, edge_dihedral_angle, edge_length, face_area, vertex_curvature);
    // }
}
