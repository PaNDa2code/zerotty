const std = @import("std");
const Build = std.Build;

const DEFAULT_RENDER_BACKEND: RenderBackend = .vulkan;

pub const RenderBackend = enum {
    d3d11,
    opengl,
    vulkan,
};

pub const WindowSystem = enum {
    win32,
    xlib,
    xcb,
    glfw,
};

pub fn build(b: *Build) !void {
    // -------------------------------------------------------------------------
    // Target & Optimization
    // -------------------------------------------------------------------------
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // const debug_mode = optimize == .Debug;
    const target_tag = target.result.os.tag;
    const is_native = target.query.isNativeOs();
    const is_gnu = target.result.isGnuLibC();
    const linkage: std.builtin.LinkMode = if (is_gnu and is_native) .dynamic else .static;

    // -------------------------------------------------------------------------
    // Build Options
    // -------------------------------------------------------------------------
    const use_llvm = b.option(bool, "use-llvm", "") orelse false;
    const comptime_check = b.option(bool, "comptime-check", "") orelse false;
    const render_backend = b.option(RenderBackend, "render-backend", "") orelse DEFAULT_RENDER_BACKEND;

    const default_window_system: WindowSystem = switch (target_tag) {
        .windows => .win32,
        .linux => if (DEFAULT_RENDER_BACKEND == .vulkan) .xcb else .xlib,
        else => .glfw,
    };

    const window_system = b.option(WindowSystem, "window-system", "") orelse default_window_system;

    const disable_renderer_debug = b.option(
        bool,
        "disable-renderer-debug",
        "Disable debugging for renderer backends (Vulkan validation layers, OpenGL debug callbacks)",
    ) orelse !comptime_check;

    const options = b.addOptions();
    options.addOption(RenderBackend, "render-backend", render_backend);
    options.addOption(WindowSystem, "window-system", window_system);
    options.addOption(bool, "renderer-debug", !disable_renderer_debug);
    options.addOption(bool, "comptime_check", comptime_check);
    const options_mod = options.createModule();

    // -------------------------------------------------------------------------
    // External Dependencies
    // -------------------------------------------------------------------------
    const vtparse_dep = b.dependency("vtparse", .{ .target = target, .optimize = optimize });
    const vtparse_mod = vtparse_dep.module("vtparse");

    const truetype_dep = b.dependency("TrueType", .{ .target = target, .optimize = optimize });
    const truetype_mod = truetype_dep.module("TrueType");

    const zigimg_dep = b.dependency("zigimg", .{ .target = target, .optimize = optimize });
    const zigimg_mod = zigimg_dep.module("zigimg");

    // -------------------------------------------------------------------------
    // Internal Modules Definition
    // -------------------------------------------------------------------------
    const input_mod = b.createModule(.{ .root_source_file = b.path("src/input/root.zig") });
    const window_mod = b.createModule(.{ .root_source_file = b.path("src/window/root.zig") });
    const pty_mod = b.createModule(.{ .root_source_file = b.path("src/pty/root.zig") });
    const childprocess_mod = b.createModule(.{ .root_source_file = b.path("src/ChildProcess.zig") });
    const color_mod = b.createModule(.{ .root_source_file = b.path("src/color.zig") });
    const grid_mod = b.createModule(.{ .root_source_file = b.path("src/Grid.zig") });
    const cursor_mod = b.createModule(.{ .root_source_file = b.path("src/Cursor.zig") });
    const dynamiclibrary_mod = b.createModule(.{ .root_source_file = b.path("src/DynamicLibrary.zig") });
    const debug_mod = b.createModule(.{ .root_source_file = b.path("src/debug/ErrDebugInfo.zig") });
    const io_mod = b.createModule(.{ .root_source_file = b.path("src/io/root.zig") });
    const math_mod = b.createModule(.{ .root_source_file = b.path("src/renderer/common/math.zig") });
    const font_mod = b.createModule(.{ .root_source_file = b.path("src/font/root.zig") });
    const assets_mod = b.createModule(.{ .root_source_file = b.path("assets/assets.zig") });
    const renderer_mod = b.createModule(.{ .root_source_file = b.path("src/renderer/root.zig") });
    const circulararray_mod = b.createModule(.{ .root_source_file = b.path("src/circular_array/root.zig") });

    // -------------------------------------------------------------------------
    // Internal Module Wiring (Imports)
    // -------------------------------------------------------------------------

    // Window imports
    window_mod.addImport("build_options", options_mod);
    window_mod.addImport("input", input_mod);
    window_mod.addImport("zigimg", zigimg_mod);
    window_mod.addImport("assets", assets_mod);
    window_mod.addImport("renderer", renderer_mod);

    // PTY imports
    pty_mod.addImport("build_options", options_mod);

    // ChildProcess imports
    childprocess_mod.addImport("pty", pty_mod);

    // Font imports
    font_mod.addImport("build_options", options_mod);
    font_mod.addImport("math", math_mod);
    font_mod.addImport("TrueType", truetype_mod);
    font_mod.addImport("zigimg", zigimg_mod);
    font_mod.addImport("assets", assets_mod);

    // Renderer imports
    renderer_mod.addImport("build_options", options_mod);
    renderer_mod.addImport("font", font_mod);
    renderer_mod.addImport("grid", grid_mod);
    renderer_mod.addImport("cursor", cursor_mod);
    renderer_mod.addImport("color", color_mod);
    renderer_mod.addImport("window", window_mod);
    renderer_mod.addImport("math", math_mod);
    renderer_mod.addImport("assets", assets_mod);

    // -------------------------------------------------------------------------
    // Conditional System Dependencies
    // -------------------------------------------------------------------------

    // Windows Dependencies
    if (comptime_check or target_tag == .windows) {
        if (b.lazyDependency("zigwin32", .{})) |dep| {
            const win32_mod = dep.module("win32");
            window_mod.addImport("win32", win32_mod);
            pty_mod.addImport("win32", win32_mod);
            childprocess_mod.addImport("win32", win32_mod);
        }
    }

    // Linux Dependencies
    if (comptime_check or target_tag == .linux) {
        if (b.lazyDependency("zig_openpty", .{})) |dep| {
            const openpty_mod = dep.module("openpty");
            pty_mod.addImport("openpty", openpty_mod);
        }
    }

    // -------------------------------------------------------------------------
    // Backend Specific Setup
    // -------------------------------------------------------------------------

    // Shaders
    const compiled_shaders = @import("build/shaders.zig").compiledShadersPathes(
        b,
        b.path("src/renderer/shaders"),
        &.{ "cell.frag", "cell.vert" },
        render_backend,
    ) catch unreachable;
    @import("build/shaders.zig").addCompiledShadersToModule(compiled_shaders, assets_mod);

    // Backend Bindings
    switch (render_backend) {
        .d3d11 => {},
        .opengl => {
            const gl_mod = createOpenGLBindings(b, target);
            renderer_mod.addImport("gl", gl_mod);
        },
        .vulkan => {
            const vulkan_headers = b.lazyDependency("vulkan_headers", .{});

            // Resolve Vulkan dependency based on headers presence
            const vulkan_dep = if (vulkan_headers) |vk_headers|
                b.lazyDependency("vulkan", .{ .registry = vk_headers.path("registry/vk.xml") })
            else
                b.lazyDependency("vulkan", .{});

            if (vulkan_headers != null) {
                if (vulkan_dep) |dep| {
                    renderer_mod.addImport("vulkan", dep.module("vulkan-zig"));
                }
            }

            const core_mod = b.createModule(.{ .root_source_file = b.path("src/renderer/vulkan/core/root.zig") });
            const memory_mod = b.createModule(.{ .root_source_file = b.path("src/renderer/vulkan/core/memory/root.zig") });

            renderer_mod.addImport("core", core_mod);
            renderer_mod.addImport("memory", memory_mod);
        },
    }

    // -------------------------------------------------------------------------
    // Application Assembly
    // -------------------------------------------------------------------------

    // Create Executable
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "vtparse", .module = vtparse_mod },
            .{ .name = "assets", .module = assets_mod },
            .{ .name = "io", .module = io_mod },
            .{ .name = "pty", .module = pty_mod },
            .{ .name = "grid", .module = grid_mod },
            .{ .name = "math", .module = math_mod },
            .{ .name = "font", .module = font_mod },
            .{ .name = "debug", .module = debug_mod },
            .{ .name = "color", .module = color_mod },
            .{ .name = "input", .module = input_mod },
            .{ .name = "window", .module = window_mod },
            .{ .name = "cursor", .module = cursor_mod },
            .{ .name = "Renderer", .module = renderer_mod },
            .{ .name = "ChildProcess", .module = childprocess_mod },
            .{ .name = "DynamicLibrary", .module = dynamiclibrary_mod },
            .{ .name = "circular_array", .module = circulararray_mod },
        },
    });

    exe_mod.addImport("build_options", options_mod);
    if (window_system == .xlib) {
        exe_mod.linkSystemLibrary("X11", .{ .needed = true });
        if (render_backend == .opengl) {
            exe_mod.linkSystemLibrary("GL", .{});
        }
    }

    if (window_system == .xcb) {
        if (target.query.isNativeOs()) {
            exe_mod.linkSystemLibrary("xcb", .{});
            exe_mod.linkSystemLibrary("xkbcommon", .{});
        } else {
            if (b.lazyDependency("xcb", .{
                .target = target,
                .optimize = exe_mod.optimize.?,
                .linkage = linkage,
            })) |dep| {
                exe_mod.linkLibrary(dep.artifact("xcb"));
            }
            if (b.lazyDependency("xkbcommon", .{
                .target = target,
                .optimize = exe_mod.optimize.?,
                .@"xkb-config-root" = "/usr/share/X11/xkb",
            })) |dep| {
                exe_mod.linkLibrary(dep.artifact("xkbcommon"));
            }
        }
    }

    if (window_system == .glfw) {
        if (b.lazyDependency("glfw_zig", .{
            .target = target,
            .optimize = exe_mod.optimize.?,
        })) |dep| exe_mod.linkLibrary(dep.artifact("glfw"));

        if (b.lazyDependency("xkbcommon", .{
            .target = target,
            .optimize = exe_mod.optimize.?,
            .@"xkb-config-root" = "/usr/share/X11/xkb",
        })) |dep| exe_mod.linkLibrary(dep.artifact("xkbcommon"));
    }

    const exe = b.addExecutable(.{
        .name = "zerotty",
        .root_module = exe_mod,
        .use_llvm = use_llvm,
    });

    // Windows Specific EXE settings
    if (window_system == .win32 and optimize != .Debug) {
        exe.subsystem = .Windows;
        exe.mingw_unicode_entry_point = true;
        exe.bundle_compiler_rt = true;
    }
    exe.addWin32ResourceFile(.{ .file = b.path("assets/zerotty.rc") });

    b.installArtifact(exe);

    // -------------------------------------------------------------------------
    // Run Step
    // -------------------------------------------------------------------------
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // -------------------------------------------------------------------------
    // Test Step
    // -------------------------------------------------------------------------
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        // .imports = exe_imports.items,
    });
    test_mod.addImport("build_options", options_mod);

    const unit_test = b.addTest(.{
        .name = "zerotty",
        .root_module = test_mod,
    });

    const run_unit_test = b.addRunArtifact(unit_test);
    const test_step = b.step("test", "run test.zig tests");
    test_step.dependOn(&run_unit_test.step);
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

        const output = zigglgen_run.captureStdOut();
        zigglgen_run.captured_stdout.?.basename = "gl.zig";
        gl.root_source_file = output;
    }

    return gl;
}
