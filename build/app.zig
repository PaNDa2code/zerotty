const std = @import("std");
const Build = std.Build;

const deps_mod = @import("deps.zig");
const shaders_mod = @import("shaders.zig");
const profiles_mod = @import("profile.zig");
const android_mod = @import("android.zig");
const assets_mod = @import("assets.zig");

const Config = profiles_mod.ResolvedConfig;

const buildAndroidApk = android_mod.buildAndroidApk;

pub fn buildAppStep(b: *Build, cfg: Config, check_only: bool) *Build.Step {
    const zerrotty_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = cfg.target,
        .optimize = cfg.optimize,
    });

    deps_mod.wireAllDeps(b, zerrotty_mod, cfg);

    const options = b.addOptions();
    options.addOption(profiles_mod.Window, "window", cfg.window);
    options.addOption(bool, "renderer_debug", cfg.optimize == .Debug);

    zerrotty_mod.addImport("build_options", options.createModule());
    zerrotty_mod.addImport("zerotty", zerrotty_mod);

    const assets = assets_mod.resolveAssets(b) catch @panic("can't compress assets");

    // if (cfg.optimize == .ReleaseSmall)
    zerrotty_mod.addAnonymousImport("assets.tar.zst", .{ .root_source_file = assets.compressed_path });
    // else
    zerrotty_mod.addAnonymousImport("assets.tar", .{ .root_source_file = assets.tar_path });

    const is_android = cfg.target.result.abi.isAndroid();

    if (is_android) {
        const apk = buildAndroidApk(b, zerrotty_mod, "aarch64", cfg);
        if (apk) |path| {
            const install_step = b.addInstallBinFile(path, "zerotty.apk");
            return &install_step.step;
        }
    }

    const exe = b.addExecutable(.{
        .name = "zerotty",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = cfg.target,
            .optimize = cfg.optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "zerotty", .module = zerrotty_mod },
            },
        }),
        .use_llvm = cfg.use_llvm,
    });

    if (check_only) return &exe.step;

    const install = b.addInstallArtifact(exe, .{});

    const run_step = b.step("run", "run exe");

    const exe_run = b.addRunArtifact(exe);

    // get the final exe in zig-out before running run step
    run_step.dependOn(&install.step);

    run_step.dependOn(&exe_run.step);

    return &install.step;
}
