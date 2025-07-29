const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

const Builder = @import("Builder.zig");

const JsonBuilder = struct {
    target: []const u8,
    render_backend: Builder.RenderBackend,
    window_system: Builder.WindowSystem,

    pub fn toBuilder(self: JsonBuilder, b: *Build) !Builder {
        const target_query = try std.Target.Query.parse(.{
            .arch_os_abi = self.target,
        });
        const resolved_target = std.Build.resolveTargetQuery(b, target_query);

        const options = b.addOptions();
        options.addOption(Builder.RenderBackend, "render-backend", self.render_backend);
        options.addOption(Builder.WindowSystem, "window-system", self.window_system);

        var builder = Builder.init(b, resolved_target, .Debug);

        _ = builder
            .setRenderBackend(self.render_backend)
            .setWindowSystem(self.window_system)
            .addOptionsModule("build_options", options)
            .setRootFile(b.path("src/main.zig"))
            .addStaticLibrary("zerotty_check");

        return builder;
    }
};

pub fn addCheckStep(b: *Build) !void {
    const check_step = b.step("check", "check the compilation status of build configs in build/check.json");

    const check_json_file = try std.fs.cwd().openFile("build/check.json", .{});
    const check_json_buffer = try check_json_file.readToEndAlloc(b.allocator, 1024 * 1024 * 20);
    defer b.allocator.free(check_json_buffer);

    const check_json = try std.json.parseFromSlice([]JsonBuilder, b.allocator, check_json_buffer, .{});

    for (check_json.value) |json_builder| {
        const builder = try json_builder.toBuilder(b);
        check_step.dependOn(builder.builder_step);
    }
}
