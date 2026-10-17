const std = @import("std");
const Build = std.Build;

const deps_mod = @import("deps.zig");
const shaders_mod = @import("shaders.zig");
const profiles_mod = @import("profile.zig");
const android_mod = @import("android.zig");
const assets_mod = @import("assets.zig");

const Config = profiles_mod.ResolvedConfig;

const buildAndroidApk = android_mod.buildAndroidApk;

pub const AppArtifact = struct {
    artifact: ArtifactType,
    mod: *Build.Module,

    pub const ArtifactType = union(enum) {
        exe: *Build.Step.Compile,
        apk: Build.LazyPath,
    };

    pub fn getStep(self: AppArtifact, b: *Build) *Build.Step {
        return switch (self.artifact) {
            .exe => |exe| &exe.step,
            .apk => |apk| switch (apk) {
                .generated => |g| b.graph.generated_files.items[@intFromEnum(g.index)],
                else => unreachable,
            },
        };
    }
};

pub const InstallOptions = struct {
    dest_dir: ?Build.InstallDir = null,
    dest_sub_path: ?[]const u8 = null,
};

pub fn buildAppArtifact(b: *Build, cfg: Config) AppArtifact {
    const zerrotty_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = cfg.target,
        .optimize = cfg.optimize,
    });

    deps_mod.wireAllDeps(b, zerrotty_mod, cfg);

    const options = b.addOptions();
    options.addOption(profiles_mod.Window, "window", cfg.window);
    options.addOption(bool, "renderer_debug", cfg.optimize == .debug);

    zerrotty_mod.addImport("build_options", options.createModule());
    zerrotty_mod.addImport("zerotty", zerrotty_mod);

    const assets = assets_mod.resolveAssets(b) catch @panic("can't compress assets");

    // if (cfg.optimize == .ReleaseSmall)
    zerrotty_mod.addAnonymousImport("assets.tar.zst", .{ .root_source_file = assets.compressed_path });
    // else
    zerrotty_mod.addAnonymousImport("assets.tar", .{ .root_source_file = assets.tar_path });

    // const is_android = cfg.target.result.abi.isAndroid();
    //
    // if (is_android) {
    //     const apk = buildAndroidApk(b, zerrotty_mod, "aarch64", cfg);
    //     if (apk) |path| {
    //         return .{
    //             .artifact = .{ .apk = path },
    //             .mod = zerrotty_mod,
    //         };
    //     }
    // }

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

    return .{
        .artifact = .{ .exe = exe },
        .mod = zerrotty_mod,
    };
}

pub fn installAppArtifact(
    b: *Build,
    app_artifact: AppArtifact,
    opts: InstallOptions,
) *Build.Step {
    switch (app_artifact.artifact) {
        .apk => |path| {
            const dest_name = if (opts.dest_sub_path) |sub| sub else "zerotty.apk";
            if (opts.dest_dir) |dir| {
                const install_step = b.addInstallFileWithDir(path, dir, dest_name);
                return &install_step.step;
            } else {
                const install_step = b.addInstallBinFile(path, dest_name);
                return &install_step.step;
            }
        },
        .exe => |exe| {
            var install_opts: Build.Step.InstallArtifact.Options = .{};
            if (opts.dest_dir) |dir| {
                install_opts.dest_dir = .{ .override = dir };
            }
            if (opts.dest_sub_path) |sub| {
                install_opts.dest_sub_path = sub;
            }
            const install = b.addInstallArtifact(exe, install_opts);
            return &install.step;
        },
    }
}

pub fn buildAppStep(b: *Build, cfg: Config, check_only: bool) *Build.Step {
    const app_artifact = buildAppArtifact(b, cfg);
    if (check_only) return app_artifact.getStep(b);

    switch (app_artifact.artifact) {
        .apk => {
            return installAppArtifact(b, app_artifact, .{});
        },
        .exe => |exe| {
            if (b.top_level_steps.get("test") == null) {
                const tests = b.addTest(.{
                    .name = "zerotty-tests",
                    .root_module = app_artifact.mod,
                    .use_llvm = cfg.use_llvm,
                });

                const run_tests = b.addRunArtifact(tests);
                const test_step = b.step("test", "run unit tests");
                test_step.dependOn(&run_tests.step);
            }

            const install = installAppArtifact(b, app_artifact, .{});

            if (b.top_level_steps.get("run") == null) {
                const run_step = b.step("run", "run exe");
                const exe_run = b.addRunArtifact(exe);

                // get the final exe in zig-out before running run step
                run_step.dependOn(install);
                run_step.dependOn(&exe_run.step);
            }

            return install;
        },
    }
}
