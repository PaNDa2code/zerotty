const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_freetype = b.option(bool, "enable_freetype", "Build Freetype") orelse true;

    const hurfbuzz_upstream = b.dependency("harfbuzz", .{});
    const freetype_upstream = b.dependency("freetype", .{});

    const harfbuzz_lib = b.addStaticLibrary(.{
        .name = "harfbuzz",
        .target = target,
        .optimize = optimize,
    });

    harfbuzz_lib.addCSourceFile(.{
        .file = hurfbuzz_upstream.path("src/harfbuzz.cc"),
        .flags = &.{} ++
            if (enable_freetype) &.{"-DHAVE_FREETYPE"} else &.{},
    });

    harfbuzz_lib.linkLibCpp();

    harfbuzz_lib.installHeadersDirectory(
        hurfbuzz_upstream.path("src/"),
        "harfbuzz",
        .{ .include_extensions = &.{".h"} },
    );
    harfbuzz_lib.addIncludePath(freetype_upstream.path("include"));

    const harfbuzz_mod = b.addModule("harfbuzz", .{
        .root_source_file = b.path("src/root.zig"),
    });

    harfbuzz_mod.addIncludePath(hurfbuzz_upstream.path("src"));
    harfbuzz_mod.addIncludePath(freetype_upstream.path("include"));
    harfbuzz_mod.linkLibrary(harfbuzz_lib);

    b.installArtifact(harfbuzz_lib);
}
