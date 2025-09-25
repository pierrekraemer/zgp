const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");
const vec = @import("../../geometry/vec.zig");
const Vec3 = vec.Vec3;

/// Compute the gradient of a scalar field defined on the vertices of the given face.
/// The gradient is returned as a vector in the plane of the face,
/// pointing in the direction of maximum increase of the scalar field,
/// and with a magnitude equal to the rate of increase per unit length.
/// The face is assumed to be triangular.
pub fn scalarFieldFaceGradient(
    sm: *const SurfaceMesh,
    face: SurfaceMesh.Cell,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    vertex_scalar_field: SurfaceMesh.CellData(.vertex, f32),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
) Vec3 {
    assert(face.cellType() == .face);
    var g = vec.zero3;
    var dart_it = sm.cellDartIterator(face);
    while (dart_it.next()) |d| {
        const v0 = vertex_position.value(.{ .vertex = sm.phi1(d) });
        const v1 = vertex_position.value(.{ .vertex = sm.phi_1(d) });
        const e = vec.sub3(v1, v0);
        const ortho = vec.cross3(face_normal.value(face), e);
        g = vec.add3(
            g,
            vec.mulScalar3(
                ortho,
                vertex_scalar_field.value(.{ .vertex = d }),
            ),
        );
    }
    g = vec.divScalar3(g, face_area.value(face));
    return g;
}

/// Compute the gradient of a scalar field defined on the vertices of the given SurfaceMesh,
/// and store them in the given face_gradient data.
pub fn computeScalarFieldFaceGradients(
    sm: *SurfaceMesh,
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    vertex_scalar_field: SurfaceMesh.CellData(.vertex, f32),
    face_normal: SurfaceMesh.CellData(.face, Vec3),
    face_area: SurfaceMesh.CellData(.face, f32),
    face_gradient: SurfaceMesh.CellData(.face, Vec3),
) !void {
    var face_it = try SurfaceMesh.CellIterator(.face).init(sm);
    defer face_it.deinit();
    while (face_it.next()) |face| {
        face_gradient.valuePtr(face).* = scalarFieldFaceGradient(
            sm,
            face,
            vertex_position,
            vertex_scalar_field,
            face_area,
            face_normal,
        );
    }
}

/// Compute the divergence of a vector field defined on the faces of the given vertex.
/// The divergence is returned as a scalar value.
/// Incident faces are assumed to be triangular.
pub fn vectorFieldVertexDivergence(
    sm: *const SurfaceMesh,
    vertex: SurfaceMesh.Cell,
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face_vector_field: SurfaceMesh.CellData(.face, Vec3),
) f32 {
    assert(vertex.cellType() == .vertex);
    var div: f32 = 0.0;
    var dart_it = sm.cellDartIterator(vertex);
    while (dart_it.next()) |d| {
        if (sm.isBoundaryDart(d)) continue;
        const d1 = sm.phi1(d);
        const d_1 = sm.phi_1(d);
        const p1 = vertex_position.value(.{ .vertex = d });
        const p2 = vertex_position.value(.{ .vertex = d1 });
        const p3 = vertex_position.value(.{ .vertex = d_1 });
        const X = face_vector_field.value(.{ .face = d });
        div += halfedge_cotan_weight.value(.{ .halfedge = d }) * vec.dot3(
            vec.sub3(p2, p1),
            X,
        );
        div += halfedge_cotan_weight.value(.{ .halfedge = d_1 }) * vec.dot3(
            vec.sub3(p3, p1),
            X,
        );
    }
    return div;
}

/// Compute the divergence of a vector field defined on the faces of the given SurfaceMesh,
/// and store them in the given vertex_divergence data.
pub fn computeVectorFieldVertexDivergences(
    sm: *SurfaceMesh,
    halfedge_cotan_weight: SurfaceMesh.CellData(.halfedge, f32),
    vertex_position: SurfaceMesh.CellData(.vertex, Vec3),
    face_vector_field: SurfaceMesh.CellData(.face, Vec3),
    vertex_divergence: SurfaceMesh.CellData(.vertex, f32),
) !void {
    var vertex_it = try SurfaceMesh.CellIterator(.vertex).init(sm);
    defer vertex_it.deinit();
    while (vertex_it.next()) |vertex| {
        vertex_divergence.valuePtr(vertex).* = vectorFieldVertexDivergence(
            sm,
            vertex,
            halfedge_cotan_weight,
            vertex_position,
            face_vector_field,
        );
    }
}
