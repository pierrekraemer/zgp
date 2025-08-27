const VBO = @This();

const std = @import("std");
const gl = @import("gl");

const Data = @import("../utils/Data.zig").Data;

index: c_uint = 0,

pub fn init() VBO {
    var v: VBO = .{};
    gl.GenBuffers(1, (&v.index)[0..1]);
    return v;
}

pub fn deinit(v: *VBO) void {
    if (v.index != 0) {
        gl.DeleteBuffers(1, (&v.index)[0..1]);
        v.index = 0;
    }
}

pub fn fillFrom(v: *VBO, comptime T: type, data: *const Data(T)) !void {
    gl.BindBuffer(gl.ARRAY_BUFFER, v.index);
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    const vec_size = switch (@typeInfo(T)) {
        .array => @typeInfo(T).array.len,
        else => @compileError("VBO.fillFrom only supports array types"),
    };
    const buf_size = data.rawSize();
    gl.BufferData(gl.ARRAY_BUFFER, @intCast(buf_size), null, gl.STATIC_DRAW);
    const maybe_buffer = gl.MapBuffer(gl.ARRAY_BUFFER, gl.WRITE_ONLY);
    if (maybe_buffer) |buffer| {
        const buffer_f32: [*]f32 = @ptrCast(@alignCast(buffer));
        var it = data.rawConstIterator();
        var index: u32 = 0;
        while (it.next()) |value| {
            defer index += 1;
            const offset = index * vec_size;
            @memcpy(buffer_f32[offset .. offset + vec_size], value);
        }
        _ = gl.UnmapBuffer(gl.ARRAY_BUFFER);
    } else {
        return error.GlMapBufferFailed;
    }
}
