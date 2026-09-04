const std = @import("std");
const Build = std.Build;

const cli = @import("build/cli.zig");
const app = @import("build/app.zig");
const profile = @import("build/profile.zig");

pub fn build(b: *Build) !void {
    const build_cmd = cli.addOptions(b);

    switch (build_cmd) {
        .check => {},
        .build => |prof| {
            const cfg = profile.resolveProfile(b, prof);
            const build_step = app.buildAppStep(b, cfg, false).?;
            b.getInstallStep().dependOn(build_step);
        },
    }
}
