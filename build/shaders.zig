const std = @import("std");
const Build = std.Build;

pub fn compiledShadersPathes(b: *Build, dir: Build.LazyPath, files: []const []const u8) !*Build.Module {
    const shader_pathes = b.addOptions();

    for (files) |file| {
        const path = try dir.join(b.allocator, file);

        const glsl_cmd = b.addSystemCommand(&.{"glslang"});

        glsl_cmd.addFileArg(path);

        glsl_cmd.addArg("-G");

        // addPrefixedOutputFileArg not working with glslang
        glsl_cmd.addArg("-o");
        const output_path = glsl_cmd.addOutputFileArg(b.fmt("{s}.spv", .{file}));

        shader_pathes.addOptionPath(file, output_path);
    }

    return shader_pathes.createModule();
}
