const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

pub const CompiledShader = struct {
    name: []const u8,
    path: Build.LazyPath,
};

pub fn compiledShadersPathes(b: *Build, dir: Build.LazyPath, files: []const []const u8, renderer: anytype) ![]CompiledShader {
    const shader_pathes = try b.allocator.alloc(CompiledShader, files.len);

    const glslang_tools_installed =
        try findPathAlloc(b.allocator, "glslangValidator") != null and
        try findPathAlloc(b.allocator, "spirv-opt") != null;

    var glslang: ?*Build.Dependency = null;
    var spirv_opt: ?*Build.Step.Compile = null;
    var glslangValidator: ?*Build.Step.Compile = null;

    if (!glslang_tools_installed) {
        glslang = b.lazyDependency("glslang", .{ .optimize = .ReleaseFast }) orelse return shader_pathes;
        glslangValidator = glslang.?.artifact("glslangValidator");
        spirv_opt = glslang.?.artifact("spirv-opt");
    }

    for (files, 0..) |file, i| {
        const path = try dir.join(b.allocator, file);
        const output_basename = b.fmt("{s}.spv", .{file});

        const glslangValidator_cmd =
            if (glslang_tools_installed)
                b.addSystemCommand(&.{"glslangValidator"})
            else
                b.addRunArtifact(glslangValidator.?);

        glslangValidator_cmd.addFileArg(path);
        glslangValidator_cmd.addPrefixedDirectoryArg("-I", path.dirname());

        if (renderer == .Vulkan)
            glslangValidator_cmd.addArg("-V");
        if (renderer == .OpenGL)
            glslangValidator_cmd.addArg("-G");

        // addPrefixedOutputFileArg not working with glslang
        glslangValidator_cmd.addArg("-o");
        const shader_spv_path = glslangValidator_cmd.addOutputFileArg(output_basename);

        if (b.release_mode == .off) {
            const spirv_opt_cmd =
                if (glslang_tools_installed)
                    b.addSystemCommand(&.{"spirv-opt"})
                else
                    b.addRunArtifact(spirv_opt.?);

            spirv_opt_cmd.addFileArg(shader_spv_path);

            switch (b.release_mode) {
                .small => spirv_opt_cmd.addArg("-Os"),
                else => spirv_opt_cmd.addArg("-O"),
            }
            spirv_opt_cmd.addArg("-o");

            shader_pathes[i] = .{
                .name = output_basename,
                .path = spirv_opt_cmd.addOutputFileArg(output_basename),
            };
        } else {
            shader_pathes[i] = .{
                .name = output_basename,
                .path = shader_spv_path,
            };
        }
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

fn findPathAlloc(allocator: std.mem.Allocator, exe: []const u8) !?[]const u8 {
    const sep = std.fs.path.sep;
    const delimiter = std.fs.path.delimiter;

    if (std.mem.containsAtLeastScalar(u8, exe, 1, sep)) return exe;

    const suffix =
        if (builtin.os.tag == .windows and !std.mem.endsWith(u8, exe, ".exe"))
            ".exe"
        else
            "";

    const PATH = try std.process.getEnvVarOwned(allocator, "PATH");
    defer allocator.free(PATH);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    var it = std.mem.tokenizeScalar(u8, PATH, delimiter);

    while (it.next()) |search_path| {
        const full_path = try std.fmt.bufPrintZ(&path_buf, "{s}{c}{s}{s}", .{ search_path, sep, exe, suffix });
        const file = std.fs.cwd().openFile(full_path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound, error.AccessDenied => continue,
                else => return err,
            }
        };
        defer file.close();
        const stat = try file.stat();
        if (stat.kind != .directory and (builtin.os.tag == .windows or stat.mode & 0o0111 != 0)) {
            return try allocator.dupe(u8, full_path);
        }
    }

    return null;
}
