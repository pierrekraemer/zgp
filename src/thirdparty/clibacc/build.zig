const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("clibacc", .{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
    });

    const lib = b.addLibrary(.{
        .name = "clibacc",
        .linkage = .static,
        .root_module = mod,
    });

    mod.addIncludePath(b.path("lib"));
    mod.addIncludePath(b.path("include"));
    mod.addCSourceFiles(.{
        .root = b.path("src"),
        .files = &.{
            "bvh.cpp",
            "kd.cpp",
        },
    });
    lib.installHeadersDirectory(
        b.path("include"),
        "clibacc",
        .{},
    );

    b.installArtifact(lib);
}
