const SurfacePoint = @This();

const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const Cell = SurfaceMesh.Cell;

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

// TODO: this code assumes that faces are triangles

pub const SurfacePointType = union(enum) {
    vertex: Cell, // a .vertex
    edge: struct { cell: Cell, t: f32 }, // cell is a .edge, t in [0, 1], orientation of cell.dart()
    face: struct { cell: Cell, bcoords: Vec3f }, // cell is a .face, bcoords simplex barycentric coordinates
};

surface_mesh: *SurfaceMesh,
type: SurfacePointType,

pub fn readData(sp: *const SurfacePoint, comptime T: type, comptime cell_type: SurfaceMesh.CellType, data: SurfaceMesh.CellData(cell_type, T)) T {
    assert(sp.surface_mesh == data.surface_mesh);
    return switch (sp.type) {
        // the SurfacePoint sits on a vertex
        .vertex => |v| switch (cell_type) {
            // if the data is defined on vertices, simply take the value of the vertex
            // if the data is defined on edges or faces, take the value of the first edge or face incident to the vertex
            .vertex, .edge, .face => data.value(@unionInit(Cell, @tagName(cell_type), sp.surface_mesh.cellNonBoundaryDart(v))),
            else => unreachable,
        },
        // the SurfacePoint sits on an edge
        .edge => |e| switch (cell_type) {
            // if the data is defined on vertices, interpolate using the edge parameter t
            .vertex => interpolate2(
                data.value(.{ .vertex = e.cell.dart() }),
                data.value(.{ .vertex = sp.surface_mesh.phi1(e.cell.dart()) }),
                e.t,
            ),
            // if the data is defined on edges, simply take the value of the edge
            // if the data is defined on faces, take the value of the first face incident to the edge
            .edge, .face => data.value(@unionInit(Cell, @tagName(cell_type), sp.surface_mesh.cellNonBoundaryDart(e.cell))),
            else => unreachable,
        },
        // the SurfacePoint sits on a face
        .face => |f| switch (cell_type) {
            // if the data is defined on vertices, interpolate using the face barycentric coordinates
            .vertex => interpolate3(
                data.value(.{ .vertex = f.cell.dart() }),
                data.value(.{ .vertex = sp.surface_mesh.phi1(f.cell.dart()) }),
                data.value(.{ .vertex = sp.surface_mesh.phi_1(f.cell.dart()) }),
                f.bcoords[0],
                f.bcoords[1],
                f.bcoords[2],
            ),
            // if the data is defined on edges, compute edge distances from barycentric coordinates and interpolate edge values
            .edge => interpolate3(
                data.value(.{ .edge = sp.surface_mesh.phi1(f.cell.dart()) }), // opposite edge of v0 in the triangle
                data.value(.{ .edge = f.cell.dart() }), // opposite edge of v1 in the triangle
                data.value(.{ .edge = sp.surface_mesh.phi_1(f.cell.dart()) }), // opposite edge of v2 in the triangle
                f.bcoords[1] * f.bcoords[2],
                f.bcoords[0] * f.bcoords[2],
                f.bcoords[0] * f.bcoords[1],
            ),
            // if the data is defined on faces, simply take the value
            .face => data.value(f.cell),
            else => unreachable,
        },
    };
}

fn interpolate2(a: anytype, b: @TypeOf(a), t: f32) @TypeOf(a) {
    const t_info = @typeInfo(@TypeOf(a));
    switch (t_info) {
        .int, .float => return a * (1.0 - t) + b * t,
        .array => {
            const t_info_array_child = @typeInfo(t_info.array.child);
            if (t_info_array_child != .int and t_info_array_child != .float) {
                @compileError("interpolate2: unsupported data type");
            }
            switch (t_info.array.len) {
                1 => return .{a[0] * (1.0 - t) + b[0] * t},
                2 => return vec.add2f(vec.mulScalar2f(a, 1.0 - t), vec.mulScalar2f(b, t)),
                3 => return vec.add3f(vec.mulScalar3f(a, 1.0 - t), vec.mulScalar3f(b, t)),
                4 => return vec.add4f(vec.mulScalar4f(a, 1.0 - t), vec.mulScalar4f(b, t)),
                else => @compileError("interpolate2: unsupported data type"),
            }
        },
        else => @compileError("interpolate2: unsupported data type"),
    }
}

fn interpolate3(a: anytype, b: @TypeOf(a), c: @TypeOf(a), t0: f32, t1: f32, t2: f32) @TypeOf(a) {
    const t_info = @typeInfo(@TypeOf(a));
    switch (t_info) {
        .int, .float => return a * t0 + b * t1 + c * t2,
        .array => {
            const t_info_array_child = @typeInfo(t_info.array.child);
            if (t_info_array_child != .int and t_info_array_child != .float) {
                @compileError("interpolate3: unsupported data type");
            }
            switch (t_info.array.len) {
                1 => return .{a[0] * t0 + b[0] * t1 + c[0] * t2},
                2 => return vec.add2f(vec.mulScalar2f(a, t0), vec.add2f(vec.mulScalar2f(b, t1), vec.mulScalar2f(c, t2))),
                3 => return vec.add3f(vec.mulScalar3f(a, t0), vec.add3f(vec.mulScalar3f(b, t1), vec.mulScalar3f(c, t2))),
                4 => return vec.add4f(vec.mulScalar4f(a, t0), vec.add4f(vec.mulScalar4f(b, t1), vec.mulScalar4f(c, t2))),
                else => @compileError("interpolate3: unsupported data type"),
            }
        },
        else => @compileError("interpolate3: unsupported data type"),
    }
}
