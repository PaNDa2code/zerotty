const std = @import("std");
const Build = std.Build;

const config_mod = @import("build/config.zig");
const app_mod = @import("build/app.zig");
const tests_mod = @import("build/tests.zig");

var io = std.Io.Threaded.global_single_threaded.io();

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
    const render_backend = b.option(config_mod.RenderBackend, "render-backend", "") orelse .vulkan;
    const window_system = b.option(config_mod.WindowSystem, "window-system", "") orelse .glfw;
    const dist_json_path = b.option([]const u8, "dist-json", "multi-build config list json file");

    const disable_renderer_debug = b.option(
        bool,
        "disable-renderer-debug",
        "Disable debugging for renderer backends (Vulkan validation layers, OpenGL debug callbacks)",
    ) orelse (optimize != .Debug);

    if (dist_json_path) |json_path| {
        try config_mod.jsonFileToStep(b, b.default_step, json_path, optimize, use_llvm);
        return;
    } else {
        const check_step = b.step("check", "default step for zls to run");
        try config_mod.jsonFileToStep(b, check_step, "build/check_configs.json", .Debug, use_llvm);
    }

    const native_config = config_mod.AppConfig{
        .use_llvm = use_llvm,
        .comptime_check = comptime_check,
        .render_backend = render_backend,
        .window_system = window_system,
        .disable_renderer_debug = disable_renderer_debug,
    };

    // Setup native app build
    const native_build = try app_mod.setupApp(b, target, optimize, native_config);
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

    try tests_mod.addTests(b, native_build, target);
}
