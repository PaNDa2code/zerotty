const std = @import("std");
const Build = std.Build;

const profile_mod = @import("profile.zig");
const app_mod = @import("app.zig");

const BuildProfile = profile_mod.BuildProfile;
const BuildProfileEnum = profile_mod.BuildProfileEnum;
const ResolvedConfig = profile_mod.ResolvedConfig;

/// Default release profiles when none are explicitly provided via CLI.
pub const DEFAULT_RELEASE_PROFILES = [_]BuildProfileEnum{
    .linux_glfw,
    .windows_glfw,
};

/// Sets up the release pipeline, creating the `release` top-level step and
/// individual `release-<preset>` steps.
pub fn setupReleasePipeline(b: *Build) *Build.Step {
    const release_step = b.step("release", "Build release artifacts for all specified targets");

    // CLI options for release configuration
    const release_profiles_opt = b.option(
        []const BuildProfileEnum,
        "release_profiles",
        "Predefined profiles to produce for release (e.g. linux_glfw, windows_glfw)",
    );

    const release_targets_opt = b.option(
        []const []const u8,
        "release_targets",
        "Target triples to produce for release (e.g. x86_64-linux, x86_64-windows)",
    );

    const targets_opt = b.option(
        []const []const u8,
        "targets",
        "Target triples to produce for release (comma-separated or multiple flags)",
    );

    const release_mode_opt = b.option(
        std.builtin.OptimizeMode,
        "release_mode",
        "Optimization mode for release builds (default: ReleaseFast)",
    );

    const archive_opt = b.option(
        bool,
        "archive",
        "Create .tar.gz and .zip archives of release bundles (default: false)",
    ) orelse false;

    const optimize_mode = release_mode_opt orelse .fast;

    // Resolve list of profiles to build for the main `release` step
    const profiles = resolveReleaseProfiles(b, release_profiles_opt, release_targets_opt, targets_opt);

    for (profiles) |prof| {
        const prof_step = buildReleaseProfile(b, prof, optimize_mode, archive_opt);
        release_step.dependOn(prof_step);
    }

    // Also register individual release steps without backend in name
    const aliases = [_]struct { step_name: []const u8, preset_enum: BuildProfileEnum }{
        .{ .step_name = "release-linux", .preset_enum = .linux_glfw },
        .{ .step_name = "release-windows", .preset_enum = .windows_glfw },
    };

    for (aliases) |alias| {
        if (b.top_level_steps.get(alias.step_name) == null) {
            const single_step = b.step(alias.step_name, b.fmt("Build release artifact for {s}", .{alias.step_name}));
            const prof_step = buildReleaseProfile(b, alias.preset_enum.getProfile(), optimize_mode, archive_opt);
            single_step.dependOn(prof_step);
        }
    }

    // Also keep release-<preset> steps for presets
    for (profile_mod.PRESETS) |preset| {
        const step_name = b.fmt("release-{s}", .{preset.name});
        if (b.top_level_steps.get(step_name) == null) {
            const single_step = b.step(step_name, b.fmt("Build release artifact for {s}", .{preset.name}));
            const prof_step = buildReleaseProfile(b, preset, optimize_mode, archive_opt);
            single_step.dependOn(prof_step);
        }
    }

    return release_step;
}

/// Resolves release profiles from user inputs or falls back to defaults.
pub fn resolveReleaseProfiles(
    b: *Build,
    release_profiles: ?[]const BuildProfileEnum,
    release_targets: ?[]const []const u8,
    targets: ?[]const []const u8,
) []const BuildProfile {
    var list: std.ArrayList(BuildProfile) = .empty;

    // 1. If explicit target triples were specified:
    const raw_targets = release_targets orelse targets;
    if (raw_targets) |rt| {
        for (rt) |item| {
            var it = std.mem.splitScalar(u8, item, ',');
            while (it.next()) |triple| {
                const trimmed = std.mem.trim(u8, triple, " \t\r\n");
                if (trimmed.len == 0) continue;
                const query = std.Target.Query.parse(.{ .arch_os_abi = trimmed }) catch |err| {
                    std.debug.panic("Invalid target query '{s}': {}", .{ trimmed, err });
                };
                const prof = profile_mod.fromTargetQuery(trimmed, query, null);
                list.append(b.allocator, prof) catch @panic("OOM");
            }
        }
    }

    // 2. If explicit profile enums were specified:
    if (release_profiles) |profs| {
        for (profs) |pe| {
            list.append(b.allocator, pe.getProfile()) catch @panic("OOM");
        }
    }

    // 3. Fallback to default release profiles if none specified:
    if (list.items.len == 0) {
        for (DEFAULT_RELEASE_PROFILES) |pe| {
            list.append(b.allocator, pe.getProfile()) catch @panic("OOM");
        }
    }

    return list.toOwnedSlice(b.allocator) catch @panic("OOM");
}

/// Builds and installs release artifacts for a single profile.
pub fn buildReleaseProfile(
    b: *Build,
    profile: BuildProfile,
    optimize: std.builtin.OptimizeMode,
    archive: bool,
) *Build.Step {
    var prof = profile;
    prof.optimize = optimize;
    prof.use_llvm = true;

    const cfg = profile_mod.resolveProfile(b, prof);
    const target = cfg.target;
    const is_windows = target.result.os.tag == .windows;
    const is_android = target.result.abi.isAndroid();

    const app_artifact = app_mod.buildAppArtifact(b, cfg);

    const arch_name = @tagName(target.result.cpu.arch);
    const mode_name = optimizeName(optimize);
    const os_name = @tagName(target.result.os.tag);

    // Name format: zerotty + arch + release mode (e.g. zerotty-x86_64-ReleaseFast)
    const release_base_name = b.fmt("zerotty-{s}-{s}-{s}", .{ arch_name, os_name, mode_name });

    // Destination bundle directory in prefix: zig-out/release/{arch}-{os}/
    const release_sub_path = b.fmt("release/{s}-{s}", .{ arch_name, os_name });
    const release_dir: Build.InstallDir = .{
        .custom = release_sub_path,
    };

    const exe_name = if (is_windows) "zerotty.exe" else if (is_android) "zerotty.apk" else "zerotty";

    // 1. Install executable/apk into zig-out/release/{arch}-{os}/
    const install_in_release_dir = app_mod.installAppArtifact(b, app_artifact, .{
        .dest_dir = release_dir,
        .dest_sub_path = exe_name,
    });

    // 2. Install target-prefixed executable into zig-out/bin/zerotty-{arch}-{mode}[.exe]
    const bin_name = if (is_windows)
        b.fmt("{s}.exe", .{release_base_name})
    else if (is_android)
        b.fmt("{s}.apk", .{release_base_name})
    else
        release_base_name;

    const install_in_bin = app_mod.installAppArtifact(b, app_artifact, .{
        .dest_sub_path = bin_name,
    });

    // 3. Include README.md and LICENSE in release bundle directory
    const copy_license = b.addInstallFileWithDir(b.path("LICENSE"), release_dir, "LICENSE");
    const copy_readme = b.addInstallFileWithDir(b.path("README.md"), release_dir, "README.md");

    // Zig 0.17 removed custom build steps, so this group is represented by the
    // last install step with the remaining install/archive steps attached to it.
    const group_step = install_in_bin;
    group_step.dependOn(install_in_release_dir);
    group_step.dependOn(&copy_license.step);
    group_step.dependOn(&copy_readme.step);

    // 4. Archive packaging if requested
    if (archive and !is_android) {
        const bundle_dir = installPrefixPath(release_sub_path);
        const out_zip_path = b.fmt("release/{s}.zip", .{release_base_name});
        const out_tar_path = b.fmt("release/{s}.tar.gz", .{release_base_name});
        if (is_windows) {
            const zip_cmd = b.addSystemCommand(&.{"zip"});
            zip_cmd.setCwd(bundle_dir);
            zip_cmd.addArgs(&.{ "-q", "-r" });
            zip_cmd.addFileArg2(installPrefixPath(out_zip_path), .{});
            zip_cmd.addArg(".");
            group_step.dependOn(&zip_cmd.step);
        } else {
            const tar_cmd = b.addSystemCommand(&.{
                "tar",
                "-czf",
            });
            tar_cmd.addFileArg2(installPrefixPath(out_tar_path), .{});
            tar_cmd.addArg("-C");
            tar_cmd.addFileArg2(bundle_dir, .{});
            tar_cmd.addArg(".");
            group_step.dependOn(&tar_cmd.step);
        }
    }

    return group_step;
}

/// `std.lang.Optimize` tag names are lowercase in Zig 0.17; keep the historical
/// `ReleaseFast`-style naming used by release artifacts.
fn optimizeName(optimize: std.lang.Optimize) []const u8 {
    return switch (optimize) {
        .debug => "Debug",
        .safe => "ReleaseSafe",
        .fast => "ReleaseFast",
        .small => "ReleaseSmall",
    };
}

/// A path relative to the install prefix. The prefix is only known at make
/// time, so it is expressed lazily instead of via `b.getInstallPath` (removed
/// in Zig 0.17).
fn installPrefixPath(sub_path: []const u8) Build.LazyPath {
    return .{ .relative = .{ .base = .install_prefix, .sub_path = sub_path } };
}
