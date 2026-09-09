const std = @import("std");
const Build = std.Build;

const profile_mod = @import("profile.zig");
const Window = profile_mod.Window;
const ResolvedConfig = profile_mod.ResolvedConfig;

pub fn wireAllDeps(b: *Build, mod: *Build.Module, cfg: ResolvedConfig) void {
    wireCore(b, mod, cfg);
    wireVulkan(b, mod);
    wireWindow(b, mod, cfg);
}

/// Core rendering/text/raster deps that every profile needs.
pub fn wireCore(b: *Build, mod: *Build.Module, cfg: ResolvedConfig) void {
    const target = cfg.target;
    const optimize = cfg.optimize;

    const vtparse_dep = b.dependency("vtparse", .{ .target = target, .optimize = optimize });
    mod.addImport("vtparse", vtparse_dep.module("vtparse"));

    const truetype_dep = b.dependency("TrueType", .{ .target = target, .optimize = optimize });
    mod.addImport("TrueType", truetype_dep.module("TrueType"));

    // const machfreetype_dep = b.dependency("mach_freetype", .{
    //     .target = target,
    //     .optimize = optimize,
    //     .use_llvm = cfg.use_llvm,
    // });
    // mod.addImport("mach-freetype", machfreetype_dep.module("mach-freetype"));
    // mod.addImport("mach-harfbuzz", machfreetype_dep.module("mach-harfbuzz"));

    const zigimg_dep = b.dependency("zigimg", .{ .target = target, .optimize = optimize });
    mod.addImport("zigimg", zigimg_dep.module("zigimg"));

    // const zg_dep = b.dependency("zg", .{ .target = target, .optimize = optimize });
    // mod.addImport("Graphemes", zg_dep.module("Graphemes"));
}

/// Vulkan binding + headers. Always required (renderer is fixed to Vulkan).
/// Uses the system-provided registry when available, otherwise falls back.
pub fn wireVulkan(b: *Build, mod: *Build.Module) void {
    const vulkan_headers = b.lazyDependency("vulkan_headers", .{});
    const vulkan_dep = if (vulkan_headers) |vh|
        b.lazyDependency("vulkan", .{
            .optimize = .Debug,
            .target = "native",
            .registry = vh.path("registry/vk.xml"),
        })
    else
        b.lazyDependency("vulkan", .{
            .optimize = .Debug,
            .target = "native",
        });

    if (vulkan_headers != null) {
        if (vulkan_dep) |dep|
            mod.addImport("vulkan", dep.module("vulkan-zig"));
    }
}

/// Window-system specific deps: linked libraries and imports chosen by `cfg.window`.
/// All resolved lazily so unrelated profiles don't pull foreign deps.
pub fn wireWindow(b: *Build, mod: *Build.Module, cfg: ResolvedConfig) void {
    const target = cfg.target;
    const optimize = cfg.optimize;

    switch (cfg.window) {
        .glfw => {
            if (b.lazyDependency("glfw_zig", .{ .target = target, .optimize = optimize })) |dep|
                mod.linkLibrary(dep.artifact("glfw"));
        },
        .win32 => {
            if (b.lazyDependency("zigwin32", .{})) |dep|
                mod.addImport("win32", dep.module("win32"));
        },
        .xcb => {
            if (target.query.isNative()) {
                mod.linkSystemLibrary("xcb", .{});
                mod.linkSystemLibrary("xkbcommon", .{});
            } else {
                if (b.lazyDependency("xcb", .{ .target = target, .optimize = optimize })) |dep|
                    mod.linkLibrary(dep.artifact("xcb"));
                if (b.lazyDependency("xkbcommon", .{ .target = target, .optimize = optimize })) |dep|
                    mod.linkLibrary(dep.artifact("xkbcommon"));
            }
        },
        .android => {
            // _ = b.lazyDependency("ndk_linux");
            // _ = b.lazyDependency("android_sdk_linux");
        },
    }

    // Terminal pty/IO deps by OS, independent of window system.
    switch (target.result.os.tag) {
        .windows => {
            if (b.lazyDependency("zigwin32", .{})) |dep|
                mod.addImport("win32", dep.module("win32"));
        },
        .linux, .macos => {
            if (!target.result.abi.isAndroid()) {
                if (b.lazyDependency("zig_openpty", .{})) |dep|
                    mod.addImport("openpty", dep.module("openpty"));
            }
        },
        else => {},
    }

    // The executable (main entry) links system libs that the app module doesn't.
    if (target.result.os.tag == .linux and !target.result.abi.isAndroid()) {
        if (b.lazyDependency("xkbcommon", .{
            .target = target,
            .optimize = optimize,
            .@"xkb-config-root" = "/usr/share/X11/xkb",
        })) |dep| mod.linkLibrary(dep.artifact("xkbcommon"));
    }
}
