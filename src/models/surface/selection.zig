const std = @import("std");
const assert = std.debug.assert;

const SurfaceMesh = @import("SurfaceMesh.zig");

const vec = @import("../../geometry/vec.zig");
const Vec3f = vec.Vec3f;
const geometry_utils = @import("../../geometry/utils.zig");

/// A reusable context for selecting cells within a sphere of given radius around a vertex.
/// The vertex, edge and face buffers are filled with cells entirely contained in the sphere,
/// and the dart buffer is filled with outgoing darts that are crossed by the sphere.
pub const WithinSphereSelectionContext = struct {
    sm: *SurfaceMesh = undefined,
    vertex_position: SurfaceMesh.VertexData(Vec3f) = undefined,
    dm: SurfaceMesh.DartMarker = undefined,
    vertex_buffer: std.ArrayList(SurfaceMesh.Vertex) = undefined,
    edge_buffer: std.ArrayList(SurfaceMesh.Edge) = undefined,
    face_buffer: std.ArrayList(SurfaceMesh.Face) = undefined,
    crossed_dart_buffer: std.ArrayList(SurfaceMesh.Dart) = undefined,
    initialized: bool = false,

    pub fn init(
        sel_ctx: *WithinSphereSelectionContext,
        sm: *SurfaceMesh,
        vertex_position: SurfaceMesh.VertexData(Vec3f),
    ) !void {
        assert(!sel_ctx.initialized);
        sel_ctx.sm = sm;
        sel_ctx.vertex_position = vertex_position;
        sel_ctx.dm = try .init(sm);
        sel_ctx.vertex_buffer = try .initCapacity(sm.allocator, 32);
        sel_ctx.edge_buffer = try .initCapacity(sm.allocator, 32);
        sel_ctx.face_buffer = try .initCapacity(sm.allocator, 32);
        sel_ctx.crossed_dart_buffer = try .initCapacity(sm.allocator, 32);
        sel_ctx.initialized = true;
    }

    pub fn deinit(sel_ctx: *WithinSphereSelectionContext) void {
        if (!sel_ctx.initialized) {
            return;
        }
        sel_ctx.dm.deinit();
        sel_ctx.vertex_buffer.deinit(sel_ctx.sm.allocator);
        sel_ctx.edge_buffer.deinit(sel_ctx.sm.allocator);
        sel_ctx.face_buffer.deinit(sel_ctx.sm.allocator);
        sel_ctx.crossed_dart_buffer.deinit(sel_ctx.sm.allocator);
        sel_ctx.initialized = false;
    }

    pub fn reset(sel_ctx: *WithinSphereSelectionContext) void {
        assert(sel_ctx.initialized);
        sel_ctx.vertex_buffer.clearRetainingCapacity();
        sel_ctx.edge_buffer.clearRetainingCapacity();
        sel_ctx.face_buffer.clearRetainingCapacity();
        sel_ctx.crossed_dart_buffer.clearRetainingCapacity();
        sel_ctx.dm.reset();
    }

    fn includeVertex(
        sel_ctx: *WithinSphereSelectionContext,
        v: SurfaceMesh.Vertex,
    ) !void {
        try sel_ctx.vertex_buffer.append(sel_ctx.sm.allocator, v);
        var dart_it = sel_ctx.sm.vertexDartIterator(sel_ctx.sm.dart(v));
        while (dart_it.next()) |d| {
            sel_ctx.dm.mark(d);
            // if all darts of the edge are now marked, include edge in result
            if (sel_ctx.dm.isMarked(d) and sel_ctx.dm.isMarked(sel_ctx.sm.phi2(d))) {
                try sel_ctx.edge_buffer.append(sel_ctx.sm.allocator, sel_ctx.sm.edge(d));
            }
            // if all darts of the face are now marked, include face in result (after checking that the face is not a boundary face)
            if (!sel_ctx.sm.isBoundaryDart(d)) {
                const face = sel_ctx.sm.face(d);
                var face_dart_it = sel_ctx.sm.faceDartIterator(sel_ctx.sm.dart(face));
                const face_in = while (face_dart_it.next()) |fd| {
                    if (!sel_ctx.dm.isMarked(fd)) {
                        break false;
                    }
                } else true;
                if (face_in) {
                    try sel_ctx.face_buffer.append(sel_ctx.sm.allocator, face);
                }
            }
        }
    }

    // Collect all cells within a sphere of given radius around the given vertex
    pub fn cellsWithinSphereAroundVertex(
        sel_ctx: *WithinSphereSelectionContext,
        vertex: SurfaceMesh.Vertex,
        radius: f32,
    ) !void {
        sel_ctx.reset();

        const p = sel_ctx.vertex_position.value(vertex);
        try sel_ctx.includeVertex(vertex);

        var i: u32 = 0;
        while (i < sel_ctx.vertex_buffer.items.len) : (i += 1) {
            const v = sel_ctx.vertex_buffer.items[i];
            var dart_it = sel_ctx.sm.vertexDartIterator(sel_ctx.sm.dart(v));
            while (dart_it.next()) |d| {
                const d2 = sel_ctx.sm.phi2(d);
                if (sel_ctx.dm.isMarked(d2)) {
                    continue;
                }
                const nv = sel_ctx.sm.vertex(d2);
                const nvp = sel_ctx.vertex_position.value(nv);
                if (geometry_utils.pointInSphere(nvp, p, radius)) {
                    try sel_ctx.includeVertex(nv);
                } else {
                    try sel_ctx.crossed_dart_buffer.append(sel_ctx.sm.allocator, d);
                }
            }
        }
    }
};
