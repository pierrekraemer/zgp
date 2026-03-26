const IBO = @This();

const std = @import("std");
const gl = @import("gl");

const PointCloud = @import("../models/point/PointCloud.zig");
const SurfaceMesh = @import("../models/surface/SurfaceMesh.zig");
const IncidenceGraph = @import("../models/incidenceGraph/IncidenceGraph.zig");

const Primitive = enum {
    points,
    lines,
    triangles,
};

// this buffer stores the vertex indices of the primitives to render
// (1 index per point, 2 indices per line, 3 indices per triangle, etc.)
index: c_uint = 0,
nb_indices: usize = 0,

primitive: Primitive = undefined,

// for primitives that are not vertices (line, triangle),
// this buffer stores the cell index corresponding to each primitive in the order they appear in the index buffer
// (e.g. for line primitives, it stores the edge index corresponding to each pair of vertex indices in the index buffer,
// for triangle primitives it stores the face index corresponding to each triplet of vertex indices in the index buffer, etc.),
// so that data associated to the cell corresponding to a primitive can be accessed in the shader via PrimitiveID and a texture buffer
cell_index_buffer_index: c_uint = 0,
cell_index_buffer_nb_indices: usize = 0,

pub fn init() IBO {
    var i: IBO = .{};
    gl.GenBuffers(1, (&i.index)[0..1]);
    gl.GenBuffers(1, (&i.cell_index_buffer_index)[0..1]);
    return i;
}

pub fn deinit(i: *IBO) void {
    if (i.index != 0) {
        gl.DeleteBuffers(1, (&i.index)[0..1]);
        i.index = 0;
        i.nb_indices = 0;
    }
    if (i.cell_index_buffer_index != 0) {
        gl.DeleteBuffers(1, (&i.cell_index_buffer_index)[0..1]);
        i.cell_index_buffer_index = 0;
        i.cell_index_buffer_nb_indices = 0;
    }
}

pub fn fillFromIndexSlice(i: *IBO, indices: []const u32, cell_indices: []const u32) void {
    i.nb_indices = indices.len;
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, i.index);
    gl.BufferData(
        gl.ELEMENT_ARRAY_BUFFER,
        @intCast(i.nb_indices * @sizeOf(u32)),
        indices.ptr,
        gl.STATIC_DRAW,
    );
    i.cell_index_buffer_nb_indices = cell_indices.len;
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, i.cell_index_buffer_index);
    gl.BufferData(
        gl.ELEMENT_ARRAY_BUFFER,
        @intCast(i.cell_index_buffer_nb_indices * @sizeOf(u32)),
        cell_indices.ptr,
        gl.STATIC_DRAW,
    );
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
}

// TODO: PointCloud, SurfaceMesh & IncidenceGraph types should not really be here

pub fn fillFromPointCloud(i: *IBO, pc: *PointCloud, allocator: std.mem.Allocator) !void {
    var indices = try std.ArrayList(u32).initCapacity(allocator, 1024);
    defer indices.deinit(allocator);
    var p_it = pc.pointIterator();
    while (p_it.next()) |p| {
        try indices.append(allocator, p);
    }
    i.primitive = .points;
    i.fillFromIndexSlice(indices.items, &.{});
}

// TODO: check for potentially non-initialized IBO primitive type

pub fn fillFromSurfaceMeshCellSlice(i: *IBO, sm: *SurfaceMesh, cells: []const SurfaceMesh.Cell, allocator: std.mem.Allocator) !void {
    if (cells.len == 0) {
        i.fillFromIndexSlice(&.{}, &.{});
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
    var cell_indices: std.ArrayList(u32) = try std.ArrayList(u32).initCapacity(allocator, if (cell_type == .vertex) 0 else cells.len);
    defer cell_indices.deinit(allocator);
    switch (cell_type) {
        .vertex => {
            i.primitive = .points;
            for (cells) |v| {
                try indices.append(allocator, sm.cellIndex(v));
            }
        },
        .edge => {
            i.primitive = .lines;
            for (cells) |e| {
                const d = e.dart();
                const d1 = sm.phi1(d);
                try indices.append(allocator, sm.cellIndex(.{ .vertex = d }));
                try indices.append(allocator, sm.cellIndex(.{ .vertex = d1 }));
                // line primitive is associated to its edge index
                try cell_indices.append(allocator, sm.cellIndex(e));
            }
        },
        .face => {
            i.primitive = .triangles;
            for (cells) |f| {
                // TODO: should perform ear-triangulation on polygonal faces instead of just a triangle fan
                var dart_it = sm.cellDartIterator(f);
                const dart_start = dart_it.next() orelse continue;
                const start_index = sm.cellIndex(.{ .vertex = dart_start });
                var dart_v1 = dart_it.next() orelse continue;
                var v1_index = sm.cellIndex(.{ .vertex = dart_v1 });
                while (dart_it.next()) |dart_v2| {
                    const v2_index = sm.cellIndex(.{ .vertex = dart_v2 });
                    try indices.append(allocator, start_index);
                    try indices.append(allocator, v1_index);
                    try indices.append(allocator, v2_index);
                    // triangle primitive is associated to its face index
                    // (for polygonal faces, multiple triangle primitives are associated to the same face index)
                    try cell_indices.append(allocator, sm.cellIndex(f));
                    dart_v1 = dart_v2;
                    v1_index = v2_index;
                }
            }
        },
        .boundary => {
            i.primitive = .lines;
            for (cells) |b| {
                var dart_it = sm.cellDartIterator(b);
                while (dart_it.next()) |d| {
                    try indices.append(allocator, sm.cellIndex(.{ .vertex = d }));
                    try indices.append(allocator, sm.cellIndex(.{ .vertex = sm.phi1(d) }));
                    // boundary line primitive is associated to its edge index
                    try cell_indices.append(allocator, sm.cellIndex(.{ .edge = d }));
                }
            }
        },
        else => unreachable,
    }
    i.fillFromIndexSlice(indices.items, cell_indices.items);
}

pub fn fillFromSurfaceMesh(i: *IBO, sm: *SurfaceMesh, comptime cell_type: SurfaceMesh.CellType, allocator: std.mem.Allocator) !void {
    i.primitive = switch (cell_type) {
        .vertex => .points,
        .edge => .lines,
        .boundary => .lines,
        .face => .triangles,
        else => unreachable,
    };
    const nb_cells = switch (cell_type) {
        .boundary => 512, // counting boundary cells is expensive, so we just assume a number of cells for the preallocation of the index buffers
        else => sm.nbCells(cell_type),
    };
    if (nb_cells == 0) {
        i.fillFromIndexSlice(&.{}, &.{});
        return;
    }
    var indices = try std.ArrayList(u32).initCapacity(allocator, switch (cell_type) {
        .vertex => nb_cells,
        .edge => nb_cells * 2,
        .face => nb_cells * 3, // TODO: this assumes all faces are triangles
        .boundary => nb_cells * 2,
        else => unreachable,
    });
    defer indices.deinit(allocator);
    var cell_indices: std.ArrayList(u32) = try std.ArrayList(u32).initCapacity(allocator, if (cell_type == .vertex) 0 else nb_cells);
    defer cell_indices.deinit(allocator);
    switch (cell_type) {
        .vertex => {
            var v_it: SurfaceMesh.CellIterator = try .init(sm, .vertex);
            defer v_it.deinit();
            while (v_it.next()) |v| {
                try indices.append(allocator, sm.cellIndex(v));
            }
        },
        .edge => {
            var e_it: SurfaceMesh.CellIterator = try .init(sm, .edge);
            defer e_it.deinit();
            while (e_it.next()) |e| {
                const d = e.dart();
                const d1 = sm.phi1(d);
                try indices.append(allocator, sm.cellIndex(.{ .vertex = d }));
                try indices.append(allocator, sm.cellIndex(.{ .vertex = d1 }));
                // line primitive is associated to its edge index
                try cell_indices.append(allocator, sm.cellIndex(e));
            }
        },
        .face => {
            var f_it: SurfaceMesh.CellIterator = try .init(sm, .face);
            defer f_it.deinit();
            while (f_it.next()) |f| {
                // TODO: should perform ear-triangulation on polygonal faces instead of just a triangle fan
                var dart_it = sm.cellDartIterator(f);
                const dart_start = dart_it.next() orelse continue;
                const start_index = sm.cellIndex(.{ .vertex = dart_start });
                var dart_v1 = dart_it.next() orelse continue;
                var v1_index = sm.cellIndex(.{ .vertex = dart_v1 });
                while (dart_it.next()) |dart_v2| {
                    const v2_index = sm.cellIndex(.{ .vertex = dart_v2 });
                    try indices.append(allocator, start_index);
                    try indices.append(allocator, v1_index);
                    try indices.append(allocator, v2_index);
                    // triangle primitive is associated to its face index
                    // (for polygonal faces, multiple triangle primitives are associated to the same face index)
                    try cell_indices.append(allocator, sm.cellIndex(f));
                    dart_v1 = dart_v2;
                    v1_index = v2_index;
                }
            }
        },
        .boundary => {
            var b_it: SurfaceMesh.CellIterator = try .init(sm, .boundary);
            defer b_it.deinit();
            while (b_it.next()) |b| {
                var dart_it = sm.cellDartIterator(b);
                while (dart_it.next()) |d| {
                    try indices.append(allocator, sm.cellIndex(.{ .vertex = d }));
                    try indices.append(allocator, sm.cellIndex(.{ .vertex = sm.phi1(d) }));
                    // boundary line primitive is associated to its edge index
                    try cell_indices.append(allocator, sm.cellIndex(.{ .edge = d }));
                }
            }
        },
        else => unreachable,
    }
    i.fillFromIndexSlice(indices.items, cell_indices.items);
}

pub fn fillFromIncidenceGraph(i: *IBO, ig: *IncidenceGraph, comptime cell_type: IncidenceGraph.CellType, allocator: std.mem.Allocator) !void {
    i.primitive = switch (cell_type) {
        .vertex => .points,
        .edge => .lines,
        .face => .triangles,
    };
    const nb_cells = ig.nbCells(cell_type);
    if (nb_cells == 0) {
        i.fillFromIndexSlice(&.{}, &.{});
        return;
    }
    var indices = try std.ArrayList(u32).initCapacity(allocator, switch (cell_type) {
        .vertex => nb_cells,
        .edge => nb_cells * 2,
        .face => nb_cells * 3, // TODO: this assumes all faces are triangles
    });
    defer indices.deinit(allocator);
    var cell_indices: std.ArrayList(u32) = try std.ArrayList(u32).initCapacity(allocator, if (cell_type == .vertex) 0 else nb_cells);
    defer cell_indices.deinit(allocator);
    switch (cell_type) {
        .vertex => {
            var v_it = ig.cellIterator(.vertex);
            while (v_it.next()) |v| {
                try indices.append(allocator, v.index());
            }
        },
        .edge => {
            var e_it = ig.cellIterator(.edge);
            while (e_it.next()) |e| {
                const e_idx = e.index();
                const iv = ig.edge_incident_vertices.value(e_idx);
                try indices.append(allocator, iv[0]);
                try indices.append(allocator, iv[1]);
                // line primitive is associated to its edge index
                try cell_indices.append(allocator, e_idx);
            }
        },
        .face => {
            var f_it = ig.cellIterator(.face);
            while (f_it.next()) |f| {
                // TODO: should perform ear-triangulation on polygonal faces instead of just a triangle fan
                const f_idx = f.index();
                const ie = ig.face_incident_edges.value(f_idx);
                if (ie.items.len < 3) continue;
                const ie_dir = ig.face_incident_edges_dir.value(f_idx);
                const start_index = if (ie_dir.items[0]) ig.edge_incident_vertices.value(ie.items[0])[0] else ig.edge_incident_vertices.value(ie.items[0])[1];
                for (1..ie.items.len) |ie_idx| {
                    const v1_index = if (ie_dir.items[ie_idx]) ig.edge_incident_vertices.value(ie.items[ie_idx])[0] else ig.edge_incident_vertices.value(ie.items[ie_idx])[1];
                    const v2_index = if (ie_dir.items[ie_idx]) ig.edge_incident_vertices.value(ie.items[ie_idx])[1] else ig.edge_incident_vertices.value(ie.items[ie_idx])[0];
                    try indices.append(allocator, start_index);
                    try indices.append(allocator, v1_index);
                    try indices.append(allocator, v2_index);
                    // triangle primitive is associated to its face index
                    // (for polygonal faces, multiple triangle primitives are associated to the same face index)
                    try cell_indices.append(allocator, f_idx);
                }
            }
        },
    }
    i.fillFromIndexSlice(indices.items, cell_indices.items);
}
