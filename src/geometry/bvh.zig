const std = @import("std");

const zgp = @import("../main.zig");
const c = zgp.c;

const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");

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
    bvh_ptr: ?*anyopaque = null,
    surface_mesh: ?*SurfaceMesh = null,
    vertex_position: ?SurfaceMesh.CellData(.vertex, Vec3f) = null,
    surface_mesh_faces: std.ArrayList(SurfaceMesh.Cell) = .empty,

    pub fn init(
        sm: *SurfaceMesh,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    ) !TrianglesBVH {
        var vertex_index = try sm.addData(.vertex, u32, "__vertex_index");
        defer sm.removeData(.vertex, vertex_index.gen());

        var surface_mesh_faces = try std.ArrayList(SurfaceMesh.Cell).initCapacity(sm.allocator, sm.nbCells(.face));

        var triangles_indices_array = try std.ArrayList(Index).initCapacity(sm.allocator, 3 * sm.nbCells(.face));
        defer triangles_indices_array.deinit(sm.allocator);
        var position_array = try std.ArrayList(Vec3f).initCapacity(sm.allocator, sm.nbCells(.vertex));
        defer position_array.deinit(sm.allocator);

        var vertex_it = try SurfaceMesh.CellIterator(.vertex).init(sm);
        defer vertex_it.deinit();
        var nb_vertices: u32 = 0;
        while (vertex_it.next()) |v| : (nb_vertices += 1) {
            vertex_index.valuePtr(v).* = nb_vertices;
            try position_array.append(sm.allocator, vertex_position.value(v));
        }

        // TODO: this code makes the assumption that the mesh is made of triangle faces
        var face_it = try SurfaceMesh.CellIterator(.face).init(sm);
        defer face_it.deinit();
        while (face_it.next()) |f| {
            try surface_mesh_faces.append(sm.allocator, f);
            var dart_it = sm.cellDartIterator(f);
            while (dart_it.next()) |d| {
                try triangles_indices_array.append(sm.allocator, vertex_index.value(.{ .vertex = d }));
            }
        }

        return .{
            .bvh_ptr = c.createTrianglesBVH(
                triangles_indices_array.items.ptr,
                @intCast(triangles_indices_array.items.len / 3),
                @ptrCast(position_array.items.ptr),
                @intCast(position_array.items.len),
            ),
            .surface_mesh = sm,
            .vertex_position = vertex_position,
            .surface_mesh_faces = surface_mesh_faces,
        };
    }

    pub fn deinit(tbvh: *TrianglesBVH) void {
        if (tbvh.bvh_ptr) |b| {
            c.destroyTrianglesBVH(b);
            tbvh.bvh_ptr = null;
        }
        if (tbvh.surface_mesh) |sm| {
            tbvh.surface_mesh_faces.deinit(sm.allocator);
        }
        tbvh.surface_mesh = null;
        tbvh.vertex_position = null;
    }

    pub fn intersect(tbvh: TrianglesBVH, ray: Ray) ?Hit {
        var hit: Hit = undefined;
        if (c.intersect(tbvh.bvh_ptr, &ray, &hit)) {
            return hit;
        }
        return null;
    }

    pub fn intersectedTriangle(tbvh: TrianglesBVH, ray: Ray) ?SurfaceMesh.Cell {
        if (tbvh.intersect(ray)) |h| {
            return tbvh.surface_mesh_faces.items[h.triIndex];
        }
        return null;
    }

    pub fn intersectedVertex(tbvh: TrianglesBVH, ray: Ray) ?SurfaceMesh.Cell {
        if (tbvh.intersect(ray)) |h| {
            const f = tbvh.surface_mesh_faces.items[h.triIndex];
            if (h.bcoords[0] > h.bcoords[1]) {
                if (h.bcoords[0] > h.bcoords[2]) { // bcoords[0] is largest
                    return .{ .vertex = f.dart() };
                } else { // bcoords[2] is largest
                    return .{ .vertex = tbvh.surface_mesh.?.phi_1(f.dart()) };
                }
            } else {
                if (h.bcoords[1] > h.bcoords[2]) { // bcoords[1] is largest
                    return .{ .vertex = tbvh.surface_mesh.?.phi1(f.dart()) };
                } else { // bcoords[2] is largest
                    return .{ .vertex = tbvh.surface_mesh.?.phi_1(f.dart()) };
                }
            }
        }
        return null;
    }

    pub fn closestPoint(tbvh: TrianglesBVH, point: Vec3f) Vec3f {
        var closest: Vec3f = undefined;
        c.closestPoint(tbvh.bvh_ptr, &point, &closest);
        return closest;
    }
};
