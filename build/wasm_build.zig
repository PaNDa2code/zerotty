const std = @import("std");
const em_build = @import("em_build.zig");
const Build = std.Build;
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;

pub fn build(b: *Build, target: ResolvedTarget, optimize: OptimizeMode) !void {
    const emsdk = b.dependency("emsdk", .{});
    const emsdk_setup = em_build.emsdkSetup(b, emsdk);

    const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{
        .api = .gles,
        .version = .@"3.0",
        .extensions = &.{},
    });

    const root_mod = b.addModule("zerotty", .{
        .root_source_file = b.path("src/WASM.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
        .link_libc = true,
    });

    root_mod.addImport("gl", gl_bindings);

    const lib_main = b.addLibrary(.{
        .name = "zerotty",
        .root_module = root_mod,
        .linkage = .static,
    });

    const em_link = try em_build.emLinkStep(b, .{
        .lib_main = lib_main,
        .target = target,
        .optimize = optimize,
        .release_use_closure = true,
        .release_use_lto = true,
        .use_offset_converter = true,
        .exports = &.{"main"},
        .use_webgl2 = true,
        .full_es3 = true,
        .emsdk = emsdk,
        .extra_args = &.{},
    });

    if (emsdk_setup) |setup| {
        em_link.step.dependOn(&setup.step);
    }
    em_link.step.dependOn(&lib_main.step);

    b.default_step.dependOn(&em_link.step);
}
