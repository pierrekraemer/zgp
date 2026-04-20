const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("ceigen", .{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
    });

    const lib = b.addLibrary(.{
        .name = "ceigen",
        .linkage = .static,
        .root_module = mod,
    });

    mod.addIncludePath(b.path("lib"));
    mod.addIncludePath(b.path("include"));
    mod.addCSourceFiles(.{
        .root = b.path("src"),
        .files = &.{
            "small.cpp",
            "sparse.cpp",
            "dense.cpp",
        },
    });
    lib.installHeadersDirectory(
        b.path("include"),
        "ceigen",
        .{},
    );

    b.installArtifact(lib);
}
