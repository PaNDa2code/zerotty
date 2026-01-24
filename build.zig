const std = @import("std");
const Build = std.Build;

const android = @import("android");

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
    android,
};

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const render_backend = b.option(RenderBackend, "render-backend", "") orelse DEFAULT_RENDER_BACKEND;

    const is_android = target.result.os.tag == .linux and target.result.abi == .android;

    var android_build_tools_version: ?[]const u8 = null;
    var android_ndk_version: ?[]const u8 = null;
    var android_api_level: ?android.ApiLevel = null;
    var android_home: ?[]const u8 = null;

    if (is_android) {
        android_home = b.option([]const u8, "android_home", "");
        android_build_tools_version = b.option([]const u8, "android_build_tools_version", "") orelse "36.1.0";
        android_ndk_version = b.option([]const u8, "android_ndk_version", "") orelse "29.0.14206865";
        android_api_level = b.option(android.ApiLevel, "android_api_level", "") orelse .android7;
    }

    const default_window_system: WindowSystem = if (is_android)
        .android
    else switch (target.result.os.tag) {
        .windows => .win32,
        .linux => if (DEFAULT_RENDER_BACKEND == .vulkan) .xcb else .xlib,
        else => .glfw,
    };

    const window_system = b.option(WindowSystem, "window-system", "") orelse default_window_system;
    const disable_renderer_debug = b.option(
        bool,
        "disable-renderer-debug",
        "Disable debugging for renderer backends (Vulkan validation layers, OpenGL debug callbacks)",
    ) orelse if (optimize == .Debug) false else true;

    const options = b.addOptions();
    options.addOption(RenderBackend, "render-backend", render_backend);
    options.addOption(WindowSystem, "window-system", window_system);
    options.addOption(bool, "renderer-debug", !disable_renderer_debug);
    const options_mod = options.createModule();

    const is_native = target.query.isNativeOs();
    const is_gnu = target.result.isGnuLibC();
    const linkage: std.builtin.LinkMode = if (is_gnu and is_native) .dynamic else .static;

    var imports = std.ArrayList(Build.Module.Import).empty;
    try imports.append(b.allocator, .{ .name = "build_options", .module = options_mod });

    const window_module = b.createModule(.{
        .root_source_file = b.path("src/window/root.zig"),
        .imports = &.{
            .{ .name = "build_options", .module = options_mod },
        },
    });

    const pty_module = b.createModule(.{
        .root_source_file = b.path("src/pty/root.zig"),
        .imports = &.{
            .{ .name = "build_options", .module = options_mod },
        },
    });

    const font_module = b.createModule(.{
        .root_source_file = b.path("src/font/root.zig"),
        .imports = &.{
            .{ .name = "build_options", .module = options_mod },
        },
    });

    const renderer_module = b.createModule(.{
        .root_source_file = b.path("src/renderer/root.zig"),
        .imports = &.{
            .{ .name = "build_options", .module = options_mod },
        },
    });

    if (!is_android) {
        switch (target.result.os.tag) {
            .windows => {
                if (b.lazyDependency("zigwin32", .{})) |dep| {
                    const win32_mod = dep.module("win32");
                    window_module.addImport("win32", win32_mod);
                    pty_module.addImport("win32", win32_mod);
                    try imports.append(b.allocator, .{ .name = "win32", .module = win32_mod });
                }
            },
            .linux, .macos => {
                if (target.result.abi == .gnu) {
                    if (b.lazyDependency("zig_openpty", .{})) |dep| {
                        const openpty_mod = dep.module("openpty");
                        pty_module.addImport("openpty", openpty_mod);
                        try imports.append(b.allocator, .{ .name = "openpty", .module = openpty_mod });
                    }
                }
            },
            else => {},
        }
    }

    switch (render_backend) {
        .d3d11 => {},
        .opengl => {
            const gl_mod = createOpenGLBindings(b, target);
            renderer_module.addImport("gl", gl_mod);
            try imports.append(b.allocator, .{ .name = "gl", .module = gl_mod });
        },
        .vulkan => {
            const vulkan_headers = b.lazyDependency("vulkan_headers", .{});
            const vulkan = if (vulkan_headers) |vk_headers|
                b.lazyDependency("vulkan", .{ .registry = vk_headers.path("registry/vk.xml") })
            else
                b.lazyDependency("vulkan", .{});

            if (vulkan_headers != null and vulkan != null) {
                const vulkan_mod = vulkan.?.module("vulkan-zig");
                renderer_module.addImport("vulkan", vulkan_mod);
                try imports.append(b.allocator, .{ .name = "vulkan", .module = vulkan_mod });
            }
        },
    }

    const vtparse = b.dependency("vtparse", .{
        .target = target,
        .optimize = optimize,
    });
    const vtparse_mod = vtparse.module("vtparse");
    try imports.append(b.allocator, .{ .name = "vtparse", .module = vtparse_mod });

    const truetype = b.dependency("TrueType", .{
        .target = target,
        .optimize = optimize,
    });
    const truetype_mod = truetype.module("TrueType");
    try imports.append(b.allocator, .{ .name = "TrueType", .module = truetype_mod });

    const zigimg = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });
    const zigimg_mod = zigimg.module("zigimg");
    try imports.append(b.allocator, .{ .name = "zigimg", .module = zigimg_mod });

    const compiled_shaders = @import("build/shaders.zig").compiledShadersPathes(
        b,
        b.path("src/renderer/shaders"),
        &.{ "cell.frag", "cell.vert" },
        render_backend,
    ) catch unreachable;

    const assets_mod = b.createModule(.{
        .root_source_file = b.path("assets/assets.zig"),
    });
    @import("build/shaders.zig").addCompiledShadersToModule(compiled_shaders, assets_mod);
    try imports.append(b.allocator, .{ .name = "assets", .module = assets_mod });

    try imports.append(b.allocator, .{ .name = "window", .module = window_module });
    try imports.append(b.allocator, .{ .name = "pty", .module = pty_module });
    try imports.append(b.allocator, .{ .name = "font", .module = font_module });
    try imports.append(b.allocator, .{ .name = "renderer", .module = renderer_module });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    exe_mod.addImport("build_options", options_mod);
    for (imports.items) |import| {
        exe_mod.addImport(import.name, import.module);
    }

    linkSystemLibraries(exe_mod, window_system, render_backend, target, b, linkage);

    if (is_android) {
        const android_sdk = android.Sdk.create(b, .{});
        const apk = android_sdk.createApk(.{
            .api_level = android_api_level.?,
            .build_tools_version = android_build_tools_version.?,
            .ndk_version = android_ndk_version.?,
        });

        apk.setAndroidManifest(b.path("android/AndroidManifest.xml"));
        apk.addResourceDirectory(b.path("android/res"));
        // apk.addJavaSourceFile(.{ .file = b.path("android/src/ZerottyActivity.java") });

        // Add the library to APK for all Android targets
        const android_targets = android.standardTargets(b, target);

        const key_store = android_sdk.createKeyStore(.example);

        apk.setKeyStore(key_store);

        const native_app_glue_dir: std.Build.LazyPath = .{
            .cwd_relative = b.fmt("{s}/sources/android/native_app_glue", .{apk.ndk.path}),
        };

        for (android_targets) |android_target| {
            const mod = b.createModule(.{
                .root_source_file = b.path("src/android.zig"),
                .target = android_target,
                .imports = imports.items,
                .optimize = optimize,
            });

            mod.addImport(
                "android",
                b.dependency("android", .{}).module("android"),
            );

            const lib = b.addLibrary(.{
                .name = "zerotty",
                .root_module = mod,
                .linkage = .dynamic,
            });

            lib.root_module.addIncludePath(native_app_glue_dir);

            lib.root_module.addCSourceFiles(.{
                .root = native_app_glue_dir,
                .files = &.{"android_native_app_glue.c"},
            });

            apk.addArtifact(lib);
            apk.installApk();
        }
        return;
    }

    const exe = b.addExecutable(.{
        .name = "zerotty",
        .root_module = exe_mod,
        .use_llvm = true,
    });

    if (window_system == .win32 and optimize != .Debug) {
        exe.subsystem = .Windows;
        exe.mingw_unicode_entry_point = true;
        exe.bundle_compiler_rt = true;
    }

    exe.addWin32ResourceFile(.{
        .file = b.path("assets/zerotty.rc"),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    test_mod.addImport("build_options", options_mod);
    for (imports.items) |import| {
        test_mod.addImport(import.name, import.module);
    }

    linkSystemLibraries(test_mod, window_system, render_backend, target, b, linkage);

    const unit_test = b.addTest(.{
        .name = "zerotty",
        .root_module = test_mod,
    });

    const run_unit_test = b.addRunArtifact(unit_test);
    const test_step = b.step("test", "run main.zig tests");
    test_step.dependOn(&run_unit_test.step);
}

fn linkSystemLibraries(
    module: *Build.Module,
    window_system: WindowSystem,
    render_backend: RenderBackend,
    target: Build.ResolvedTarget,
    b: *Build,
    linkage: std.builtin.LinkMode,
) void {
    switch (window_system) {
        .win32 => {},
        .xlib => {
            module.linkSystemLibrary("X11", .{ .needed = true });
            if (render_backend == .opengl) {
                module.linkSystemLibrary("GL", .{});
            }
        },
        .xcb => {
            if (target.query.isNativeOs()) {
                module.linkSystemLibrary("xcb", .{});
                module.linkSystemLibrary("xkbcommon", .{});
            } else {
                if (b.lazyDependency("xcb", .{
                    .target = target,
                    .optimize = module.optimize.?,
                    .linkage = linkage,
                })) |dep| {
                    const libxcb = dep.artifact("xcb");
                    module.linkLibrary(libxcb);
                }
                if (b.lazyDependency("xkbcommon", .{
                    .target = target,
                    .optimize = module.optimize.?,
                    .@"xkb-config-root" = "/usr/share/X11/xkb",
                })) |dep| {
                    const libxkbcommon = dep.artifact("xkbcommon");
                    module.linkLibrary(libxkbcommon);
                }
            }
        },
        .glfw => {
            if (b.lazyDependency("glfw_zig", .{
                .target = target,
                .optimize = module.optimize.?,
            })) |dep| module.linkLibrary(dep.artifact("glfw"));
            if (b.lazyDependency("xkbcommon", .{
                .target = target,
                .optimize = module.optimize.?,
                .@"xkb-config-root" = "/usr/share/X11/xkb",
            })) |dep| {
                const libxkbcommon = dep.artifact("xkbcommon");
                module.linkLibrary(libxkbcommon);
            }
        },
        .android => {
            // Android NDK libraries
            module.linkSystemLibrary("android", .{});
            module.linkSystemLibrary("log", .{});
            module.linkSystemLibrary("android_native_app_glue", .{});

            if (render_backend == .opengl) {
                module.linkSystemLibrary("EGL", .{});
                module.linkSystemLibrary("GLESv3", .{});
            } else if (render_backend == .vulkan) {
                module.linkSystemLibrary("vulkan", .{});
            }
        },
    }
}

fn shouldUseGLES(target: Build.ResolvedTarget) bool {
    return switch (target.result.os.tag) {
        .emscripten, .wasi, .ios => true,
        .linux => switch (target.result.abi) {
            .android => true, // Android uses GLES
            else => switch (target.result.cpu.arch) {
                .arm, .armeb, .aarch64 => true,
                else => false,
            },
        },
        .windows => switch (target.result.cpu.arch) {
            .arm, .armeb, .aarch64 => true,
            else => false,
        },
        else => false,
    };
}

fn createOpenGLBindings(b: *Build, target: Build.ResolvedTarget) *Build.Module {
    const extensions: []const []const u8 = &.{
        "KHR_debug",
        "ARB_shader_storage_buffer_object",
        "ARB_gl_spirv",
    };

    const use_gles = shouldUseGLES(target);
    const gl_target = if (use_gles) "gles-3.2" else "gl-4.1-core";

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
