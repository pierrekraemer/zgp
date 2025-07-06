const std = @import("std");
const gl = @import("gl");

const Data = @import("../utils/Data.zig").Data;

const Self = @This();

index: c_uint = 0,

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

pub fn fillFrom(self: *Self, comptime T: type, data: *const Data(T)) !void {
    gl.BindBuffer(gl.ARRAY_BUFFER, self.index);
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    const vec_size = @typeInfo(T).array.len;
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
