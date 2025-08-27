const IBO = @This();

const std = @import("std");
const gl = @import("gl");

const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const PointCloud = @import("../models/point/PointCloud.zig");

index: c_uint = 0,
nb_indices: usize = 0,

pub fn init() IBO {
    var i: IBO = .{};
    gl.GenBuffers(1, (&i.index)[0..1]);
    return i;
}

pub fn deinit(i: *IBO) void {
    if (i.index != 0) {
        gl.DeleteBuffers(1, (&i.index)[0..1]);
        i.index = 0;
    }
}

pub fn fillFrom(i: *IBO, sm: *SurfaceMesh, cell_type: SurfaceMesh.CellType, allocator: std.mem.Allocator) !void {
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, i.index);
    defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(allocator);
    switch (cell_type) {
        .face => {
            var f_it = try SurfaceMesh.CellIterator(.face).init(sm);
            defer f_it.deinit();
            while (f_it.next()) |f| {
                var dart_it = sm.cellDartIterator(f); // TODO: triangulate polygonal faces
                while (dart_it.next()) |d| {
                    try indices.append(allocator, sm.cellIndex(.{ .vertex = d }));
                }
            }
        },
        .edge => {
            var e_it = try SurfaceMesh.CellIterator(.edge).init(sm);
            defer e_it.deinit();
            while (e_it.next()) |e| {
                var dart_it = sm.cellDartIterator(e);
                while (dart_it.next()) |d| {
                    try indices.append(allocator, sm.cellIndex(.{ .vertex = d }));
                }
            }
        },
        .vertex => {
            var v_it = try SurfaceMesh.CellIterator(.vertex).init(sm);
            defer v_it.deinit();
            while (v_it.next()) |v| {
                try indices.append(allocator, sm.cellIndex(v));
            }
        },
        .boundary => {
            var b_it = try SurfaceMesh.CellIterator(.boundary).init(sm);
            defer b_it.deinit();
            while (b_it.next()) |b| {
                var dart_it = sm.cellDartIterator(b);
                while (dart_it.next()) |d| {
                    try indices.append(allocator, sm.cellIndex(.{ .vertex = d }));
                    try indices.append(allocator, sm.cellIndex(.{ .vertex = sm.phi1(d) }));
                }
            }
        },
        else => unreachable,
    }
    i.nb_indices = indices.items.len;
    gl.BufferData(
        gl.ELEMENT_ARRAY_BUFFER,
        @intCast(i.nb_indices * @sizeOf(u32)),
        indices.items.ptr,
        gl.STATIC_DRAW,
    );
}
