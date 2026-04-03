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

    lib.addIncludePath(b.path("lib"));
    lib.addIncludePath(b.path("include"));
    lib.addCSourceFiles(.{
        .root = b.path("src"),
        .files = &.{
            "bvh.cpp",
        },
    });
    lib.installHeadersDirectory(
        b.path("include"),
        "clibacc",
        .{},
    );

    b.installArtifact(lib);
}
