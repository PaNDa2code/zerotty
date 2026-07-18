const std = @import("std");
const Build = std.Build;

const config_mod = @import("config.zig");
const RenderBackend = config_mod.RenderBackend;
const WindowSystem = config_mod.WindowSystem;

const AppConfig = config_mod.AppConfig;

const shaders_mod = @import("shaders.zig");

pub fn setupApp(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    config: AppConfig,
) !struct { exe: *Build.Step.Compile, modules: std.StringHashMap(*Build.Module), target: std.Build.ResolvedTarget } {
    const target_tag = target.result.os.tag;

    const options = b.addOptions();
    options.addOption(RenderBackend, "render-backend", config.render_backend);
    options.addOption(WindowSystem, "window-system", config.window_system);
    options.addOption(bool, "renderer-debug", !config.disable_renderer_debug);
    options.addOption(bool, "comptime_check", config.comptime_check);
    const options_mod = options.createModule();

    // -------------------------------------------------------------------------
    // External Dependencies
    // -------------------------------------------------------------------------
    const vtparse_dep = b.dependency("vtparse", .{ .target = target, .optimize = optimize });
    const vtparse_mod = vtparse_dep.module("vtparse");

    const truetype_dep = b.dependency("TrueType", .{ .target = target, .optimize = optimize });
    const truetype_mod = truetype_dep.module("TrueType");

    const machfreetype_dep = b.dependency("mach_freetype", .{
        .target = target,
        .optimize = optimize,
        .use_llvm = config.use_llvm,
    });
    const machfreetype_mod = machfreetype_dep.module("mach-freetype");
    const machharfbuzz_mod = machfreetype_dep.module("mach-harfbuzz");

    const zigimg_dep = b.dependency("zigimg", .{ .target = target, .optimize = optimize });
    const zigimg_mod = zigimg_dep.module("zigimg");

    const zg_dep = b.dependency("zg", .{ .target = target, .optimize = optimize });
    const graphemes_mod = zg_dep.module("Graphemes");

    // -------------------------------------------------------------------------
    // Internal Modules Definition & Wiring
    // -------------------------------------------------------------------------
    var modules = std.StringHashMap(*Build.Module).init(b.allocator);

    const zerotty_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    try modules.put("zerotty", zerotty_mod);
    zerotty_mod.addImport("Graphemes", graphemes_mod);

    const assets_mod = b.createModule(.{
        .root_source_file = b.path("assets/assets.zig"),
    });
    try modules.put("assets", assets_mod);
    zerotty_mod.addImport("assets", assets_mod);

    // Add external dependencies to the lookup map and wire them to zerotty
    try modules.put("build_options", options_mod);
    zerotty_mod.addImport("build_options", options_mod);

    try modules.put("vtparse", vtparse_mod);
    zerotty_mod.addImport("vtparse", vtparse_mod);

    try modules.put("TrueType", truetype_mod);
    zerotty_mod.addImport("TrueType", truetype_mod);

    try modules.put("mach-freetype", machfreetype_mod);
    zerotty_mod.addImport("mach-freetype", machfreetype_mod);

    try modules.put("mach-harfbuzz", machharfbuzz_mod);
    zerotty_mod.addImport("mach-harfbuzz", machharfbuzz_mod);

    try modules.put("zigimg", zigimg_mod);
    zerotty_mod.addImport("zigimg", zigimg_mod);

    // Allow importing the root module within the module itself
    zerotty_mod.addImport("zerotty", zerotty_mod);

    // Dynamic external dependencies depending on OS target
    if (config.comptime_check or target_tag == .windows) {
        if (b.lazyDependency("zigwin32", .{})) |dep| {
            const win32_mod = dep.module("win32");
            zerotty_mod.addImport("win32", win32_mod);
            try modules.put("win32", win32_mod);
        }
    }

    if (config.comptime_check or target_tag == .linux) {
        if (b.lazyDependency("zig_openpty", .{})) |dep| {
            const openpty_mod = dep.module("openpty");
            zerotty_mod.addImport("openpty", openpty_mod);
            try modules.put("openpty", openpty_mod);
        }
    }

    // Compress fonts assets using system tar command and feed it to AssetsManager module as anonymous import
    const assets_compress_run = b.addSystemCommand(&.{
        "tar",
        "-a",
        "-cf",
    });
    assets_compress_run.setCwd(b.path("assets"));
    const assets_archive_path = assets_compress_run.addOutputFileArg("assets.tar.zst");
    assets_compress_run.addDirectoryArg(b.path("assets/fonts"));

    zerotty_mod.addAnonymousImport("assets.tar.zst", .{
        .root_source_file = assets_archive_path,
    });

    // Shaders Compilation
    const compiled_shaders = shaders_mod.compiledShadersPathes(
        b,
        b.path("src/renderer/shaders"),
        &.{
            "cell.frag", "cell.vert",
            "text.frag", "text.vert",
        },
        config.render_backend,
    ) catch unreachable;

    shaders_mod.addCompiledShadersToModule(compiled_shaders, assets_mod);

    // Backend Bindings
    switch (config.render_backend) {
        .d3d11 => {},
        .opengl => {
            const gl_mod = createOpenGLBindings(b, target);
            zerotty_mod.addImport("gl", gl_mod);
            try modules.put("gl", gl_mod);
        },
        .vulkan => {
            const vulkan_headers = b.lazyDependency("vulkan_headers", .{});
            const vulkan_dep = if (vulkan_headers) |vk_headers|
                b.lazyDependency("vulkan", .{ .registry = vk_headers.path("registry/vk.xml") })
            else
                b.lazyDependency("vulkan", .{});

            if (vulkan_headers != null) {
                if (vulkan_dep) |dep| {
                    const mod = dep.module("vulkan-zig");
                    zerotty_mod.addImport("vulkan", mod);
                    try modules.put("vulkan", mod);
                }
            }
        },
    }

    // Create Executable module
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    exe_mod.addImport("build_options", options_mod);
    exe_mod.addImport("zerotty", zerotty_mod);

    // Link system libraries to the module
    if (config.window_system == .xlib) {
        zerotty_mod.linkSystemLibrary("X11", .{ .needed = true });
        if (config.render_backend == .opengl) {
            zerotty_mod.linkSystemLibrary("GL", .{});
        }
    }

    if (config.window_system == .xcb) {
        if (target.query.isNative()) {
            zerotty_mod.resolved_target = target;
            zerotty_mod.linkSystemLibrary("xcb", .{});
            zerotty_mod.linkSystemLibrary("xkbcommon", .{});
        } else {
            if (b.lazyDependency("xcb", .{
                .target = target,
                .optimize = optimize,
            })) |dep| {
                zerotty_mod.linkLibrary(dep.artifact("xcb"));
            }
            if (b.lazyDependency("xkbcommon", .{
                .target = target,
                .optimize = optimize,
            })) |dep| {
                zerotty_mod.linkLibrary(dep.artifact("xkbcommon"));
            }
        }
    }

    if (config.window_system == .glfw) {
        if (b.lazyDependency("glfw_zig", .{
            .target = target,
            .optimize = optimize,
        })) |dep| {
            const glfw_lib = dep.artifact("glfw");
            zerotty_mod.linkLibrary(glfw_lib);
        }
    }

    if (target_tag == .linux) {
        if (b.lazyDependency("xkbcommon", .{
            .target = target,
            .optimize = optimize,
            .@"xkb-config-root" = "/usr/share/X11/xkb",
        })) |dep| exe_mod.linkLibrary(dep.artifact("xkbcommon"));
    }

    const exe = b.addExecutable(.{
        .name = "zerotty",
        .root_module = exe_mod,
        .use_llvm = config.use_llvm,
    });

    // Windows Specific EXE settings
    if (config.window_system == .win32) {
        if (optimize != .Debug) {
            exe.subsystem = .Windows;
            exe.mingw_unicode_entry_point = true;
        }
        exe.bundle_compiler_rt = true;
    }
    exe_mod.addWin32ResourceFile(.{ .file = b.path("assets/zerotty.rc") });

    return .{ .exe = exe, .modules = modules, .target = target };
}

fn createOpenGLBindings(b: *Build, target: Build.ResolvedTarget) *Build.Module {
    const extensions: []const []const u8 = &.{
        "KHR_debug",
        "ARB_shader_storage_buffer_object",
        "ARB_gl_spirv",
    };

    const is_gles = switch (target.result.os.tag) {
        .emscripten, .wasi, .ios => true,
        .linux, .windows => switch (target.result.cpu.arch) {
            .arm, .armeb, .aarch64 => true,
            else => false,
        },
        else => false,
    };

    const gl_target = if (is_gles) "gles-3.2" else "gl-4.1-core";
    const gl = b.createModule(.{});

    if (b.lazyDependency("zigglgen", .{})) |dep| {
        const zigglgen_exe = dep.artifact("zigglgen");
        const zigglgen_run = b.addRunArtifact(zigglgen_exe);
        zigglgen_run.addArg(gl_target);
        for (extensions) |extension| {
            zigglgen_run.addArg(extension);
        }

        const output = zigglgen_run.captureStdOut(.{ .basename = "gl.zig" });
        gl.root_source_file = output;
    }

    return gl;
}
