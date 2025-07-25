const std = @import("std");
const Build = std.Build;

const Builder = @import("build/Builder.zig");

pub fn build(b: *Build) !void {
    var builder = Builder.init(b, b.standardTargetOptions(.{}), b.standardOptimizeOption(.{}));

    const render_backend: Builder.RenderBackend =
        b.option(Builder.RenderBackend, "render-backend", "") orelse DEFULAT_RENDER_BACKEND;

    const window_system: Builder.WindowSystem =
        b.option(Builder.WindowSystem, "window-system", "") orelse
        switch (builder.target.result.os.tag) {
            .windows => .Win32,
            .linux => switch (render_backend) {
                .Vulkan => .Xcb,
                else => .Xlib,
            },
            else => .Xlib,
        };

    const options = b.addOptions();
    options.addOption(Builder.RenderBackend, "render-backend", render_backend);
    options.addOption(Builder.WindowSystem, "window-system", window_system);

    builder.setRootFile(b.path("src/main.zig"))
        .setRenderBackend(render_backend)
        .setWindowSystem(window_system)
        .addOptionsModule("build_options", options)
        .addExcutable("zerotty")
        .addRunStep()
        .apply();

    const test_step = b.step("test", "run main.zig tests");
    const unit_test = b.addTest(.{ .name = "zerotty", .root_module = builder.getModule() });
    const run_unit_test = b.addRunArtifact(unit_test);
    test_step.dependOn(&run_unit_test.step);
}

const DEFULAT_RENDER_BACKEND: Builder.RenderBackend = .OpenGL;
