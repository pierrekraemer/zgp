const SurfacePoint = @This();

const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const Cell = SurfaceMesh.Cell;
const Dart = SurfaceMesh.Dart;

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const geometry_utils = @import("../../geometry/utils.zig");

// TODO: this code assumes that faces are triangles

/// A SurfacePoint represents a point on the surface of a SurfaceMesh
/// It can be of three types: vertex, edge or face, depending on whether the point sits on a vertex, edge or face of the SurfaceMesh.
/// The SurfacePoint stores a Dart that represents the underlying Cell of the SurfacePoint.
/// In the case of edge or face type, the SurfacePoint also stores barycentric coordinates to express the position of the point on the edge or face.
/// These coordinates are expressed w.r.t. the Dart
/// The SurfacePoint also stores a reference to the underlying SurfaceMesh, which is used to read data from the mesh CellData (readData).
pub const SurfacePointType = union(enum) {
    vertex: Dart,
    edge: struct { dart: Dart, t: f32 }, // t in [0, 1], t=0 corresponds to vertex(dart), t=1 corresponds to vertex(phi1(dart))
    face: struct { dart: Dart, bcoords: Vec3f }, // bcoords barycentric coordinates, corresponding to vertices of { dart, phi1(dart), phi_1(dart) }
};

surface_mesh: *const SurfaceMesh,
type: SurfacePointType,

// Read values from the given data in the underlying SurfaceMesh.
// Value is interpolated depending on the type of the SurfacePoint and the CellType on which the data is defined.
pub fn readData(sp: *const SurfacePoint, comptime T: type, comptime cell_type: SurfaceMesh.CellType, data: SurfaceMesh.CellData(cell_type, T)) T {
    return switch (sp.type) {
        // the SurfacePoint sits on a vertex
        .vertex => |v| switch (cell_type) {
            // if the data is defined on vertices, simply take the value of the vertex
            .vertex => data.value(sp.surface_mesh.vertex(v)),
            // if the data is defined on edges, take the value of an arbitrary edge incident to the vertex
            .edge => data.value(sp.surface_mesh.edge(v)),
            // if the data is defined on faces, take the value of an arbitrary non-boundary face incident to the vertex
            .face => data.value(sp.surface_mesh.face(sp.surface_mesh.orbitNonBoundaryDart(v, .vertex))),
            else => unreachable,
        },
        // the SurfacePoint sits on an edge
        .edge => |e| switch (cell_type) {
            // if the data is defined on vertices, interpolate using the edge parameter t
            .vertex => blk: {
                break :blk interpolate2(
                    data.value(sp.surface_mesh.vertex(e.dart)),
                    data.value(sp.surface_mesh.vertex(sp.surface_mesh.phi1(e.dart))),
                    e.t,
                );
            },
            // if the data is defined on edges, simply take the value of the edge
            .edge => data.value(sp.surface_mesh.edge(e.dart)),
            // if the data is defined on faces, take the value of the first non-boundary face incident to the edge
            .face => data.value(sp.surface_mesh.face(sp.surface_mesh.orbitNonBoundaryDart(e.dart, .edge))),
            else => unreachable,
        },
        // the SurfacePoint sits on a face
        .face => |f| switch (cell_type) {
            // if the data is defined on vertices, interpolate using the face barycentric coordinates
            .vertex => blk: {
                break :blk interpolate3(
                    data.value(sp.surface_mesh.vertex(f.dart)),
                    data.value(sp.surface_mesh.vertex(sp.surface_mesh.phi1(f.dart))),
                    data.value(sp.surface_mesh.vertex(sp.surface_mesh.phi_1(f.dart))),
                    f.bcoords[0],
                    f.bcoords[1],
                    f.bcoords[2],
                );
            },
            // if the data is defined on edges, interpolate using the face barycentric coordinates
            .edge => blk: {
                const wa = f.bcoords[1] * f.bcoords[2];
                const wb = f.bcoords[0] * f.bcoords[2];
                const wc = f.bcoords[0] * f.bcoords[1];
                break :blk interpolate3(
                    data.value(sp.surface_mesh.edge(sp.surface_mesh.phi1(f.dart))), // opposite edge of v0 in the triangle
                    data.value(sp.surface_mesh.edge(sp.surface_mesh.phi_1(f.dart))), // opposite edge of v1 in the triangle
                    data.value(sp.surface_mesh.edge(f.dart)), // opposite edge of v2 in the triangle
                    wa / @max((wa + wb + wc), geometry_utils.epsilon),
                    wb / @max((wa + wb + wc), geometry_utils.epsilon),
                    wc / @max((wa + wb + wc), geometry_utils.epsilon),
                );
            },
            // if the data is defined on faces, simply take the value of the face
            .face => data.value(sp.surface_mesh.face(f.dart)),
            else => unreachable,
        },
    };
}

fn interpolate2(a: anytype, b: @TypeOf(a), t: f32) @TypeOf(a) {
    const T = @TypeOf(a);
    const t_info = @typeInfo(T);
    return switch (t_info) {
        .int => @as(T, @intFromFloat(@as(f32, @floatFromInt(a)) * (1.0 - t) + @as(f32, @floatFromInt(b)) * t)),
        .float => a * (1.0 - t) + b * t,
        .array => blk: {
            const t_info_array_child = @typeInfo(t_info.array.child);
            // if (t_info_array_child != .int and t_info_array_child != .float) {
            if (t_info_array_child != .float) {
                @compileError("interpolate2 only supports float, int, or array of float/int types");
            }
            break :blk switch (t_info.array.len) {
                1 => .{a[0] * (1.0 - t) + b[0] * t},
                2 => vec.add2f(vec.mulScalar2f(a, 1.0 - t), vec.mulScalar2f(b, t)),
                3 => vec.add3f(vec.mulScalar3f(a, 1.0 - t), vec.mulScalar3f(b, t)),
                4 => vec.add4f(vec.mulScalar4f(a, 1.0 - t), vec.mulScalar4f(b, t)),
                else => @compileError("interpolate2 only supports float, int, or array of float/int types"),
            };
        },
        else => @compileError("interpolate2 only supports float, int, or array of float/int types"),
    };
}

fn interpolate3(a: anytype, b: @TypeOf(a), c: @TypeOf(a), t0: f32, t1: f32, t2: f32) @TypeOf(a) {
    const T = @TypeOf(a);
    const t_info = @typeInfo(T);
    return switch (t_info) {
        .int => @as(T, @intFromFloat(@as(f32, @floatFromInt(a)) * t0 + @as(f32, @floatFromInt(b)) * t1 + @as(f32, @floatFromInt(c)) * t2)),
        .float => a * t0 + b * t1 + c * t2,
        .array => blk: {
            const t_info_array_child = @typeInfo(t_info.array.child);
            // if (t_info_array_child != .int and t_info_array_child != .float) {
            if (t_info_array_child != .float) {
                @compileError("interpolate3 only supports float, int, or array of float/int types");
            }
            break :blk switch (t_info.array.len) {
                1 => .{a[0] * t0 + b[0] * t1 + c[0] * t2},
                2 => vec.add2f(vec.mulScalar2f(a, t0), vec.add2f(vec.mulScalar2f(b, t1), vec.mulScalar2f(c, t2))),
                3 => vec.add3f(vec.mulScalar3f(a, t0), vec.add3f(vec.mulScalar3f(b, t1), vec.mulScalar3f(c, t2))),
                4 => vec.add4f(vec.mulScalar4f(a, t0), vec.add4f(vec.mulScalar4f(b, t1), vec.mulScalar4f(c, t2))),
                else => @compileError("interpolate3 only supports float, int, or array of float/int types"),
            };
        },
        else => @compileError("interpolate3 only supports float, int, or array of float/int types"),
    };
}
