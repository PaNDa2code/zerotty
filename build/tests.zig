const std = @import("std");

pub fn addTests(
    b: *std.Build,
    native_build: anytype,
    target: std.Build.ResolvedTarget,
) !void {

    // -------------------------------------------------------------------------
    // Testing
    // -------------------------------------------------------------------------
    const test_step = b.step("test_all", "will run all submodules test");
    const app_imports = [_][]const u8{
        "vtparse",        "assets",        "io",     "pty",    "grid",     "math",         "font",
        "color",          "input",         "window", "cursor", "renderer", "ChildProcess", "DynamicLibrary",
        "circular_array", "AssetsManager",
    };

    for (app_imports) |name| {
        if (native_build.modules.get(name)) |mod| {
            const test_name = b.fmt("test_{s}", .{name});
            const test_desc = b.fmt("run module {s} test", .{name});
            const test_mod_step = b.step(test_name, test_desc);

            mod.resolved_target = target;

            const unit_test = b.addTest(.{
                .name = test_name,
                .root_module = mod,
            });

            const run_unit_test = b.addRunArtifact(unit_test);
            test_mod_step.dependOn(&run_unit_test.step);
            test_step.dependOn(test_mod_step);
        }
    }
}
