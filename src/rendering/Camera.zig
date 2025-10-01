const Camera = @This();

const std = @import("std");

const View = @import("View.zig");

const mat = @import("../geometry/mat.zig");
const Mat4f = mat.Mat4f;
const vec = @import("../geometry/vec.zig");
const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;

const CameraProjectionType = enum {
    perspective,
    orthographic,
};

position: Vec3f,
look_dir: Vec3f,
up_dir: Vec3f,
pivot_position: Vec3f,

view_matrix: Mat4f = undefined,

aspect_ratio: f32,
field_of_view: f32,
projection_type: CameraProjectionType,

projection_matrix: Mat4f = undefined,

views_using_camera: std.ArrayList(*View),

pub fn init(
    position: Vec3f,
    look_dir: Vec3f,
    up_dir: Vec3f,
    pivot_position: Vec3f,
    aspect_ratio: f32,
    field_of_view: f32,
    projection_type: CameraProjectionType,
) Camera {
    var c: Camera = .{
        .position = position,
        .look_dir = look_dir,
        .up_dir = up_dir,
        .pivot_position = pivot_position,
        .aspect_ratio = aspect_ratio,
        .field_of_view = field_of_view,
        .projection_type = projection_type,
        .views_using_camera = .empty,
    };
    c.updateViewMatrix();
    c.updateProjectionMatrix();
    return c;
}

pub fn deinit(c: *Camera, allocator: std.mem.Allocator) void {
    c.views_using_camera.deinit(allocator);
}

pub fn updateViewMatrix(c: *Camera) void {
    c.view_matrix = mat.lookAt(c.position, c.look_dir, c.up_dir);
    for (c.views_using_camera.items) |view| {
        view.need_redraw = true;
    }
}

pub fn updateProjectionMatrix(c: *Camera) void {
    c.projection_matrix = switch (c.projection_type) {
        .perspective => mat.perspective(c.field_of_view, c.aspect_ratio, 0.1, 3.0),
        .orthographic => mat.orthographic(c.aspect_ratio * -c.view_matrix[3][2], -c.view_matrix[3][2], 0.1, 3.0),
    };
    for (c.views_using_camera.items) |view| {
        view.need_redraw = true;
    }
}

pub fn rotateFromScreenVec(c: *Camera, screen_vec: Vec2f) void {
    const screen_axis4: Vec4f = .{ screen_vec[1], screen_vec[0], 0.0, 0.0 };
    const angle = vec.norm4f(screen_axis4) * 0.01; // TODO: normalize with window dimensions
    const world_axis4 = mat.preMulVec4f(screen_axis4, c.view_matrix);
    const world_axis3: Vec3f = vec.normalized3f(.{ world_axis4[0], world_axis4[1], world_axis4[2] });
    const rot = mat.rotMat3FromNormalizedAxisAndAngle(world_axis3, angle);
    c.position = vec.add3f(
        c.pivot_position,
        mat.preMulVec3f(
            vec.sub3f(c.position, c.pivot_position),
            rot,
        ),
    );
    c.look_dir = mat.preMulVec3f(c.look_dir, rot);
    c.up_dir = mat.preMulVec3f(c.up_dir, rot);
    c.updateViewMatrix();
}

pub fn translateFromScreenVec(c: *Camera, screen_vec: Vec2f) void {
    const screen_tr4: Vec4f = .{ -screen_vec[0] * 0.001, screen_vec[1] * 0.001, 0.0, 0.0 }; // TODO: normalize with window dimensions
    const world_tr4 = mat.preMulVec4f(screen_tr4, c.view_matrix);
    c.position = vec.add3f(
        c.position,
        .{ world_tr4[0], world_tr4[1], world_tr4[2] },
    );
    c.updateViewMatrix();
}

pub fn moveForward(c: *Camera, distance: f32) void {
    c.position = vec.add3f(c.position, vec.mulScalar3f(c.look_dir, distance));
    c.updateViewMatrix();
}
