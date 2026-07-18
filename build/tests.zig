const std = @import("std");

pub fn addTests(
    b: *std.Build,
    native_build: anytype,
    target: std.Build.ResolvedTarget,
) !void {
    // -------------------------------------------------------------------------
    // Testing
    // -------------------------------------------------------------------------
    const test_step = b.step("test", "Run all tests");
    const test_all_step = b.step("test_all", "Run all tests");
    test_all_step.dependOn(test_step);

    if (native_build.modules.get("zerotty")) |mod| {
        const test_name = "test_zerotty";
        mod.resolved_target = target;

        const unit_test = b.addTest(.{
            .name = test_name,
            .root_module = mod,
            .test_runner = .{
                .mode = .simple,
                .path = b.path("tests/simple_runner.zig"),
            },
        });

        const run_unit_test = b.addRunArtifact(unit_test);
        test_step.dependOn(&run_unit_test.step);
    }
}
