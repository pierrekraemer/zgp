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

pub fn fillFromIndexSlice(i: *IBO, indices: []const u32) !void {
    i.nb_indices = indices.len;
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, i.index);
    defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
    gl.BufferData(
        gl.ELEMENT_ARRAY_BUFFER,
        @intCast(i.nb_indices * @sizeOf(u32)),
        indices.ptr,
        gl.STATIC_DRAW,
    );
}

pub fn fillFromCellSlice(i: *IBO, sm: *SurfaceMesh, cells: []const SurfaceMesh.Cell, allocator: std.mem.Allocator) !void {
    if (cells.len == 0) {
        try i.fillFromIndexSlice(&.{});
        return;
    }
    const cell_type = cells[0].cellType();
    var indices = try std.ArrayList(u32).initCapacity(allocator, switch (cell_type) {
        .vertex => cells.len,
        .edge => cells.len * 2,
        .face => cells.len * 3, // TODO: this assumes all faces are triangles
        .boundary => cells.len * 2,
        else => unreachable,
    });
    defer indices.deinit(allocator);
    switch (cell_type) {
        .vertex => {
            for (cells) |cell| {
                try indices.append(allocator, sm.cellIndex(cell));
            }
        },
        .edge => {
            for (cells) |edge| {
                const d = edge.dart();
                const d1 = sm.phi1(d);
                try indices.append(allocator, sm.cellIndex(.{ .vertex = d }));
                try indices.append(allocator, sm.cellIndex(.{ .vertex = d1 }));
            }
        },
        .face => {
            for (cells) |face| {
                // TODO: should perform ear-triangulation on polygonal faces instead of just a triangle fan
                var dart_it = sm.cellDartIterator(face);
                const dart_start = dart_it.next() orelse break;
                const start_index = sm.cellIndex(.{ .vertex = dart_start });
                var dart_v1 = dart_it.next() orelse break;
                var v1_index = sm.cellIndex(.{ .vertex = dart_v1 });
                while (dart_it.next()) |dart_v2| {
                    const v2_index = sm.cellIndex(.{ .vertex = dart_v2 });
                    try indices.append(allocator, start_index);
                    try indices.append(allocator, v1_index);
                    try indices.append(allocator, v2_index);
                    dart_v1 = dart_v2;
                    v1_index = v2_index;
                }
            }
        },
        .boundary => {
            for (cells) |boundary| {
                var dart_it = sm.cellDartIterator(boundary);
                while (dart_it.next()) |d| {
                    try indices.append(allocator, sm.cellIndex(.{ .vertex = d }));
                    try indices.append(allocator, sm.cellIndex(.{ .vertex = sm.phi1(d) }));
                }
            }
        },
        else => unreachable,
    }
    try i.fillFromIndexSlice(indices.items);
}

pub fn fillFromSurfaceMesh(i: *IBO, sm: *SurfaceMesh, cell_type: SurfaceMesh.CellType, allocator: std.mem.Allocator) !void {
    var indices = try std.ArrayList(u32).initCapacity(allocator, 1024);
    defer indices.deinit(allocator);
    switch (cell_type) {
        .vertex => {
            var v_it = try SurfaceMesh.CellIterator(.vertex).init(sm);
            defer v_it.deinit();
            while (v_it.next()) |v| {
                try indices.append(allocator, sm.cellIndex(v));
            }
        },
        .edge => {
            var e_it = try SurfaceMesh.CellIterator(.edge).init(sm);
            defer e_it.deinit();
            while (e_it.next()) |e| {
                const d = e.dart();
                const d1 = sm.phi1(d);
                try indices.append(allocator, sm.cellIndex(.{ .vertex = d }));
                try indices.append(allocator, sm.cellIndex(.{ .vertex = d1 }));
            }
        },
        .face => {
            var f_it = try SurfaceMesh.CellIterator(.face).init(sm);
            defer f_it.deinit();
            while (f_it.next()) |f| {
                // TODO: should perform ear-triangulation on polygonal faces instead of just a triangle fan
                var dart_it = sm.cellDartIterator(f);
                const dart_start = dart_it.next() orelse break;
                const start_index = sm.cellIndex(.{ .vertex = dart_start });
                var dart_v1 = dart_it.next() orelse break;
                var v1_index = sm.cellIndex(.{ .vertex = dart_v1 });
                while (dart_it.next()) |dart_v2| {
                    const v2_index = sm.cellIndex(.{ .vertex = dart_v2 });
                    try indices.append(allocator, start_index);
                    try indices.append(allocator, v1_index);
                    try indices.append(allocator, v2_index);
                    dart_v1 = dart_v2;
                    v1_index = v2_index;
                }
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
    try i.fillFromIndexSlice(indices.items);
}

pub fn fillFromPointCloud(i: *IBO, pc: *PointCloud, allocator: std.mem.Allocator) !void {
    var indices = try std.ArrayList(u32).initCapacity(allocator, 1024);
    defer indices.deinit(allocator);
    var p_it = pc.pointIterator();
    while (p_it.next()) |p| {
        try indices.append(allocator, p);
    }
    try i.fillFromIndexSlice(indices.items);
}
