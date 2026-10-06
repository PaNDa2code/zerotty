const std = @import("std");
const Build = std.Build;

const deps_mod = @import("deps.zig");
const shaders_mod = @import("shaders.zig");
const profiles_mod = @import("profile.zig");
const android_mod = @import("android.zig");
const assets_mod = @import("assets.zig");

pub fn testAllRunStep(
    b: *Build,
    filters: []const []const u8,
    cfg: profiles_mod.ResolvedConfig,
) *Build.Step {
    const tests_root = b.path("src/root.zig");

    const tests_mod = b.createModule(.{
        .root_source_file = tests_root,
    });

    deps_mod.wireAllDeps(b, tests_mod, cfg);

    const unit_tests = b.addTest(.{
        .name = "zerotty tests",
        .root_module = tests_mod,
        .filters = filters,
    });

    const run_tests = b.addRunArtifact(unit_tests);

    return &run_tests.step;
}
