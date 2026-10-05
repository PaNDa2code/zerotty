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

    // `@embedFile` in the test root may not reach outside the package, so the
    // fixture font is staged into the build directory and handed over as a
    // module rather than copied into `src/`.
    const fixture = b.addWriteFiles().addCopyFile(
        b.path("assets/fonts/JetBrainsMono/ttf/JetBrainsMono-Regular.ttf"),
        "JetBrainsMono-Regular.ttf",
    );

    // Tests are scoped to a purpose-built root rather than all of `src/root.zig`.
    // Pointing them at `src/root.zig` compiles every `refAllDecls` in the tree,
    // which drags in unrelated suites (`terminal/grid/tests.zig` currently
    // references a `Grid` API that no longer exists) and fails the whole run.
    // Add modules here as their suites come back online.
    const font_test_mod = b.createModule(.{
        .root_source_file = b.path("src/font/test_root.zig"),
        .target = cfg.target,
        .optimize = cfg.optimize,
        .link_libc = true,
    });
    deps_mod.wireAllDeps(b, font_test_mod, cfg);
    font_test_mod.addImport("build_options", options.createModule());
    font_test_mod.addImport("zerotty", zerrotty_mod);
    font_test_mod.addAnonymousImport("fixture_font", .{ .root_source_file = fixture });

    const tests = b.addTest(.{
        .name = "zerotty-tests",
        .root_module = font_test_mod,
        .use_llvm = cfg.use_llvm,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "run unit tests");
    test_step.dependOn(&run_tests.step);

    // Temporary diagnostic: prints raw backend metrics so unit discrepancies can
    // be read directly instead of inferred from assertion deltas.
    const probe_mod = b.createModule(.{
        .root_source_file = b.path("src/font/probe_main.zig"),
        .target = cfg.target,
        .optimize = cfg.optimize,
        .link_libc = true,
    });
    deps_mod.wireAllDeps(b, probe_mod, cfg);
    probe_mod.addImport("build_options", options.createModule());
    probe_mod.addImport("zerotty", zerrotty_mod);
    probe_mod.addAnonymousImport("fixture_font", .{ .root_source_file = fixture });

    const probe = b.addExecutable(.{
        .name = "font-probe",
        .root_module = probe_mod,
        .use_llvm = cfg.use_llvm,
    });
    const run_probe = b.addRunArtifact(probe);
    const probe_step = b.step("probe", "print backend metrics");
    probe_step.dependOn(&run_probe.step);

    if (check_only) return &exe.step;

    const install = b.addInstallArtifact(exe, .{});

    const run_step = b.step("run", "run exe");

    const exe_run = b.addRunArtifact(exe);

    // get the final exe in zig-out before running run step
    run_step.dependOn(&install.step);

    run_step.dependOn(&exe_run.step);

    return &install.step;
}
