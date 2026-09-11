const std = @import("std");
const Build = std.Build;

const shaders_mod = @import("shaders.zig");

const Assets = struct {
    tar_path: Build.LazyPath,
    compressed_path: Build.LazyPath,
};

pub fn resolveAssets(b: *Build) !Assets {
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

    const tar_cmd = b.addSystemCommand(&.{ "tar", "-cf" });

    const tar_path = tar_cmd.addOutputFileArg("assets.tar");

    tar_cmd.addArg("-C");
    tar_cmd.addDirectoryArg(stage.getDirectory());

    tar_cmd.addArg(".");

    const zstd_cmd = b.addSystemCommand(&.{ "zstd", "-q", "-f", "-o" });
    const zstd_cmp_path = zstd_cmd.addOutputFileArg("assets.tar.zst");

    zstd_cmd.addFileArg(tar_path);

    return .{
        .tar_path = tar_path,
        .compressed_path = zstd_cmp_path
    };
}
