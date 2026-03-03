const std = @import("std");
const assert = std.debug.assert;

const AppContext = @import("../../main.zig").AppContext;
const PointCloud = @import("../point/PointCloud.zig");
const SurfaceMesh = @import("../surface/SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

const geometry_utils = @import("../../geometry/utils.zig");

/// Given a point cloud, fills the given surface mesh with the convex hull of the point cloud.
/// The given SurfaceMesh is supposed to be empty.
pub fn generateConvexHull(
    app_ctx: *AppContext,
    pc: *const PointCloud,
    point_position: PointCloud.CellData(Vec3f),
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
) !void {
    // no convex hull for less than 3 points
    if (pc.nbPoints() < 4) {
        return error.NotEnoughPoints;
    }

    // if only 4 points, simply create a tet with the four points
    if (pc.nbPoints() == 4) {
        var points: [4]Vec3f = undefined;
        var it = point_position.data.constIterator();
        var idx: u32 = 0;
        while (it.next()) |p| : (idx += 1) {
            points[idx] = p.*;
        }
        var ids: [4]u32 = .{ 0, 1, 2, 3 };
        if (geometry_utils.planeOrientation(points[0], points[1], points[2], points[3]) == .over) {
            ids = .{ 0, 2, 1, 3 };
        }
        const tet = try sm.addPyramid(3);
        vertex_position.valuePtr(.{ .vertex = tet.dart() }).* = points[ids[0]];
        vertex_position.valuePtr(.{ .vertex = sm.phi1(tet.dart()) }).* = points[ids[1]];
        vertex_position.valuePtr(.{ .vertex = sm.phi_1(tet.dart()) }).* = points[ids[2]];
        vertex_position.valuePtr(.{ .vertex = sm.phi_1(sm.phi2(tet.dart())) }).* = points[ids[3]];

        return;
    }

    const extreme_points: [6]Vec3f = geometry_utils.extremePoints(point_position.data);

    // find 2 most distant extreme points
    var max_dist = geometry_utils.epsilon;
    var selected_points_index: [2]u32 = undefined;
    for (0..6) |i| {
        for (i + 1..6) |j| {
            const dist = vec.squaredNorm3f(vec.sub3f(extreme_points[i], extreme_points[j]));
            if (dist > max_dist) {
                max_dist = dist;
                selected_points_index = .{ @intCast(i), @intCast(j) };
            }
        }
    }
    if (max_dist == geometry_utils.epsilon or selected_points_index[0] == selected_points_index[1]) {
        return error.NotEnoughPoints;
    }

    // find the most distant point to the line between the 2 chosen extreme points
    max_dist = geometry_utils.epsilon * geometry_utils.epsilon;
    var most_distant_index: u32 = 0;
    for (0..6) |i| {
        if (i == selected_points_index[0] or i == selected_points_index[1]) {
            continue;
        }
        const dist = geometry_utils.squaredDistanceLinePoint(
            extreme_points[selected_points_index[0]],
            extreme_points[selected_points_index[1]],
            extreme_points[i],
        );
        if (dist > max_dist) {
            max_dist = dist;
            most_distant_index = @intCast(i);
        }
    }
    if (max_dist == geometry_utils.epsilon * geometry_utils.epsilon) {
        return error.NotEnoughPoints;
    }

    // these three points form the base triangle for our tet
    const base_triangle_pos: [3]Vec3f = .{
        extreme_points[selected_points_index[0]],
        extreme_points[selected_points_index[1]],
        extreme_points[most_distant_index],
    };

    // next step is to find the 4th vertex of the tetrahedron
    // we naturally choose the point farthest away from the triangle plane
    max_dist = geometry_utils.epsilon;
    most_distant_index = 0;
    for (0..6) |i| {
        if (i == selected_points_index[0] or i == selected_points_index[1] or i == most_distant_index) {
            continue;
        }
        const dist = geometry_utils.distancePlanePoint(
            base_triangle_pos[0],
            base_triangle_pos[1],
            base_triangle_pos[2],
            extreme_points[i],
        );
        if (dist > max_dist) {
            max_dist = dist;
            most_distant_index = @intCast(i);
        }
    }
    if (max_dist == geometry_utils.epsilon) {
        return error.NotEnoughPoints;
    }

    // create the initial tetrahedron from the selected points
    var base_triangle_ids: [3]u32 = .{ 0, 1, 2 };
    if (geometry_utils.planeOrientation(base_triangle_pos[0], base_triangle_pos[1], base_triangle_pos[2], extreme_points[most_distant_index]) == .over) {
        base_triangle_ids = .{ 0, 2, 1 };
    }
    const tet = try sm.addPyramid(3);
    vertex_position.valuePtr(.{ .vertex = tet.dart() }).* = base_triangle_pos[base_triangle_ids[0]];
    vertex_position.valuePtr(.{ .vertex = sm.phi1(tet.dart()) }).* = base_triangle_pos[base_triangle_ids[1]];
    vertex_position.valuePtr(.{ .vertex = sm.phi_1(tet.dart()) }).* = base_triangle_pos[base_triangle_ids[2]];
    vertex_position.valuePtr(.{ .vertex = sm.phi_1(sm.phi2(tet.dart())) }).* = extreme_points[most_distant_index];

    // create datas to keep track of points on the exterior side of each face
    var face_points_on_positive_side = try sm.addData(.face, std.ArrayList(u32), "points_on_positive_side");
    defer {
        var it = face_points_on_positive_side.data.iterator();
        while (it.next()) |list| {
            list.deinit(app_ctx.allocator);
        }
        sm.removeData(.face, face_points_on_positive_side.gen());
    }
    var face_most_distant_point_dist = try sm.addData(.face, f32, "most_distant_point_dist");
    defer sm.removeData(.face, face_most_distant_point_dist.gen());
    var face_most_distant_point_index = try sm.addData(.face, u32, "most_distant_point_index");
    defer sm.removeData(.face, face_most_distant_point_index.gen());

    face_points_on_positive_side.data.fill(.empty);
    face_most_distant_point_dist.data.fill(0.0);
    face_most_distant_point_index.data.fill(0);

    // register points outside the initial tetrahedron in the faces
    var face_it = try SurfaceMesh.CellIterator(.face).init(sm);
    defer face_it.deinit();
    var point_it = pc.pointIterator();
    while (point_it.next()) |p| {
        face_it.reset();
        while (face_it.next()) |f| {
            const d = geometry_utils.signedDistancePlanePoint(
                vertex_position.value(.{ .vertex = f.dart() }),
                vertex_position.value(.{ .vertex = sm.phi1(f.dart()) }),
                vertex_position.value(.{ .vertex = sm.phi_1(f.dart()) }),
                point_position.value(p),
            );
            if (d > 0) {
                try face_points_on_positive_side.valuePtr(f).append(app_ctx.allocator, p);
                if (d > face_most_distant_point_dist.value(f)) {
                    face_most_distant_point_dist.valuePtr(f).* = d;
                    face_most_distant_point_index.valuePtr(f).* = p;
                }
                break;
            }
        }
    }

    // initialize active faces list (faces with points on their exterior side)
    var active_faces: std.ArrayList(SurfaceMesh.Cell) = .empty;
    defer active_faces.deinit(app_ctx.allocator);
    face_it.reset();
    while (face_it.next()) |f| {
        if (face_points_on_positive_side.value(f).items.len > 0) {
            try active_faces.append(app_ctx.allocator, f);
        }
    }

    // while there are active faces, process them
    while (active_faces.pop()) |f| {
        // pick the most distant point to this triangle plane as the point to which we extrude
        const active_point_index = face_most_distant_point_index.value(f);
        const active_point = point_position.value(active_point_index);

        // create the list of horizon halfedges
        var horizon_halfedges, var visible_faces = try buildHorizon(sm, vertex_position, active_point, f, app_ctx.allocator);
        defer horizon_halfedges.deinit(app_ctx.allocator);
        defer visible_faces.deinit(app_ctx.allocator);

        // save visible faces points
        var visible_points: std.ArrayList(u32) = .empty;
        defer visible_points.deinit(app_ctx.allocator);
        for (visible_faces.items) |vf| {
            var vp = face_points_on_positive_side.value(vf);
            try visible_points.appendSlice(app_ctx.allocator, vp.items);
            vp.deinit(app_ctx.allocator);
        }

        // remove faces & fill hole with new umbrella
        for (visible_faces.items) |vf| {
            sm.removeFace(vf);
        }
        const v = try sm.closeHoleWithUmbrella(horizon_halfedges.items[0].dart());
        vertex_position.valuePtr(v).* = active_point;

        // clear the face datas for the new umbrella faces
        var dart_it = sm.cellDartIterator(v);
        while (dart_it.next()) |d| {
            const uf: SurfaceMesh.Cell = .{ .face = d };
            face_points_on_positive_side.valuePtr(uf).* = .empty;
            face_most_distant_point_dist.valuePtr(uf).* = 0.0;
            face_most_distant_point_index.valuePtr(uf).* = 0;
        }

        // register points in the new umbrella faces
        for (visible_points.items) |p| {
            if (p == active_point_index) {
                continue;
            }
            dart_it.reset();
            while (dart_it.next()) |d| {
                const uf: SurfaceMesh.Cell = .{ .face = d };
                const dist = geometry_utils.signedDistancePlanePoint(
                    vertex_position.value(.{ .vertex = uf.dart() }),
                    vertex_position.value(.{ .vertex = sm.phi1(uf.dart()) }),
                    vertex_position.value(.{ .vertex = sm.phi_1(uf.dart()) }),
                    point_position.value(p),
                );
                if (dist > 0) {
                    try face_points_on_positive_side.valuePtr(uf).append(app_ctx.allocator, p);
                    if (dist > face_most_distant_point_dist.value(uf)) {
                        face_most_distant_point_dist.valuePtr(uf).* = dist;
                        face_most_distant_point_index.valuePtr(uf).* = p;
                    }
                    break;
                }
            }
        }

        // add faces with points on their exterior side to the active faces list
        dart_it.reset();
        while (dart_it.next()) |d| {
            const uf: SurfaceMesh.Cell = .{ .face = d };
            if (face_points_on_positive_side.value(uf).items.len > 0) {
                try active_faces.append(app_ctx.allocator, uf);
            }
        }
    }
}

fn buildHorizon(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    point: Vec3f,
    face: SurfaceMesh.Cell,
    allocator: std.mem.Allocator,
) !struct {
    std.ArrayList(SurfaceMesh.Cell), // horizon halfedges
    std.ArrayList(SurfaceMesh.Cell), // visible faces
} {
    var horizon_halfedges: std.ArrayList(SurfaceMesh.Cell) = .empty;
    var visible_faces: std.ArrayList(SurfaceMesh.Cell) = .empty;

    try visible_faces.append(allocator, face);
    var visible_faces_marker = try SurfaceMesh.CellMarker(.face).init(sm);
    defer visible_faces_marker.deinit();
    visible_faces_marker.valuePtr(face).* = true;

    var i: usize = 0;
    while (i < visible_faces.items.len) : (i += 1) {
        const f = visible_faces.items[i];
        var dart_it = sm.cellDartIterator(f);
        while (dart_it.next()) |d| {
            const d2 = sm.phi2(d);
            if (visible_faces_marker.value(.{ .face = d2 })) {
                continue;
            }
            if (geometry_utils.planeOrientation(
                vertex_position.value(.{ .vertex = d2 }),
                vertex_position.value(.{ .vertex = sm.phi1(d2) }),
                vertex_position.value(.{ .vertex = sm.phi_1(d2) }),
                point,
            ) == .over) {
                const af: SurfaceMesh.Cell = .{ .face = d2 };
                try visible_faces.append(allocator, af);
                visible_faces_marker.valuePtr(af).* = true;
            } else {
                try horizon_halfedges.append(allocator, .{ .halfedge = sm.phi2(d) });
            }
        }
    }

    // // reorder horizon halfedges into a cycle
    // for (horizon_halfedges.items, 0..) |h, i| {
    //     const end_vertex_index = sm.cellIndex(.{ .vertex = sm.phi1(h.dart()) });
    //     for (horizon_halfedges.items[i + 1 ..], i + 1..) |h2, j| {
    //         const begin_vertex_index = sm.cellIndex(.{ .vertex = h2.dart() });
    //         if (begin_vertex_index == end_vertex_index) {
    //             if (j > i + 1) {
    //                 const tmp = horizon_halfedges.items[i + 1];
    //                 horizon_halfedges.items[i + 1] = horizon_halfedges.items[j];
    //                 horizon_halfedges.items[j] = tmp;
    //             }
    //             break;
    //         }
    //     }
    // }

    return .{ horizon_halfedges, visible_faces };
}
