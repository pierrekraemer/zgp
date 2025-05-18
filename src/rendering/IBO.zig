const std = @import("std");
const gl = @import("gl");

const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const PointCloud = @import("../models/point/PointCloud.zig");

const Self = @This();

index: c_uint = 0,
nb_indices: usize = 0,

pub fn init() Self {
    var s: Self = .{};
    gl.GenBuffers(1, (&s.index)[0..1]);
    return s;
}

pub fn deinit(self: *Self) void {
    if (self.index != 0) {
        gl.DeleteBuffers(1, (&self.index)[0..1]);
        self.index = 0;
    }
}

pub fn fillFrom(self: *Self, sm: *SurfaceMesh, cell_type: SurfaceMesh.CellType, allocator: std.mem.Allocator) !void {
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.index);
    defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
    var indices = std.ArrayList(u32).init(allocator);
    defer indices.deinit();
    switch (cell_type) {
        .face => {
            var f_it = try SurfaceMesh.CellIterator(.face).init(sm); // TODO: replace with a more user friendly iterator initializer
            while (f_it.next()) |f| {
                var he_it: SurfaceMesh.CellHalfEdgeIterator = .{ // TODO: replace with a more user friendly local iterator
                    .surface_mesh = sm,
                    .cell = f,
                    .current = SurfaceMesh.halfEdge(f),
                };
                while (he_it.next()) |he| {
                    try indices.append(sm.indexOf(.{ .vertex = he }));
                }
            }
        },
        .edge => {
            var e_it = try SurfaceMesh.CellIterator(.edge).init(sm);
            while (e_it.next()) |e| {
                var he_it: SurfaceMesh.CellHalfEdgeIterator = .{
                    .surface_mesh = sm,
                    .cell = e,
                    .current = SurfaceMesh.halfEdge(e),
                };
                while (he_it.next()) |he| {
                    try indices.append(sm.indexOf(.{ .vertex = he }));
                }
            }
        },
        .vertex => {
            var v_it = try SurfaceMesh.CellIterator(.vertex).init(sm);
            while (v_it.next()) |v| {
                try indices.append(sm.indexOf(v));
            }
        },
        else => unreachable,
    }
    self.nb_indices = indices.items.len;
    gl.BufferData(
        gl.ELEMENT_ARRAY_BUFFER,
        @intCast(self.nb_indices * @sizeOf(u32)),
        indices.items.ptr,
        gl.STATIC_DRAW,
    );
}
