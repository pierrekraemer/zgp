const std = @import("std");

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");

pub fn faceDataVertexAverage(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Vertex,
    comptime T: type,
    incident_data: SurfaceMesh.FaceData(T),
) T {
    const t_info = @typeInfo(T);
    var sum: T = switch (t_info) {
        .float, .int => 0,
        .array => blk: {
            const s_info = @typeInfo(vec.ScalarTypeOf(T));
            if (s_info != .float and s_info != .int) {
                @compileError("faceDataVertexAverage only supports float, int, or array of float/int types");
            }
            break :blk vec.zero(T);
        },
        else => @compileError("faceDataVertexAverage only supports float, int, or array of float/int types"),
    };
    var count: usize = 0;
    var it = sm.vertexDartIterator(sm.dart(vertex));
    while (it.next()) |d| {
        count += 1;
        switch (t_info) {
            .float, .int => sum += incident_data.value(sm.face(d)),
            .array => sum = vec.add(sum, incident_data.value(sm.face(d))),
            else => unreachable,
        }
    }
    if (count == 0) {
        return sum; // return zero if no elements
    }
    return switch (t_info) {
        .float => sum / @as(T, @floatFromInt(count)),
        .int => sum / @as(T, @intCast(count)),
        .array => vec.divScalar(sum, @floatFromInt(count)),
        else => unreachable,
    };
}

pub fn computeFaceDataVertexAverages(
    io: std.Io,
    sm: *SurfaceMesh,
    comptime T: type,
    face_data: SurfaceMesh.FaceData(T),
    vertex_data: *SurfaceMesh.VertexData(T),
) !void {
    const Task = struct {
        surface_mesh: *const SurfaceMesh,
        face_data: SurfaceMesh.FaceData(T),
        vertex_data: *SurfaceMesh.VertexData(T),

        pub fn run(t: *const @This(), vertex: SurfaceMesh.Vertex) void {
            t.vertex_data.valuePtr(vertex).* = faceDataVertexAverage(
                t.surface_mesh,
                vertex,
                T,
                t.face_data,
            );
        }
    };

    var pctr: SurfaceMesh.ParallelVertexTaskRunner = try .init(sm);
    defer pctr.deinit();
    try pctr.run(io, Task{
        .surface_mesh = sm,
        .face_data = face_data,
        .vertex_data = vertex_data,
    });
}
