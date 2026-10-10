const std = @import("std");
const Build = std.Build;

const cli = @import("build/cli.zig");
const app = @import("build/app.zig");
const profile = @import("build/profile.zig");
const tests = @import("build/tests.zig");
const release_pipeline = @import("build/release_pipeline.zig");

pub fn build(b: *Build) !void {
    // Setup release pipeline step (`zig build release`) and target steps
    _ = release_pipeline.setupReleasePipeline(b);

    const build_cmd = cli.addOptions(b);

    switch (build_cmd) {
        .check => {},
        .build => |prof| {
            const cfg = profile.resolveProfile(b, prof);
            const build_step = app.buildAppStep(b, cfg, false);
            b.default_step.dependOn(build_step);
        },
        .multi_build => |profs| {
            for (profs) |prof| {
                const step = release_pipeline.buildReleaseProfile(
                    b,
                    prof,
                    prof.optimize orelse .Debug,
                    false,
                );
                b.default_step.dependOn(step);
            }
        },
    }
}

