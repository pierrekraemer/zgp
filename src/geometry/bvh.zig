const std = @import("std");
const assert = std.debug.assert;

const c = @import("../main.zig").c;

const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const SurfacePoint = @import("../models/surface/SurfacePoint.zig");

const vec = @import("vec.zig");
const Vec3f = vec.Vec3f;

pub const Ray = extern struct {
    origin: Vec3f,
    direction: Vec3f,
    tmin: f32 = 0.0,
    tmax: f32 = std.math.inf(f32),
};

pub const Hit = extern struct {
    t: f32,
    triIndex: Index,
    bcoords: Vec3f,
};

pub const Index = u32;

pub const TrianglesBVH = struct {
    initialized: bool = false,
    bvh_ptr: *anyopaque = undefined,
    surface_mesh: *SurfaceMesh = undefined,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3f) = undefined,
    surface_mesh_faces: std.ArrayList(SurfaceMesh.Cell) = .empty,

    pub fn init(
        sm: *SurfaceMesh,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    ) !TrianglesBVH {
        var vertex_index = try sm.addData(.vertex, u32, "__vertex_index");
        defer sm.removeData(.vertex, u32, vertex_index);

        var surface_mesh_faces = try std.ArrayList(SurfaceMesh.Cell).initCapacity(sm.allocator, sm.nbCells(.face));
        errdefer surface_mesh_faces.deinit(sm.allocator);

        var triangles_indices_array = try std.ArrayList(Index).initCapacity(sm.allocator, 3 * sm.nbCells(.face));
        defer triangles_indices_array.deinit(sm.allocator);
        var position_array = try std.ArrayList(Vec3f).initCapacity(sm.allocator, sm.nbCells(.vertex));
        defer position_array.deinit(sm.allocator);

        var vertex_it: SurfaceMesh.CellIterator = try .init(sm, .vertex);
        defer vertex_it.deinit();
        var nb_vertices: u32 = 0;
        while (vertex_it.next()) |v| : (nb_vertices += 1) {
            vertex_index.valuePtr(v).* = nb_vertices;
            try position_array.append(sm.allocator, vertex_position.value(v));
        }

        // TODO: this code makes the assumption that the mesh is made of triangle faces
        var face_it: SurfaceMesh.CellIterator = try .init(sm, .face);
        defer face_it.deinit();
        while (face_it.next()) |f| {
            try surface_mesh_faces.append(sm.allocator, f);
            var dart_it = sm.cellDartIterator(f);
            while (dart_it.next()) |d| {
                try triangles_indices_array.append(sm.allocator, vertex_index.value(.{ .vertex = d }));
            }
        }

        const bvh_ptr = c.createTrianglesBVH(
            triangles_indices_array.items.ptr,
            @intCast(triangles_indices_array.items.len / 3),
            @ptrCast(position_array.items.ptr),
            @intCast(position_array.items.len),
        ) orelse return error.FailedToCreateBVH;

        return .{
            .initialized = true,
            .bvh_ptr = bvh_ptr,
            .surface_mesh = sm,
            .vertex_position = vertex_position,
            .surface_mesh_faces = surface_mesh_faces,
        };
    }

    pub fn deinit(tbvh: *TrianglesBVH) void {
        if (tbvh.initialized) {
            c.destroyTrianglesBVH(tbvh.bvh_ptr);
            tbvh.surface_mesh_faces.deinit(tbvh.surface_mesh.allocator);
        }
        tbvh.initialized = false;
    }

    pub fn intersect(tbvh: TrianglesBVH, ray: Ray) ?Hit {
        assert(tbvh.initialized);
        var hit: Hit = undefined;
        if (c.intersect(tbvh.bvh_ptr, &ray, &hit)) {
            return hit;
        }
        return null;
    }

    pub fn intersectedTriangle(tbvh: TrianglesBVH, ray: Ray) ?SurfaceMesh.Cell {
        assert(tbvh.initialized);
        if (tbvh.intersect(ray)) |h| {
            return tbvh.surface_mesh_faces.items[h.triIndex];
        }
        return null;
    }

    pub fn intersectedEdge(tbvh: TrianglesBVH, ray: Ray) ?SurfaceMesh.Cell {
        assert(tbvh.initialized);
        if (tbvh.intersect(ray)) |h| {
            const f = tbvh.surface_mesh_faces.items[h.triIndex];
            if (h.bcoords[0] < h.bcoords[1]) {
                if (h.bcoords[0] < h.bcoords[2]) { // bcoords[0] is smallest
                    return .{ .edge = tbvh.surface_mesh.phi1(f.dart()) };
                } else { // bcoords[2] is smallest
                    return .{ .edge = f.dart() };
                }
            } else {
                if (h.bcoords[1] < h.bcoords[2]) { // bcoords[1] is smallest
                    return .{ .edge = tbvh.surface_mesh.phi_1(f.dart()) };
                } else { // bcoords[2] is smallest
                    return .{ .edge = f.dart() };
                }
            }
        }
        return null;
    }

    pub fn intersectedVertex(tbvh: TrianglesBVH, ray: Ray) ?SurfaceMesh.Cell {
        assert(tbvh.initialized);
        if (tbvh.intersect(ray)) |h| {
            const f = tbvh.surface_mesh_faces.items[h.triIndex];
            if (h.bcoords[0] > h.bcoords[1]) {
                if (h.bcoords[0] > h.bcoords[2]) { // bcoords[0] is largest
                    return .{ .vertex = f.dart() };
                } else { // bcoords[2] is largest
                    return .{ .vertex = tbvh.surface_mesh.phi_1(f.dart()) };
                }
            } else {
                if (h.bcoords[1] > h.bcoords[2]) { // bcoords[1] is largest
                    return .{ .vertex = tbvh.surface_mesh.phi1(f.dart()) };
                } else { // bcoords[2] is largest
                    return .{ .vertex = tbvh.surface_mesh.phi_1(f.dart()) };
                }
            }
        }
        return null;
    }

    pub fn intersectedSurfacePoint(tbvh: TrianglesBVH, ray: Ray) ?SurfacePoint {
        assert(tbvh.initialized);
        if (tbvh.intersect(ray)) |h| {
            return SurfacePoint{
                .surface_mesh = tbvh.surface_mesh,
                .type = .{
                    .face = .{
                        .cell = tbvh.surface_mesh_faces.items[h.triIndex],
                        .bcoords = h.bcoords,
                    },
                },
            };
        }
        return null;
    }

    pub fn closestPoint(tbvh: TrianglesBVH, point: Vec3f) Vec3f {
        assert(tbvh.initialized);
        var closest: Vec3f = undefined;
        var triIndex: Index = undefined;
        var bcoords: Vec3f = undefined;
        c.closestPoint(tbvh.bvh_ptr, &point, &closest, &triIndex, &bcoords);
        return closest;
    }

    pub fn closestPointWithSurfacePoint(tbvh: TrianglesBVH, point: Vec3f) struct { Vec3f, SurfacePoint } {
        assert(tbvh.initialized);
        var closest: Vec3f = undefined;
        var triIndex: Index = undefined;
        var bcoords: Vec3f = undefined;
        c.closestPoint(tbvh.bvh_ptr, &point, &closest, &triIndex, &bcoords);
        return .{
            closest,
            .{
                .surface_mesh = tbvh.surface_mesh,
                .type = .{
                    .face = .{
                        .cell = tbvh.surface_mesh_faces.items[triIndex],
                        .bcoords = bcoords,
                    },
                },
            },
        };
    }
};
