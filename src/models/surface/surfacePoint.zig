const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const Cell = SurfaceMesh.Cell;

pub const SurfacePoint = union(enum) {
    vertex: Cell,
    edge: struct { cell: Cell, t: f32 }, // between 0 and 1 },
    face: struct { cell: Cell, bcoords: Vec3f },
};
