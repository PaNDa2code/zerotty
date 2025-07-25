const std = @import("std");
const Build = std.Build;

pub fn compiledShadersPathes(b: *Build, dir: Build.LazyPath, files: []const []const u8, renderer: anytype) !*Build.Module {
    const shader_pathes = b.addOptions();

    const glslang_exe = glslang(b);

    for (files) |file| {
        const path = try dir.join(b.allocator, file);

        const glsl_cmd = b.addRunArtifact(glslang_exe);

        glsl_cmd.addFileArg(path);

        if (renderer == .Vulkan)
            glsl_cmd.addArg("-V");
        if (renderer == .OpenGL)
            glsl_cmd.addArg("-G");

        // addPrefixedOutputFileArg not working with glslang
        glsl_cmd.addArg("-o");
        const output_path = glsl_cmd.addOutputFileArg(b.fmt("{s}.spv", .{file}));

        shader_pathes.addOptionPath(file, output_path);
    }

    return shader_pathes.createModule();
}

fn glslang(b: *Build) *Build.Step.Compile {
    const glslang_d = b.dependency("glslang", .{ .optimize = .ReleaseFast });
    return glslang_d.artifact("glslangValidator");
}
