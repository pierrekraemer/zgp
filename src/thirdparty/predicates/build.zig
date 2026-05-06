const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("predicates", .{
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "predicates",
        .linkage = .static,
        .root_module = mod,
    });

    mod.addIncludePath(b.path("include"));
    mod.addCSourceFiles(.{
        .root = b.path("src"),
        .files = &.{
            "predicates.c",
        },
    });
    lib.installHeadersDirectory(
        b.path("include"),
        "predicates",
        .{},
    );

    b.installArtifact(lib);
}
