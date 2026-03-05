const SurfacePoint = @This();

const SurfaceMesh = @import("SurfaceMesh.zig");
const Cell = SurfaceMesh.Cell;

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;

// TODO: this code assumes that faces are triangles

pub const SurfacePointType = union(enum) {
    vertex: Cell, // a .vertex
    edge: struct { cell: Cell, t: f32 }, // cell is a .edge, t in [0, 1], orientation of cell.dart()
    face: struct { cell: Cell, bcoords: Vec3f }, // cell is a .face, bcoords simplex barycentric coordinates
};

surface_mesh: *SurfaceMesh,
type: SurfacePointType,

pub fn interpolate(sp: *const SurfacePoint, comptime T: type, data: SurfaceMesh.CellData(.vertex, T)) T {
    return switch (sp.type) {
        .vertex => |v| data.value(v),
        .edge => |e| {
            const v0 = data.value(.{ .vertex = e.cell.dart() });
            const v1 = data.value(.{ .vertex = sp.surface_mesh.phi1(e.cell.dart()) });
            return vec.add3f(
                vec.mulScalar3f(v0, 1.0 - e.t),
                vec.mulScalar3f(v1, e.t),
            );
        },
        .face => |f| {
            const v0 = data.value(.{ .vertex = f.cell.dart() });
            const v1 = data.value(.{ .vertex = sp.surface_mesh.phi1(f.cell.dart()) });
            const v2 = data.value(.{ .vertex = sp.surface_mesh.phi_1(f.cell.dart()) });
            return vec.add3f(
                vec.mulScalar3f(v0, f.bcoords[0]),
                vec.add3f(
                    vec.mulScalar3f(v1, f.bcoords[1]),
                    vec.mulScalar3f(v2, f.bcoords[2]),
                ),
            );
        },
    };
}
