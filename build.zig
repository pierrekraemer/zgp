const std = @import("std");

const zigglgen = @import("zigglgen");
const cimgui = @import("cimgui_zig");

fn addIncludePathsToTranslateC(translate_c: *std.Build.Step.TranslateC, lib: *std.Build.Step.Compile) void {
    for (lib.root_module.include_dirs.items) |*included| {
        switch (included.*) {
            .path => translate_c.addIncludePath(included.path),
            .config_header_step => translate_c.addConfigHeader(included.config_header_step),
            .path_system => translate_c.addSystemIncludePath(included.path_system),
            .other_step => addIncludePathsToTranslateC(translate_c, included.other_step),
            else => unreachable,
        }
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // EXE MODULE

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // TRANSLATE C

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
    });
    const c_mod = translate_c.createModule();
    exe_mod.addImport("c", c_mod);

    // FOR INCLUDE-ONLY THIRDPARTY HEADERS (WITHOUT BUILD STEPS)

    translate_c.addIncludePath(b.path("src/thirdparty"));

    // PREDICATES

    const predicates_dep = b.dependency("predicates", .{
        .target = target,
        .optimize = optimize,
        // .lto = lto,
    });
    const predicates_lib = predicates_dep.artifact("predicates");
    addIncludePathsToTranslateC(translate_c, predicates_lib);
    c_mod.linkLibrary(predicates_lib);
    // exe_mod.addImport("predicates", predicates_dep.module("predicates"));

    // CEIGEN

    const ceigen_dep = b.dependency("ceigen", .{
        .target = target,
        .optimize = optimize,
        // .lto = lto,
    });
    const ceigen_lib = ceigen_dep.artifact("ceigen");
    addIncludePathsToTranslateC(translate_c, ceigen_lib);
    c_mod.linkLibrary(ceigen_lib);
    // exe_mod.addImport("ceigen", ceigen_dep.module("ceigen"));

    // CLIBACC

    const clibacc_dep = b.dependency("clibacc", .{
        .target = target,
        .optimize = optimize,
        // .lto = lto,
    });
    const clibacc_lib = clibacc_dep.artifact("clibacc");
    addIncludePathsToTranslateC(translate_c, clibacc_lib);
    c_mod.linkLibrary(clibacc_lib);
    // exe_mod.addImport("clibacc", clibacc_dep.module("clibacc"));

    // GL_BINDINGS

    const gl_bindings = zigglgen.generateBindingsModule(b, .{
        .api = .gl,
        .version = .@"4.1",
        .profile = .core,
        // .extensions = &.{ .ARB_clip_control, .NV_scissor_exclusive },
    });
    exe_mod.addImport("gl", gl_bindings);

    // SDL

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        // .lto = lto,
        //.preferred_linkage = .static,
        //.strip = null,
        //.sanitize_c = null,
        //.pic = null,
        //.emscripten_pthreads = false,
        //.install_build_config_h = false,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    addIncludePathsToTranslateC(translate_c, sdl_lib);
    c_mod.linkLibrary(sdl_lib);

    // CIMGUI

    const cimgui_dep = b.dependency("cimgui_zig", .{
        .target = target,
        .optimize = optimize,
        // .lto = lto,
        .platforms = &[_]cimgui.Platform{.SDL3},
        .renderers = &[_]cimgui.Renderer{.OpenGL3},
        .docking = true,
    });
    const cimgui_lib = cimgui_dep.artifact("cimgui");
    addIncludePathsToTranslateC(translate_c, cimgui_lib);
    c_mod.linkLibrary(cimgui_lib);

    // BUILD EXE

    const exe = b.addExecutable(.{
        .name = "zgp",
        .root_module = exe_mod,
    });
    // exe.lto = lto;
    exe.root_module.addIncludePath(b.path("src"));
    b.installArtifact(exe);

    // RUN CMD

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_cmd.step.dependOn(b.getInstallStep());

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
