const std = @import("std");
const cimgui = @import("cimgui_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // EXE MODULE

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // CEIGEN

    const ceigen_dep = b.dependency("ceigen", .{
        .target = target,
        .optimize = optimize,
    });
    const ceigen_lib = ceigen_dep.artifact("ceigen");
    exe_mod.linkLibrary(ceigen_lib);
    // exe_mod.addImport("zeigen", zeigen_dep.module("zeigen"));

    // SDL

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        //.preferred_linkage = .static,
        //.strip = null,
        //.pic = null,
        //.lto = optimize != .Debug,
        //.emscripten_pthreads = false,
        //.install_build_config_h = false,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    // const sdl_test_lib = sdl_dep.artifact("SDL3_test");
    exe_mod.linkLibrary(sdl_lib);

    // CIMGUI

    const cimgui_dep = b.dependency("cimgui_zig", .{
        .target = target,
        .optimize = optimize,
        .platform = cimgui.Platform.SDL3,
        .renderer = cimgui.Renderer.OpenGL3,
    });
    const cimgui_lib = cimgui_dep.artifact("cimgui");
    exe_mod.linkLibrary(cimgui_lib);

    // GL_BINDINGS

    const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{
        .api = .gl,
        .version = .@"4.1",
        .profile = .core,
        // .extensions = &.{ .ARB_clip_control, .NV_scissor_exclusive },
    });
    exe_mod.addImport("gl", gl_bindings);

    // BUILD EXE

    const exe = b.addExecutable(.{
        .name = "zgp",
        .root_module = exe_mod,
    });
    // exe.want_lto = optimize != .Debug;
    b.installArtifact(exe);

    // RUN CMD

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // TESTS

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
