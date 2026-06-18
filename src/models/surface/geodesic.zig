const std = @import("std");
const assert = std.debug.assert;
const zgp_log = std.log.scoped(.zgp);

const AppContext = @import("../../main.zig").AppContext;
const SurfaceMesh = @import("SurfaceMesh.zig");
const SurfacePoint = @import("SurfacePoint.zig");

const vec = @import("../../geometry/vec.zig");
const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const geometry_utils = @import("../../geometry/utils.zig");

// Returns .{t_ray, t_seg, out_angle} such that:
// - p + t_ray*dir = a + t_seg*(b-a)
// - out_angle is the angle between dir and the segment (b-a), in (-π, π], positive if segment b-a points to the left of dir
// Returns null if dir is parallel to the segment or if the intersection occurs outside of the segment (with some epsilon tolerance).
fn raySegmentIntersect(p: Vec2f, dir: Vec2f, a: Vec2f, b: Vec2f) ?struct { f32, f32, f32 } {
    const seg = vec.sub2f(b, a);
    const det = vec.cross2f(dir, seg);
    if (@abs(det) < geometry_utils.epsilon) return null;
    const ap = vec.sub2f(a, p);
    const t_ray = vec.cross2f(ap, seg) / det;
    const t_seg = vec.cross2f(ap, dir) / det;
    if (t_ray <= geometry_utils.epsilon) return null; // intersection occurs behind the current point
    if (t_seg < -geometry_utils.epsilon or t_seg > 1.0 + geometry_utils.epsilon) return null; // intersection occurs outside of the segment
    const dot = vec.dot2f(dir, seg);
    const out_angle = std.math.atan2(det, dot);
    return .{ t_ray, t_seg, out_angle };
}

/// Trace a geodesic on the surface of the given SurfaceMesh starting from the given SurfacePoint.
/// The SurfaceMesh is assumed to be triangulated.
/// The given angle encodes the direction of the geodesic to trace, in the tangent space of the source SurfacePoint
/// (for vertex SurfacePoints, the angle is denormalized, meaning it is not in [0, 2π) but in [0, angle_sum_at_vertex)).
/// The given length encodes the length of the geodesic to trace.
/// The SurfacePoints that compose the traced path are stored in the given ArrayList (if a trace pointer is provided).
/// Returns:
/// - the destination SurfacePoint (should always be on a face of the SurfaceMesh)
/// - the final angle (in the tangent space of the destination SurfacePoint)
/// - the remaining length (should be zero if the geodesic is fully traced)
pub fn traceGeodesic(
    app_ctx: *AppContext,
    sm: *const SurfaceMesh,
    src_sp: SurfacePoint,
    angle: f32,
    length: f32,
    corner_angle: SurfaceMesh.CellData(.corner, f32),
    edge_length: SurfaceMesh.CellData(.edge, f32),
    trace: ?*std.ArrayList(SurfacePoint),
) !struct { SurfacePoint, f32, f32 } {
    if (trace) |t| {
        t.clearRetainingCapacity();
    }

    // current SurfacePoint of the trace, updated at each step of the tracing
    var current_sp = src_sp;
    // the tracing direction is determined by the current angle,
    // expressed in the tangent space of the current SurfacePoint (denormalized for vertex SurfacePoints)
    // (the reference Dart being the one representing the underlying Cell of the SurfacePoint)
    var current_angle = angle;
    // the remaining geodesic length to trace
    var remaining_length = length;

    if (trace) |t| {
        try t.append(app_ctx.allocator, current_sp);
    }

    while (remaining_length > geometry_utils.epsilon) {
        switch (current_sp.type) {
            // for a vertex SurfacePoint, the angle is measured CCW from the direction of the reference Dart of the vertex
            // the value is in [0, angle_sum_at_vertex)
            .vertex => |v| {
                // find the incident triangle containing the geodesic direction
                var accumulated_angle: f32 = 0.0;
                var angle_before: f32 = 0.0;
                var d_it = sm.cellDartIterator(v);
                const face_dart: ?SurfaceMesh.Dart = while (d_it.next()) |vd| {
                    angle_before = accumulated_angle;
                    accumulated_angle += corner_angle.value(.{ .corner = vd });
                    if (accumulated_angle >= angle - geometry_utils.epsilon) {
                        break vd;
                    }
                } else null;
                if (face_dart) |fd| {
                    // the tracing is expressed in the tangent space of the found incident triangle
                    current_angle = angle - angle_before;
                    current_sp = .{
                        .surface_mesh = sm,
                        .type = .{ .face = .{
                            .cell = .{ .face = fd },
                            .bcoords = .{ 1.0, 0.0, 0.0 },
                        } },
                    };
                    continue;
                } else {
                    zgp_log.warn("traceGeodesic: on Vertex SurfacePoint: could not find containing face", .{});
                    return .{ current_sp, current_angle, remaining_length };
                }
            },
            .edge => |e| {
                const face_dart: SurfaceMesh.Dart = if (current_angle < std.math.pi) e.cell.dart() else blk: {
                    current_angle -= std.math.pi;
                    break :blk sm.phi2(e.cell.dart());
                };
                // the tracing is expressed in the tangent space of the incident triangle
                current_sp = .{
                    .surface_mesh = sm,
                    .type = .{ .face = .{
                        .cell = .{ .face = face_dart },
                        .bcoords = .{ e.t, 1.0 - e.t, 0.0 },
                    } },
                };
                continue;
            },
            .face => |f| {
                const fd = f.cell.dart();
                // Darts of the triangle
                const darts: [3]SurfaceMesh.Dart = .{ fd, sm.phi1(fd), sm.phi_1(fd) };
                // lengths of the triangle edges
                const l_v0v1 = edge_length.value(.{ .edge = darts[0] });
                const l_v1v2 = edge_length.value(.{ .edge = darts[1] });
                const l_v2v0 = edge_length.value(.{ .edge = darts[2] });
                // positions of the triangle vertices in the 2D triangle layout
                const p2d: [3]Vec2f = .{
                    .{ 0.0, 0.0 },
                    .{ l_v0v1, 0.0 },
                    geometry_utils.layoutTriangleVertex(
                        .{ 0.0, 0.0 },
                        .{ l_v0v1, 0.0 },
                        l_v1v2,
                        l_v2v0,
                    ),
                };
                // position of the current SurfacePoint in the 2D triangle layout
                const p: Vec2f = .{
                    p2d[0][0] * f.bcoords[0] + p2d[1][0] * f.bcoords[1] + p2d[2][0] * f.bcoords[2],
                    p2d[0][1] * f.bcoords[0] + p2d[1][1] * f.bcoords[1] + p2d[2][1] * f.bcoords[2],
                };

                // current_angle is expressed relative to fd
                const in_face_dir: Vec2f = .{ @cos(current_angle), @sin(current_angle) };
                // find the intersection of the ray (p, in_face_dir) with the triangle edges
                var t_ray: f32 = 0.0;
                var t_seg: f32 = 0.0;
                var out_angle: f32 = 0.0;
                const intersected_dart = for (0..3) |idx| {
                    t_ray, t_seg, out_angle = raySegmentIntersect(p, in_face_dir, p2d[idx], p2d[(idx + 1) % 3]) orelse continue;
                    break darts[idx];
                } else {
                    zgp_log.warn("traceGeodesic: on Face SurfacePoint: no intersection with edges found", .{});
                    return .{ current_sp, current_angle, remaining_length };
                };
                if (t_ray > remaining_length + geometry_utils.epsilon) {
                    // the traced geodesic ends before reaching the edge of the triangle
                    const p_end = vec.add2f(p, vec.mulScalar2f(in_face_dir, remaining_length));
                    remaining_length = 0.0;
                    current_sp = .{
                        .surface_mesh = sm,
                        .type = .{
                            .face = .{
                                .cell = f.cell,
                                .bcoords = geometry_utils.barycentricCoordinates(p_end, p2d[0], p2d[1], p2d[2]),
                            },
                        },
                    };
                    if (trace) |t| {
                        try t.append(app_ctx.allocator, current_sp);
                    }
                    continue; // will stop the loop since remaining_length is now 0
                } else {
                    // the traced geodesic reaches the edge of the triangle
                    remaining_length -= t_ray;
                    current_angle = std.math.pi - out_angle;
                    const s_clamped = std.math.clamp(t_seg, 0.0, 1.0);
                    // the tracing is expressed in the tangent space of the triangle on the other side of the edge
                    current_sp = .{
                        .surface_mesh = sm,
                        .type = .{
                            .face = .{
                                .cell = .{ .face = sm.phi2(intersected_dart) },
                                .bcoords = .{ s_clamped, 1.0 - s_clamped, 0.0 },
                            },
                        },
                    };
                    if (trace) |t| {
                        // an edge SurfacePoint is added to the trace
                        try t.append(app_ctx.allocator, .{
                            .surface_mesh = sm,
                            .type = .{
                                .edge = .{
                                    .cell = .{ .edge = intersected_dart },
                                    .t = s_clamped,
                                },
                            },
                        });
                    }
                    continue;
                }
            },
        }
    }

    return .{ current_sp, current_angle, remaining_length };
}
