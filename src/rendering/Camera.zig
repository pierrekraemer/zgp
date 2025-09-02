const Camera = @This();

const std = @import("std");
const mat = @import("../geometry/mat.zig");
const Mat4 = mat.Mat4;
const vec = @import("../geometry/vec.zig");
const Vec2 = vec.Vec2;
const Vec3 = vec.Vec3;
const Vec4 = vec.Vec4;

const CameraProjectionType = enum {
    perspective,
    orthographic,
};

position: Vec3 = undefined,
look_dir: Vec3 = undefined,
up_dir: Vec3 = undefined,
pivot_position: Vec3 = undefined,

view_matrix: Mat4 = undefined,

aspect_ratio: f32 = undefined,
field_of_view: f32 = undefined,
projection_type: CameraProjectionType = undefined,

projection_matrix: Mat4 = undefined,

pub fn updateViewMatrix(c: *Camera) void {
    c.view_matrix = mat.lookAt(c.position, c.look_dir, c.up_dir);
}

pub fn updateProjectionMatrix(c: *Camera) void {
    c.projection_matrix = switch (c.projection_type) {
        .perspective => mat.perspective(c.field_of_view, c.aspect_ratio, 0.01, 5.0),
        .orthographic => mat.orthographic(c.aspect_ratio * -c.view_matrix[3][2], -c.view_matrix[3][2], 0.01, 5.0),
    };
}

pub fn rotateFromScreenVec(c: *Camera, screen_vec: Vec2) void {
    const screen_axis4: Vec4 = .{ screen_vec[1], screen_vec[0], 0.0, 0.0 };
    const angle = vec.norm4(screen_axis4) * 0.01; // TODO: normalize with window dimensions
    const world_axis4 = mat.preMulVec4(screen_axis4, c.view_matrix);
    const world_axis3: Vec3 = vec.normalized3(.{ world_axis4[0], world_axis4[1], world_axis4[2] });
    const rot = mat.rotMat3FromNormalizedAxisAndAngle(world_axis3, angle);
    c.position = vec.add3(c.pivot_position, mat.preMulVec3(vec.sub3(c.position, c.pivot_position), rot));
    c.look_dir = mat.preMulVec3(c.look_dir, rot);
    c.up_dir = mat.preMulVec3(c.up_dir, rot);
    c.updateViewMatrix();
}

pub fn translateFromScreenVec(c: *Camera, screen_vec: Vec2) void {
    const screen_tr4: Vec4 = .{ -screen_vec[0] * 0.001, screen_vec[1] * 0.001, 0.0, 0.0 }; // TODO: normalize with window dimensions
    const world_tr4 = mat.preMulVec4(screen_tr4, c.view_matrix);
    c.position = vec.add3(c.position, .{ world_tr4[0], world_tr4[1], world_tr4[2] });
    c.updateViewMatrix();
}

pub fn moveForward(c: *Camera, distance: f32) void {
    c.position = vec.add3(c.position, vec.mulScalar3(c.look_dir, distance));
    c.updateViewMatrix();
}
