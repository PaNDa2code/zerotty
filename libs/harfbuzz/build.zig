const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.builtin.LinkMode, "linkage", "") orelse .static;
    const enable_freetype = b.option(bool, "enable_freetype", "Build Freetype") orelse true;

    const hurfbuzz_upstream = b.dependency("harfbuzz", .{});
    const freetype_upstream = b.dependency("freetype", .{});

    const harfbuzz_mod = b.addModule("harfbuzz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
    });

    harfbuzz_mod.addCSourceFile(.{
        .file = hurfbuzz_upstream.path("src/harfbuzz.cc"),
        .flags = &.{
            if (enable_freetype) "-DHAVE_FREETYPE" else "",
            "-DHB_NO_FEATURES_H",
            "-std=c++11",
            "-nostdlib++",
            "-fno-exceptions",
            "-fno-rtti",
            "-fno-threadsafe-statics",
            "-fvisibility-inlines-hidden",
        },
    });

    harfbuzz_mod.addIncludePath(freetype_upstream.path("include"));
    harfbuzz_mod.addIncludePath(hurfbuzz_upstream.path("src"));

    const harfbuzz_lib = b.addLibrary(.{
        .name = "harfbuzz",
        .linkage = linkage,
        .root_module = harfbuzz_mod,
    });

    harfbuzz_lib.installHeadersDirectory(
        hurfbuzz_upstream.path("src/"),
        "harfbuzz",
        .{ .include_extensions = &.{".h"} },
    );

    b.installArtifact(harfbuzz_lib);
}
