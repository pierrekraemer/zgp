const std = @import("std");

const zgp = @import("../main.zig");
const c = zgp.c;

const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");

const vec = @import("vec.zig");
const Vec3f = vec.Vec3f;

pub const Index = u32;
pub const Scalar = f32;

pub const TrianglesBVH = struct {
    bvh_ptr: ?*anyopaque = null,

    pub fn init(
        sm: *SurfaceMesh,
        vertex_position: SurfaceMesh.CellData(.vertex, Vec3f),
    ) !TrianglesBVH {
        var vertex_index = try sm.addData(.vertex, u32, "__vertex_index");
        defer sm.removeData(.vertex, vertex_index.gen());

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

        var face_it = try SurfaceMesh.CellIterator(.face).init(sm);
        defer face_it.deinit();
        while (face_it.next()) |f| {
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
        };
    }

    pub fn deinit(tbvh: *TrianglesBVH) void {
        if (tbvh.bvh_ptr) |b| {
            c.destroyTrianglesBVH(b);
            tbvh.bvh_ptr = null;
        }
    }

    pub fn closestPoint(tbvh: TrianglesBVH, point: Vec3f) Vec3f {
        var closest: Vec3f = undefined;
        c.closestPoint(tbvh.bvh_ptr, &point, &closest);
        return closest;
    }
};
