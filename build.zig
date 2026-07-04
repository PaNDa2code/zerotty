const std = @import("std");
const Build = std.Build;

const DEFAULT_RENDER_BACKEND: RenderBackend = .vulkan;

pub const RenderBackend = enum {
    d3d11,
    opengl,
    vulkan,
    // webgpu,
};

pub const WindowSystem = enum {
    win32,
    xlib,
    xcb,
    glfw,
    // web,
};

pub const AppConfig = struct {
    use_llvm: bool,
    comptime_check: bool,
    render_backend: RenderBackend,
    window_system: WindowSystem,
    disable_renderer_debug: bool,
};

var io = std.Io.Threaded.global_single_threaded.io();

pub fn setupApp(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    config: AppConfig,
) !struct { exe: *Build.Step.Compile, modules: std.StringHashMap(*Build.Module) } {
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

    // -------------------------------------------------------------------------
    // Internal Modules Definition & Wiring
    // -------------------------------------------------------------------------
    var modules = std.StringHashMap(*Build.Module).init(b.allocator);

    const ModuleDef = struct {
        name: []const u8,
        path: []const u8,
        deps: []const []const u8 = &.{},
    };

    const internal_modules = [_]ModuleDef{
        .{ .name = "input", .path = "src/input/root.zig" },
        .{ .name = "window", .path = "src/window/root.zig", .deps = &.{ "build_options", "input", "zigimg", "assets", "renderer" } },
        .{ .name = "pty", .path = "src/pty/root.zig", .deps = &.{"build_options"} },
        .{ .name = "ChildProcess", .path = "src/ChildProcess.zig", .deps = &.{"pty"} },
        .{ .name = "color", .path = "src/color.zig" },
        .{ .name = "grid", .path = "src/Grid.zig" },
        .{ .name = "cursor", .path = "src/Cursor.zig" },
        .{ .name = "DynamicLibrary", .path = "src/DynamicLibrary.zig" },
        .{ .name = "io", .path = "src/io/root.zig" },
        .{ .name = "math", .path = "src/renderer/common/math.zig" },
        .{ .name = "font", .path = "src/font/root.zig", .deps = &.{ "build_options", "math", "TrueType", "mach-freetype", "mach-harfbuzz", "zigimg", "assets", "AssetsManager" } },
        .{ .name = "assets", .path = "assets/assets.zig" },
        .{ .name = "renderer", .path = "src/renderer/root.zig", .deps = &.{ "build_options", "font", "grid", "cursor", "color", "window", "math", "assets", "DynamicLibrary", "AssetsManager" } },
        .{ .name = "circular_array", .path = "src/circular_array/root.zig" },
        .{ .name = "AssetsManager", .path = "src/AssetsManager.zig" },
    };

    // First pass: Create all modules and add to lookup map
    for (internal_modules) |def| {
        const mod = b.createModule(.{ .root_source_file = b.path(def.path) });
        try modules.put(def.name, mod);
    }

    // Add external dependencies to the lookup map
    try modules.put("build_options", options_mod);
    try modules.put("vtparse", vtparse_mod);
    try modules.put("TrueType", truetype_mod);
    try modules.put("mach-freetype", machfreetype_mod);
    try modules.put("mach-harfbuzz", machharfbuzz_mod);
    try modules.put("zigimg", zigimg_mod);

    // Dynamic external dependencies depending on OS target
    if (config.comptime_check or target_tag == .windows) {
        if (b.lazyDependency("zigwin32", .{})) |dep| {
            const win32_mod = dep.module("win32");
            try modules.put("win32", win32_mod);
        }
    }

    if (config.comptime_check or target_tag == .linux) {
        if (b.lazyDependency("zig_openpty", .{})) |dep| {
            const openpty_mod = dep.module("openpty");
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

    modules.get("AssetsManager").?.addAnonymousImport("assets.tar.zst", .{
        .root_source_file = assets_archive_path,
    });

    // Shaders Compilation
    const compiled_shaders = @import("build/shaders.zig").compiledShadersPathes(
        b,
        b.path("src/renderer/shaders"),
        &.{
            "cell.frag", "cell.vert",
            "text.frag", "text.vert",
        },
        config.render_backend,
    ) catch unreachable;
    @import("build/shaders.zig").addCompiledShadersToModule(compiled_shaders, modules.get("assets").?);

    // Backend Bindings
    switch (config.render_backend) {
        .d3d11 => {},
        .opengl => {
            const gl_mod = createOpenGLBindings(b, target);
            try modules.put("gl", gl_mod);
        },
        .vulkan => {
            const core_mod = b.createModule(.{ .root_source_file = b.path("src/renderer/vulkan/core/root.zig") });
            const memory_mod = b.createModule(.{ .root_source_file = b.path("src/renderer/vulkan/core/memory/root.zig") });

            core_mod.addImport("DynamicLibrary", modules.get("DynamicLibrary").?);

            try modules.put("core", core_mod);
            try modules.put("memory", memory_mod);

            const vulkan_headers = b.lazyDependency("vulkan_headers", .{});
            const vulkan_dep = if (vulkan_headers) |vk_headers|
                b.lazyDependency("vulkan", .{ .registry = vk_headers.path("registry/vk.xml") })
            else
                b.lazyDependency("vulkan", .{});

            if (vulkan_headers != null) {
                if (vulkan_dep) |dep| {
                    const mod = dep.module("vulkan-zig");
                    core_mod.addImport("vulkan", mod);
                    try modules.put("vulkan", mod);
                }
            }
        },
    }

    // Second pass: Wire module dependencies
    for (internal_modules) |def| {
        const mod = modules.get(def.name).?;
        for (def.deps) |dep_name| {
            if (modules.get(dep_name)) |dep_mod| {
                mod.addImport(dep_name, dep_mod);
            }
        }
    }

    // Wire target-specific dependencies dynamically
    if (modules.get("win32")) |win32_mod| {
        modules.get("window").?.addImport("win32", win32_mod);
        modules.get("renderer").?.addImport("win32", win32_mod);
        modules.get("DynamicLibrary").?.addImport("win32", win32_mod);
        modules.get("pty").?.addImport("win32", win32_mod);
        modules.get("ChildProcess").?.addImport("win32", win32_mod);
        modules.get("io").?.addImport("win32", win32_mod);
    }

    if (modules.get("openpty")) |openpty_mod| {
        modules.get("pty").?.addImport("openpty", openpty_mod);
    }

    if (config.render_backend == .vulkan) {
        if (modules.get("vulkan")) |vk_mod| {
            modules.get("renderer").?.addImport("vulkan", vk_mod);
        }
        if (modules.get("core")) |core_mod| {
            modules.get("renderer").?.addImport("core", core_mod);
        }
        if (modules.get("memory")) |mem_mod| {
            modules.get("renderer").?.addImport("memory", mem_mod);
        }
    }

    if (config.render_backend == .opengl) {
        if (modules.get("gl")) |gl_mod| {
            modules.get("renderer").?.addImport("gl", gl_mod);
        }
    }

    // Create Executable module
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    exe_mod.addImport("build_options", options_mod);

    // Import all relevant internal and external modules to the main application
    const app_imports = [_][]const u8{
        "vtparse",      "assets",         "io",             "pty",
        "grid",         "math",           "font",           "color",
        "input",        "window",         "cursor",         "renderer",
        "ChildProcess", "DynamicLibrary", "circular_array", "AssetsManager",
    };
    for (app_imports) |name| {
        if (modules.get(name)) |mod| {
            exe_mod.addImport(name, mod);
        }
    }

    // Link system libraries to the modules that need them
    if (config.window_system == .xlib) {
        modules.get("window").?.linkSystemLibrary("X11", .{ .needed = true });
        if (config.render_backend == .opengl) {
            modules.get("renderer").?.linkSystemLibrary("GL", .{});
        }
    }

    if (config.window_system == .xcb) {
        if (target.query.isNativeOs()) {
            modules.get("window").?.resolved_target = target;
            modules.get("window").?.linkSystemLibrary("xcb", .{});
            modules.get("window").?.linkSystemLibrary("xkbcommon", .{});
        }
    }

    if (config.window_system == .glfw) {
        if (b.lazyDependency("glfw_zig", .{
            .target = target,
            .optimize = optimize,
        })) |dep| {
            const glfw_lib = dep.artifact("glfw");
            modules.get("window").?.linkLibrary(glfw_lib);
            modules.get("renderer").?.linkLibrary(glfw_lib);
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

    return .{ .exe = exe, .modules = modules };
}

pub fn build(b: *Build) !void {
    // -------------------------------------------------------------------------
    // Target & Optimization
    // -------------------------------------------------------------------------
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const target_tag = target.result.os.tag;

    // -------------------------------------------------------------------------
    // Build Options
    // -------------------------------------------------------------------------
    const use_llvm = b.option(bool, "use_llvm", "") orelse (target_tag == .windows);
    const comptime_check = b.option(bool, "comptime-check", "") orelse false;
    const render_backend = b.option(RenderBackend, "render-backend", "") orelse DEFAULT_RENDER_BACKEND;
    const window_system = b.option(WindowSystem, "window-system", "") orelse .glfw;
    const dist_json_path = b.option([]const u8, "dist-json", "multi-build config list json file");

    const disable_renderer_debug = b.option(
        bool,
        "disable-renderer-debug",
        "Disable debugging for renderer backends (Vulkan validation layers, OpenGL debug callbacks)",
    ) orelse !comptime_check;

    const native_config = AppConfig{
        .use_llvm = use_llvm,
        .comptime_check = comptime_check,
        .render_backend = render_backend,
        .window_system = window_system,
        .disable_renderer_debug = disable_renderer_debug,
    };

    // Setup native app build
    const native_build = try setupApp(b, target, optimize, native_config);
    b.installArtifact(native_build.exe);

    // -------------------------------------------------------------------------
    // Run Step
    // -------------------------------------------------------------------------
    const run_cmd = b.addRunArtifact(native_build.exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    _ = try addTargetToStep(b, null);

    // -------------------------------------------------------------------------
    // Testing
    // -------------------------------------------------------------------------
    const test_step = b.step("test_all", "will run all submodules test");
    const app_imports = [_][]const u8{
        "vtparse",        "assets",        "io",     "pty",    "grid",     "math",         "font",
        "color",          "input",         "window", "cursor", "renderer", "ChildProcess", "DynamicLibrary",
        "circular_array", "AssetsManager",
    };

    for (app_imports) |name| {
        if (native_build.modules.get(name)) |mod| {
            const test_name = b.fmt("test_{s}", .{name});
            const test_desc = b.fmt("run module {s} test", .{name});
            const test_mod_step = b.step(test_name, test_desc);

            mod.resolved_target = target;

            const unit_test = b.addTest(.{
                .name = test_name,
                .root_module = mod,
            });

            const run_unit_test = b.addRunArtifact(unit_test);
            test_mod_step.dependOn(&run_unit_test.step);
            test_step.dependOn(test_mod_step);
        }
    }
}

const TargetConfigJson = struct {
    name: []const u8,
    target: []const u8,
    window_system: WindowSystem,
    render_backend: RenderBackend,
};

fn addTargetToStep(
    b: *std.Build,
    step: *std.Build.Step,
    targets: ?[]TargetConfigJson,
) !*std.Build.Step {
    const dist_targets = if (targets) |t| t else blk: {
        const check_buffer = try b.allocator.alloc(u8, 2048);
        const check_configs_file = try std.Io.Dir.cwd().openFile(io, "build/check_configs.json", .{});
        const check_configs_data_len = try check_configs_file.readPositionalAll(io, check_buffer, 0);
        const json_parsed = try std.json.parseFromSlice([]TargetConfigJson, b.allocator, check_buffer[0..check_configs_data_len], .{});
        break :blk json_parsed.value;
    };

    for (dist_targets) |t_cfg| {
        const resolved_target = b.resolveTargetQuery(try .parse(.{ .arch_os_abi = t_cfg.target }));
        const dist_config = AppConfig{
            .use_llvm = true,
            .comptime_check = false,
            .render_backend = t_cfg.render_backend,
            .window_system = t_cfg.window_system,
            .disable_renderer_debug = true,
        };

        const dist_build = try setupApp(b, resolved_target, .Debug, dist_config);

        const install_dir = b.addInstallArtifact(dist_build.exe, .{
            .dest_dir = .{
                .override = .{ .custom = b.fmt("dist/{s}", .{t_cfg.name}) },
            },
        });

        step.dependOn(&install_dir.step);
    }

    return check_step;
}

// -------------------------------------------------------------------------
// Helper Functions
// -------------------------------------------------------------------------

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
