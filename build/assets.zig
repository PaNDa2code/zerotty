const std = @import("std");
const Build = std.Build;

const shaders_mod = @import("shaders.zig");

pub fn compressAssets(b: *Build) !Build.LazyPath {
    const shaders = try shaders_mod.compiledShadersPathes(
        b,
        b.path("src/renderer/shaders"),
        &.{ "text.vert", "text.frag" },
        .vulkan,
    );

    const stage = b.addWriteFiles();

    _ = stage.addCopyDirectory(b.path("assets/fonts"), "fonts", .{});

    for (shaders) |shader| {
        _ = stage.addCopyFile(shader.path, b.fmt("shaders/{s}", .{shader.name}));
    }

    const tar_cmd = b.addSystemCommand(&.{
        "tar",
        "-a",
        "-cf",
    });

    const archive_path = tar_cmd.addOutputFileArg("assets.tar.zst");

    tar_cmd.addArg("-C");
    tar_cmd.addDirectoryArg(stage.getDirectory());

    tar_cmd.addArg(".");

    return archive_path;
}
