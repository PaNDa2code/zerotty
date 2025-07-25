const std = @import("std");
const Build = std.Build;

pub const CompiledShader = struct {
    name: []const u8,
    path: Build.LazyPath,
};

pub fn compiledShadersPathes(b: *Build, dir: Build.LazyPath, files: []const []const u8, renderer: anytype) ![]CompiledShader {
    const shader_pathes = try b.allocator.alloc(CompiledShader, files.len);
    const glslang = b.dependency("glslang", .{ .optimize = .ReleaseFast });

    // const spirv_opt = glslang.artifact("spirv-opt");
    const glslangValidator = glslang.artifact("glslangValidator");

    for (files, 0..) |file, i| {
        const path = try dir.join(b.allocator, file);
        const output_basename = b.fmt("{s}.spv", .{file});

        const glsl_cmd = b.addRunArtifact(glslangValidator);

        glsl_cmd.addFileArg(path);

        if (renderer == .Vulkan)
            glsl_cmd.addArg("-V");
        if (renderer == .OpenGL)
            glsl_cmd.addArg("-G");

        // addPrefixedOutputFileArg not working with glslang
        glsl_cmd.addArg("-o");
        shader_pathes[i] = .{
            .name = output_basename,
            .path = glsl_cmd.addOutputFileArg(output_basename),
        };
    }

    return shader_pathes;
}

pub fn addCompiledShadersToModule(compiled_shaders: []CompiledShader, module: *Build.Module) void {
    for (compiled_shaders) |compiled_shader| {
        module.addAnonymousImport(compiled_shader.name, .{
            .root_source_file = compiled_shader.path,
        });
    }
}
